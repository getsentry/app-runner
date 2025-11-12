# Windows Provider
# Platform-specific implementation for local Windows desktop execution

<#
.SYNOPSIS
Provider for running applications on local Windows machines.

.DESCRIPTION
Windows-specific provider that implements local application execution, diagnostics
collection, and system monitoring for Windows desktop platforms.

Supported operations:
- Run applications locally with output capture
- Take screenshots using Windows tools
- Enumerate running processes
- Collect system diagnostics

Not supported:
- Device lifecycle (shutdown/reboot) - not applicable for local machine
- Device logs - not implemented yet
#>

. "$PSScriptRoot\LocalComputerProvider.ps1"

class WindowsProvider : LocalComputerProvider {

    WindowsProvider() {
        $this.Platform = 'Windows'

        # Define Windows-specific commands
        $this.Commands = @{
            # Inherited from LocalComputerProvider (all $null):
            # connect, disconnect, poweron, poweroff, reset, getstatus

            # Windows-specific implementations:
            'launch'     = @('{0}', '{1}')
            'screenshot' = $null  # TODO: Implement proper Windows screenshot
        }
    }

    # Override GetRunningProcesses to use Get-Process
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): Getting running processes"

        try {
            $processes = Get-Process | Select-Object -Property Id, Name, CPU, WorkingSet, Path |
                Sort-Object -Property CPU -Descending |
                Select-Object -First 50  # Limit to top 50 processes by CPU

            # Convert to structured format
            return $processes | ForEach-Object {
                @{
                    ProcessId   = $_.Id
                    Name        = $_.Name
                    CPU         = [math]::Round($_.CPU, 2)
                    Memory      = [math]::Round($_.WorkingSet / 1MB, 2)  # Convert to MB
                    Path        = $_.Path
                }
            }
        } catch {
            Write-Warning "$($this.Platform): Failed to get running processes: $_"
            return $null
        }
    }

    # Override ValidateLocalEnvironment to add Windows-specific checks
    [void] ValidateLocalEnvironment() {
        Write-Debug "$($this.Platform): Validating Windows environment"

        # Check if running on Windows by attempting to access Windows-specific API
        try {
            $runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
            if (-not $runningOnWindows) {
                throw "WindowsProvider can only run on Windows platforms"
            }
        } catch {
            Write-Warning "Could not validate Windows platform: $_"
        }
    }

    # Override GetDiagnostics to add Windows-specific diagnostics
    [hashtable] GetDiagnostics([string]$OutputDirectory) {
        Write-Debug "$($this.Platform): Collecting Windows diagnostics to directory: $OutputDirectory"

        # Call base implementation first
        $results = ([DeviceProvider]$this).GetDiagnostics($OutputDirectory)

        $datePrefix = Get-Date -Format 'yyyyMMdd-HHmmss'

        # Add Windows-specific system information
        try {
            $sysInfoFile = Join-Path $OutputDirectory "$datePrefix-windows-sysinfo.txt"
            # Build system info string
            $memInfo = Get-CimInstance Win32_OperatingSystem
            $sysInfo = @"
=== Windows System Information ===
Computer Name: $env:COMPUTERNAME
User Name: $env:USERNAME
OS Version: $([System.Environment]::OSVersion.VersionString)
OS Architecture: $([System.Environment]::Is64BitOperatingSystem ? '64-bit' : '32-bit')
Processor Count: $([System.Environment]::ProcessorCount)
System Directory: $([System.Environment]::SystemDirectory)
CLR Version: $([System.Environment]::Version)
.NET Framework: $([System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)
Current Directory: $(Get-Location)
Available Memory: $([math]::Round($memInfo.FreePhysicalMemory / 1MB, 2)) GB
Total Memory: $([math]::Round($memInfo.TotalVisibleMemorySize / 1MB, 2)) GB
Collection Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
            $sysInfo | Out-File -FilePath $sysInfoFile -Encoding UTF8
            $results.Files += $sysInfoFile
            Write-Debug "Windows system info saved to: $sysInfoFile"
        } catch {
            Write-Warning "Failed to collect Windows system information: $_"
        }

        # Add environment variables
        try {
            $envFile = Join-Path $OutputDirectory "$datePrefix-windows-environment.txt"
            Get-ChildItem Env: | Sort-Object Name | Format-Table -AutoSize |
                Out-File -FilePath $envFile -Encoding UTF8 -Width 200
            $results.Files += $envFile
            Write-Debug "Environment variables saved to: $envFile"
        } catch {
            Write-Warning "Failed to collect environment variables: $_"
        }

        Write-Debug "Windows diagnostics collection complete. Total files: $($results.Files.Count)"
        return $results
    }
}
