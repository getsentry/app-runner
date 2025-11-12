# macOS Provider
# Platform-specific implementation for local macOS desktop execution

<#
.SYNOPSIS
Provider for running applications on local macOS machines.

.DESCRIPTION
macOS-specific provider that implements local application execution, diagnostics
collection, and system monitoring for macOS desktop platforms.

Supported operations:
- Run applications locally with output capture
- Take screenshots using screencapture
- Enumerate running processes
- Collect system diagnostics

Not supported:
- Device lifecycle (shutdown/reboot) - not applicable for local machine
- Device logs - not implemented yet
#>

. "$PSScriptRoot\LocalComputerProvider.ps1"

class MacOSProvider : LocalComputerProvider {

    MacOSProvider() {
        $this.Platform = 'MacOS'

        # Define macOS-specific commands
        $this.Commands = @{
            # Inherited from LocalComputerProvider (all $null):
            # connect, disconnect, poweron, poweroff, reset, getstatus

            # macOS-specific implementations:
            'launch'     = @('{0}', '{1}')
            'screenshot' = @('screencapture', '-x ''{0}/{1}''')
        }
    }

    # Override GetRunningProcesses to use ps
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): Getting running processes"

        try {
            # Use ps with specific format to get process information
            # Format: PID, %CPU, %MEM, COMMAND
            $psOutput = ps -Aco pid,%cpu,%mem,comm | Select-Object -Skip 1

            if (-not $psOutput) {
                return $null
            }

            # Parse ps output
            $processes = $psOutput | ForEach-Object {
                $line = $_.Trim()
                # Split on whitespace, limit to 4 fields
                $parts = $line -split '\s+', 4

                if ($parts.Count -ge 4) {
                    @{
                        ProcessId = [int]$parts[0]
                        CPU       = [decimal]$parts[1]
                        Memory    = [decimal]$parts[2]
                        Name      = $parts[3]
                    }
                }
            } | Where-Object { $null -ne $_ } |
                Sort-Object -Property CPU -Descending |
                Select-Object -First 50  # Limit to top 50 processes by CPU

            return $processes

        } catch {
            Write-Warning "$($this.Platform): Failed to get running processes: $_"
            return $null
        }
    }

    # Override ValidateLocalEnvironment to add macOS-specific checks
    [void] ValidateLocalEnvironment() {
        Write-Debug "$($this.Platform): Validating macOS environment"

        # Check if running on macOS by attempting to access macOS-specific API
        try {
            $runningOnMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
            if (-not $runningOnMacOS) {
                throw "MacOSProvider can only run on macOS platforms"
            }
        } catch {
            Write-Warning "Could not validate macOS platform: $_"
        }

        # Verify screencapture tool exists
        $screencaptureExists = Get-Command screencapture -ErrorAction SilentlyContinue
        if (-not $screencaptureExists) {
            Write-Warning "screencapture command not found. Screenshot functionality may not work."
        }
    }

    # Override GetDiagnostics to add macOS-specific diagnostics
    [hashtable] GetDiagnostics([string]$OutputDirectory) {
        Write-Debug "$($this.Platform): Collecting macOS diagnostics to directory: $OutputDirectory"

        # Call base implementation first
        $results = ([DeviceProvider]$this).GetDiagnostics($OutputDirectory)

        $datePrefix = Get-Date -Format 'yyyyMMdd-HHmmss'

        # Add macOS-specific system information using system_profiler
        try {
            $sysInfoFile = Join-Path $OutputDirectory "$datePrefix-macos-sysinfo.txt"

            # Get basic system info
            $hostname = hostname
            $osVersion = sw_vers -productVersion
            $buildVersion = sw_vers -buildVersion

            $sysInfo = @"
=== macOS System Information ===
Computer Name: $hostname
OS Version: macOS $osVersion (Build $buildVersion)
Current Directory: $(Get-Location)
Collection Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

=== Hardware Overview ===
"@
            # Get hardware info (this can be slow, so we limit it)
            $hwInfo = system_profiler SPHardwareDataType 2>&1
            $sysInfo += "`n$hwInfo"

            $sysInfo | Out-File -FilePath $sysInfoFile -Encoding UTF8
            $results.Files += $sysInfoFile
            Write-Debug "macOS system info saved to: $sysInfoFile"
        } catch {
            Write-Warning "Failed to collect macOS system information: $_"
        }

        # Add environment variables
        try {
            $envFile = Join-Path $OutputDirectory "$datePrefix-macos-environment.txt"
            Get-ChildItem Env: | Sort-Object Name | Format-Table -AutoSize |
                Out-File -FilePath $envFile -Encoding UTF8 -Width 200
            $results.Files += $envFile
            Write-Debug "Environment variables saved to: $envFile"
        } catch {
            Write-Warning "Failed to collect environment variables: $_"
        }

        Write-Debug "macOS diagnostics collection complete. Total files: $($results.Files.Count)"
        return $results
    }
}
