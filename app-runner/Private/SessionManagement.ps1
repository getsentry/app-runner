# Session Management Functions
# Handles device connection state and session management


# Module-level variable to store current session
$script:CurrentSession = $null

function Assert-DeviceSession {
    <#
    .SYNOPSIS
    Internal function to validate that a device session is active.

    .DESCRIPTION
    Throws an error if no device session is active. Used by other functions
    to ensure they have a valid session before executing.

    .EXAMPLE
    Assert-DeviceSession
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CurrentSession) {
        throw "No active device session. Use Connect-Device to establish a connection first."
    }

    if (-not (Test-DeviceConnection)) {
        throw "Device session is not healthy. Please reconnect using Connect-Device."
    }

    Write-Debug "Device session validation passed"
}