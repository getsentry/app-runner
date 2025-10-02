function Get-DeviceScreenshot {
    <#
    .SYNOPSIS
    Takes a screenshot of the device display.

    .DESCRIPTION
    This function captures a screenshot from the device's display output.
    Uses the current device session.

    .PARAMETER OutputPath
    Path to save the screenshot file.


    .EXAMPLE
    Connect-Device -Platform "Xbox"
    Get-DeviceScreenshot -OutputPath "screenshot.png"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath

    )

    Assert-DeviceSession

    Write-Debug "Taking screenshot of device: $($script:CurrentSession.Platform)"
    Write-Debug "Output path: $OutputPath"

    # Use the provider to take a screenshot
    $provider = $script:CurrentSession.Provider
    $provider.TakeScreenshot($OutputPath)

    Write-Output "Screenshot saved to: $OutputPath"
}