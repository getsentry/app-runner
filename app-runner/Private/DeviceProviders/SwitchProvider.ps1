# Switch Device Provider Implementation
# Implements device operations for Nintendo Switch development units


# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

<#
.SYNOPSIS
Device provider for Nintendo Switch development units.

.DESCRIPTION
This provider implements Nintendo Switch specific device operations using the Nintendo Switch development CLI tools.
It handles connection management, device lifecycle operations, and application management.
#>
class SwitchProvider : DeviceProvider {
    [string]$TargetControlTool = 'ControlTarget.exe'
    [string]$ApplicationRunnerTool = 'RunOnTarget.exe'
    [string]$Target = $null  # Stores the target device identifier for commands that need explicit --target

    SwitchProvider() {
        $this.Platform = 'Switch'

        # Switch supports checking if a default target is set even with multiple targets registered,
        # so start detection at state 0 (check default first) instead of state 1 (list all targets)
        $this.DetectTargetInitialState = 0

        # Set SDK path if NINTENDO_SDK_ROOT environment variable is available
        $nintendoSdkRoot = $env:NINTENDO_SDK_ROOT
        if ($nintendoSdkRoot) {
            $this.SdkPath = Join-Path $nintendoSdkRoot 'Tools\CommandLineTools'
        } else {
            Write-Warning 'NINTENDO_SDK_ROOT environment variable not set. Assuming Nintendo Switch SDK tools are in PATH.'
            $this.SdkPath = $null
        }

        # Configure Nintendo Switch specific commands using Command objects
        $this.Commands = @{
            'connect'            = @($this.TargetControlTool, 'connect --force')
            'disconnect'         = @($this.TargetControlTool, 'disconnect')
            'poweron'            = @($this.TargetControlTool, 'power-on')
            'poweroff'           = @($this.TargetControlTool, 'power-off')
            'press-power-button' = @($this.TargetControlTool, 'press-power-button')
            'reset'              = @($this.TargetControlTool, 'reset')
            'getstatus'          = @($this.TargetControlTool, 'get-default --detail --json', { $input | ConvertFrom-Json })
            'get-default-target' = @($this.TargetControlTool, 'get-default --json', { $input | ConvertFrom-Json })
            'set-default-target' = @($this.TargetControlTool, 'set-default --target "{0}"')
            'list-target'        = @($this.TargetControlTool, 'list-target --json', { $input | ConvertFrom-Json })
            'detect-target'      = @($this.TargetControlTool, 'detect-target --json', { $input | ConvertFrom-Json })
            'register-target'    = @($this.TargetControlTool, 'register --target "{0}"')
            'launch'             = @($this.ApplicationRunnerTool, '"{0}" -- {1}')
            'screenshot'         = @($this.TargetControlTool, 'take-screenshot --directory "{0}" --file-name "{1}"')
            'test-internet'      = @($this.TargetControlTool, 'devmenu -- network confirm-internet-connection')
        }
    }

    [string] GetDeviceIdentifier() {
        $status = $this.GetDeviceStatus()
        $statusData = $status.StatusData
        return $statusData.IpAddress
    }

    # Override Connect to support target parameter
    # Sets the default target via ControlTarget so subsequent commands (including RunOnTarget via ctest) use it
    [hashtable] Connect([string]$target) {
        if (-not [string]::IsNullOrEmpty($target)) {
            Write-Debug "$($this.Platform): Setting target device: $target"
            $this.Target = $target
            $this.InvokeCommand('set-default-target', @($target))
        }
        return $this.Connect()
    }

    # Override Connect to provide Switch specific wakeup
    [hashtable] Connect() {
        Write-Debug 'Connecting to Switch Devkit...'

        $this.DetectAndSetDefaultTarget()

        # Note: Connect may hang so we run it in a background job and manually time out.
        $builtCommand = $this.BuildCommand('connect', @())
        $job = Start-Job { param($cmd) Invoke-Expression $cmd } -ArgumentList $builtCommand.Command

        $nextTimeout = 20
        for ($i = 0; $i -le 3; $i++) {
            $jobStatus = Wait-Job $job -Timeout 20

            # Get device status using base class method
            $info = $this.GetDeviceStatus().StatusData

            if ($jobStatus -ne $null) {
                if (("$($info.Status)" -eq 'Asleep') -and ($i -ne 0)) {
                    $i = 0
                    continue
                } elseif ("$($info.Status)" -eq 'Connected') {
                    break
                } else {
                    Write-Warning "Switch Devkit is in an unexpected state: $($info.Status)."
                }
            }

            switch ($i) {
                0 {
                    Write-Warning 'Attempting to wake up the Devkit from sleep...'
                    $this.InvokeCommand('press-power-button', @())
                }
                1 {
                    Write-Warning 'Attempting to start the Devkit...'
                    $this.StartDevice()
                }
                2 {
                    Write-Warning 'Attempting to reboot the Devkit...'
                    $job2 = Start-Job {
                        ControlTarget power-off
                        Start-Sleep -Seconds 5
                        ControlTarget power-on
                    }
                    Wait-Job $job2 -Timeout 20 | Out-Null
                }
                3 {
                    if ($info.IpAddress -ne $null) {
                        Write-Warning 'Attempting to reboot host bridge...'
                        Invoke-WebRequest -Uri "http://$($info.IpAddress)/cgi-bin/config?reboot"
                        $nextTimeout = 300 # This takes a long time so wait longer next time
                    }
                }
            }
        }

        if ((Wait-Job $job -Timeout $nextTimeout) -eq $null) {
            Stop-Job $job
            throw 'Failed to connect to the Switch Devkit.'
        }

        Write-Debug 'Successfully connected to the Switch Devkit.'
        return $this.CreateSessionInfo()
    }

    # override StopDevice because it exits immediately but actually takes a while to finish
    [void] StopDevice() {
        ([DeviceProvider] $this).StopDevice();
        Start-Sleep -Seconds 3
    }

    # Override TakeScreenshot to pass --target when a target is specified
    [void] TakeScreenshot([string]$OutputPath) {
        $directory = Split-Path $OutputPath -Parent
        $filename = Split-Path $OutputPath -Leaf
        if (-not $directory) {
            $directory = Get-Location
        }

        Write-Debug "$($this.Platform): Taking screenshot (directory: $directory, file: $filename)"

        # Build command with --target if target was specified during Connect()
        $targetArg = if (-not [string]::IsNullOrEmpty($this.Target)) { "--target $($this.Target) " } else { '' }
        $toolPath = $this.GetToolPath($this.TargetControlTool)
        $command = "& '$toolPath' ${targetArg}take-screenshot --directory `"$directory`" --file-name `"$filename`" 2>&1"

        Write-Debug "$($this.Platform): Invoking screenshot command: $command"
        $result = Invoke-Expression "$command | $($this.DebugOutputForwarder)"
        if ($LASTEXITCODE -ne 0) {
            throw "Screenshot command failed with exit code $LASTEXITCODE"
        }

        $size = (Get-Item $OutputPath).Length
        Write-Debug "Screenshot saved to $OutputPath ($size bytes)"
    }

    # override GetDeviceLogs to provide Switch specific log retrieval
    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        $session = Get-DeviceSession

        $result = @{}
        if ($LogType -eq 'System' -or $LogType -eq 'All') {
            $url = "http://$($session.StatusData.IpAddress)/cgi-bin/messages"
            Write-Debug "Retrieving system logs from $url"
            $text = (Invoke-WebRequest -Uri $url).Content
            $result['System'] = $text -split "`n" | Select-Object -Last $MaxEntries | ForEach-Object {
                # Parse 'Jan  1 18:38:07 XAL06100010154 user.info pc_control[936]: 1970/01/01 18:38:07 [user@WIN01 187]stream.Recv() returned err, rpc error: code = Canceled desc = context canceled. End SetUser'
                $logLine = $_.Trim()
                if ([string]::IsNullOrEmpty($logLine) -or $logLine.Length -lt 16) {
                    return $null
                }
                try {
                    $date = $logLine.Substring(0, 15)
                    $rest = $logLine.Substring(16).Split(' ')
                    @{
                        Timestamp = $date
                        Device    = $rest[0]
                        Level     = $rest[1]
                        Source    = $rest[2].TrimEnd(':')
                        Message   = $rest[3..($rest.Length - 1)] -join ' '
                    }
                } catch {
                    Write-Warning "Failed to parse log entry: $logLine"
                    return $null
                }
            } | Where-Object { $_ -ne $null }
        } else {
            Write-Error 'Unknown log type requested. Only System logs are supported.'
        }

        return $result
    }

    # override TestInternetConnection to provide Switch specific implementation
    [bool] TestInternetConnection() {
        Write-Debug 'Testing internet connection on Switch Devkit...'

        $result = $this.InvokeCommand('test-internet', @())

        # Check if the output contains the success indicator
        if ($result -match 'Internet Connection: Confirmed') {
            Write-Debug 'Internet connection confirmed on Switch Devkit'
            return $true
        } else {
            Write-Debug 'No internet connection detected on Switch Devkit'
            return $false
        }
    }
}
