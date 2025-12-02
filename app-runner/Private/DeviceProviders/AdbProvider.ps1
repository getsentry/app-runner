# Android ADB Provider Implementation
# Provides device management for Android devices/emulators via ADB

# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

# Load Android helpers
. "$PSScriptRoot\..\AndroidHelpers.ps1"

<#
.SYNOPSIS
Device provider for Android devices and emulators via ADB (Android Debug Bridge).

.DESCRIPTION
This provider implements Android-specific device operations using ADB commands.
It supports both physical devices connected via USB and emulators running locally.

Key features:
- Auto-discovery of connected devices
- APK installation with automatic cleanup of previous versions
- App execution with logcat monitoring
- Screenshot capture and file transfer
- Device status and diagnostics

Requirements:
- ADB (Android Debug Bridge) must be installed and in PATH
- Android device or emulator connected and visible via 'adb devices'
- USB debugging enabled on physical devices
#>
class AdbProvider : DeviceProvider {
    [string]$DeviceSerial = $null
    [string]$CurrentPackageName = $null  # Track current app package for monitoring

    AdbProvider() {
        $this.Platform = 'Adb'

        # ADB should be in PATH - no SDK path needed
        $this.SdkPath = $null

        # Configure ADB commands
        # Format: 'action' = @('tool', 'arguments', optional-processing-scriptblock)
        $this.Commands = @{
            # Device management
            'list-devices'  = @('adb', 'devices')
            'getstatus'     = @('adb', '-s {0} shell getprop')
            'reboot'        = @('adb', '-s {0} reboot')

            # Package management
            'list-packages' = @('adb', '-s {0} shell pm list packages')
            'install'       = @('adb', '-s {0} install {1}')
            'uninstall'     = @('adb', '-s {0} uninstall {1}')

            # App execution
            'launch'        = @('adb', '-s {0} shell am start -n {1} {2} -W')
            'pidof'         = @('adb', '-s {0} shell pidof {1}')

            # Logging
            'logcat'        = @('adb', '-s {0} logcat -d')
            'logcat-pid'    = @('adb', '-s {0} logcat -d --pid={1}')
            'logcat-clear'  = @('adb', '-s {0} logcat -c')

            # Diagnostics
            'screenshot'    = @('adb', '-s {0} shell screencap -p {1}')
            'pull'          = @('adb', '-s {0} pull {1} {2}')
            'rm'            = @('adb', '-s {0} shell rm {1}')
            'ping'          = @('adb', '-s {0} shell ping -c 1 {1}')
            'ps'            = @('adb', '-s {0} shell ps')
        }

        # Configure timeouts for slow operations
        $this.Timeouts = @{
            'launch'                 = 180  # App launch can take time on slower devices
            'install'                = 300  # APK installation can be slow for large apps
            'run-timeout'            = 300  # Maximum time to wait for app execution
            'pid-retry'              = 30   # Time to wait for process ID to appear
            'process-check-interval' = 2    # Interval between process status checks
        }
    }

    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Auto-discovering connected device"

        # Get list of connected devices
        $output = $this.InvokeCommand('list-devices', @())

        # Parse 'adb devices' output
        # Format: "device_serial\tdevice" (skip header line)
        # Wrap in @() to ensure array type even with single device
        $devices = @($output | Where-Object { $_ -match '\tdevice$' } | ForEach-Object { ($_ -split '\t')[0] })

        if ($null -eq $devices -or $devices.Count -eq 0) {
            throw "No Android devices found. Ensure a device or emulator is connected and visible via 'adb devices'"
        }

        if ($devices.Count -gt 1) {
            Write-Warning "$($this.Platform): Multiple devices found, using first one: $($devices[0])"
        }

        $this.DeviceSerial = $devices[0]
        Write-Debug "$($this.Platform): Connected to device: $($this.DeviceSerial)"

        return $this.CreateSessionInfo()
    }

    [hashtable] Connect([string]$target) {
        # If no target specified, fall back to auto-discovery
        if ([string]::IsNullOrEmpty($target)) {
            Write-Debug "$($this.Platform): No target specified, falling back to auto-discovery"
            return $this.Connect()
        }

        Write-Debug "$($this.Platform): Connecting to specific device: $target"

        # Validate that the specified device exists
        $output = $this.InvokeCommand('list-devices', @())
        # Wrap in @() to ensure array type even with single device
        $devices = @($output | Where-Object { $_ -match '\tdevice$' } | ForEach-Object { ($_ -split '\t')[0] })

        if ($devices -notcontains $target) {
            throw "Device '$target' not found. Available devices: $($devices -join ', ')"
        }

        $this.DeviceSerial = $target
        Write-Debug "$($this.Platform): Connected to device: $($this.DeviceSerial)"

        return $this.CreateSessionInfo()
    }

    [void] Disconnect() {
        Write-Debug "$($this.Platform): Disconnecting (no-op for ADB)"
        $this.DeviceSerial = $null
        $this.CurrentPackageName = $null
    }

    [bool] TestConnection() {
        Write-Debug "$($this.Platform): Testing connection to device"

        try {
            $this.InvokeCommand('getstatus', @($this.DeviceSerial))
            return $true
        }
        catch {
            return $false
        }
    }

    [hashtable] InstallApp([string]$PackagePath) {
        Write-Debug "$($this.Platform): Installing APK: $PackagePath"

        # Validate APK file
        if (-not (Test-Path $PackagePath)) {
            throw "APK file not found: $PackagePath"
        }

        if ($PackagePath -notlike '*.apk') {
            throw "Package must be an .apk file. Got: $PackagePath"
        }

        # Extract actual package name from APK
        $packageName = Get-ApkPackageName -ApkPath $PackagePath

        # Check for existing installation
        Write-Debug "$($this.Platform): Checking for existing package: $packageName"
        $listOutput = $this.InvokeCommand('list-packages', @($this.DeviceSerial))
        $existingPackage = $listOutput | Where-Object { $_ -eq "package:$packageName" } | Select-Object -First 1

        if ($existingPackage) {
            Write-Host "Uninstalling previous version: $packageName" -ForegroundColor Yellow

            try {
                $this.InvokeCommand('uninstall', @($this.DeviceSerial, $packageName))
            }
            catch {
                Write-Warning "Failed to uninstall previous version: $_"
            }

            Start-Sleep -Seconds 1
        }

        # Install APK
        Write-Host "Installing APK to device: $($this.DeviceSerial)" -ForegroundColor Yellow
        $installOutput = $this.InvokeCommand('install', @($this.DeviceSerial, $PackagePath))

        # Verify installation
        # Join output to string first since -match on arrays returns matching elements, not boolean
        if (($installOutput -join "`n") -notmatch 'Success') {
            throw "Failed to install APK. Output: $($installOutput -join "`n")"
        }

        Write-Host "APK installed successfully" -ForegroundColor Green

        return @{
            PackagePath  = $PackagePath
            DeviceSerial = $this.DeviceSerial
        }
    }

    [hashtable] RunApplication([string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "$($this.Platform): Running application: $ExecutablePath"

        # Parse ExecutablePath: "package.name/activity.name"
        $parsed = ConvertFrom-AndroidActivityPath -ExecutablePath $ExecutablePath
        $packageName = $parsed.PackageName
        $activityName = $parsed.ActivityName
        $this.CurrentPackageName = $packageName

        # Validate Intent extras format
        if ($Arguments) {
            Test-IntentExtrasFormat -Arguments $Arguments | Out-Null
        }

        $timeoutSeconds = $this.Timeouts['run-timeout']
        $pidRetrySeconds = $this.Timeouts['pid-retry']
        $processCheckIntervalSeconds = $this.Timeouts['process-check-interval']

        $startTime = Get-Date

        # Clear logcat before launch
        Write-Debug "$($this.Platform): Clearing logcat"
        $this.InvokeCommand('logcat-clear', @($this.DeviceSerial))

        # Launch activity
        Write-Host "Launching: $ExecutablePath" -ForegroundColor Cyan
        if ($Arguments) {
            Write-Host "  Arguments: $Arguments" -ForegroundColor Cyan
        }

        $launchOutput = $this.InvokeCommand('launch', @($this.DeviceSerial, $ExecutablePath, $Arguments))

        # Join output to string first since -match on arrays returns matching elements, not boolean
        if (($launchOutput -join "`n") -match 'Error') {
            throw "Failed to start activity: $($launchOutput -join "`n")"
        }

        # Wait for process to appear
        Write-Debug "$($this.Platform): Waiting for app process..."

        $appPID = $this.WaitForProcess($packageName, $pidRetrySeconds)

        # Initialize log cache
        [array]$logCache = @()

        if (-not $appPID) {
            # App might have already exited (fast execution) - capture logs anyway
            Write-Warning "Could not find process ID (app may have exited quickly)" -ForegroundColor Yellow
            $logCache = @($this.InvokeCommand('logcat', @($this.DeviceSerial)))
            $exitCode = 0
        }
        else {
            Write-Host "App PID: $appPID" -ForegroundColor Green

            # Monitor process until it exits (generic approach - no app-specific log checking)
            Write-Host "Monitoring app execution..." -ForegroundColor Yellow
            $processExited = $false

            while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($timeoutSeconds)) {
                # Check if process still exists
                try {
                    $pidCheck = $this.InvokeCommand('pidof', @($this.DeviceSerial, $packageName))

                    if (-not $pidCheck) {
                        # Process exited
                        Write-Host "App process exited" -ForegroundColor Green
                        $processExited = $true
                        break
                    }
                }
                catch {
                    # Process not found - assume exited
                    Write-Host "App process exited" -ForegroundColor Green
                    $processExited = $true
                    break
                }

                Start-Sleep -Seconds $processCheckIntervalSeconds
            }

            if (-not $processExited) {
                Write-Host "Warning: Process did not exit within timeout" -ForegroundColor Yellow
            }

            # Fetch all logs after app completes
            Write-Host "Retrieving logs..." -ForegroundColor Yellow
            $logCache = @($this.InvokeCommand('logcat-pid', @($this.DeviceSerial, $appPID)))
            Write-Host "Retrieved $($logCache.Count) log lines" -ForegroundColor Cyan

            Write-Host "Android doesn't report exit codes via adb so exit code is always NULL"
            $exitCode = $null
        }

        # Format logs consistently
        $formattedLogs = Format-LogcatOutput -LogcatOutput $logCache

        # Return result matching app-runner pattern
        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startTime
            FinishedAt     = Get-Date
            Output         = $formattedLogs
            ExitCode       = $exitCode
        }
    }

    # Helper method to wait for process with retry
    [string] WaitForProcess([string]$packageName, [int]$timeoutSeconds) {
        Write-Debug "$($this.Platform): Waiting for process: $packageName"

        for ($i = 0; $i -lt $timeoutSeconds; $i++) {
            try {
                $pidOutput = $this.InvokeCommand('pidof', @($this.DeviceSerial, $packageName))

                if ($pidOutput) {
                    $processId = $pidOutput.ToString().Trim()
                    if ($processId -match '^\d+$') {
                        return $processId
                    }
                    else {
                        Write-Warning "Unexpected pidof output: $processId"
                    }
                }
            }
            catch {
                # Process not found yet, continue waiting
                Write-Debug "$($this.Platform): Process not found yet (attempt $i/$timeoutSeconds)"
            }

            Start-Sleep -Seconds 1
        }

        return $null
    }

    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "$($this.Platform): Getting device logs (type: $LogType, max: $MaxEntries)"

        $logs = $this.InvokeCommand('logcat', @($this.DeviceSerial))
        $formattedLogs = Format-LogcatOutput -LogcatOutput $logs

        if ($MaxEntries -gt 0) {
            $formattedLogs = $formattedLogs | Select-Object -Last $MaxEntries
        }

        return @{
            Platform  = $this.Platform
            LogType   = $LogType
            Logs      = $formattedLogs
            Count     = $formattedLogs.Count
            Timestamp = Get-Date
        }
    }

    [void] TakeScreenshot([string]$OutputPath) {
        Write-Debug "$($this.Platform): Taking screenshot to: $OutputPath"

        # Use intermediate file on device to avoid binary data corruption in stdout capture
        $tempDevicePath = "/sdcard/temp_screenshot_$([Guid]::NewGuid()).png"

        try {
            # Capture to temp file on device
            $this.InvokeCommand('screenshot', @($this.DeviceSerial, $tempDevicePath))

            # Copy file from device (handles directory creation)
            $this.CopyDeviceItem($tempDevicePath, $OutputPath)

            $size = (Get-Item $OutputPath).Length
            Write-Debug "$($this.Platform): Screenshot saved ($size bytes)"
        }
        finally {
            # Clean up temp file on device
            try {
                $this.InvokeCommand('rm', @($this.DeviceSerial, $tempDevicePath))
            }
            catch {
                Write-Warning "Failed to cleanup temp screenshot file: $_"
            }
        }
    }

    [void] CopyDeviceItem([string]$DevicePath, [string]$Destination) {
        Write-Debug "$($this.Platform): Copying from device: $DevicePath -> $Destination"

        # Ensure destination directory exists
        $destDir = Split-Path $Destination -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        $this.InvokeCommand('pull', @($this.DeviceSerial, $DevicePath, $Destination))
    }

    [hashtable] GetDeviceStatus() {
        Write-Debug "$($this.Platform): Getting device status"

        $props = $this.InvokeCommand('getstatus', @($this.DeviceSerial))

        # Parse key properties
        $statusData = @{}
        foreach ($line in $props) {
            if ($line -match '^\[(.+?)\]:\s*\[(.+?)\]$') {
                $statusData[$matches[1]] = $matches[2]
            }
        }

        return @{
            Platform   = $this.Platform
            Status     = 'Online'
            StatusData = $statusData
            Timestamp  = Get-Date
        }
    }

    [string] GetDeviceIdentifier() {
        return $this.DeviceSerial
    }

    [void] StartDevice() {
        Write-Warning "$($this.Platform): StartDevice is not supported for ADB devices"
    }

    [void] StopDevice() {
        Write-Warning "$($this.Platform): StopDevice is not supported for ADB devices"
    }

    [void] RestartDevice() {
        Write-Debug "$($this.Platform): Restarting device"

        $this.InvokeCommand('reboot', @($this.DeviceSerial))

        # Wait for device to come back online
        Write-Host "Waiting for device to reboot..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30

        $maxWait = 120
        $waited = 0
        $isReady = $false

        while ($waited -lt $maxWait) {
            try {
                if ($this.TestConnection()) {
                    $isReady = $true
                    Write-Host "Device is ready after $waited seconds" -ForegroundColor Green
                    break
                }
            }
            catch {
                # Device not ready yet
            }

            Start-Sleep -Seconds 5
            $waited += 5
            Write-Debug "$($this.Platform): Waiting for device ($waited/$maxWait seconds)"
        }

        if (-not $isReady) {
            throw "Device did not come back online after $maxWait seconds"
        }
    }

    [bool] TestInternetConnection() {
        Write-Debug "$($this.Platform): Testing internet connection"

        try {
            # Ping a reliable server (Google DNS)
            $output = $this.InvokeCommand('ping', @($this.DeviceSerial, '8.8.8.8'))
            # Join output to string first since -match on arrays returns matching elements, not boolean
            return ($output -join "`n") -match '1 packets transmitted, 1 received'
        }
        catch {
            return $false
        }
    }

    # Override GetRunningProcesses to provide Android process list
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): Getting running processes"

        try {
            $output = $this.InvokeCommand('ps', @($this.DeviceSerial))

            # Parse ps output
            # Format varies by Android version but typically: USER PID PPID ... NAME
            $processes = @()
            foreach ($line in $output) {
                # Skip header line
                if ($line -match '^\s*USER' -or $line -match '^\s*PID') {
                    continue
                }

                # Basic parsing - extract PID and process name
                if ($line -match '\s+(\d+)\s+.*\s+([^\s]+)\s*$') {
                    $processes += [PSCustomObject]@{
                        Id   = [int]$matches[1]
                        Name = $matches[2]
                    }
                }
            }

            return $processes
        }
        catch {
            Write-Warning "$($this.Platform): Failed to get process list: $_"
            return @()
        }
    }

    # Override DetectAndSetDefaultTarget - not needed for ADB
    [void] DetectAndSetDefaultTarget() {
        Write-Debug "$($this.Platform): Target detection not needed for ADB"
        # No-op: Device auto-discovery happens in Connect()
    }
}
