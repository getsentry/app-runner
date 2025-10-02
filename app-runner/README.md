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

## Requirements

- PowerShell 7+
- Platform-specific SDKs:
  - Xbox: GameDK (`$env:GameDK`)
  - PlayStation 5: Prospero SDK (`$env:SCE_ROOT_DIR`)
  - Switch: Nintendo SDK (`$env:NINTENDO_SDK_ROOT`)

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development standards, testing guidelines, and code analysis instructions.