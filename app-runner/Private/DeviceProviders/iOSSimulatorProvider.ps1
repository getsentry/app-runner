# iOS Simulator Provider Implementation
# Provides device management for iOS Simulators via xcrun simctl

# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

<#
.SYNOPSIS
Device provider for iOS Simulators via xcrun simctl.

.DESCRIPTION
This provider implements iOS Simulator-specific device operations using xcrun simctl commands.
It supports booting, installing .app bundles, launching apps with console output capture,
and shutting down simulators.

Key features:
- Auto-discovery of available simulators
- Runtime version filtering (e.g. "iOS 17.0")
- UUID and device name targeting
- .app bundle installation with bundle ID extraction
- App execution with console output capture via --console-pty
- Screenshot capture
- Tracks whether simulator was booted by this provider

Requirements:
- macOS with Xcode and xcrun in PATH
- At least one iOS Simulator runtime installed
#>
class iOSSimulatorProvider : DeviceProvider {
    [string]$SimulatorUUID = $null
    [string]$CurrentBundleId = $null
    [bool]$DidBootSimulator = $false

    iOSSimulatorProvider() {
        $this.Platform = 'iOSSimulator'
        $this.SdkPath = $null

        # Validate macOS platform
        if (-not $global:IsMacOS) {
            throw "iOSSimulator provider is only supported on macOS"
        }

        # Validate xcrun is available
        if (-not (Get-Command 'xcrun' -ErrorAction SilentlyContinue)) {
            throw "xcrun not found in PATH. Please install Xcode Command Line Tools."
        }

        # Configure simctl commands
        $this.Commands = @{
            'list-devices'     = @('xcrun', 'simctl list devices')
            'list-runtimes'    = @('xcrun', 'simctl list runtimes iOS')
            'boot'             = @('xcrun', 'simctl boot {0}')
            'shutdown'         = @('xcrun', 'simctl shutdown {0}')
            'install'          = @('xcrun', 'simctl install {0} {1}')
            'uninstall'        = @('xcrun', 'simctl uninstall {0} {1}')
            'screenshot'       = @('xcrun', 'simctl io {0} screenshot {1}')
            'get-app-container' = @('xcrun', 'simctl get_app_container {0} {1}')
            'log-show'         = @('xcrun', 'simctl spawn {0} log show --style compact --last 5m')
        }

        # Configure timeouts
        $this.Timeouts = @{
            'boot'        = 60
            'run-timeout' = 300
        }
    }

    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Auto-discovering available simulator"

        $simulators = $this.GetAvailableSimulators($null)

        if ($null -eq $simulators -or $simulators.Count -eq 0) {
            throw "No iOS simulators found. Ensure at least one iOS Simulator runtime is installed via Xcode."
        }

        return $this.SelectAndConnect($simulators, $null)
    }

    [hashtable] Connect([string]$target) {
        if ([string]::IsNullOrEmpty($target) -or $target -eq 'latest') {
            if ($target -eq 'latest') {
                $latestRuntime = $this.GetLatestRuntime()
                Write-Debug "$($this.Platform): Resolved 'latest' to runtime: $latestRuntime"
                return $this.ConnectWithRuntimeFilter($latestRuntime)
            }
            return $this.Connect()
        }

        Write-Debug "$($this.Platform): Connecting with target: $target"

        # Check if target matches "iOS <version>" pattern
        if ($target -match '^iOS\s+\d+\.\d+') {
            return $this.ConnectWithRuntimeFilter($target)
        }

        # Check if target is a UUID
        if ($target -match '^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$') {
            return $this.ConnectWithUUID($target)
        }

        # Otherwise, try to match by device name
        return $this.ConnectWithDeviceName($target)
    }

    hidden [hashtable] ConnectWithRuntimeFilter([string]$runtimeFilter) {
        Write-Debug "$($this.Platform): Filtering simulators by runtime: $runtimeFilter"

        $simulators = $this.GetAvailableSimulators($runtimeFilter)

        if ($null -eq $simulators -or $simulators.Count -eq 0) {
            throw "No simulators found for runtime '$runtimeFilter'. Check installed runtimes with: xcrun simctl list runtimes iOS"
        }

        return $this.SelectAndConnect($simulators, $runtimeFilter)
    }

    hidden [hashtable] ConnectWithUUID([string]$uuid) {
        Write-Debug "$($this.Platform): Connecting to simulator by UUID: $uuid"

        $simulators = $this.GetAvailableSimulators($null)
        $matched = @($simulators | Where-Object { $_.UUID -eq $uuid })

        if ($matched.Count -eq 0) {
            throw "No simulator found with UUID '$uuid'. Check available simulators with: xcrun simctl list devices"
        }

        return $this.SelectAndConnect($matched, $null)
    }

    hidden [hashtable] ConnectWithDeviceName([string]$deviceName) {
        Write-Debug "$($this.Platform): Connecting to simulator by name: $deviceName"

        $simulators = $this.GetAvailableSimulators($null)
        $matched = @($simulators | Where-Object { $_.Name -eq $deviceName })

        if ($matched.Count -eq 0) {
            $availableNames = ($simulators | Select-Object -ExpandProperty Name -Unique) -join ', '
            throw "No simulator found with name '$deviceName'. Available: $availableNames"
        }

        return $this.SelectAndConnect($matched, $null)
    }

    [void] Disconnect() {
        Write-Debug "$($this.Platform): Disconnecting"

        if ($this.DidBootSimulator -and $this.SimulatorUUID) {
            Write-Host "Shutting down simulator: $($this.SimulatorUUID)" -ForegroundColor Yellow
            try {
                $this.InvokeCommand('shutdown', @($this.SimulatorUUID))
            }
            catch {
                Write-Warning "Failed to shutdown simulator: $_"
            }
        }
        else {
            Write-Debug "$($this.Platform): Skipping shutdown (simulator was already booted before connect)"
        }

        $this.SimulatorUUID = $null
        $this.CurrentBundleId = $null
        $this.DidBootSimulator = $false
    }

    [bool] TestConnection() {
        Write-Debug "$($this.Platform): Testing connection"

        if ([string]::IsNullOrEmpty($this.SimulatorUUID)) {
            return $false
        }

        try {
            $status = $this.GetSimulatorState()
            return $status -eq 'Booted'
        }
        catch {
            return $false
        }
    }

    [hashtable] InstallApp([string]$PackagePath) {
        Write-Debug "$($this.Platform): Installing app: $PackagePath"

        # Validate .app bundle
        if (-not (Test-Path $PackagePath)) {
            throw "App bundle not found: $PackagePath"
        }

        if ($PackagePath -notlike '*.app') {
            throw "iOS Simulator requires a .app bundle directory (not .ipa). Got: $PackagePath"
        }

        if (-not (Test-Path "$PackagePath/Info.plist")) {
            throw "Invalid .app bundle: Info.plist not found in $PackagePath"
        }

        # Extract bundle ID from Info.plist
        $bundleId = $null
        try {
            $bundleId = & /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PackagePath/Info.plist" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "PlistBuddy failed with exit code $LASTEXITCODE"
            }
            $bundleId = "$bundleId".Trim()
        }
        catch {
            throw "Failed to extract bundle ID from $PackagePath/Info.plist: $_"
        }

        Write-Debug "$($this.Platform): Bundle ID: $bundleId"

        # Check for existing installation and uninstall
        try {
            $this.InvokeCommand('get-app-container', @($this.SimulatorUUID, $bundleId))
            # If we get here, app is installed - uninstall it
            Write-Host "Uninstalling previous version: $bundleId" -ForegroundColor Yellow
            try {
                $this.InvokeCommand('uninstall', @($this.SimulatorUUID, $bundleId))
            }
            catch {
                Write-Warning "Failed to uninstall previous version: $_"
            }
            Start-Sleep -Seconds 1
        }
        catch {
            # App not installed - that's fine
            Write-Debug "$($this.Platform): No previous installation found"
        }

        # Install app
        Write-Host "Installing app to simulator: $($this.SimulatorUUID)" -ForegroundColor Yellow
        $this.InvokeCommand('install', @($this.SimulatorUUID, $PackagePath))
        $this.CurrentBundleId = $bundleId

        Write-Host "App installed successfully: $bundleId" -ForegroundColor Green

        return @{
            PackagePath   = $PackagePath
            BundleId      = $bundleId
            SimulatorUUID = $this.SimulatorUUID
        }
    }

    [hashtable] RunApplication([string]$ExecutablePath, [string[]]$Arguments, [string]$LogFilePath = $null, [string]$WorkingDirectory = $null) {
        if (-not ([string]::IsNullOrEmpty($LogFilePath))) {
            Write-Warning "LogFilePath parameter is not supported on this platform."
        }
        if (-not ([string]::IsNullOrEmpty($WorkingDirectory))) {
            Write-Warning "WorkingDirectory parameter is not supported on this platform."
        }

        Write-Debug "$($this.Platform): Running application: $ExecutablePath"

        $bundleId = $ExecutablePath
        $this.CurrentBundleId = $bundleId
        $timeoutSeconds = $this.Timeouts['run-timeout']

        $startTime = Get-Date

        # Build argument list for simctl launch
        $simctlArgs = @("simctl", "launch", "--console-pty", $this.SimulatorUUID, $bundleId)
        if ($Arguments -and $Arguments.Count -gt 0) {
            $simctlArgs += $Arguments
        }

        # Terminate any previous instance to ensure a clean launch.
        # This prevents stale processes from interfering with console-pty output capture.
        try {
            & xcrun simctl terminate $this.SimulatorUUID $bundleId 2>&1 | Out-Null
        }
        catch {
            # App may not be running - that's fine
        }

        Write-Host "Launching: $bundleId" -ForegroundColor Cyan
        if ($Arguments -and $Arguments.Count -gt 0) {
            Write-Host "  Arguments: $($Arguments -join ' ')" -ForegroundColor Cyan
        }

        # Use Start-Process with output redirection and timeout (pattern from smoke-test-ios.ps1)
        $outFile = New-TemporaryFile
        $errFile = New-TemporaryFile
        $consoleOut = @()
        $exitCode = $null

        try {
            $process = Start-Process "xcrun" `
                -ArgumentList $simctlArgs `
                -NoNewWindow -PassThru `
                -RedirectStandardOutput $outFile `
                -RedirectStandardError $errFile

            $timedOut = $null
            $process | Wait-Process -Timeout $timeoutSeconds -ErrorAction SilentlyContinue -ErrorVariable timedOut

            if ($timedOut) {
                Write-Warning "App timed out after $timeoutSeconds seconds - stopping process"
                $process | Stop-Process -Force -ErrorAction SilentlyContinue

                # Terminate the app on the simulator to ensure proper cleanup.
                # This is important after crashes where the app process may have died
                # but the console-pty connection keeps xcrun alive.
                try {
                    & xcrun simctl terminate $this.SimulatorUUID $bundleId 2>&1 | Out-Null
                }
                catch {
                    Write-Debug "$($this.Platform): terminate after timeout failed (app may already be terminated): $_"
                }
                Start-Sleep -Seconds 1

                $exitCode = -1
            }
            else {
                $exitCode = $process.ExitCode
            }

            # Read captured output
            $consoleOut = @(Get-Content $outFile -ErrorAction SilentlyContinue) + `
                          @(Get-Content $errFile -ErrorAction SilentlyContinue)
        }
        finally {
            Remove-Item $outFile -ErrorAction SilentlyContinue
            Remove-Item $errFile -ErrorAction SilentlyContinue
        }

        Write-Host "Retrieved $($consoleOut.Count) output lines" -ForegroundColor Cyan

        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startTime
            FinishedAt     = Get-Date
            Output         = $consoleOut
            ExitCode       = $exitCode
        }
    }

    [void] TakeScreenshot([string]$OutputPath) {
        Write-Debug "$($this.Platform): Taking screenshot to: $OutputPath"

        # Ensure destination directory exists
        $destDir = Split-Path $OutputPath -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        $this.InvokeCommand('screenshot', @($this.SimulatorUUID, $OutputPath))

        if (Test-Path $OutputPath) {
            $size = (Get-Item $OutputPath).Length
            Write-Debug "$($this.Platform): Screenshot saved ($size bytes)"
        }
    }

    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "$($this.Platform): Getting device logs (type: $LogType, max: $MaxEntries)"

        $logs = @()
        try {
            $logs = @($this.InvokeCommand('log-show', @($this.SimulatorUUID)))
        }
        catch {
            Write-Warning "Failed to retrieve simulator logs: $_"
        }

        if ($MaxEntries -gt 0 -and $logs.Count -gt $MaxEntries) {
            $logs = $logs | Select-Object -Last $MaxEntries
        }

        return @{
            Platform  = $this.Platform
            LogType   = $LogType
            Logs      = $logs
            Count     = $logs.Count
            Timestamp = Get-Date
        }
    }

    [hashtable] GetDeviceStatus() {
        Write-Debug "$($this.Platform): Getting device status"

        $state = $this.GetSimulatorState()

        return @{
            Platform   = $this.Platform
            Status     = if ($state -eq 'Booted') { 'Online' } else { $state }
            StatusData = @{
                SimulatorUUID = $this.SimulatorUUID
                State         = $state
            }
            Timestamp  = Get-Date
        }
    }

    [string] GetDeviceIdentifier() {
        return $this.SimulatorUUID
    }

    [void] StartDevice() {
        Write-Debug "$($this.Platform): Starting simulator"
        if ($this.SimulatorUUID) {
            $this.BootSimulator()
        }
        else {
            Write-Warning "$($this.Platform): No simulator selected. Call Connect() first."
        }
    }

    [void] StopDevice() {
        Write-Debug "$($this.Platform): Stopping simulator"
        if ($this.SimulatorUUID) {
            try {
                $this.InvokeCommand('shutdown', @($this.SimulatorUUID))
            }
            catch {
                Write-Warning "Failed to shutdown simulator: $_"
            }
        }
    }

    [void] RestartDevice() {
        Write-Debug "$($this.Platform): Restarting simulator"
        $this.StopDevice()
        Start-Sleep -Seconds 2
        $this.BootSimulator()
    }

    # Helper: Select the best simulator from the list (prefer booted), boot if needed, and return session info
    hidden [hashtable] SelectAndConnect([object[]]$simulators, [string]$context) {
        $label = if ($context) { " [$context]" } else { '' }

        $booted = @($simulators | Where-Object { $_.State -eq 'Booted' })
        if ($booted.Count -gt 0) {
            $selected = $booted[0]
            Write-Host "Using already-booted simulator: $($selected.Name) ($($selected.UUID))$label" -ForegroundColor Green
            $this.SimulatorUUID = $selected.UUID
            $this.DidBootSimulator = $false
        }
        else {
            $selected = $simulators[0]
            Write-Host "Booting simulator: $($selected.Name) ($($selected.UUID))$label" -ForegroundColor Yellow
            $this.SimulatorUUID = $selected.UUID
            $this.BootSimulator()
        }

        return $this.CreateSessionInfo()
    }

    # Helper: Boot the simulator with graceful handling
    hidden [void] BootSimulator() {
        Write-Debug "$($this.Platform): Booting simulator: $($this.SimulatorUUID)"

        try {
            $this.InvokeCommand('boot', @($this.SimulatorUUID))
        }
        catch {
            # Check if already booted
            if ("$_" -match 'Unable to boot device in current state: Booted') {
                Write-Debug "$($this.Platform): Simulator is already booted"
                $this.DidBootSimulator = $false
                return
            }
            throw
        }

        # Wait for simulator to be ready
        $maxWait = $this.Timeouts['boot']
        $waited = 0
        while ($waited -lt $maxWait) {
            $state = $this.GetSimulatorState()
            if ($state -eq 'Booted') {
                Write-Host "Simulator booted successfully" -ForegroundColor Green
                $this.DidBootSimulator = $true
                return
            }
            Start-Sleep -Seconds 1
            $waited++
            Write-Debug "$($this.Platform): Waiting for simulator to boot ($waited/$maxWait seconds)"
        }

        throw "Simulator did not boot within $maxWait seconds"
    }

    # Helper: Get available simulators, optionally filtered by runtime
    hidden [object[]] GetAvailableSimulators([string]$runtimeFilter) {
        $output = $this.InvokeCommand('list-devices', @())

        $simulators = @()
        $currentRuntime = $null

        foreach ($line in $output) {
            # Match runtime headers: "-- iOS 17.0 --" or "-- iOS 18.2 (18.2 - 22C150) --"
            if ($line -match '^--\s+(.+?)\s+--') {
                $currentRuntime = $matches[1]
                # Normalize: extract just "iOS X.Y" from longer strings like "iOS 18.2 (18.2 - 22C150)"
                if ($currentRuntime -match '^(iOS\s+\d+\.\d+)') {
                    $currentRuntime = $matches[1]
                }
                continue
            }

            # Skip non-iOS runtimes
            if ($null -eq $currentRuntime -or $currentRuntime -notmatch '^iOS') {
                continue
            }

            # Apply runtime filter if specified
            if ($runtimeFilter -and $currentRuntime -ne $runtimeFilter) {
                continue
            }

            # Parse device lines: "    iPhone 15 Pro (UUID) (State)"
            if ($line -match '^\s+(?<model>.+)\s+\((?<uuid>[0-9A-Fa-f\-]{36})\)\s+\((?<state>\w+)\)') {
                $simulators += [PSCustomObject]@{
                    Name    = $matches['model'].Trim()
                    UUID    = $matches['uuid']
                    State   = $matches['state']
                    Runtime = $currentRuntime
                }
            }
        }

        # Filter out unavailable devices
        $simulators = @($simulators | Where-Object { $_.State -ne 'Unavailable' })

        return $simulators
    }

    # Helper: Get the latest available iOS runtime
    hidden [string] GetLatestRuntime() {
        $runtimes = $this.InvokeCommand('list-runtimes', @())
        $lastRuntime = $runtimes | Select-Object -Last 1
        $result = [regex]::Match($lastRuntime, '(?<runtime>iOS\s+[0-9.]+)')
        if (-not $result.Success) {
            throw "Failed to determine latest iOS runtime. Output: $lastRuntime"
        }
        $latestRuntime = $result.Groups['runtime'].Value
        Write-Debug "$($this.Platform): Latest runtime: $latestRuntime"
        return $latestRuntime
    }

    # Helper: Get current simulator state
    hidden [string] GetSimulatorState() {
        $output = $this.InvokeCommand('list-devices', @())
        foreach ($line in $output) {
            if ($line -match $this.SimulatorUUID) {
                if ($line -match '\((?<state>Booted|Shutdown|Shutting Down)\)\s*$') {
                    return $matches['state']
                }
            }
        }
        return 'Unknown'
    }

    # Override DetectAndSetDefaultTarget - not needed for iOS Simulator
    [void] DetectAndSetDefaultTarget() {
        Write-Debug "$($this.Platform): Target detection not needed for iOS Simulator"
    }
}
