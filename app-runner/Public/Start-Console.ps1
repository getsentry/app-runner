function Start-Console {
    <#
    .SYNOPSIS
    Powers on the console and waits for it to be ready.

    .DESCRIPTION
    This function powers on the console and monitors its status until it's ready for use.
    Uses the current console session.


    .EXAMPLE
    Connect-Console -Platform "Xbox"
    Start-Console
    #>
    [CmdletBinding()]
    param()

    Assert-ConsoleSession

    Write-Debug "Starting console: $($script:CurrentSession.Platform)"

    # Use the provider to start the console
    $provider = $script:CurrentSession.Provider
    $provider.StartConsole()

    Write-Output "Console started successfully"
}