function Import-DeviceSettings {
    <#
    .SYNOPSIS
    Imports settings from a file to the connected device.

    .DESCRIPTION
    Imports settings from an XML file to the connected device.
    Uses the current device session.

    .PARAMETER InputFile
    Path to the input XML file containing settings to import.

    .EXAMPLE
    Connect-Device -Platform "PlayStation5"
    Import-DeviceSettings -InputFile "settings.xml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputFile
    )

    Assert-DeviceSession

    Write-Debug "Importing device settings: $($script:CurrentSession.Platform)"
    Write-Debug "Input file: $InputFile"

    $provider = $script:CurrentSession.Provider
    $provider.ImportSettings($InputFile)

    Write-Output "Settings imported from: $InputFile"
}
