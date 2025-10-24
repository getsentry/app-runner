# PlayStation5 Device Provider Implementation
# Implements device operations for PlayStation 5 development kits


# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

<#
.SYNOPSIS
Device provider for PlayStation 5 development kits.

.DESCRIPTION
This provider implements PlayStation 5 specific device operations using the PlayStation 5 development CLI tools.
It handles connection management, device lifecycle operations, and application management.
#>
class PlayStation5Provider : DeviceProvider {
    [string]$TargetControlTool = "prospero-ctrl.exe"
    [string]$ApplicationRunnerTool = "prospero-run.exe"

    PlayStation5Provider() {
        $this.Platform = "PlayStation5"

        # Set SDK path if SCE_ROOT_DIR environment variable is available
        $sceRootDir = $env:SCE_ROOT_DIR
        if ($sceRootDir) {
            $this.SdkPath = Join-Path $sceRootDir "Prospero\Tools\Target Manager Server\bin"
        } else {
            Write-Warning "SCE_ROOT_DIR environment variable not set. Assuming PlayStation SDK tools are in PATH."
            $this.SdkPath = $null
        }

        # Configure PlayStation 5 specific commands using Command objects
        $this.Commands = @{
            "connect"     = @($this.TargetControlTool, "target connect")
            "disconnect"  = @($this.TargetControlTool, "target disconnect")
            "poweron"     = @($this.TargetControlTool, "power on")
            "poweroff"    = @($this.TargetControlTool, "power off")
            "reset"       = @($this.TargetControlTool, "power reboot")
            "getstatus"   = @($this.TargetControlTool, "target info")
            "launch"      = @($this.ApplicationRunnerTool, '/elf "{0}" {1}')
            "getlogs"     = @($this.TargetControlTool, "target console /timestamp /history")
            "screenshot"  = @($this.TargetControlTool, 'target screenshot "{0}/{1}"')
            "healthcheck" = @($this.TargetControlTool, "diagnostics health-check")
            "ipconfig"    = @($this.TargetControlTool, "network ip-config")
            "natinfo"     = @($this.TargetControlTool, "network get-nat-traversal-info")
            "processlist" = @($this.TargetControlTool, "process list")
        }
    }

    # override GetDeviceLogs to provide PlayStation 5 specific log retrieval
    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        $result = @{}
        if ($LogType -eq 'System' -or $LogType -eq 'All') {
            # prospero-ctrl target console waits for ctrl+c to exit so we run it as a job and stop it after an arbitrary timeout
            Write-Debug "Retrieving system logs"
            $job = Start-Job { param($cmd)
                Write-Debug "Executing command: $cmd"
                return Invoke-Expression $cmd
            } -ArgumentList $this.BuildCommand('getlogs', @())
            $job | Wait-Job -Timeout 5 | Stop-Job
            # Note: the command is actually executed internally as another job, so we need to retrieve the output from the child job
            # Printing the following helps:
            # $job | Select-Object -Property * | Out-Host
            # $job.ChildJobs[0] | Select-Object -Property * | Out-Host
            $text = $job.ChildJobs[0].Output

            $result['System'] = $text | Select-Object -Last $MaxEntries | ForEach-Object {
                # Parse '[16:30:17] [DECI] Finished to notify DRFP disconnection to DRFS.'
                $logLine = $_.Trim()
                if ([string]::IsNullOrEmpty($logLine)) {
                    return $null
                }
                try {
                    $timestamp = $logLine.Substring(1, 8)
                    $rest = $logLine.Substring(11).Split(' ')
                    @{
                        Timestamp = $timestamp
                        Source    = $rest[0].Trim('[', ']')
                        Message   = $rest[1..($rest.Length - 1)] -join ' '
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

    [string] GetDeviceIdentifier() {
        $status = $this.GetDeviceStatus()
        $statusData = $status.StatusData

        # Try to extract GameLanIpAddress from PS5 status text
        $line = $statusData | Where-Object { $_ -match 'GameLanIpAddress' }
        return $line.Split(':')[1].Trim()
    }

    # Override GetRunningProcesses to provide PlayStation 5 process list via prospero-ctrl
    # Returns array of objects with Id, ParentPid, Name, and Path properties
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): Collecting running processes via prospero-ctrl process list"
        $output = $this.InvokeCommand('processlist', @())

        # Parse prospero-ctrl process list output
        # Format is YAML-like:
        # - Id: 0x00000063
        #   ParentPid: 0x0000003b
        #   Name: eboot.bin
        #   Path: /app0/eboot.bin
        $processes = @()
        $currentProcess = $null

        foreach ($line in $output) {
            $trimmedLine = $line.Trim()

            if ($trimmedLine -match '^- Id: (0x[0-9a-fA-F]+)') {
                # Start of a new process entry
                if ($currentProcess) {
                    $processes += $currentProcess
                }
                $currentProcess = [PSCustomObject]@{
                    Id = [Convert]::ToInt32($matches[1], 16)  # Convert hex to decimal
                    ParentPid = $null
                    Name = $null
                    Path = $null
                }
            }
            elseif ($currentProcess) {
                if ($trimmedLine -match '^ParentPid: (0x[0-9a-fA-F]+)') {
                    $currentProcess.ParentPid = [Convert]::ToInt32($matches[1], 16)
                }
                elseif ($trimmedLine -match '^Name: (.+)') {
                    $currentProcess.Name = $matches[1].Trim()
                }
                elseif ($trimmedLine -match '^Path: (.+)') {
                    $currentProcess.Path = $matches[1].Trim()
                }
            }
        }

        # Add the last process if exists
        if ($currentProcess) {
            $processes += $currentProcess
        }

        return $processes
    }

    [hashtable] GetDiagnostics([string]$OutputDirectory) {
        # Call base implementation to collect standard diagnostics
        $results = ([DeviceProvider]$this).GetDiagnostics($OutputDirectory)

        # Add PlayStation 5 specific diagnostics
        $datePrefix = Get-Date -Format 'yyyyMMdd-HHmmss'

        # Run prospero-ctrl diagnostics health-check
        try {
            $healthCheckFile = Join-Path $OutputDirectory "$datePrefix-health-check.txt"
            $healthCheckOutput = $this.InvokeCommand('healthcheck', @())
            $healthCheckOutput | Out-File -FilePath $healthCheckFile -Encoding UTF8
            $results.Files += $healthCheckFile
            Write-Debug "Health check saved to: $healthCheckFile"
        } catch {
            Write-Warning "Failed to collect health check diagnostics: $_"
        }

        # Run prospero-ctrl network ip-config
        try {
            $ipConfigFile = Join-Path $OutputDirectory "$datePrefix-network-ip-config.txt"
            $ipConfigOutput = $this.InvokeCommand('ipconfig', @())
            $ipConfigOutput | Out-File -FilePath $ipConfigFile -Encoding UTF8
            $results.Files += $ipConfigFile
            Write-Debug "Network IP config saved to: $ipConfigFile"
        } catch {
            Write-Warning "Failed to collect network IP config: $_"
        }

        # Run prospero-ctrl network get-nat-traversal-info
        try {
            $natInfoFile = Join-Path $OutputDirectory "$datePrefix-network-nat-traversal-info.txt"
            $natInfoOutput = $this.InvokeCommand('natinfo', @())
            $natInfoOutput | Out-File -FilePath $natInfoFile -Encoding UTF8
            $results.Files += $natInfoFile
            Write-Debug "NAT traversal info saved to: $natInfoFile"
        } catch {
            Write-Warning "Failed to collect NAT traversal info: $_"
        }

        return $results
    }

}
