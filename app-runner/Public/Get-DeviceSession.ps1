function Get-DeviceSession {
    <#
    .SYNOPSIS
    Gets information about the current device session.

    .DESCRIPTION
    Returns details about the currently active device session, or null if no session is active.

    .EXAMPLE
    Get-DeviceSession
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CurrentSession) {
        Write-Debug "No active device session"
        return $null
    }

    Write-Debug "Current session: $($script:CurrentSession.Platform) (ID: $($script:CurrentSession.SessionId))"
    return $script:CurrentSession
}