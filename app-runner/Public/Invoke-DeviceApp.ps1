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
    The caller is responsible for quoting/escaping the arguments.
    For example, if the executable requires arguments with spaces, they should be quoted:
    Invoke-DeviceApp -ExecutablePath "Game.exe" -Arguments @('"/path/to/some file.txt"', '--debug')

    .PARAMETER LogFilePath
    Optional path to a log file on the device to retrieve instead of using system logs (syslog/logcat).
    This parameter is only supported on SauceLabs platforms for now.
    Path format is platform-specific:
    - iOS: Use bundle format like "@com.example.app:documents/logs/app.log"
    - Android: Use absolute path like "/data/data/com.example.app/files/logs/app.log"

    .PARAMETER WorkingDirectory
    Optional path to a working directory on the host PC that contains additional files required by the application.
    This parameter is currently only supported on PlayStation 5 for Unreal Engine applications that need
    access to cooked content (PAK files, configs, etc.) via the /app0/ virtual path.

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "MyGame.exe" -Arguments @("--debug", "--level=1")

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "MyGame.exe" -Arguments "--debug --level=1"

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "com.example.app" -LogFilePath "@com.example.app:documents/logs/app.log"

    .EXAMPLE
    Invoke-DeviceApp -ExecutablePath "Game.self" -Arguments @("-unattended") -WorkingDirectory "C:\Build\StagedBuilds\PS5"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = $null,

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $null
    )

    Assert-DeviceSession

    Write-Debug "Running application: $ExecutablePath with arguments: $Arguments"
    Write-Debug "Target platform: $($script:CurrentSession.Platform)"

    Write-GitHub "::group::Run log"

    # Use the provider to run the application
    $provider = $script:CurrentSession.Provider
    $result = $provider.RunApplication($ExecutablePath, $Arguments, $LogFilePath, $WorkingDirectory)

    Write-GitHub "::endgroup::"

    return $result
}
