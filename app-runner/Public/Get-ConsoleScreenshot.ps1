function Get-ConsoleScreenshot {
    <#
    .SYNOPSIS
    Takes a screenshot of the console display.

    .DESCRIPTION
    This function captures a screenshot from the console's display output.
    Uses the current console session.

    .PARAMETER OutputPath
    Path to save the screenshot file.


    .EXAMPLE
    Connect-Console -Platform "Xbox"
    Get-ConsoleScreenshot -OutputPath "screenshot.png"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath

    )

    Assert-ConsoleSession

    Write-Debug "Taking screenshot of console: $($script:CurrentSession.Platform)"
    Write-Debug "Output path: $OutputPath"
    
    # Use the provider to take a screenshot
    $provider = $script:CurrentSession.Provider
    $provider.TakeScreenshot($OutputPath)

    Write-Output "Screenshot saved to: $OutputPath"
}