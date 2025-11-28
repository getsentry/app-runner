# TestApp

A minimal Android test application used for automated testing of the SentryAppRunner device management functionality.

## Overview

This is a simple Android application that:
- Accepts parameters via intent extras
- Logs all received parameters to logcat with tag `SentryTestApp`
- Automatically closes after 3 seconds
- Is built in debug mode for log parsing

## Package Information

- **Package Name**: `com.sentry.test.minimal`
- **Main Activity**: `.MainActivity`
- **Full Activity Path**: `com.sentry.test.minimal/.MainActivity`

## Building

### Prerequisites

- Java Development Kit (JDK) 8 or higher
- Android SDK (automatically downloaded by Gradle if not present)

### Build the Debug APK

Using PowerShell (recommended):
```powershell
./Build-TestApp.ps1
```

Using Gradle directly:
```bash
# On macOS/Linux
./gradlew assembleDebug

# On Windows
gradlew.bat assembleDebug
```

The APK will be automatically copied to `../SentryTestApp.apk` (in the Tests/Fixtures directory) after a successful build.

## Usage

### Installing the APK

```bash
adb install -r SentryTestApp.apk
```

### Launching with Intent Parameters

```bash
# Launch with string parameters
adb shell am start -n com.sentry.test.minimal/.MainActivity \
  --es param1 "value1" \
  --es param2 "value2"

# Launch with integer parameter
adb shell am start -n com.sentry.test.minimal/.MainActivity \
  --ei count 42

# Launch with boolean parameter
adb shell am start -n com.sentry.test.minimal/.MainActivity \
  --ez enabled true
```

### Viewing Logs

```bash
# View all SentryTestApp logs
adb logcat -s SentryTestApp:V

# Clear logs and view new ones
adb logcat -c && adb logcat -s SentryTestApp:V
```

## Intent Parameter Types

The app supports all standard Android intent extra types:
- `--es <key> <value>` - String
- `--ei <key> <value>` - Integer
- `--el <key> <value>` - Long
- `--ez <key> <value>` - Boolean (true/false)
- `--ef <key> <value>` - Float
- `--ed <key> <value>` - Double

## Auto-Close Behavior

The app automatically closes 3 seconds after launch. This is controlled by the `AUTO_CLOSE_DELAY_MS` constant in `MainActivity.java`.

## Log Output Format

The app logs the following information:
```
I/SentryTestApp: MainActivity started
I/SentryTestApp: Received 2 intent parameter(s):
I/SentryTestApp:   param1 = value1
I/SentryTestApp:   param2 = value2
I/SentryTestApp: Auto-closing activity
I/SentryTestApp: MainActivity destroyed
```

## Testing

This APK is used by the PowerShell tests in `Tests/Android.Tests.ps1` to verify:
- Device connection management
- APK installation
- Application execution with intent parameters
- Log retrieval and parsing
