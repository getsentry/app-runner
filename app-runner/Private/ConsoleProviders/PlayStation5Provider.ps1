# PlayStation5 Console Provider Implementation
# Implements console operations for PlayStation 5 development kits


# Load the base provider
. "$PSScriptRoot\ConsoleProvider.ps1"

<#
.SYNOPSIS
Console provider for PlayStation 5 development kits.

.DESCRIPTION
This provider implements PlayStation 5 specific console operations using the PlayStation 5 development CLI tools.
It handles connection management, console lifecycle operations, and application management.
#>
class PlayStation5Provider : ConsoleProvider {
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
            "connect"    = @($this.TargetControlTool, "target connect")
            "disconnect" = @($this.TargetControlTool, "target disconnect")
            "poweron"    = @($this.TargetControlTool, "power on")
            "poweroff"   = @($this.TargetControlTool, "power off")
            "reset"      = @($this.TargetControlTool, "power reboot")
            "getstatus"  = @($this.TargetControlTool, "target info")
            "launch"     = @($this.ApplicationRunnerTool, '/elf "{0}" {1}')
            "getlogs"    = @($this.TargetControlTool, "target console /timestamp /history")
            "screenshot" = @($this.TargetControlTool, 'target screenshot "{0}/{1}"')
        }
    }

    # override GetConsoleLogs to provide Switch specific log retrieval
    [hashtable] GetConsoleLogs([string]$LogType, [int]$MaxEntries) {
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

    [string] GetConsoleIdentifier() {
        $status = $this.GetConsoleStatus()
        $statusData = $status.StatusData

        # Try to extract GameLanIpAddress from PS5 status text
        $line = $statusData | Where-Object { $_ -match 'GameLanIpAddress' }
        return $line.Split(':')[1].Trim()
    }

}
