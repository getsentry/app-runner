function Stop-DeviceApp {
    <#
    .SYNOPSIS
    Stops the application running on the connected device.

    .DESCRIPTION
    Terminates the application currently running on the connected device, using the
    current device session. Platforms that don't support this write a warning and return.

    This is required after a crash on Nintendo Switch 2 (Ounce) devkits: the crashed
    process stays held in debug mode and keeps the network use request, which prevents the
    devkit from uploading the crash report. Terminating it releases the request so the
    report gets forwarded.

    .EXAMPLE
    Connect-Device -Platform Switch
    Invoke-DeviceApp -ExecutablePath "Game.nsp" -Arguments "crash-capture"
    Stop-DeviceApp

    .EXAMPLE
    # Terminating may fail if nothing is running - don't let that abort the caller.
    try { Stop-DeviceApp } catch { Write-Warning "Failed to stop app: $_" }
    #>
    [CmdletBinding()]
    param()

    Assert-DeviceSession

    Write-Debug "Stopping application on platform: $($script:CurrentSession.Platform)"

    $provider = $script:CurrentSession.Provider
    $provider.StopApplication()
}
