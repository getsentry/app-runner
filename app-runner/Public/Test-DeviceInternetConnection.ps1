# Test-DeviceInternetConnection.ps1
# Tests if the connected device has internet connectivity


<#
.SYNOPSIS
Tests if the connected device has internet connectivity.

.DESCRIPTION
This cmdlet tests if the connected device has internet connectivity by running platform-specific
network connectivity checks. It uses the active device session to perform the test.

.EXAMPLE
Test-DeviceInternetConnection
Tests internet connectivity on the current device session.

.OUTPUTS
System.Boolean
Returns $true if internet connectivity is confirmed, $false otherwise.

.NOTES
Requires an active device session established with Connect-Device.
#>
function Test-DeviceInternetConnection {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Validate active session
    Assert-DeviceSession

    try {
        Write-Debug "Testing internet connectivity on $($script:CurrentSession.Platform)"

        $result = $script:CurrentSession.Provider.TestInternetConnection()

        if ($result) {
            Write-Verbose "Internet connection confirmed on $($script:CurrentSession.Platform)"
        } else {
            Write-Verbose "No internet connection detected on $($script:CurrentSession.Platform)"
        }

        return $result
    } catch {
        Write-Error "Failed to test internet connectivity: $_"
        throw
    }
}