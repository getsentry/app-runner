# Android Helper Functions
# Shared utilities for Android device providers (ADB and SauceLabs)

<#
.SYNOPSIS
Converts an Android activity path into package name and activity name components.

.DESCRIPTION
Converts the ExecutablePath format used by Android apps: "package.name/activity.name"
Returns a hashtable with PackageName and ActivityName properties.

.PARAMETER ExecutablePath
The full activity path in format "package.name/activity.name"

.EXAMPLE
ConvertFrom-AndroidActivityPath "io.sentry.unreal.sample/com.epicgames.unreal.GameActivity"
Returns: @{ PackageName = "io.sentry.unreal.sample"; ActivityName = "com.epicgames.unreal.GameActivity" }

.EXAMPLE
ConvertFrom-AndroidActivityPath "com.example.app/.MainActivity"
Returns: @{ PackageName = "com.example.app"; ActivityName = ".MainActivity" }
#>
function ConvertFrom-AndroidActivityPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    if ($ExecutablePath -notmatch '^([^/]+)/(.+)$') {
        throw "ExecutablePath must be in format 'package.name/activity.name'. Got: $ExecutablePath"
    }

    return @{
        PackageName  = $matches[1]
        ActivityName = $matches[2]
    }
}

<#
.SYNOPSIS
Extracts the package name from an APK file using aapt.

.DESCRIPTION
Extracts the real package name from an APK file using aapt (Android Asset Packaging Tool).
Requires aapt or aapt2 to be available in PATH.

.PARAMETER ApkPath
Path to the APK file

.EXAMPLE
Get-ApkPackageName "MyApp.apk"
Returns: "com.example.myapp" (actual package name from AndroidManifest.xml)

.EXAMPLE
Get-ApkPackageName "SentryPlayground.apk"
Returns: "io.sentry.sample"

.NOTES
Requires aapt or aapt2 to be in PATH or Android SDK to be installed.
Throws an error if aapt is not available or if the package name cannot be extracted.
#>
function Get-ApkPackageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApkPath
    )

    if (-not (Test-Path $ApkPath)) {
        throw "APK file not found: $ApkPath"
    }

    if ($ApkPath -notlike '*.apk') {
        throw "File must be an .apk file. Got: $ApkPath"
    }

    # Find aapt or aapt2
    $aaptCmd = Get-Command aapt -ErrorAction SilentlyContinue
    if (-not $aaptCmd) {
        $aaptCmd = Get-Command aapt2 -ErrorAction SilentlyContinue
    }

    if (-not $aaptCmd) {
        throw "aapt or aapt2 not found in PATH. Please install Android SDK Build Tools and ensure aapt is available in PATH."
    }

    Write-Debug "Using $($aaptCmd.Name) to extract package name from APK"

    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $aaptCmd.Name dump badging $ApkPath 2>&1

        # Parse output for package name: package: name='com.example.app'
        foreach ($line in $output) {
            if ($line -match "package:\s+name='([^']+)'") {
                $packageName = $matches[1]
                Write-Debug "Extracted package name: $packageName"
                return $packageName
            }
        }

        throw "Failed to extract package name from APK using aapt. APK may be corrupted or invalid."
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $true
    }
}

<#
.SYNOPSIS
Parses logcat output into structured format.

.DESCRIPTION
Converts raw logcat output (array of strings) into a consistent format
that can be used by test utilities like Get-EventIds.

.PARAMETER LogcatOutput
Array of logcat log lines (raw output from adb or SauceLabs)

.EXAMPLE
$logs = adb -s emulator-5554 logcat -d
Format-LogcatOutput $logs
#>
function Format-LogcatOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$LogcatOutput
    )

    if ($null -eq $LogcatOutput -or $LogcatOutput.Count -eq 0) {
        return @()
    }

    # Ensure output is an array of strings
    return @($LogcatOutput | ForEach-Object {
        if ($null -ne $_) {
            $_.ToString()
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
