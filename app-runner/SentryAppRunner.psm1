$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Import console providers in the correct order (base provider first, then implementations, then factory)
$ProviderFiles = @(
    "$PSScriptRoot\Private\ConsoleProviders\ConsoleProvider.ps1",
    "$PSScriptRoot\Private\ConsoleProviders\XboxProvider.ps1",
    "$PSScriptRoot\Private\ConsoleProviders\PlayStation5Provider.ps1",
    "$PSScriptRoot\Private\ConsoleProviders\SwitchProvider.ps1",
    "$PSScriptRoot\Private\ConsoleProviders\MockConsoleProvider.ps1",
    "$PSScriptRoot\Private\ConsoleProviders\ConsoleProviderFactory.ps1"
)

foreach ($import in $ProviderFiles) {
    if (Test-Path $import) {
        try {
            . $import
            Write-Debug "Imported console provider: $(Split-Path -Leaf $import)"
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
        Write-Debug "Imported private function: $($import.Name)"
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
    'Connect-Console',
    'Disconnect-Console',
    'Get-ConsoleSession',
    'Test-ConsoleConnection',
    'Test-ConsoleInternetConnection',
    'Invoke-ConsoleApp',

    # Console Lifecycle
    'Start-Console',
    'Stop-Console',
    'Restart-Console',
    'Get-ConsoleStatus',

    # Diagnostics & Monitoring
    'Get-ConsoleLogs',
    'Get-ConsoleScreenshot',
    'Get-ConsoleDiagnostics'
)
