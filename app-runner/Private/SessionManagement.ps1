# Session Management Functions
# Handles console connection state and session management


# Module-level variable to store current session
$script:CurrentSession = $null

function Assert-ConsoleSession {
    <#
    .SYNOPSIS
    Internal function to validate that a console session is active.

    .DESCRIPTION
    Throws an error if no console session is active. Used by other functions
    to ensure they have a valid session before executing.

    .EXAMPLE
    Assert-ConsoleSession
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CurrentSession) {
        throw "No active console session. Use Connect-Console to establish a connection first."
    }

    if (-not (Test-ConsoleConnection)) {
        throw "Console session is not healthy. Please reconnect using Connect-Console."
    }

    Write-Debug "Console session validation passed"
}