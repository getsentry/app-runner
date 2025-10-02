function Get-DeviceStatus {
    <#
    .SYNOPSIS
    Gets the current status of the device.

    .DESCRIPTION
    This function retrieves the current operational status of the device.
    Uses the current device session.

    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Get-DeviceStatus
    #>
    [CmdletBinding()]
    param()

    Assert-DeviceSession

    Write-Debug "Getting status for device: $($script:CurrentSession.Platform)"

    # Use the provider to get device status
    $provider = $script:CurrentSession.Provider
    $status = $provider.GetDeviceStatus()

    return $status
}