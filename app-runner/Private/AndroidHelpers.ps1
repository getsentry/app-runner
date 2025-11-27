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
Validates that Android Intent extras are in the correct format.

.DESCRIPTION
Android Intent extras should be passed in the format understood by `am start`.
This function validates and optionally formats the arguments string.

Common Intent extra formats:
  -e key value          String extra
  -es key value         String extra (explicit)
  -ez key true|false    Boolean extra
  -ei key value         Integer extra
  -el key value         Long extra

.PARAMETER Arguments
The arguments string to validate/format

.EXAMPLE
Test-IntentExtrasFormat "-e cmdline -crash-capture"
Returns: $true

.EXAMPLE
Test-IntentExtrasFormat "-e test true -ez debug false"
Returns: $true
#>
function Test-IntentExtrasFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Arguments
    )

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        return $true
    }

    # Intent extras must start with flags: -e, -es, -ez, -ei, -el, -ef, -eu, etc.
    # Followed by at least one whitespace and additional content
    if ($Arguments -notmatch '^--?[a-z]{1,2}\s+') {
        throw "Invalid Intent extras format: '$Arguments'. Must start with flags like -e, -es, -ez, -ei, -el, etc. followed by key-value pairs."
    }

    return $true
}

<#
.SYNOPSIS
Extracts the package name from an APK file using aapt.

.DESCRIPTION
Attempts to extract the real package name from an APK file using aapt (Android Asset Packaging Tool).
If aapt is not available, falls back to using the APK filename without extension as a hint.

.PARAMETER ApkPath
Path to the APK file

.EXAMPLE
Get-ApkPackageName "MyApp.apk"
Returns: "com.example.myapp" (actual package name from AndroidManifest.xml)

.EXAMPLE
Get-ApkPackageName "SentryPlayground.apk"
Returns: "io.sentry.sample" (if aapt available) or "SentryPlayground" (filename fallback)

.NOTES
Requires aapt or aapt2 to be in PATH or Android SDK to be installed for accurate extraction.
Falls back to filename-based hint if aapt is unavailable.
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

    # Try to use aapt to extract real package name
    $aaptCmd = Get-Command aapt -ErrorAction SilentlyContinue
    if (-not $aaptCmd) {
        $aaptCmd = Get-Command aapt2 -ErrorAction SilentlyContinue
    }

    if ($aaptCmd) {
        try {
            Write-Debug "Using $($aaptCmd.Name) to extract package name from APK"
            $PSNativeCommandUseErrorActionPreference = $false
            $output = & $aaptCmd.Name dump badging $ApkPath 2>&1
            $PSNativeCommandUseErrorActionPreference = $true

            # Parse output for package name: package: name='com.example.app'
            foreach ($line in $output) {
                if ($line -match "package:\s+name='([^']+)'") {
                    $packageName = $matches[1]
                    Write-Debug "Extracted package name: $packageName"
                    return $packageName
                }
            }

            Write-Warning "Failed to parse package name from aapt output, falling back to filename hint"
        }
        catch {
            Write-Warning "Failed to execute aapt: $_. Falling back to filename hint"
        }
    }
    else {
        Write-Debug "aapt/aapt2 not found in PATH, falling back to filename hint"
    }

    # Fallback: Use APK filename without extension as package name hint
    $hint = [System.IO.Path]::GetFileNameWithoutExtension($ApkPath)
    Write-Warning "Using APK filename as package name hint: $hint (aapt not available for accurate extraction)"
    return $hint
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
