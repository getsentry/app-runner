function Test-ConsoleConnection {
    <#
    .SYNOPSIS
    Tests if the current console session is active and healthy.

    .DESCRIPTION
    Validates that there is an active console session and that the connection is still valid.

    .EXAMPLE
    Test-ConsoleConnection
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CurrentSession) {
        Write-Debug "No active console session"
        return $false
    }

    # Use the provider to test connection
    $provider = $script:CurrentSession.Provider
    $isHealthy = $provider.TestConnection()

    Write-Debug "Console connection health check: $isHealthy"
    return $isHealthy
}