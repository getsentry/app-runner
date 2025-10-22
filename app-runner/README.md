# SentryAppRunner PowerShell Module

PowerShell module for automating device lifecycle management, app deployment, and diagnostics collection for Sentry SDK testing across multiple platforms (Xbox, PlayStation 5, Nintendo Switch, mobile, desktop).

## Installation

```powershell
Import-Module ./SentryAppRunner.psd1
```

## Quick Start

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

## Supported Platforms

- **Xbox** - Xbox One and Xbox Series X/S development kits
- **PlayStation5** - PS5 development kits
- **Switch** - Nintendo Switch development units

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
- Other processes wait (with progress updates) or timeout after 30 minutes
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
- Platform-specific SDKs:
  - Xbox: GameDK (`$env:GameDK`)
  - PlayStation 5: Prospero SDK (`$env:SCE_ROOT_DIR`)
  - Switch: Nintendo SDK (`$env:NINTENDO_SDK_ROOT`)

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development standards, testing guidelines, and code analysis instructions.
