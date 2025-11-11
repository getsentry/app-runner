function Copy-DeviceItem {
    <#
    .SYNOPSIS
    Copies a file or directory from the connected device to local filesystem.

    .DESCRIPTION
    Copies a file or directory from the device to a local destination path.

    .PARAMETER DevicePath
    Full path to the file or directory on the device (e.g., "D:\Logs\SentryPlayground.log").

    .PARAMETER Destination
    Local directory where the item will be copied.

    .EXAMPLE
    Copy-DeviceItem -DevicePath "D:\Logs\SentryPlayground.log" -Destination "output/logs"
    $content = Get-Content "output/logs/SentryPlayground.log"

    .EXAMPLE
    Copy-DeviceItem -DevicePath "D:\Logs" -Destination "output"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DevicePath,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Assert-DeviceSession

    Write-Debug "Copying item from device: $DevicePath"
    Write-Debug "Destination: $Destination"

    if (-not (Test-Path $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }

    $provider = $script:CurrentSession.Provider
    $provider.CopyDeviceItem($DevicePath, $Destination)
}
