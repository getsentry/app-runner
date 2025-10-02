function Restart-Device {
    <#
    .SYNOPSIS
    Restarts the device.

    .DESCRIPTION
    This function performs a graceful restart of the device.
    Uses the current device session.


    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Restart-Device
    #>
    [CmdletBinding()]
    param()

    Assert-DeviceSession

    Write-Debug "Restarting device: $($script:CurrentSession.Platform)"

    # Use the provider to restart the device
    $provider = $script:CurrentSession.Provider
    $provider.RestartDevice()

    Write-Output "Device restarted successfully"
}