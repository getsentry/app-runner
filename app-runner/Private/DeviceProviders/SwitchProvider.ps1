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

    SwitchProvider() {
        $this.Platform = 'Switch'

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
            'poweron-target'     = @($this.TargetControlTool, 'power-on -t {0}')
            'poweroff'           = @($this.TargetControlTool, 'power-off')
            'press-power-button' = @($this.TargetControlTool, 'press-power-button')
            'reset'              = @($this.TargetControlTool, 'reset')
            'getstatus'          = @($this.TargetControlTool, 'get-default --detail --json')
            'detect-target'      = @($this.TargetControlTool, 'detect-target --detail --json')
            'launch'             = @($this.ApplicationRunnerTool, '"{0}" {1}')
            'screenshot'         = @($this.TargetControlTool, 'take-screenshot --directory "{0}" --file-name "{1}"')
            'test-internet'      = @($this.TargetControlTool, 'devmenu -- network confirm-internet-connection')
        }
    }

    [void] HandleMissingDefaultDevkit() {
        Write-Warning 'No default devkit found. Attempting to detect available devkits on the network...'

        # Run detect-target to find available devkits
        $detectResult = $this.InvokeCommand('detect-target', @())

        if ([string]::IsNullOrWhiteSpace($detectResult)) {
            throw 'No default devkit is set and no devkits were detected on the network.'
        }

        $detectedTargets = $detectResult | ConvertFrom-Json
        Write-Debug "Detected targets: $($detectedTargets | ConvertTo-Json -Compress)"

        # Extract target name
        $targetId = $detectedTargets[0].Name
        if ([string]::IsNullOrWhiteSpace($targetId)) {
            throw 'No detected Devkit on the network.'
        }

        Write-Warning "Attempting to power on devkit at $targetId..."
        $this.InvokeCommand('poweron-target', @($targetId))
    }

    # Override GetDeviceStatus to provide Switch specific wakeup
    [hashtable] GetDeviceStatus() {
        $status = ([DeviceProvider] $this).GetDeviceStatus()
        $status.StatusData = $status.StatusData | ConvertFrom-Json
        return $status
    }

    [string] GetDeviceIdentifier() {
        $status = $this.GetDeviceStatus()
        $statusData = $status.StatusData
        return $statusData.IpAddress
    }

    # Override Connect to provide Switch specific wakeup
    [hashtable] Connect() {
        Write-Debug 'Connecting to Switch Devkit...'

        # Note: Connect may hang so we run it in a background job and manually time out.
        $connectCommand = $this.BuildCommand('connect', @())
        $job = Start-Job { param($cmd) Invoke-Expression $cmd } -ArgumentList $connectCommand

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
                    $this.HandleMissingDefaultDevkit()
                }
                1 {
                    Write-Warning 'Attempting to start the Devkit...'
                    if ($info.IpAddress) {
                        $this.InvokeCommand('poweron-target', @($targetId))
                    }
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
