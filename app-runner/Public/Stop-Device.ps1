function Stop-Device {
    <#
    .SYNOPSIS
    Powers off the device gracefully.

    .DESCRIPTION
    This function sends a shutdown command to the device and waits for it to power down.
    Uses the current device session.

    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Stop-Device
    #>
    Assert-DeviceSession

    Disconnect-Device -PowerOff
}