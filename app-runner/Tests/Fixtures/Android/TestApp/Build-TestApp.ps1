#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the TestApp debug APK.

.DESCRIPTION
    This script builds the debug version of the TestApp Android application.
    The APK is automatically copied to the parent directory (Tests/Fixtures/Android) by the Gradle build task.

.EXAMPLE
    ./Build-TestApp.ps1
#>

$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot

Write-Information "Building SentryTestApp debug APK..." -InformationAction Continue

try {
    Push-Location $ProjectRoot
    
    # Use gradlew to build the debug APK
    if ($IsWindows) {
        & "$ProjectRoot\gradlew.bat" assembleDebug
    }
    else {
        & "$ProjectRoot/gradlew" assembleDebug
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE"
    }
    
    $apkPath = Join-Path $ProjectRoot ".." "SentryTestApp.apk"
    if (Test-Path $apkPath) {
        Write-Information "✓ APK built successfully: $apkPath" -InformationAction Continue
        $apkInfo = Get-Item $apkPath
        Write-Information "  Size: $([math]::Round($apkInfo.Length / 1MB, 2)) MB" -InformationAction Continue
    }
    else {
        Write-Warning "APK was built but not found at expected location: $apkPath"
    }
}
catch {
    Write-Error "Failed to build APK: $_"
    exit 1
}
finally {
    Pop-Location
}
