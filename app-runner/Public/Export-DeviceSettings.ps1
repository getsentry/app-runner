function Export-DeviceSettings {
    <#
    .SYNOPSIS
    Exports the settings of the connected device to a file.

    .DESCRIPTION
    Exports the current settings of the connected device to an XML file.
    Uses the current device session.

    .PARAMETER OutputFile
    Path to the output XML file where settings will be saved.

    .EXAMPLE
    Connect-Device -Platform "PlayStation5"
    Export-DeviceSettings -OutputFile "settings.xml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile
    )

    Assert-DeviceSession

    Write-Debug "Exporting device settings: $($script:CurrentSession.Platform)"
    Write-Debug "Output file: $OutputFile"

    $provider = $script:CurrentSession.Provider
    $provider.ExportSettings($OutputFile)

    Write-Output "Settings exported to: $OutputFile"
}
