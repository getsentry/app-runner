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

# Install and run Android app (format: "package.name/activity.name")
Invoke-DeviceApp -ExecutablePath "com.example.app/.MainActivity" -Arguments "-e test_mode true"

# Or install APK first, then run
Invoke-DeviceApp -ExecutablePath "MyApp.apk" -Arguments "-e debug true"

# Collect diagnostics
Get-DeviceScreenshot -OutputPath "screenshot.png"
Get-DeviceLogs -LogType "All" -MaxEntries 1000

# Disconnect
Disconnect-Device
```

## Supported Platforms

### Gaming Consoles

- **Xbox** - Xbox One and Xbox Series X/S development kits
- **PlayStation5** - PS5 development kits
- **Switch** - Nintendo Switch development units

### Mobile Platforms

- **Adb** - Android devices and emulators via Android Debug Bridge
- **AndroidSauceLabs** - Android devices on SauceLabs Real Device Cloud
- **iOSSauceLabs** - iOS devices on SauceLabs Real Device Cloud (coming soon)

### Desktop Platforms

- **Windows** - Local Windows machines
- **MacOS** - Local macOS machines
- **Linux** - Local Linux machines

**Notes:**
- Desktop platforms execute applications locally on the same machine running the module. Device lifecycle operations (power on/off, reboot) are not supported for desktop platforms.
- Mobile platforms support app installation and execution. For Android, ExecutablePath can be either:
  - APK file path for installation (e.g., "MyApp.apk")
  - Package/Activity format for launching installed apps (e.g., "com.example.app/.MainActivity")
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

**Android/iOS (SauceLabs):**
- SauceLabs account with Real Device Cloud access
- Environment variables: `SAUCE_USERNAME`, `SAUCE_ACCESS_KEY`, `SAUCE_REGION`
- Valid SauceLabs device ID or capabilities for device selection

### Desktop Platform Requirements

- **Windows:** PowerShell 5.0+ (included with Windows)
- **MacOS:** PowerShell 7+ and `screencapture` command (built-in)
- **Linux:** PowerShell 7+ and optional screenshot tools (`gnome-screenshot`, `scrot`, or ImageMagick)

Desktop platforms don't require additional SDKs and execute applications locally.

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development standards, testing guidelines, and code analysis instructions.
