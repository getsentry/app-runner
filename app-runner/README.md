# SentryAppRunner PowerShell Module

PowerShell module for automating device lifecycle management, app deployment, and diagnostics collection for Sentry SDK testing across multiple platforms (Xbox, PlayStation 5, Nintendo Switch, Windows, macOS, Linux).

## Installation

```powershell
Import-Module ./SentryAppRunner.psd1
```

## Quick Start

### Gaming Console Example

```powershell
# Connect to device
Connect-Device -Platform "Xbox" -Target "192.168.1.100"

# Run application
Invoke-DeviceApp -ExecutablePath "MyGame.exe" -Arguments "--debug --level=verbose"

# Collect diagnostics
Get-DeviceLogs -LogType "Error"
Get-DeviceScreenshot -OutputPath "screenshot.png"

# Disconnect
Disconnect-Device
```

### Desktop Platform Example

```powershell
# Connect to local computer (auto-detects OS)
Connect-Device -Platform "Local"

# Or specify explicitly:
# Connect-Device -Platform "Windows"  # or "MacOS" or "Linux"

# Run application locally
Invoke-DeviceApp -ExecutablePath "MyApp.exe" -Arguments "--test-mode"

# Collect diagnostics
Get-DeviceScreenshot -OutputPath "screenshot.png"
Get-DeviceDiagnostics -OutputDirectory "./diagnostics"

# Disconnect
Disconnect-Device
```

### Android Platform Example

```powershell
# Connect to Android device via ADB (auto-discovers connected devices)
Connect-Device -Platform "Adb"

# Or connect to specific device serial
Connect-Device -Platform "Adb" -Target "emulator-5554"

# Or use SauceLabs Real Device Cloud
Connect-Device -Platform "AndroidSauceLabs"

# Install APK
Install-DeviceApp -Path "MyApp.apk"

# Run Android app using package/activity format
Invoke-DeviceApp -ExecutablePath "com.example.app/.MainActivity" -Arguments "-e test_mode true"

# Collect diagnostics
Get-DeviceScreenshot -OutputPath "screenshot.png"
Get-DeviceLogs -LogType "All" -MaxEntries 1000

# Disconnect
Disconnect-Device
```

### iOS Simulator Example

```powershell
# Connect to iOS Simulator (auto-discovers available simulators)
Connect-Device -Platform "iOSSimulator"

# Or connect to a specific iOS runtime version
Connect-Device -Platform "iOSSimulator" -Target "iOS 17.0"

# Or use latest available runtime
Connect-Device -Platform "iOSSimulator" -Target "latest"

# Install .app bundle (built for simulator)
Install-DeviceApp -Path "MyApp.app"

# Run app using bundle ID
Invoke-DeviceApp -ExecutablePath "com.example.app" -Arguments @("--test", "smoke")

# Collect diagnostics
Get-DeviceScreenshot -OutputPath "screenshot.png"

# Disconnect (shuts down simulator only if it was booted by this session)
Disconnect-Device
```

## Supported Platforms

### Gaming Consoles

- **Xbox** - Xbox One and Xbox Series X/S development kits
- **PlayStation5** - PS5 development kits
- **Switch** - Nintendo Switch development units

### Mobile Platforms

- **Adb** - Android devices and emulators via Android Debug Bridge
- **iOSSimulator** - iOS Simulators via xcrun simctl (macOS only)
- **AndroidSauceLabs** - Android devices on SauceLabs Real Device Cloud
- **iOSSauceLabs** - iOS devices on SauceLabs Real Device Cloud (coming soon)

### Desktop Platforms

- **Windows** - Local Windows machines
- **MacOS** - Local macOS machines
- **Linux** - Local Linux machines

**Notes:**
- Desktop platforms execute applications locally on the same machine running the module. Device lifecycle operations (power on/off, reboot) are not supported for desktop platforms.
- Mobile platforms require separate installation and execution steps:
  - Android: Use `Install-DeviceApp "MyApp.apk"` to install APK files, then `Invoke-DeviceApp "package.name/.ActivityName"` to run
  - iOS Simulator: Use `Install-DeviceApp "MyApp.app"` to install .app bundles, then `Invoke-DeviceApp "com.example.app"` with bundle ID
  - Android Intent extras should be passed as Arguments in the format: `-e key value` or `-ez key true/false`

## Functions

### Session Management
- `Connect-Device` - Connect to device (auto-discovery or specific target)
- `Disconnect-Device` - Disconnect from device
- `Get-DeviceSession` - Get current session info
- `Test-DeviceConnection` - Verify connection health

### App Execution
- `Invoke-DeviceApp` - Install and run application (unified command)

### Device Lifecycle
- `Start-Device` - Power on device
- `Stop-Device` - Power off device
- `Restart-Device` - Restart device
- `Get-DeviceStatus` - Check device status
- `Test-DeviceInternetConnection` - Test device's internet connectivity

### Diagnostics
- `Get-DeviceLogs` - Retrieve device logs
- `Get-DeviceScreenshot` - Capture screenshot
- `Get-DeviceDiagnostics` - Collect diagnostics and performance metrics

### Retry Policies
- `New-RetryPolicy` - Build a retry policy, optionally deriving from an existing one
- `Register-RetryPolicy` - Register a policy under a name, replacing any policy already there
- `Get-RetryPolicy` - Resolve a registered policy by name

## Retry Policies

Cloud device APIs fail transiently. HTTP calls run under a named retry policy, resolved from a
registry at the point of the call, so a test run can change retry behaviour without touching the
providers.

Built-in policies:

name | used for
--- | ---
`default` | short reads against an established session
`session` | Appium session creation, the largest budget and a body-aware classifier
`upload` | app upload, kept modest because each attempt burns a Sauce Labs upload slot
`launch` | app launch, never retried on a transport failure that may have landed
`quick` | best-effort teardown, small budget so an outage does not stall cleanup
`none` | calls whose caller already retries, or fast health probes

Policy fields:

field | meaning
--- | ---
`Name` | identifies the policy in log lines and error messages
`MaxAttempts` | total attempts including the first; 1 disables retrying
`BaseDelaySeconds` | the first backoff step, doubled on each further attempt
`MaxDelaySeconds` | upper bound on the computed backoff
`MaxRetryAfterSeconds` | upper bound on a server-requested `Retry-After`; a longer request fails immediately
`JitterFactor` | fraction of the backoff, 0 to 1, randomly shaved off each delay
`RetryStatusCodes` | HTTP status codes to retry
`RetryTransport` | whether to retry a transport failure, which carries no response and may have landed
`ShouldRetry` | optional scriptblock replacing the declarative classification entirely

Derive from a built-in rather than restating every field:

```powershell
$patient = New-RetryPolicy -Name "patient-session" -BasedOn (Get-RetryPolicy "session") -MaxAttempts 10
```

Registering under an existing name overrides it for every call site that resolves that name, which
is how a whole test run is retuned:

```powershell
Register-RetryPolicy -Name "session" -Policy $patient
```

`ShouldRetry` is the extension point for decisions the status code cannot express. It receives a
context object with `Attempt`, `Exception`, `StatusCode`, `Body`, `ParsedBody`, `Detail`,
`RetryAfterSeconds` and `Policy`, and returns whether to retry:

```powershell
New-RetryPolicy -Name "capacity-only" -BasedOn (Get-RetryPolicy "session") -ShouldRetry {
    param($Context)
    $Context.StatusCode -eq 500 -and $Context.Detail -like "*was Cancelled before a Sauce Labs Virtual Machine was Found*"
}
```

## Architecture

Session-based workflow where all operations use an active device session:

```powershell
Connect-Device -Platform "PlayStation5"
Start-Device
Invoke-DeviceApp -ExecutablePath "MyGame.exe" -Arguments "--profile"
Get-DeviceLogs -LogType "Error" -MaxEntries 500
Disconnect-Device
```

## Exclusive Device Access

The module uses named semaphores to enforce exclusive access to device resources, preventing conflicts when multiple processes or sessions attempt to use the same device.

**How it works:**

- Each device connection acquires an exclusive system-wide lock based on `Platform-Target`
- Only one connection can hold a device at a time
- Other processes wait (with progress updates) or timeout after 60 minutes
- Lock is released on disconnect, connection failure, or when the PowerShell session ends

**Resource naming:**

- Same platform + target = **exclusive** (blocks concurrent access)
- Different targets = **parallel** (allows concurrent access)
- Examples: `Xbox-192.168.1.100`, `Xbox-Default`, `PlayStation5-Default`

**Example scenario:**

```powershell
# Terminal 1 - Connects successfully
Connect-Device -Platform "Xbox" -Target "192.168.1.100"

# Terminal 2 - Waits or times out (same device)
Connect-Device -Platform "Xbox" -Target "192.168.1.100" -TimeoutSeconds 60

# Terminal 3 - Connects successfully (different device)
Connect-Device -Platform "Xbox" -Target "192.168.1.101"
```

**Custom timeout:**

```powershell
# Use shorter timeout for local environments
Connect-Device -Platform "Xbox" -TimeoutSeconds 300  # 5 minutes
```

## Requirements

- PowerShell 7+

### Console Platform SDKs

- Xbox: GameDK (`$env:GameDK`)
- PlayStation 5: Prospero SDK (`$env:SCE_ROOT_DIR`)
- Switch: Nintendo SDK (`$env:NINTENDO_SDK_ROOT`)

### Mobile Platform Requirements

**Android (ADB):**
- Android SDK with ADB (Android Debug Bridge) in PATH
- USB debugging enabled on physical devices
- Device connected via USB or emulator running locally

**iOS Simulator:**
- macOS with Xcode and `xcrun` in PATH
- At least one iOS Simulator runtime installed
- `.app` bundles built for simulator (not `.ipa` archives)

**Android/iOS (SauceLabs):**
- SauceLabs account with Real Device Cloud access
- Environment variables: `SAUCE_USERNAME`, `SAUCE_ACCESS_KEY`, `SAUCE_REGION`
- Valid SauceLabs device ID or capabilities for device selection
- Optional `SAUCE_LOGCAT_FILTER` (Android only): whitespace-separated logcat filterspecs
  (`tag[:priority]`, e.g. `godot:V sentry-native:V *:S`) applied via the `logcatFilterSpecs`
  session capability to trim the noisy system-wide logcat down to the given tags at capture
  time. Unset returns the full logcat.

### Desktop Platform Requirements

- **Windows:** PowerShell 5.0+ (included with Windows)
- **MacOS:** PowerShell 7+ and `screencapture` command (built-in)
- **Linux:** PowerShell 7+ and optional screenshot tools (`gnome-screenshot`, `scrot`, or ImageMagick)

Desktop platforms don't require additional SDKs and execute applications locally.

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development standards, testing guidelines, and code analysis instructions.
