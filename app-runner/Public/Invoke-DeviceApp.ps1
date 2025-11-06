function Invoke-DeviceApp {
    <#
    .SYNOPSIS
    Installs and runs an application on the connected device.

    .DESCRIPTION
    Combines installation and execution of an application on the currently connected device.
    The application is installed (if needed) and then started with the specified arguments.

    .PARAMETER ExecutablePath
    Path to the executable file to run on the device.

    .PARAMETER Arguments
    Arguments to pass to the executable when starting it.

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "MyGame.exe" -Arguments "--debug --level=1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = ""
    )

    Assert-DeviceSession

    Write-Debug "Running application: $ExecutablePath with arguments: $Arguments"
    Write-Debug "Target platform: $($script:CurrentSession.Platform)"

    # Use the provider to run the application
    $provider = $script:CurrentSession.Provider
    $result = $provider.RunApplication($ExecutablePath, $Arguments)

    return $result
}