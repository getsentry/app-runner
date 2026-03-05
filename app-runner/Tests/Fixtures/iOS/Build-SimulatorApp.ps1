#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the TestApp for iOS Simulator.

.DESCRIPTION
    This script builds the TestApp as a .app bundle for the iOS Simulator.
    The .app is copied to the parent directory (Tests/Fixtures/iOS) after a successful build.

.EXAMPLE
    ./Build-SimulatorApp.ps1
#>

$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot

Write-Information "Building SentryTestApp for iOS Simulator..." -InformationAction Continue

try {
    Push-Location $ProjectRoot

    # Clean previous builds
    & xcodebuild -project TestApp.xcodeproj -scheme TestApp clean -quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Xcode clean failed with exit code $LASTEXITCODE"
    }

    # Build for iOS Simulator
    $derivedDataPath = Join-Path $ProjectRoot "DerivedData"

    & xcodebuild -project TestApp.xcodeproj `
        -scheme TestApp `
        -sdk iphonesimulator `
        -configuration Debug `
        -derivedDataPath $derivedDataPath `
        -quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Xcode build failed with exit code $LASTEXITCODE"
    }

    # Find the built .app bundle
    $builtApp = Get-ChildItem -Path "$derivedDataPath/Build/Products/Debug-iphonesimulator" -Filter "*.app" -Directory | Select-Object -First 1

    if (-not $builtApp) {
        throw "No .app bundle found in build output"
    }

    # Copy to fixture directory
    $targetApp = Join-Path $ProjectRoot "TestApp.app"
    if (Test-Path $targetApp) {
        Remove-Item $targetApp -Recurse -Force
    }
    Copy-Item -Path $builtApp.FullName -Destination $targetApp -Recurse

    Write-Information "App built successfully: $targetApp" -InformationAction Continue
    $appSize = (Get-ChildItem $targetApp -Recurse | Measure-Object -Property Length -Sum).Sum
    Write-Information "  Size: $([math]::Round($appSize / 1MB, 2)) MB" -InformationAction Continue

    # Cleanup
    if (Test-Path $derivedDataPath) {
        Remove-Item $derivedDataPath -Recurse -Force
    }
}
catch {
    Write-Error "Failed to build simulator app: $_"
    exit 1
}
finally {
    Pop-Location
}
