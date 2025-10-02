function Get-DeviceLogs {
    <#
    .SYNOPSIS
    Retrieves logs from the device.

    .DESCRIPTION
    This function collects various types of logs from the device including system logs, application logs, and error logs.
    Uses the current device session.

    .PARAMETER LogType
    Type of logs to collect (System, Application, Error, All).

    .PARAMETER StartTime
    Start time for log collection (default: last 24 hours).

    .PARAMETER EndTime
    End time for log collection (default: current time).

    .PARAMETER OutputPath
    Optional path to save logs to file.

    .PARAMETER MaxEntries
    Maximum number of log entries to retrieve (default: 1000).

    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Get-DeviceLogs -LogType "Error"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("System", "Application", "Error", "All")]
        [string]$LogType = "All",

        [Parameter(Mandatory = $false)]
        [DateTime]$StartTime = (Get-Date).AddDays(-1),

        [Parameter(Mandatory = $false)]
        [DateTime]$EndTime = (Get-Date),

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxEntries = 1000
    )

    Assert-DeviceSession

    Write-Debug "Collecting logs for device: $($script:CurrentSession.Platform)"
    Write-Debug "Log type: $LogType, Start: $StartTime, End: $EndTime"
    Write-Debug "Max entries: $MaxEntries"
    if ($OutputPath) {
        Write-Debug "Output path: $OutputPath"
    }
    # Use the provider to get device logs
    $provider = $script:CurrentSession.Provider
    $logs = $provider.GetDeviceLogs($LogType, $MaxEntries)

    # Save to file if output path is specified
    if ($OutputPath) {
        $logs | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Debug "Device logs saved to: $OutputPath"
    }

    return $logs
}