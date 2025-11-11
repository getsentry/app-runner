# Initialize Sentry telemetry (opt-in)
try {
    Import-Module (Join-Path $PSScriptRoot '..\utils\TrySentry.psm1') -ErrorAction Stop
    $moduleManifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'SentryApiClient.psd1')
    TrySentry\Start-Sentry -Dsn $env:SENTRY_API_CLIENT_DSN -ModuleName 'SentryApiClient' -ModuleVersion $moduleManifest.ModuleVersion
} catch {
    Write-Debug "Sentry telemetry initialization failed: $_"
}

$Script:SentryApiConfig = @{
    BaseUrl = 'https://sentry.io/api/0'
    ApiToken = $null
    Organization = $null
    Project = $null
    Headers = @{}
}

$PublicFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)

foreach ($Function in @($PublicFunctions + $PrivateFunctions)) {
    try {
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import function $($Function.FullName): $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $PublicFunctions.BaseName
