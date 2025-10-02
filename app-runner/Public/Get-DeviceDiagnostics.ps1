function Get-DeviceDiagnostics {
    <#
    .SYNOPSIS
    Collects diagnostic information from the device.

    .DESCRIPTION
    This function gathers comprehensive diagnostic data from the device including system info, performance metrics, and error logs.
    Uses the current device session.

    .PARAMETER OutputPath
    Optional path to save diagnostic data to file.

    .PARAMETER IncludePerformanceMetrics
    Include performance metrics in the diagnostic output.

    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Get-DeviceDiagnostics
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$IncludePerformanceMetrics
    )

    Assert-DeviceSession

    Write-Debug "Collecting diagnostics for device: $($script:CurrentSession.Platform)"
    if ($OutputPath) {
        Write-Debug "Output path: $OutputPath"
    }
    if ($IncludePerformanceMetrics) {
        Write-Debug "Including performance metrics"
    }

    # Use the provider to collect diagnostics
    $provider = $script:CurrentSession.Provider
    $diagnostics = $provider.GetDiagnostics($IncludePerformanceMetrics)

    # Save to file if output path is specified
    if ($OutputPath) {
        $diagnostics | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Output "Diagnostics saved to: $OutputPath"
    }

    return $diagnostics
}