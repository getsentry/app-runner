function Disconnect-Console {
    <#
    .SYNOPSIS
    Disconnects from the current console session.

    .DESCRIPTION
    Closes the current console session and cleans up any associated resources.
    Optionally powers off the console before disconnecting.

    .PARAMETER PowerOff
    Powers off the console before disconnecting from the session.

    .EXAMPLE
    Disconnect-Console

    .EXAMPLE
    Disconnect-Console -PowerOff
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$PowerOff
    )

    if (-not $script:CurrentSession) {
        Write-Warning "No active console session to disconnect"
        return
    }

    Write-Debug "Disconnecting from console: $($script:CurrentSession.Identifier)"

    # Use the provider to disconnect
    $provider = $script:CurrentSession.Provider
    $platform = $script:CurrentSession.Platform

    try {
        # Power off console first if requested
        if ($PowerOff) {
            Write-Debug "Powering off console before disconnect"
            $provider.StopConsole()
            Write-Output "Console powered off"
        }
        $provider.Disconnect()
    } finally {
        $script:CurrentSession = $null

        Write-Debug "Successfully disconnected from $platform console"
        Write-Output "Disconnected from console"
    }
}