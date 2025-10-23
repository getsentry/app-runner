function Get-DeviceDiagnostics {
    <#
    .SYNOPSIS
    Collects diagnostic information from the device.

    .DESCRIPTION
    This function gathers comprehensive diagnostic data from the device including system info, logs, screenshots, and device status.
    All diagnostic data is saved to multiple files in the specified directory with the naming format: yyyyMMdd-HHmmss-<subject>.<extension>
    Uses the current device session.

    .PARAMETER OutputDirectory
    Directory path where diagnostic files will be saved. If not specified, uses the current directory.
    Multiple files will be created with timestamps and descriptive names.

    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Get-DeviceDiagnostics -OutputDirectory "C:\diagnostics"

    .EXAMPLE
    Connect-Device -Platform "PlayStation5"
    Get-DeviceDiagnostics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory = (Get-Location).Path
    )

    Assert-DeviceSession

    Write-Debug "Collecting diagnostics for device: $($script:CurrentSession.Platform)"
    Write-Debug "Output directory: $OutputDirectory"

    # Ensure output directory exists
    if (-not (Test-Path $OutputDirectory)) {
        Write-Debug "Creating output directory: $OutputDirectory"
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    # Use the provider to collect diagnostics
    $provider = $script:CurrentSession.Provider
    $results = $provider.GetDiagnostics($OutputDirectory)

    if ($results.Files -and $results.Files.Count -gt 0) {
        Write-Host "Diagnostics collected: $($results.Files.Count) file(s) saved to $OutputDirectory"
        foreach ($file in $results.Files) {
            Write-Debug "  - $(Split-Path $file -Leaf)"
        }
    } else {
        Write-Warning 'No diagnostic files were created'
    }

    return $results
}
