#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the TestApp debug IPA.

.DESCRIPTION
    This script builds the debug version of the TestApp iOS application.
    The IPA is automatically copied to the parent directory (Tests/Fixtures/iOS) after a successful build.

.EXAMPLE
    ./Build-TestApp.ps1
#>

$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot
$ProjectFile = Join-Path (Split-Path $ProjectRoot -Parent) "TestApp.xcodeproj"

Write-Information "Building SentryTestApp debug IPA..." -InformationAction Continue

try {
    Push-Location (Split-Path $ProjectFile -Parent)

    # Clean previous builds
    & xcodebuild -project TestApp.xcodeproj -scheme TestApp clean -quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Xcode clean failed with exit code $LASTEXITCODE"
    }

    # Archive for iOS devices
    $archivePath = Join-Path $ProjectRoot "TestApp.xcarchive"
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Recurse -Force
    }

    & xcodebuild -project TestApp.xcodeproj `
        -scheme TestApp `
        -destination 'generic/platform=iOS' `
        -configuration Release `
        -archivePath $archivePath `
        archive `
        -quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Xcode archive failed with exit code $LASTEXITCODE"
    }

    # Export IPA
    $exportPath = Join-Path $ProjectRoot "export"
    $exportOptionsFile = Join-Path $ProjectRoot "ExportOptions.plist"

    if (Test-Path $exportPath) {
        Remove-Item $exportPath -Recurse -Force
    }

    & xcodebuild -exportArchive `
        -archivePath $archivePath `
        -exportPath $exportPath `
        -exportOptionsPlist $exportOptionsFile `
        -quiet

    if ($LASTEXITCODE -ne 0) {
        throw "IPA export failed with exit code $LASTEXITCODE"
    }

    # Find and copy the IPA
    $exportedIPA = Get-ChildItem -Path $exportPath -Filter "*.ipa" -Recurse | Select-Object -First 1

    if (-not $exportedIPA) {
        throw "No IPA file found in export directory"
    }

    $targetIPA = Join-Path (Split-Path $ProjectRoot -Parent) "TestApp.ipa"
    Copy-Item -Path $exportedIPA.FullName -Destination $targetIPA -Force

    Write-Information "✓ IPA built successfully: $targetIPA" -InformationAction Continue
    $ipaInfo = Get-Item $targetIPA
    Write-Information "  Size: $([math]::Round($ipaInfo.Length / 1MB, 2)) MB" -InformationAction Continue

    # Cleanup
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Recurse -Force
    }
    if (Test-Path $exportPath) {
        Remove-Item $exportPath -Recurse -Force
    }

}
catch {
    Write-Error "Failed to build IPA: $_"
    exit 1
}
finally {
    Pop-Location
}
