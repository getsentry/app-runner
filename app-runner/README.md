# SentryAppRunner PowerShell Module

PowerShell module for automating console lifecycle management, game/app deployment, and diagnostics collection for Sentry SDK testing on game consoles (Xbox, PlayStation 5, Nintendo Switch).

## Installation

```powershell
Import-Module ./SentryAppRunner.psd1
```

## Quick Start

```powershell
# Connect to console
Connect-Console -Platform "Xbox" -Target "192.168.1.100"

# Run application
Invoke-ConsoleApp -ExecutablePath "MyGame.exe" -Arguments "--debug --level=verbose"

# Collect diagnostics
Get-ConsoleLogs -LogType "Error"
Get-ConsoleScreenshot -OutputPath "screenshot.png"

# Disconnect
Disconnect-Console
```

## Supported Platforms

- **Xbox** - Xbox One and Xbox Series X/S development kits
- **PlayStation5** - PS5 development kits
- **Switch** - Nintendo Switch development units

## Functions

### Session Management
- `Connect-Console` - Connect to console (auto-discovery or specific target)
- `Disconnect-Console` - Disconnect from console
- `Get-ConsoleSession` - Get current session info
- `Test-ConsoleConnection` - Verify connection health

### App Execution
- `Invoke-ConsoleApp` - Install and run application (unified command)

### Console Lifecycle
- `Start-Console` - Power on console
- `Stop-Console` - Power off console
- `Restart-Console` - Restart console
- `Get-ConsoleStatus` - Check console status
- `Test-ConsoleInternetConnection` - Test console's internet connectivity

### Diagnostics
- `Get-ConsoleLogs` - Retrieve console logs
- `Get-ConsoleScreenshot` - Capture screenshot
- `Get-ConsoleDiagnostics` - Collect diagnostics and performance metrics

## Architecture

Session-based workflow where all operations use an active console session:

```powershell
Connect-Console -Platform "PlayStation5"
Start-Console
Invoke-ConsoleApp -ExecutablePath "MyGame.exe" -Arguments "--profile"
Get-ConsoleLogs -LogType "Error" -MaxEntries 500
Disconnect-Console
```

## Development

### Testing

```powershell
# Run all tests
Invoke-Pester -Path ./Tests/ -Output Detailed

# Run specific test file
Invoke-Pester -Path ./Tests/SessionManagement.Tests.ps1 -Output Detailed

# Run tests on game consoles
Invoke-Pester -Path ./Tests/GameConsole.Tests.ps1 -Output Detailed

# Run tests for specific platform
Invoke-Pester -Path ./Tests/GameConsole.Tests.ps1 -TagFilter 'Xbox' -Output Detailed
```

### Code Analysis

```powershell
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ../PSScriptAnalyzerSettings.psd1
```

## Requirements

- PowerShell 7+
- Platform-specific SDKs:
  - Xbox: GameDK (`$env:GameDK`)
  - PlayStation 5: Prospero SDK (`$env:SCE_ROOT_DIR`)
  - Switch: Nintendo SDK (`$env:NINTENDO_SDK_ROOT`)