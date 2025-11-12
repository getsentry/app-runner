# Local Computer Provider Base Class
# Provides shared functionality for all local desktop platform providers

<#
.SYNOPSIS
Base provider for local desktop execution (Windows, MacOS, Linux).

.DESCRIPTION
This intermediate base class implements common patterns for local desktop providers,
reducing code duplication for operations that are similar across desktop platforms.
Platform-specific providers (WindowsProvider, MacOSProvider, LinuxProvider) inherit
from this base and override only platform-specific implementations.

Key differences from remote device providers (Xbox, PlayStation5, Switch):
- No network connection required (Connect is essentially a noop)
- Device identifier is localhost or computer name
- File operations use local filesystem APIs
- No device lifecycle operations (no shutdown/reboot of local machine)
#>

. "$PSScriptRoot\DeviceProvider.ps1"

class LocalComputerProvider : DeviceProvider {

    # Override GetDeviceIdentifier to return computer name
    [string] GetDeviceIdentifier() {
        return [System.Environment]::MachineName
    }

    # Override CopyDeviceItem to use local filesystem operations
    [void] CopyDeviceItem([string]$DevicePath, [string]$Destination) {
        Write-Debug "$($this.Platform): Copying local item from $DevicePath to $Destination"

        if (-not (Test-Path $DevicePath)) {
            throw "Source path not found: $DevicePath"
        }

        # Ensure destination directory exists
        $destDir = Split-Path $Destination -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $DevicePath -Destination $Destination -Force -Recurse
    }

    # Override DetectAndSetDefaultTarget to noop (no target management needed for local)
    [void] DetectAndSetDefaultTarget() {
        Write-Debug "$($this.Platform): Target detection not needed for local computer"
        # No-op: Local execution doesn't need target management
    }

    # Override GetDeviceStatus to provide local system status
    [hashtable] GetDeviceStatus() {
        Write-Debug "$($this.Platform): Getting local computer status"

        # Create a custom object with basic information
        # Platform-specific providers can override to add more details
        $statusData = [PSCustomObject]@{
            ComputerName = $this.GetDeviceIdentifier()
            Platform     = $this.Platform
            OSVersion    = [System.Environment]::OSVersion.VersionString
            OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        }

        return @{
            Platform   = $this.Platform
            Status     = 'Online'
            StatusData = $statusData
            Timestamp  = Get-Date
        }
    }
}
