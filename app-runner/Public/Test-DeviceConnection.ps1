function Test-DeviceConnection {
    <#
    .SYNOPSIS
    Tests if the current device session is active and healthy.

    .DESCRIPTION
    Validates that there is an active device session and that the connection is still valid.

    .EXAMPLE
    Test-DeviceConnection
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CurrentSession) {
        Write-Debug "No active device session"
        return $false
    }

    # Use the provider to test connection
    $provider = $script:CurrentSession.Provider
    $isHealthy = $provider.TestConnection()

    Write-Debug "Device connection health check: $isHealthy"
    return $isHealthy
}