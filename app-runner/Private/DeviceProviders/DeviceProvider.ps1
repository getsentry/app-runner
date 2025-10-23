# Device Provider Base Class
# Provides shared functionality for all device providers


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

    [object] BuildCommand([string]$action, [object[]]$parameters) {
        if (-not $this.Commands.ContainsKey($action)) {
            throw "Command '$action' not configured for platform '$($this.Platform)'"
        }

        $commandObj = $this.Commands[$action]
        if ($null -eq $commandObj) {
            # Special case: disconnect is a no-op for some platforms but users should still call it to unlock resources.
            if ($action -ne 'disconnect') {
                Write-Warning "Command '$action' is not available for platform '$($this.Platform)'"
            }
            return $null
        }

        $executablePath = $this.GetToolPath($commandObj[0])

        $arguments = $commandObj[1]
        if ($null -ne $parameters) {
            $arguments = $arguments -f $parameters
        }
        return "& '$executablePath' $arguments 2>&1"
    }


    [void] LogNotImplemented([string]$operation) {
        Write-Warning "$($this.Platform) $operation not yet implemented"
    }

    # Helper method to invoke a command with timeout and retry handling
    # This method is used internally when TimeoutSeconds > 0
    [object] InvokeCommandWithTimeoutAndRetry([scriptblock]$scriptBlock, [string]$platform, [string]$action, [string]$command) {
        $attempt = 1

        while ($attempt -le $this.MaxRetryAttempts) {
            try {
                # Only log attempt info for retries
                if ($attempt -gt 1) {
                    Write-Warning "$($this.Platform): Retry attempt $attempt of $($this.MaxRetryAttempts) for command ($action)"
                }

                # Start job with the provided scriptblock and arguments
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $platform, $action, $command

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
        # Build command once and check for null
        $command = $this.BuildCommand($action, $parameters)
        if ($null -eq $command) {
            return $null
        }

        # Build the execution scriptblock once - used for both timeout and non-timeout paths
        $scriptBlock = {
            param($platform, $act, $cmd)
            try {
                $PSNativeCommandUseErrorActionPreference = $false
                Write-Debug "${platform}: Invoking ($act) command $cmd"
                $result = Invoke-Expression "$cmd | Tee-Object -variable capturedOutput | Foreach-Object { Write-Debug `$_ } ; `$capturedOutput"
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Command ($act`: $cmd) failed with exit code $($LASTEXITCODE) $($result.Length -gt 0 ? 'and output:' : '')"
                    $result | ForEach-Object { Write-Warning $_ }
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

        # If timeout is enabled and we're not in the middle of a reboot, use timeout handling
        if ($effectiveTimeout -gt 0 -and -not $this.IsRebooting) {
            # Temporarily override TimeoutSeconds for this specific action
            $originalTimeout = $this.TimeoutSeconds
            $this.TimeoutSeconds = $effectiveTimeout
            try {
                return $this.InvokeCommandWithTimeoutAndRetry($scriptBlock, $this.Platform, $action, $command)
            } finally {
                $this.TimeoutSeconds = $originalTimeout
            }
        }

        # Otherwise, execute directly without timeout
        return & $scriptBlock $this.Platform $action $command
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

    [hashtable] RunApplication([string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "$($this.Platform): Running application: $ExecutablePath with arguments: $Arguments"

        $command = $this.BuildCommand('launch', @($ExecutablePath, $Arguments))
        return $this.InvokeApplicationCommand($command, $ExecutablePath, $Arguments)
    }

    [hashtable] InvokeApplicationCommand([string]$command, [string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "$($this.Platform): Invoking $command"

        $result = $null
        $exitCode = $null
        $startDate = Get-Date
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $result = Invoke-Expression "$command | Tee-Object -variable capturedOutput | Foreach-Object { Write-Debug `$_ } ; `$capturedOutput"
            $exitCode = $LASTEXITCODE
        } finally {
            $PSNativeCommandUseErrorActionPreference = $true
        }

        # Convert output to string (it's actually a list of ErrorRecord in case the command writes to stdout).
        if ($result) {
            $result = $result | ForEach-Object {
                ($_ | Out-String).Trim()
            } | Where-Object {
                $_.Length -gt 0
            }
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

}
