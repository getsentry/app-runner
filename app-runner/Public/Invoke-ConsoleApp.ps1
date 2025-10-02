function Invoke-ConsoleApp {
    <#
    .SYNOPSIS
    Installs and runs an application on the connected console.

    .DESCRIPTION
    Combines installation and execution of an application on the currently connected console.
    The application is installed (if needed) and then started with the specified arguments.

    .PARAMETER ExecutablePath
    Path to the executable file to run on the console.

    .PARAMETER Arguments
    Arguments to pass to the executable when starting it.

    .EXAMPLE
    Invoke-ConsoleApp -ExecutablePath "MyGame.exe" -Arguments "--debug --level=1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = ""
    )

    Assert-ConsoleSession

    Write-Debug "Running application: $ExecutablePath with arguments: $Arguments"
    Write-Debug "Target platform: $($script:CurrentSession.Platform)"

    # Use the provider to run the application
    $provider = $script:CurrentSession.Provider
    $result = $provider.RunApplication($ExecutablePath, $Arguments)

    return $result
}