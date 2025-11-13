# Linux Provider
# Platform-specific implementation for local Linux desktop execution

<#
.SYNOPSIS
Provider for running applications on local Linux machines.

.DESCRIPTION
Linux-specific provider that implements local application execution, diagnostics
collection, and system monitoring for Linux desktop platforms.

Supported operations:
- Run applications locally with output capture
- Take screenshots using various Linux utils based on session and desktop type
- Enumerate running processes
- Collect system diagnostics

Not supported:
- Device lifecycle (shutdown/reboot) - not applicable for local machine
- Device logs - not implemented yet
#>

. "$PSScriptRoot\LocalComputerProvider.ps1"

class LinuxProvider : LocalComputerProvider {

    LinuxProvider() {
        $this.Platform = 'Linux'

        # Validate environment immediately
        if (-not $global:IsLinux) {
            throw "LinuxProvider can only run on Linux platforms"
        }

        # Detect available screenshot tool
        $screenshotTool = $this.DetectScreenshotTool()

        # Define Linux-specific commands
        $this.Commands = @{
            # Local execution operations (all no-ops)
            'connect'    = $null
            'disconnect' = $null
            'poweron'    = $null
            'poweroff'   = $null
            'reset'      = $null
            'getstatus'  = $null

            # Linux-specific implementations
            'launch'     = @('{0}', '{1}')
            'screenshot' = $screenshotTool
        }

        # Warn if no screenshot tool is available (non-fatal)
        if ($null -eq $screenshotTool) {
            Write-Warning "No screenshot tool available. Install gnome-screenshot, scrot, or ImageMagick for screenshot support."
        }
    }

    # Detect available screenshot tool on Linux
    [object] DetectScreenshotTool() {
        # Check session type for optimal tool selection
        $sessionType = $env:XDG_SESSION_TYPE

        # Wayland display server
        if ($sessionType -eq "wayland") {
            # Try grim utility (using screencopy protocol)
            if (Get-Command grim -ErrorAction SilentlyContinue) {
                Write-Debug "Using grim for Wayland screenshot capture"
                return @('grim', '''{0}/{1}''')
            }
        }

        # X11 or fallback options
        if ($sessionType -eq "x11" -or $null -eq $sessionType) {
            # Try scrot (lightweight and fast)
            if (Get-Command scrot -ErrorAction SilentlyContinue) {
                Write-Debug "Using scrot for X11 capture"
                return @('scrot', '''{0}/{1}''')
            }

            # Try ImageMagick import (universal but slower)
            if (Get-Command import -ErrorAction SilentlyContinue) {
                Write-Debug "Using ImageMagick import for X11 capture"
                return @('import', '-window root ''{0}/{1}''')
            }

            # Try xwd as last resort for X11
            if ((Get-Command xwd -ErrorAction SilentlyContinue) -and (Get-Command convert -ErrorAction SilentlyContinue)) {
                Write-Debug "Using xwd+convert for X11 capture"
                return @('sh', '-c "xwd -root | convert xwd:- ''{0}/{1}''"')
            }
        }

        # Try DE-specific options
        $currentDesktop = $env:XDG_CURRENT_DESKTOP

        if ($currentDesktop -eq 'GNOME') {
            # Try gnome-screenshot (most reliable on GNOME)
            if (Get-Command gnome-screenshot -ErrorAction SilentlyContinue) {
                Write-Debug "Using gnome-screenshot for X11 capture"
                return @('gnome-screenshot', '-f ''{0}/{1}''')
            }
        }

        if ($currentDesktop -eq "KDE") {
            # Try spectacle (KDE)
            if (Get-Command spectacle -ErrorAction SilentlyContinue) {
                Write-Debug "Using spectacle as fallback"
                return @('spectacle', '-b -f -o ''{0}/{1}''')
            }
        }

        # Try maim (works on X11, some Wayland)
        if (Get-Command maim -ErrorAction SilentlyContinue) {
            Write-Debug "Using maim as fallback"
            return @('maim', '''{0}/{1}''')
        }

        # No screenshot tool available
        Write-Warning "No screenshot tool found (grim, gnome-screenshot, scrot, or ImageMagick). Screenshot functionality will not work."
        return $null
    }

    # Override GetRunningProcesses to use ps
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): Getting running processes"

        try {
            # Use ps with specific format to get process information
            # Format: PID, %CPU, %MEM, COMMAND
            $psOutput = ps -Ao pid,%cpu,%mem,comm --sort=-%cpu | Select-Object -Skip 1

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
                Select-Object -First 50  # Limit to top 50 processes by CPU

            return $processes

        } catch {
            Write-Warning "$($this.Platform): Failed to get running processes: $_"
            return $null
        }
    }

    # Override GetDiagnostics to add Linux-specific diagnostics
    [hashtable] GetDiagnostics([string]$OutputDirectory) {
        Write-Debug "$($this.Platform): Collecting Linux diagnostics to directory: $OutputDirectory"

        # Call base implementation first
        $results = ([DeviceProvider]$this).GetDiagnostics($OutputDirectory)

        $datePrefix = Get-Date -Format 'yyyyMMdd-HHmmss'

        # Add Linux-specific system information
        try {
            $sysInfoFile = Join-Path $OutputDirectory "$datePrefix-linux-sysinfo.txt"

            # Get basic system info
            $hostname = [System.Environment]::MachineName
            $kernelVersion = if (Get-Command uname -ErrorAction SilentlyContinue) { & uname -r } else { "Unknown" }
            $osInfo = if (Test-Path /etc/os-release) {
                Get-Content /etc/os-release | Where-Object { $_ -match '^(NAME|VERSION|ID)=' }
            } else {
                "OS info not available"
            }

            $sysInfo = @"
=== Linux System Information ===
Computer Name: $hostname
Kernel Version: $kernelVersion
OS Information:
$($osInfo -join "`n")
Current Directory: $(Get-Location)
Collection Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

=== CPU Information ===
$(if (Test-Path /proc/cpuinfo) { (Get-Content /proc/cpuinfo | Select-Object -First 20) -join "`n" } else { "CPU info not available" })

=== Memory Information ===
$(if (Test-Path /proc/meminfo) { (Get-Content /proc/meminfo | Select-Object -First 10) -join "`n" } else { "Memory info not available" })
"@
            $sysInfo | Out-File -FilePath $sysInfoFile -Encoding UTF8
            $results.Files += $sysInfoFile
            Write-Debug "Linux system info saved to: $sysInfoFile"
        } catch {
            Write-Warning "Failed to collect Linux system information: $_"
        }

        # Add environment variables
        try {
            $envFile = Join-Path $OutputDirectory "$datePrefix-linux-environment.txt"
            Get-ChildItem Env: | Sort-Object Name | Format-Table -AutoSize |
                Out-File -FilePath $envFile -Encoding UTF8 -Width 200
            $results.Files += $envFile
            Write-Debug "Environment variables saved to: $envFile"
        } catch {
            Write-Warning "Failed to collect environment variables: $_"
        }

        Write-Debug "Linux diagnostics collection complete. Total files: $($results.Files.Count)"
        return $results
    }
}
