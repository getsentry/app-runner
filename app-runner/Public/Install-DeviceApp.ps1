function Install-DeviceApp {
    <#
    .SYNOPSIS
    Installs a packaged application to the connected device.

    .DESCRIPTION
    Installs a packaged application (e.g., .xvc for Xbox, .pkg for PlayStation) to the currently connected device.
    The device must be connected using Connect-Device before calling this function.

    .PARAMETER Path
    Path to the package file to install.

    .EXAMPLE
    Install-DeviceApp -Path "C:\builds\MyGame.xvc"

    .NOTES
    This function requires an active device session. Use Connect-Device first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Assert-DeviceSession

    Write-Debug "Installing app from: $Path"

    $session = Get-DeviceSession
    return $session.Provider.InstallApp($Path)
}
