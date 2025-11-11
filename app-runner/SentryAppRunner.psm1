$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Initialize Sentry telemetry (opt-in)
try {
    Import-Module (Join-Path $PSScriptRoot '..\utils\TrySentry.psm1') -ErrorAction Stop
    $moduleManifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'SentryAppRunner.psd1')
    TrySentry\Start-Sentry -Dsn $env:SENTRY_APP_RUNNER_DSN -ModuleName 'SentryAppRunner' -ModuleVersion $moduleManifest.ModuleVersion
} catch {
    Write-Debug "Sentry telemetry initialization failed: $_"
}

# Import device providers in the correct order (base provider first, then implementations, then factory)
$ProviderFiles = @(
    "$PSScriptRoot\Private\DeviceProviders\DeviceProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\XboxProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\PlayStation5Provider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\SwitchProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\MockDeviceProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\DeviceProviderFactory.ps1"
)

foreach ($import in $ProviderFiles) {
    if (Test-Path $import) {
        try {
            . $import
        } catch {
            Write-Error "Failed to import provider $import`: $($_.Exception.Message)"
        }
    }
}

# Import private functions
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)
foreach ($import in $Private) {
    try {
        . $import.FullName
    } catch {
        Write-Error "Failed to import function $($import.FullName): $($_.Exception.Message)"
    }
}

# Import public functions
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
foreach ($import in $Public) {
    try {
        . $import.FullName
        Write-Debug "Imported public function: $($import.Name)"
    } catch {
        Write-Error "Failed to import function $($import.FullName): $($_.Exception.Message)"
    }
}

# Export public functions
Export-ModuleMember -Function @(
    # Session Management
    'Connect-Device',
    'Disconnect-Device',
    'Get-DeviceSession',
    'Test-DeviceConnection',
    'Test-DeviceInternetConnection',

    # Application Management
    'Install-DeviceApp',
    'Invoke-DeviceApp',

    # Device Lifecycle
    'Start-Device',
    'Stop-Device',
    'Restart-Device',
    'Get-DeviceStatus',

    # Diagnostics & Monitoring
    'Get-DeviceLogs',
    'Get-DeviceScreenshot',
    'Get-DeviceDiagnostics'
)
