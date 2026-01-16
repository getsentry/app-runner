# Device Provider Base Class
# Provides shared functionality for all device providers


<#
.SYNOPSIS
Encapsulates a built command with optional processing step.

.DESCRIPTION
Represents the result of building a platform command, consisting of the main
command string and an optional processing command (scriptblock) to transform output.
#>
class BuiltCommand {
    [string]$Command
    [scriptblock]$ProcessingCommand

    BuiltCommand([string]$command, [scriptblock]$processingCommand) {
        $this.Command = $command
        $this.ProcessingCommand = $processingCommand
    }

    [bool] IsNoOp() {
        return [string]::IsNullOrEmpty($this.Command)
    }

    [bool] HasProcessingCommand() {
        return $null -ne $this.ProcessingCommand
    }
}


<#
.SYNOPSIS
Base device provider with shared implementation for all platforms.

.DESCRIPTION
This base class implements common patterns shared across all device providers,
reducing code duplication and providing consistent behavior. Platform-specific
providers inherit from this base and override only what's different.
#>
class DeviceProvider {
    # Platform identification
    [string]$Platform

    [hashtable]$Commands
    [hashtable]$Timeouts
    [string]$SdkPath

    # Timeout handling configuration (opt-in via derived classes)
    [int]$TimeoutSeconds = 0  # 0 = no timeout (default for all commands)
    [int]$MaxRetryAttempts = 2
    [bool]$IsRebooting = $false  # Internal flag to skip retry-on-timeout during reboot

    [string]$DebugOutputForwarder = "ForEach-Object { (`$_ | Out-String).TrimEnd() } | Where-Object { `$_.Length -gt 0 } | Tee-Object -variable capturedOutput | Foreach-Object { Write-Debug `$_ } ; `$capturedOutput"

    DeviceProvider() {
        $this.Commands = @{}
        $this.Timeouts = @{}
        $this.SdkPath = $null
    }

    # Shared helper methods
    [string] GetToolPath([string]$toolName) {
        $toolPath = $toolName
        $isAvailable = if ($this.SdkPath) {
            $toolPath = Join-Path $this.SdkPath $toolName
            Test-Path $toolPath
        } else {
            # Check if command exists in PATH
            $cmd = Get-Command $toolPath -ErrorAction SilentlyContinue
            if ($cmd) { $true } else { $false }
        }


        if (-not $isAvailable) {
            throw "Tool not found: $toolPath. Please verify SDK installation."
        }

        return $toolPath
    }

    [BuiltCommand] BuildCommand([string]$action, [object[]]$parameters) {
        if (-not $this.Commands.ContainsKey($action)) {
            throw "Command '$action' not configured for platform '$($this.Platform)'"
        }

        $commandObj = $this.Commands[$action]
        if ($null -eq $commandObj) {
            # Special case: disconnect is a no-op for some platforms but users should still call it to unlock resources.
            if ($action -ne 'disconnect') {
                Write-Warning "Command '$action' is not available for platform '$($this.Platform)'"
            }
            return [BuiltCommand]::new($null, $null)
        }

        # Format executable path if it contains format strings (e.g., {0})
        $toolName = $commandObj[0]
        if ($null -ne $parameters -and $toolName -match '\{[0-9]+\}') {
            try {
                $toolName = $toolName -f $parameters[0]
            } catch {
                throw "Failed to format tool name ($toolName) for action '$action' with parameters $($parameters | Out-String): $_"
            }
        }

        $executablePath = $this.GetToolPath($toolName)

        $arguments = $commandObj[1]
        if ($null -ne $parameters) {
            try {
                $arguments = $arguments -f $parameters
            } catch {
                throw "Failed to format command arguments ($arguments) for action '$action' with parameters $($parameters | Out-String): $_"
            }
        }

        $command = "& '$executablePath' $arguments 2>&1"
        $processingCommand = if ($commandObj.Count -gt 2) { $commandObj[2] } else { $null }

        return [BuiltCommand]::new($command, $processingCommand)
    }


    [void] LogNotImplemented([string]$operation) {
        Write-Warning "$($this.Platform) $operation not yet implemented"
    }

    # Helper method to invoke a command with timeout and retry handling
    # This method is used internally when TimeoutSeconds > 0
    [object] InvokeCommandWithTimeoutAndRetry([scriptblock]$scriptBlock, [string]$platform, [string]$action, [object]$command) {
        $attempt = 1

        while ($attempt -le $this.MaxRetryAttempts) {
            try {
                # Only log attempt info for retries
                if ($attempt -gt 1) {
                    Write-Warning "$($this.Platform): Retry attempt $attempt of $($this.MaxRetryAttempts) for command ($action)"
                }

                # Start job with the provided scriptblock and arguments
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $platform, $action, $command, $this.DebugOutputForwarder

                # Wait with progress messages every 30 seconds
                $waitIntervalSeconds = 30
                $elapsedSeconds = 0
                $completed = $null

                while ($elapsedSeconds -lt $this.TimeoutSeconds) {
                    $completed = Wait-Job -Job $job -Timeout $waitIntervalSeconds

                    if ($null -ne $completed) {
                        # Job completed
                        break
                    }

                    $elapsedSeconds += $waitIntervalSeconds

                    if ($elapsedSeconds -lt $this.TimeoutSeconds) {
                        Write-Warning "$($this.Platform): Command ($action) still running after $elapsedSeconds seconds, timeout in $($this.TimeoutSeconds - $elapsedSeconds) seconds..."
                    }
                }

                if ($null -eq $completed) {
                    # Timeout occurred
                    Stop-Job -Job $job
                    Remove-Job -Job $job -Force
                    $jobResult = @{ TimedOut = $true; Success = $false; Result = $null }
                } else {
                    # Job completed within timeout
                    $result = Receive-Job -Job $job
                    $jobFailed = $job.ChildJobs[0].State -eq 'Failed'
                    Remove-Job -Job $job -Force
                    $jobResult = @{ TimedOut = $false; Success = -not $jobFailed; Result = $result }
                }

                if ($jobResult.TimedOut) {
                    Write-Warning "$($this.Platform): Command ($action) timed out after $($this.TimeoutSeconds) seconds"

                    if ($attempt -lt $this.MaxRetryAttempts) {
                        Write-Warning "$($this.Platform): Triggering device reboot and retrying..."

                        # Trigger reboot using the platform's RestartDevice method
                        # Platform-specific implementations should handle waiting for device to be ready
                        try {
                            # Set flag to prevent timeout logic during reboot
                            $this.IsRebooting = $true

                            Write-Debug "$($this.Platform): Restarting device"
                            $this.RestartDevice()
                            Write-Debug "$($this.Platform): Device reboot complete, retrying command..."
                        } catch {
                            Write-Warning "$($this.Platform): Failed to trigger reboot: $_"
                        } finally {
                            # Always clear the reboot flag
                            $this.IsRebooting = $false
                        }

                        $attempt++
                        continue
                    } else {
                        throw "Command ($action) timed out after $($this.TimeoutSeconds) seconds and retry failed"
                    }
                } elseif (-not $jobResult.Success) {
                    throw "Command ($action) failed"
                } else {
                    # Success
                    return $jobResult.Result
                }
            } catch {
                if ($attempt -lt $this.MaxRetryAttempts -and $_.Exception.Message -match 'timed out') {
                    # Already handled above, continue to next attempt
                    $attempt++
                    continue
                } else {
                    throw
                }
            }
        }

        throw "Command ($action) failed after $($this.MaxRetryAttempts) attempts"
    }

    [object] InvokeCommand([string]$action, [object[]]$parameters) {
        # Build command once and check if it's a no-op
        $builtCommand = $this.BuildCommand($action, $parameters)
        if ($builtCommand.IsNoOp()) {
            return $null
        }

        # Build the execution scriptblock once - used for both timeout and non-timeout paths
        $scriptBlock = {
            param($platform, $act, $cmd, $debugForwarder)
            try {
                $PSNativeCommandUseErrorActionPreference = $false
                Write-Debug "${platform}: Invoking ($act) command $cmd"
                $result = Invoke-Expression "$cmd | $debugForwarder"
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Command ($act`: $cmd) failed with exit code $($LASTEXITCODE) $($result.Length -gt 0 ? 'and output:' : '')"
                    $result | Out-Host
                    Write-Warning '=== End of original output. ==='
                    throw "Command ($act) failed with exit code $($LASTEXITCODE)"
                }
                return $result
            } finally {
                $PSNativeCommandUseErrorActionPreference = $true
            }
        }

        # Determine timeout for this action: use action-specific timeout if defined, otherwise use default
        $effectiveTimeout = $this.TimeoutSeconds
        if ($this.Timeouts.ContainsKey($action)) {
            $effectiveTimeout = $this.Timeouts[$action]
        }

        # Extract command string and processing command from built command
        $commandString = $builtCommand.Command
        $processingCommand = $builtCommand.ProcessingCommand

        # If timeout is enabled and we're not in the middle of a reboot, use timeout handling
        if ($effectiveTimeout -gt 0 -and -not $this.IsRebooting) {
            # Temporarily override TimeoutSeconds for this specific action
            $originalTimeout = $this.TimeoutSeconds
            $this.TimeoutSeconds = $effectiveTimeout
            try {
                $output = $this.InvokeCommandWithTimeoutAndRetry($scriptBlock, $this.Platform, $action, $commandString)
                return $this.ProcessOutput($output, $processingCommand)
            } finally {
                $this.TimeoutSeconds = $originalTimeout
            }
        } else {
            $output = & $scriptBlock $this.Platform $action $commandString $this.DebugOutputForwarder
            return $this.ProcessOutput($output, $processingCommand)
        }
    }

    [object] ProcessOutput([object]$output, [scriptblock]$processingCommand) {
        if ($null -eq $processingCommand) {
            return $output
        }

        Write-Debug "$($this.Platform): Processing output with: $processingCommand"
        try {
            return $output | & $processingCommand
        } catch {
            Write-Warning "$($this.Platform): Failed to process command output: $_"
            Write-Warning "Processing command: $processingCommand"
            Write-Warning 'Original output:'
            $output | Out-Host
            Write-Warning '=== End of original output. ==='
            throw "Failed to process command output: $_"
        }
    }

    [hashtable] CreateSessionInfo() {
        $status = $this.GetDeviceStatus()
        return @{
            Provider    = $this
            Platform    = $this.Platform
            ConnectedAt = Get-Date
            Identifier  = $this.GetDeviceIdentifier()
            IsConnected = $true
            StatusData  = $status.StatusData
        }
    }

    # Connection management (shared implementation)
    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Connecting to device"
        $this.DetectAndSetDefaultTarget()
        $this.InvokeCommand('connect', @())
        $this.InvokeCommand('poweron', @())
        return $this.CreateSessionInfo()
    }

    [hashtable] Connect([string]$target) {
        if (-not [string]::IsNullOrEmpty($target)) {
            Write-Warning "$($this.Platform): Connect doesn't support specifying the target parameter so it's ignored."
        }

        # Default implementation just calls Connect() - platforms that support targets should override
        return $this.Connect()
    }

    [void] Disconnect() {
        Write-Debug "$($this.Platform): Disconnecting from device"

        $this.InvokeCommand('disconnect', @())
    }

    [bool] TestConnection() {
        Write-Debug "$($this.Platform): Testing connection to device"

        $this.InvokeCommand('getstatus', @())
        return $true
    }

    # Device lifecycle management (shared implementation)
    [void] StartDevice() {
        Write-Debug "$($this.Platform): Starting device"

        $this.InvokeCommand('poweron', @())
    }

    [void] StopDevice() {
        Write-Debug "$($this.Platform): Stopping device"

        Write-Output $this.InvokeCommand('poweroff', @())
    }

    [void] RestartDevice() {
        Write-Debug "$($this.Platform): Restarting device"

        $this.InvokeCommand('reset', @())
    }

    [hashtable] GetDeviceStatus() {
        Write-Debug "$($this.Platform): Getting device status"

        $result = $this.InvokeCommand('getstatus', @())
        return @{
            Platform   = $this.Platform
            Status     = 'Online'
            StatusData = $result
            Timestamp  = Get-Date
        }
    }

    # Application management (shared implementation)
    [hashtable] InstallApp([string]$PackagePath) {
        Write-Debug "$($this.Platform): Installing application package: $PackagePath"
        $this.LogNotImplemented('InstallApp')
        return @{}
    }

    [hashtable] RunApplication([string]$ExecutablePath, [string[]]$Arguments, [string]$LogFilePath = $null) {
        Write-Debug "$($this.Platform): Running application: $ExecutablePath with arguments: $Arguments"

        if (-not ([string]::IsNullOrEmpty($LogFilePath))) {
            Write-Warning "LogFilePath parameter is not supported on this platform."
        }

        $argumentsString = $Arguments -join ' '
        $command = $this.BuildCommand('launch', @($ExecutablePath, $argumentsString))
        return $this.InvokeApplicationCommand($command, $ExecutablePath, $Arguments)
    }

    [hashtable] InvokeApplicationCommand([BuiltCommand]$builtCommand, [string]$ExecutablePath, [string[]]$Arguments) {
        Write-Debug "$($this.Platform): Invoking $($builtCommand.Command)"

        $result = $null
        $exitCode = $null
        $startDate = Get-Date
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $commandString = $builtCommand.Command
            $processingCommand = $builtCommand.ProcessingCommand
            $output = Invoke-Expression "$commandString | $($this.DebugOutputForwarder)"
            $result = $this.ProcessOutput($output, $processingCommand)
            $exitCode = $LASTEXITCODE
        } finally {
            $PSNativeCommandUseErrorActionPreference = $true
        }

        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startDate
            FinishedAt     = Get-Date
            Output         = $result
            ExitCode       = $exitCode
        }
    }

    [void] TakeScreenshot([string]$OutputPath) {
        # If the output path includes a directory, split it up, otherwise use current directory
        $directory = Split-Path $OutputPath -Parent
        $filename = Split-Path $OutputPath -Leaf
        if (-not $directory) {
            $directory = Get-Location
        }

        Write-Debug "$($this.Platform): Taking screenshot (directory: $directory, file: $filename)"

        $this.InvokeCommand('screenshot', @($directory, $filename))

        $size = (Get-Item $OutputPath).Length
        Write-Debug "Screenshot saved to $OutputPath ($size bytes)"
    }

    # Virtual method for getting running processes
    # Platforms should override this to provide process list information
    # Returns raw command output as string array, or $null if not supported
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): GetRunningProcesses not implemented for this platform"
        return $null
    }

    # Platforms should override this to provide item copying from device
    [void] CopyDeviceItem([string]$DevicePath, [string]$Destination) {
        Write-Warning "CopyDeviceItem is not available for $($this.Platform) devices."
    }

    [hashtable] GetDiagnostics([string]$OutputDirectory) {
        Write-Debug "$($this.Platform): Collecting diagnostics to directory: $OutputDirectory"

        # Ensure output directory exists
        if (-not (Test-Path $OutputDirectory)) {
            New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        }

        $datePrefix = Get-Date -Format 'yyyyMMdd-HHmmss'
        $results = @{
            Platform  = $this.Platform
            Timestamp = Get-Date
            Files     = @()
        }

        # Collect device status
        try {
            $statusFile = Join-Path $OutputDirectory "$datePrefix-device-status.json"
            $status = $this.GetDeviceStatus()
            $status | ConvertTo-Json -Depth 10 | Out-File -FilePath $statusFile -Encoding UTF8
            $results.Files += $statusFile
            Write-Debug "Device status saved to: $statusFile"
        } catch {
            Write-Warning "Failed to collect device status: $_"
        }

        # Take screenshot
        try {
            $screenshotFile = Join-Path $OutputDirectory "$datePrefix-screenshot.png"
            $this.TakeScreenshot($screenshotFile)
            $results.Files += $screenshotFile
            Write-Debug "Screenshot saved to: $screenshotFile"
        } catch {
            Write-Warning "Failed to capture screenshot: $_"
        }

        # Collect device logs
        try {
            $logsFile = Join-Path $OutputDirectory "$datePrefix-device-logs.json"
            $logs = $this.GetDeviceLogs('All', 1000)
            if ($logs -and $logs.Count -gt 0) {
                $logs | ConvertTo-Json -Depth 10 | Out-File -FilePath $logsFile -Encoding UTF8
                $results.Files += $logsFile
                Write-Debug "Device logs saved to: $logsFile"
            }
        } catch {
            Write-Warning "Failed to collect device logs: $_"
        }

        # Collect system information
        try {
            $sysInfoFile = Join-Path $OutputDirectory "$datePrefix-system-info.txt"
            $sysInfo = @"
Platform: $($this.Platform)
Device Identifier: $($this.GetDeviceIdentifier())
Collection Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
SDK Path: $($this.SdkPath)
"@
            $sysInfo | Out-File -FilePath $sysInfoFile -Encoding UTF8
            $results.Files += $sysInfoFile
            Write-Debug "System info saved to: $sysInfoFile"
        } catch {
            Write-Warning "Failed to collect system information: $_"
        }

        # Collect running processes
        try {
            $processList = $this.GetRunningProcesses()
            if ($processList) {
                $processListFile = Join-Path $OutputDirectory "$datePrefix-process-list.json"
                $processList | ConvertTo-Json -Depth 10 | Out-File -FilePath $processListFile -Encoding UTF8
                $results.Files += $processListFile
                Write-Debug "Process list saved to: $processListFile"
            }
        } catch {
            Write-Warning "Failed to collect process list: $_"
        }

        Write-Debug "Diagnostics collection complete. Files saved: $($results.Files.Count)"
        return $results
    }

    [string] GetDeviceIdentifier() {
        $status = $this.GetDeviceStatus()
        $statusData = $status.StatusData

        # Handle null or empty status data
        if (-not $statusData) {
            return "$($this.Platform) ($(Get-Date -Format 'HH:mm:ss'))"
        }

        # Try to extract IP address from raw status text
        if ($statusData -match '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' -and $matches -and $matches[0]) {
            return $matches[0]
        }

        # Try to extract device name/ID from status text
        if ($statusData -match '(?:Target|Console|Name|DevKit):\s*(\w+)' -and $matches -and $matches[1]) {
            return $matches[1]
        }

        return "$($this.Platform) ($(Get-Date -Format 'HH:mm:ss'))"
    }

    [bool] TestInternetConnection() {
        Write-Debug "$($this.Platform): Testing internet connection"
        $this.LogNotImplemented('TestInternetConnection')
        return $false
    }

    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "$($this.Platform): GetDeviceLogs not implemented for this platform"
        $this.LogNotImplemented('GetDeviceLogs')
        return @{}
    }

    # Target detection and configuration
    # This method implements a state machine to automatically detect and configure a default target device
    # Platforms that support target management should configure the following commands:
    # - 'get-default-target': Check if a default target is set (returns JSON)
    # - 'list-target': List existing registered targets (returns JSON)
    # - 'set-default-target': Set a target as default (parameter: target identifier)
    # - 'detect-target': Detect targets on the network (returns JSON)
    # - 'register-target': Register a new target (parameter: target identifier)
    [void] DetectAndSetDefaultTarget() {
        # This is a simple state-machine
        # States:
        # 0. Check if a default target is set.
        #    If yes, exit,
        #    if not, go to state 1
        # 1. Listing existing targets,
        #    if one exists, set as default, go to state 0
        #    if multiple exist, throw
        #    if none exist, go to state 2
        # 2. Detect targets on the network
        #    if one exists, add and go to state 1
        #    if multiple exist, throw

        # Let's have a global timeout as a limit on how long we want to try this.
        $timeout = [DateTime]::UtcNow.AddSeconds(60)

        # Start in state 1 (check if targets are registered) as trying to get default will fail if none are registered on some platforms.
        $state = 1
        while ([DateTime]::UtcNow -lt $timeout) {
            switch ($state) {
                0 {
                    # Check if a default target is set
                    $defaultTarget = $this.InvokeCommand('get-default-target', @())
                    if ($null -ne $defaultTarget) {
                        Write-Debug "Default target is currently set to: $defaultTarget"
                        return
                    } else {
                        Write-Debug 'No default target set, proceeding to list existing targets.'
                        $state = 1
                    }
                }
                1 {
                    # List existing targets
                    $existingTargets = $this.InvokeCommand('list-target', @())
                    $count = $null -eq $existingTargets ? 0 : @($existingTargets).Count
                    switch ($count) {
                        0 {
                            Write-Debug 'No existing targets found, proceeding to detect targets on the network.'
                            $state = 2
                        }
                        1 {
                            Write-Debug "One existing target found, setting as default: $($existingTargets)"
                            $this.InvokeCommand('set-default-target', "$($existingTargets.IpAddress)")
                            $state = 0
                        }
                        default {
                            throw "Multiple ($count) existing targets found in Target Manager, cannot auto-detect."
                        }
                    }
                }
                2 {
                    # Detect targets on the network
                    $detectedTargets = $this.InvokeCommand('detect-target', @())
                    $count = $null -eq $detectedTargets ? 0 : @($detectedTargets).Count
                    switch ($count) {
                        0 {
                            throw 'No targets detected on the network and no default target set in the Target Manager. Please add a target manually.'
                        }
                        1 {
                            Write-Debug "One target detected on the network, adding: $($detectedTargets)"
                            $this.InvokeCommand('register-target', "$($detectedTargets.IpAddress)")
                            $state = 1
                        }
                        default {
                            throw "Multiple ($count) targets detected on the network, cannot auto-detect."
                        }
                    }
                }
                default {
                    throw 'Invalid state in DetectAndSetDefaultTarget state machine.'
                }
            }
        }

        throw 'Timeout reached while trying to detect and set default target.'
    }

}
