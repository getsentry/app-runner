function Get-ConsoleStatus {
    <#
    .SYNOPSIS
    Gets the current status of the console.

    .DESCRIPTION
    This function retrieves the current operational status of the console.
    Uses the current console session.

    .EXAMPLE
    Connect-Console -Platform "Xbox"
    Get-ConsoleStatus
    #>
    [CmdletBinding()]
    param()

    Assert-ConsoleSession

    Write-Debug "Getting status for console: $($script:CurrentSession.Platform)"

    # Use the provider to get console status
    $provider = $script:CurrentSession.Provider
    $status = $provider.GetConsoleStatus()

    return $status
}