function Stop-Console {
    <#
    .SYNOPSIS
    Powers off the console gracefully.

    .DESCRIPTION
    This function sends a shutdown command to the console and waits for it to power down.
    Uses the current console session.

    .EXAMPLE
    Connect-Console -Platform "Xbox"
    Stop-Console
    #>
    Assert-ConsoleSession

    Disconnect-Console -PowerOff
}