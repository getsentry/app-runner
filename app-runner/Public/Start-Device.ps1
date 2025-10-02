function Start-Device {
    <#
    .SYNOPSIS
    Powers on the device and waits for it to be ready.

    .DESCRIPTION
    This function powers on the device and monitors its status until it's ready for use.
    Uses the current device session.


    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Start-Device
    #>
    [CmdletBinding()]
    param()

    Assert-DeviceSession

    Write-Debug "Starting device: $($script:CurrentSession.Platform)"

    # Use the provider to start the device
    $provider = $script:CurrentSession.Provider
    $provider.StartDevice()

    Write-Output "Device started successfully"
}