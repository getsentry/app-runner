function Get-ConsoleSession {
    <#
    .SYNOPSIS
    Gets information about the current console session.

    .DESCRIPTION
    Returns details about the currently active console session, or null if no session is active.

    .EXAMPLE
    Get-ConsoleSession
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CurrentSession) {
        Write-Debug "No active console session"
        return $null
    }

    Write-Debug "Current session: $($script:CurrentSession.Platform) (ID: $($script:CurrentSession.SessionId))"
    return $script:CurrentSession
}