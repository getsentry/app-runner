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

    TrySentry\Add-SentryBreadcrumb -Message "Starting application deployment" -Category "app" -Data @{
        executable = (Split-Path -Leaf $ExecutablePath)
        platform = $script:CurrentSession.Platform
        has_arguments = ($Arguments.Length -gt 0)
    }

    # Use the provider to run the application
    $provider = $script:CurrentSession.Provider

    TrySentry\Add-SentryBreadcrumb -Message "Invoking application on device" -Category "app" -Data @{
        executable = (Split-Path -Leaf $ExecutablePath)
        platform = $script:CurrentSession.Platform
    }

    $result = $provider.RunApplication($ExecutablePath, $Arguments)

    TrySentry\Add-SentryBreadcrumb -Message "Application execution completed" -Category "app" -Data @{
        executable = (Split-Path -Leaf $ExecutablePath)
        exit_code = $result.ExitCode
    }

    return $result
}