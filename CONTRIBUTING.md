# Contributing

## Development Standards

### Code Quality

- Follow PowerShell best practices for error handling, logging, and documentation
- All code must execute with `$ErrorActionPreference = 'Stop'` and `$PSNativeCommandUseErrorActionPreference = $true`
- Use `Write-Debug` for debug information (`$DebugPreference = 'Continue'` to enable)
- Use `Write-Warning` for important warnings

### Error Handling

- Always use `Assert-DeviceSession` before device operations
- Use consistent error messages: "No active device session" for session validation failures
- Mark unimplemented features with `# TODO: Implement <functionality>`

### Session Management

- Only one device session active at a time
- Auto-disconnect when connecting to a new platform
- All functions must validate session before executing

## Testing

Run tests before committing:

```powershell
# Run all tests
Invoke-Pester -Path ./app-runner/Tests/ -Output Detailed

# Run tests excluding device tests
Invoke-Pester -Path ./app-runner/Tests/ -ExcludeTag 'RequiresDevice' -Output Detailed

# Run device tests for specific platform
Invoke-Pester -Path ./app-runner/Tests/Device.Tests.ps1 -TagFilter 'Xbox' -Output Detailed
```

**All tests must pass before committing.**

## Code Analysis

```powershell
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./app-runner -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

## Pull Requests

- Keep changes focused and small
- Include tests for new functionality
- Ensure CI passes (unit tests, integration tests, PSScriptAnalyzer)
- Update documentation if needed