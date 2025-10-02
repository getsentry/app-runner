function Disconnect-Device {
    <#
    .SYNOPSIS
    Disconnects from the current device session.

    .DESCRIPTION
    Closes the current device session and cleans up any associated resources.
    Optionally powers off the device before disconnecting.

    .PARAMETER PowerOff
    Powers off the device before disconnecting from the session.

    .EXAMPLE
    Disconnect-Device

    .EXAMPLE
    Disconnect-Device -PowerOff
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$PowerOff
    )

    if (-not $script:CurrentSession) {
        Write-Warning "No active device session to disconnect"
        return
    }

    Write-Debug "Disconnecting from device: $($script:CurrentSession.Identifier)"

    # Use the provider to disconnect
    $provider = $script:CurrentSession.Provider
    $platform = $script:CurrentSession.Platform

    try {
        # Power off device first if requested
        if ($PowerOff) {
            Write-Debug "Powering off device before disconnect"
            $provider.StopDevice()
            Write-Output "Device powered off"
        }
        $provider.Disconnect()
    } finally {
        $script:CurrentSession = $null

        Write-Debug "Successfully disconnected from $platform device"
        Write-Output "Disconnected from device"
    }
}