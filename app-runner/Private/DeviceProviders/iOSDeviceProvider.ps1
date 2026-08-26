# iOS Device Provider Implementation
# Provides device management for physical iOS devices via xcrun devicectl

. "$PSScriptRoot\DeviceProvider.ps1"

<#
.SYNOPSIS
Device provider for physical iOS devices via xcrun devicectl.

.DESCRIPTION
This provider installs and launches signed .app bundles on paired physical iOS
devices. Devices must have Developer Mode enabled and be visible to CoreDevice.
#>
class iOSDeviceProvider : DeviceProvider {
    [string]$DeviceIdentifier = $null
    [string]$DeviceName = $null
    [string]$CurrentBundleId = $null

    iOSDeviceProvider() {
        $this.Platform = 'iOSDevice'
        $this.SdkPath = $null
        $this.Timeouts = @{
            'command-timeout' = 60
            'run-timeout'     = 300
        }

        if (-not $global:IsMacOS) {
            throw 'iOSDevice provider is only supported on macOS'
        }

        if (-not (Get-Command 'xcrun' -ErrorAction SilentlyContinue)) {
            throw 'xcrun not found in PATH. Please install Xcode Command Line Tools.'
        }
    }

    [hashtable] Connect() {
        return $this.SelectAndConnect($null)
    }

    [hashtable] Connect([string]$target) {
        return $this.SelectAndConnect($target)
    }

    hidden [hashtable] SelectAndConnect([string]$target) {
        $devices = @($this.GetAvailableDevices())
        if ($devices.Count -eq 0) {
            throw 'No paired physical iOS devices with Developer Mode enabled were found.'
        }

        if (-not [string]::IsNullOrEmpty($target)) {
            $devices = @($devices | Where-Object {
                    $_.identifier -eq $target -or
                    $_.hardwareProperties.udid -eq $target -or
                    $_.hardwareProperties.ecid -eq $target -or
                    $_.hardwareProperties.serialNumber -eq $target -or
                    $_.deviceProperties.name -eq $target -or
                    $_.connectionProperties.potentialHostnames -contains $target
                })
        }

        if ($devices.Count -eq 0) {
            throw "No available physical iOS device matched target '$target'."
        }

        if ($devices.Count -gt 1) {
            $names = $devices | ForEach-Object { $_.deviceProperties.name }
            throw "Multiple physical iOS devices are available ($($names -join ', ')). Specify -Target."
        }

        $device = $devices[0]
        $this.DeviceIdentifier = "$($device.identifier)"
        $this.DeviceName = "$($device.deviceProperties.name)"

        Write-Host "Connected to physical iOS device: $($this.DeviceName)" -ForegroundColor Green
        return $this.CreateSessionInfo()
    }

    [void] Disconnect() {
        $this.DeviceIdentifier = $null
        $this.DeviceName = $null
        $this.CurrentBundleId = $null
    }

    [bool] TestConnection() {
        if ([string]::IsNullOrEmpty($this.DeviceIdentifier)) {
            return $false
        }

        try {
            return $this.GetDeviceStatus().Status -eq 'Online'
        } catch {
            return $false
        }
    }

    [hashtable] InstallApp([string]$PackagePath) {
        if (-not (Test-Path $PackagePath -PathType Container)) {
            throw "App bundle not found: $PackagePath"
        }

        if ($PackagePath -notlike '*.app') {
            throw "iOSDevice requires a signed .app bundle directory. Got: $PackagePath"
        }

        $infoPlist = Join-Path $PackagePath 'Info.plist'
        if (-not (Test-Path $infoPlist -PathType Leaf)) {
            throw "Invalid .app bundle: Info.plist not found in $PackagePath"
        }

        $bundleId = & /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $infoPlist 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to read the bundle identifier from $infoPlist"
        }
        $bundleId = "$bundleId".Trim()

        $installed = $this.InvokeDevicectlJson(@(
                'device', 'info', 'apps',
                '--device', $this.DeviceIdentifier,
                '--bundle-id', $bundleId,
                '--timeout', "$($this.Timeouts['command-timeout'])"
            ))
        if (@($installed.result.apps).Count -gt 0) {
            Write-Host "Uninstalling previous version: $bundleId" -ForegroundColor Yellow
            $this.InvokeDevicectlJson(@(
                    'device', 'uninstall', 'app',
                    '--device', $this.DeviceIdentifier,
                    $bundleId,
                    '--timeout', "$($this.Timeouts['command-timeout'])"
                )) | Out-Null
        }

        Write-Host "Installing app on $($this.DeviceName): $bundleId" -ForegroundColor Yellow
        $this.InvokeDevicectlJson(@(
                'device', 'install', 'app',
                '--device', $this.DeviceIdentifier,
                $PackagePath,
                '--timeout', "$($this.Timeouts['command-timeout'])"
            )) | Out-Null

        $this.CurrentBundleId = $bundleId
        return @{
            PackagePath      = $PackagePath
            BundleId         = $bundleId
            DeviceIdentifier = $this.DeviceIdentifier
        }
    }

    [hashtable] RunApplication([string]$ExecutablePath, [string[]]$Arguments, [string]$LogFilePath = $null, [string]$WorkingDirectory = $null) {
        if (-not [string]::IsNullOrEmpty($LogFilePath)) {
            Write-Warning 'LogFilePath parameter is not supported on this platform.'
        }
        if (-not [string]::IsNullOrEmpty($WorkingDirectory)) {
            Write-Warning 'WorkingDirectory parameter is not supported on this platform.'
        }

        $this.CurrentBundleId = $ExecutablePath
        $timeoutSeconds = $this.Timeouts['run-timeout']
        $startTime = Get-Date

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'xcrun'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        @(
            'devicectl', 'device', 'process', 'launch',
            '--device', $this.DeviceIdentifier,
            '--terminate-existing',
            '--console',
            '--timeout', "$timeoutSeconds",
            $ExecutablePath
        ) + $Arguments | ForEach-Object { $startInfo.ArgumentList.Add($_) }

        Write-Host "Launching on $($this.DeviceName): $ExecutablePath" -ForegroundColor Cyan
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()

        $timedOut = -not $process.WaitForExit($timeoutSeconds * 1000)
        if ($timedOut) {
            Write-Warning "App timed out after $timeoutSeconds seconds"
            $process.Kill($true)
            $process.WaitForExit()
        }

        [System.Threading.Tasks.Task]::WaitAll(@($stdout, $stderr))
        $output = @($stdout.Result, $stderr.Result) |
            Where-Object { -not [string]::IsNullOrEmpty($_) } |
            ForEach-Object { $_ -split "`r?`n" } |
            Where-Object { $_.Length -gt 0 }

        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startTime
            FinishedAt     = Get-Date
            Output         = @($output)
            ExitCode       = if ($timedOut) { -1 } else { $process.ExitCode }
        }
    }

    [hashtable] GetDeviceStatus() {
        $device = @($this.GetAvailableDevices() | Where-Object {
                $_.identifier -eq $this.DeviceIdentifier
            }) | Select-Object -First 1

        return @{
            Platform   = $this.Platform
            Status     = if ($device) { 'Online' } else { 'Offline' }
            StatusData = $device
            Timestamp  = Get-Date
        }
    }

    [string] GetDeviceIdentifier() {
        return $this.DeviceIdentifier
    }

    [void] StartDevice() {
        Write-Debug 'iOSDevice: StartDevice is not applicable to a physical device'
    }

    [void] StopDevice() {
        Write-Debug 'iOSDevice: StopDevice is not applicable to a physical device'
    }

    [void] RestartDevice() {
        Write-Warning 'RestartDevice is not supported for iOSDevice.'
    }

    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        return @{
            Platform  = $this.Platform
            LogType   = $LogType
            Logs      = @()
            Count     = 0
            Timestamp = Get-Date
        }
    }

    hidden [object[]] GetAvailableDevices() {
        $result = $this.InvokeDevicectlJson(@(
                'list', 'devices',
                '--timeout', "$($this.Timeouts['command-timeout'])"
            ))

        return @($result.result.devices | Where-Object {
                $_.hardwareProperties.platform -eq 'iOS' -and
                $_.connectionProperties.pairingState -eq 'paired' -and
                $_.deviceProperties.developerModeStatus -eq 'enabled'
            })
    }

    hidden [object] InvokeDevicectlJson([string[]]$arguments) {
        $jsonFile = New-TemporaryFile
        try {
            $output = $null
            $exitCode = $null
            try {
                $PSNativeCommandUseErrorActionPreference = $false
                $output = & xcrun devicectl @arguments --json-output $jsonFile.FullName --quiet 2>&1
                $exitCode = $LASTEXITCODE
            } finally {
                $PSNativeCommandUseErrorActionPreference = $true
            }

            $result = if ($jsonFile.Length -gt 0) {
                Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json
            } else {
                $null
            }

            if ($exitCode -ne 0) {
                $details = if ($result.info.errors) {
                    $result.info.errors | ForEach-Object { $_.description }
                } else {
                    $output
                }
                throw "devicectl failed with exit code ${exitCode}: $($details -join [Environment]::NewLine)"
            }

            if (-not $result) {
                throw 'devicectl did not produce JSON output.'
            }

            return $result
        } finally {
            Remove-Item $jsonFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}
