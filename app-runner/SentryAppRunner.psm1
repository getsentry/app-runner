$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Import Android helpers first (used by Android providers)
. "$PSScriptRoot\Private\AndroidHelpers.ps1"

# Import device providers in the correct order (base provider first, then implementations, then factory)
$ProviderFiles = @(
    "$PSScriptRoot\Private\DeviceProviders\DeviceProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\XboxProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\PlayStation5Provider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\SwitchProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\LocalComputerProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\WindowsProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\MacOSProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\LinuxProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\AdbProvider.ps1",
    "$PSScriptRoot\Private\DeviceProviders\SauceLabsProvider.ps1",
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
    'Get-DeviceDiagnostics',
    'Copy-DeviceItem'
)
