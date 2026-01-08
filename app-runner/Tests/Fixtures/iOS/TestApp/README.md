# TestApp

A minimal iOS test application used for automated testing of the SentryAppRunner device management functionality on real iOS devices via SauceLabs.

## Overview

This is a simple iOS application that:
- Accepts parameters via launch arguments
- Logs all received parameters to syslog with subsystem `io.sentry.apprunner.TestApp` and category `SentryTestApp`
- Automatically closes after 3 seconds
- Is built for real iOS device testing on SauceLabs

## Bundle Information

- **Bundle ID**: `io.sentry.apprunner.TestApp`
- **Display Name**: `TestApp`
- **Target Platform**: iOS 26.0+ (real devices)

## Building

### Prerequisites

- **Xcode**: Version 16.0 or higher
- **macOS**: Version 15.0 or higher
- **PowerShell**: pwsh 7.0 or higher
- **Apple Developer Account**: Required for real device builds
- **Code Signing**: Valid provisioning profile and certificate

### Code Signing Setup

Before building, you must configure code signing for real device deployment:

1. **Open Xcode Project**:
   ```bash
   open ../TestApp.xcodeproj
   ```

2. **Configure Signing**:
   - Select the `TestApp` target
   - Go to "Signing & Capabilities" tab
   - Select your Apple Developer team
   - Ensure bundle ID `io.sentry.apprunner.TestApp` is configured
   - Verify a valid provisioning profile is selected

3. **Verify Configuration**:
   - Build should succeed without code signing errors
   - Certificate should be installed in Keychain Access

### Build the IPA

Using PowerShell (recommended):
```powershell
./Build-TestApp.ps1
```

The script will:
1. Clean previous builds
2. Archive the project for iOS devices
3. Export IPA for ad-hoc distribution
4. Copy IPA to `../TestApp.ipa` (in Tests/Fixtures/iOS directory)

### Manual Build (Alternative)

If the PowerShell script fails, you can build manually:

```bash
# Clean
xcodebuild -project ../TestApp.xcodeproj -scheme TestApp clean

# Archive
xcodebuild -project ../TestApp.xcodeproj \
  -scheme TestApp \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  -archivePath TestApp.xcarchive \
  archive

# Export (requires ExportOptions.plist)
xcodebuild -exportArchive \
  -archivePath TestApp.xcarchive \
  -exportPath export \
  -exportOptionsPlist ExportOptions.plist
```

## Usage

### SauceLabs Testing

The built IPA is designed for SauceLabs real device testing:

```powershell
# Install the IPA
Install-DeviceApp -Path "Tests/Fixtures/iOS/TestApp.ipa"

# Launch with arguments  
Invoke-DeviceApp -ExecutablePath "io.sentry.apprunner.TestApp" -Arguments @("--test-mode", "sentry")
```

### Launch Arguments Support

The app processes command-line arguments passed during launch:

```bash
# Launch with string parameters
xcrun simctl launch booted io.sentry.apprunner.TestApp --test-mode sentry --param2 value2

# Launch with multiple arguments
xcrun simctl launch booted io.sentry.apprunner.TestApp --env development --debug true --count 42
```

### Viewing Logs

The app logs to the iOS system log with structured logging:

```bash
# View app logs (on device/simulator)
xcrun simctl spawn booted log show --predicate 'subsystem == "io.sentry.apprunner.TestApp"' --info --last 5m

# Filter for SentryTestApp category
xcrun simctl spawn booted log show --predicate 'category == "SentryTestApp"' --info --last 5m
```

## Auto-Close Behavior

The app automatically terminates 3 seconds after launch. This is controlled by the `DispatchQueue.main.asyncAfter` timer in `TestAppApp.swift`.

## Log Output Format

The app logs the following information to iOS syslog:
```
[io.sentry.apprunner.TestApp:SentryTestApp] Application started
[io.sentry.apprunner.TestApp:SentryTestApp] Received 2 launch argument(s):
[io.sentry.apprunner.TestApp:SentryTestApp]   --test-mode = sentry
[io.sentry.apprunner.TestApp:SentryTestApp]   --param2 = value2
[io.sentry.apprunner.TestApp:SentryTestApp] Auto-closing application
[io.sentry.apprunner.TestApp:SentryTestApp] Application terminated
```

## Testing

This IPA is used by the PowerShell tests in `../../SauceLabs.Tests.ps1` to verify:
- Device connection management on real iOS devices
- IPA installation via SauceLabs
- Application execution with launch arguments
- iOS syslog retrieval and parsing
- App lifecycle management

## Troubleshooting

### Code Signing Issues

If you encounter code signing errors:

1. **Check Apple Developer Account**:
   - Ensure your account has device provisioning enabled
   - Verify bundle ID `io.sentry.apprunner.TestApp` is registered

2. **Verify Certificates**:
   - Check Keychain Access for valid iOS Distribution/Development certificates
   - Ensure certificates are not expired

3. **Provisioning Profiles**:
   - Download latest provisioning profiles from Apple Developer portal
   - Ensure profile includes target devices for testing

4. **Xcode Configuration**:
   - Try "Automatically manage signing" first
   - If that fails, manually select appropriate provisioning profile

### Build Failures

Common build issues and solutions:

- **"No such file or directory"**: Ensure you're running the script from the TestApp directory
- **"Archive failed"**: Check code signing configuration in Xcode
- **"Export failed"**: Verify ExportOptions.plist is valid and provisioning allows ad-hoc distribution

### SauceLabs Integration

For SauceLabs testing issues:

- Ensure IPA is built for real devices (not simulator)
- Verify bundle ID matches what's expected in test scripts  
- Check that launch arguments are properly formatted for iOS
- Confirm syslog output is accessible via SauceLabs Appium API

## Comparison with Android TestApp

| Feature | Android TestApp | iOS TestApp |
|---------|----------------|-------------|
| Package/Bundle | `com.sentry.test.minimal` | `io.sentry.apprunner.TestApp` |
| Launch Args | Intent extras (`-e key value`) | Command args (`--key value`) |
| Logging | `Log.i("SentryTestApp", msg)` | `os_log(..., category: "SentryTestApp")` |
| Auto-close | `Handler.postDelayed()` → `finish()` | `DispatchQueue.asyncAfter()` → `exit()` |
| Build Output | `.apk` | `.ipa` |
| Target | Android devices/emulators | Real iOS devices |