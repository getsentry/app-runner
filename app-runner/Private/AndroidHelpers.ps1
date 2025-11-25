# Android Helper Functions
# Shared utilities for Android device providers (ADB and SauceLabs)

<#
.SYNOPSIS
Parses an Android activity path into package name and activity name components.

.DESCRIPTION
Parses the ExecutablePath format used by Android apps: "package.name/activity.name"
Returns a hashtable with PackageName and ActivityName properties.

.PARAMETER ExecutablePath
The full activity path in format "package.name/activity.name"

.EXAMPLE
Parse-AndroidActivity "io.sentry.unreal.sample/com.epicgames.unreal.GameActivity"
Returns: @{ PackageName = "io.sentry.unreal.sample"; ActivityName = "com.epicgames.unreal.GameActivity" }

.EXAMPLE
Parse-AndroidActivity "com.example.app/.MainActivity"
Returns: @{ PackageName = "com.example.app"; ActivityName = ".MainActivity" }
#>
function Parse-AndroidActivity {
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

    # Basic validation: Intent extras should start with flags like -e, -es, -ez, etc.
    # This is a simple check - adb/Appium will validate more thoroughly
    if ($Arguments -match '^-[a-z]') {
        return $true
    }

    Write-Warning "Arguments may not be in correct Intent extras format. Expected flags like -e, -es, -ez, etc."
    return $true  # Allow it anyway, let adb/Appium handle the error
}

<#
.SYNOPSIS
Extracts the package name from an APK file using basic validation.

.DESCRIPTION
Validates that a file is an APK and returns the filename without extension
as a basic package name guess. For full package name extraction, aapt/aapt2
would be required.

.PARAMETER ApkPath
Path to the APK file

.EXAMPLE
Get-ApkPackageHint "SentryPlayground.apk"
Returns: "SentryPlayground"
#>
function Get-ApkPackageHint {
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

    # Return filename without extension as a hint
    # Full package name would require aapt parsing
    return [System.IO.Path]::GetFileNameWithoutExtension($ApkPath)
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

# Export functions
Export-ModuleMember -Function @(
    'Parse-AndroidActivity',
    'Test-IntentExtrasFormat',
    'Get-ApkPackageHint',
    'Format-LogcatOutput'
)
