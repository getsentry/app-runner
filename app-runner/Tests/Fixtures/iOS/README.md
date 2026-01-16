# TestApp

A minimal iOS test application for automated testing of SentryAppRunner device management functionality.

## Overview

This iOS app:
- Accepts launch arguments 
- Logs parameters to iOS syslog
- Automatically closes after 3 seconds
- Creates test files for mobile file operations testing

## Bundle Information

- **Bundle ID**: `io.sentry.apprunner.TestApp`
- **Target Platform**: iOS 17.0+ (real devices)

## Building

### Prerequisites
- Xcode 16.0+
- Valid Apple Developer account and code signing setup

### Build the IPA
```powershell
./Build-TestApp.ps1
```

The script creates `../TestApp.ipa` for SauceLabs testing.

## Usage

### SauceLabs Testing
```powershell
Install-DeviceApp -Path "Tests/Fixtures/iOS/TestApp.ipa"
Invoke-DeviceApp -ExecutablePath "io.sentry.apprunner.TestApp" -Arguments @("--test-mode", "sentry")
```

### Viewing Logs
```bash
xcrun simctl spawn booted log show --predicate 'subsystem == "io.sentry.apprunner.TestApp"' --last 5m
```

## Mobile File Operations

This app creates test files in the Documents directory for `CopyDeviceItem` and `LogFilePath` testing:
- Requires `UIFileSharingEnabled=true` (configured in project settings)
- Creates `test-file.txt` in Documents directory on launch

## Testing

Used by `SauceLabs.Tests.ps1` for:
- Device connection management
- App installation and execution  
- Launch argument processing
- iOS syslog retrieval
- Mobile file operations testing
