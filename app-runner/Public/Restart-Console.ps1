function Restart-Console {
    <#
    .SYNOPSIS
    Restarts the console.

    .DESCRIPTION
    This function performs a graceful restart of the console.
    Uses the current console session.


    .EXAMPLE
    Connect-Console -Platform "Xbox"
    Restart-Console
    #>
    [CmdletBinding()]
    param()

    Assert-ConsoleSession

    Write-Debug "Restarting console: $($script:CurrentSession.Platform)"

    # Use the provider to restart the console
    $provider = $script:CurrentSession.Provider
    $provider.RestartConsole()

    Write-Output "Console restarted successfully"
}