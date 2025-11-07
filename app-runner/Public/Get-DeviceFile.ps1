function Get-DeviceFile {
    <#
    .SYNOPSIS
    Retrieves a file from the connected device.

    .DESCRIPTION
    Copies a file from the device to a local directory and returns its content.

    .PARAMETER DeviceFilePath
    Full path to the file on the device (e.g., "D:\Logs\SentryPlayground.log").

    .PARAMETER OutputDirectory
    Local directory where the file will be copied.

    .OUTPUTS
    Array of strings containing the file content (lines), or empty array if file not found.

    .EXAMPLE
    Get-DeviceFile -DeviceFilePath "D:\Logs\SentryPlayground.log" -OutputDirectory "output/logs"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceFilePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    Assert-DeviceSession

    Write-Debug "Retrieving file from device: $DeviceFilePath"
    Write-Debug "Output directory: $OutputDirectory"

    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    $provider = $script:CurrentSession.Provider
    return $provider.GetDeviceFile($DeviceFilePath, $OutputDirectory)
}
