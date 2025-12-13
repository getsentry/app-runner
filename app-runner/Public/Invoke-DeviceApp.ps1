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
    Array of arguments to pass to the executable when starting it.

    .PARAMETER LogFilePath
    Optional path to a log file on the device to retrieve instead of using system logs (syslog/logcat).
    Path format is platform-specific:
    - iOS: Use bundle format like "@com.example.app:documents/logs/app.log"
    - Android: Use absolute path like "/data/data/com.example.app/files/logs/app.log"

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "MyGame.exe" -Arguments @("--debug", "--level=1")

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "com.example.app" -LogFilePath "@com.example.app:documents/logs/app.log"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = $null
    )

    Assert-DeviceSession

    Write-Debug "Running application: $ExecutablePath with arguments: $Arguments"
    Write-Debug "Target platform: $($script:CurrentSession.Platform)"

    Write-GitHub "::group::Run log"

    # Use the provider to run the application
    $provider = $script:CurrentSession.Provider
    $result = $provider.RunApplication($ExecutablePath, $Arguments, $LogFilePath)

    Write-GitHub "::endgroup::"

    return $result
}
