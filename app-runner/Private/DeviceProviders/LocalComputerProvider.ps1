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

    LocalComputerProvider() {
        # Initialize base Commands hashtable with local execution defaults
        # Lifecycle operations are not supported for local desktop platforms
        $this.Commands = @{
            'connect'    = $null  # No-op: Already on local machine
            'disconnect' = $null  # No-op: Nothing to disconnect
            'poweron'    = $null  # Not supported: Don't power on local machine
            'poweroff'   = $null  # Not supported: Don't shut down local machine
            'reset'      = $null  # Not supported: Don't reboot local machine
            'getstatus'  = $null  # Will be overridden by platform providers if needed
        }
    }

    # Override Connect to skip target detection and network operations
    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Connecting to local computer"

        # Validate local environment (platform-specific providers can add validation)
        $this.ValidateLocalEnvironment()

        # No actual connection needed for local execution
        return $this.CreateSessionInfo()
    }

    [hashtable] Connect([string]$target) {
        if (-not [string]::IsNullOrEmpty($target) -and $target -ne 'localhost' -and $target -ne 'Local') {
            Write-Warning "$($this.Platform): LocalComputerProvider only supports local execution. Target parameter '$target' is ignored."
        }

        return $this.Connect()
    }

    # Override Disconnect to be a noop (just for consistency)
    [void] Disconnect() {
        Write-Debug "$($this.Platform): Disconnecting from local computer"
        # Nothing to disconnect for local execution
    }

    # Override TestConnection to just validate local environment
    [bool] TestConnection() {
        Write-Debug "$($this.Platform): Testing local computer connection"

        try {
            $this.ValidateLocalEnvironment()
            return $true
        } catch {
            Write-Warning "$($this.Platform): Local environment validation failed: $_"
            return $false
        }
    }

    # Override GetDeviceIdentifier to return localhost or computer name
    [string] GetDeviceIdentifier() {
        # Try to get computer name, fall back to localhost
        try {
            return [System.Environment]::MachineName
        } catch {
            return 'localhost'
        }
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

    # Virtual method for platform-specific environment validation
    # Platform providers can override this to add specific checks
    [void] ValidateLocalEnvironment() {
        Write-Debug "$($this.Platform): Validating local environment"
        # Base validation: just verify we can get system info
        # Platform-specific providers can add more checks
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

    # GetDeviceLogs is not implemented for local providers (at least initially)
    # Platform providers can override if they want to implement log collection
    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "$($this.Platform): GetDeviceLogs not implemented for local computer providers"
        return @{}
    }
}
