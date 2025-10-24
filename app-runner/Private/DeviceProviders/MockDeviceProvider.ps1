# Mock Device Provider Implementation
# Provides predictable mock responses for testing


# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

<#
.SYNOPSIS
Mock device provider for testing.

.DESCRIPTION
This provider implements predictable mock responses for testing the SentryAppRunner module.
It simulates device operations without requiring actual hardware.
#>
class MockDeviceProvider : DeviceProvider {
    [bool]$IsConnected = $false
    [hashtable]$MockConfig = @{}

    MockDeviceProvider() {
        $this.Platform = "Mock"

        # Mock commands don't need real CLI tools - just use echo for simulation
        $this.Commands = @{
            "connect"    = @("echo", "'Mock connect'")
            "disconnect" = @("echo", "'Mock disconnect'")
            "poweron"    = @("echo", "'Mock power on'")
            "poweroff"   = @("echo", "'Mock power off'")
            "reset"      = @("echo", "'Mock reset'")
            "getstatus"  = @("echo", "'Mock get status'")
            "launch"     = @("echo", "'Mock launch {0} {1}'")
            "screenshot" = @("echo", "'Mock screenshot'")
        }

        # Configure mock behavior
        $this.MockConfig = @{
            ShouldFailConnection = $false
            ShouldFailCommands   = $false
            PowerState           = "Off"
            AppRunning           = $false
        }
    }

    # Override InvokeCommand to return mock responses instead of executing real commands
    [object] InvokeCommand([string]$action, [object[]]$parameters) {
        Write-Debug "Mock: Invoking $action with parameters: $($parameters -join ', ')"

        if ($this.MockConfig.ShouldFailCommands) {
            throw "Mock command execution failed"
        }

        return "Mock command executed successfully: $action"
    }

    # Override methods to provide realistic mock behavior
    [hashtable] Connect() {
        Write-Debug "Mock: Connecting to mock device"

        if ($this.MockConfig.ShouldFailConnection) {
            throw "Mock connection failed"
        }

        $this.IsConnected = $true

        return $this.CreateSessionInfo()
    }

    [void] Disconnect() {
        Write-Debug "Mock: Disconnecting from mock device"
        $this.IsConnected = $false
    }

    [bool] TestConnection() {
        Write-Debug "Mock: Testing connection"
        return $this.IsConnected
    }

    [void] StartDevice() {
        Write-Debug "Mock: Starting device"
        $this.MockConfig.PowerState = "On"
    }

    [void] StopDevice() {
        Write-Debug "Mock: Stopping device"
        $this.MockConfig.PowerState = "Off"
        $this.MockConfig.AppRunning = $false
    }

    [void] RestartDevice() {
        Write-Debug "Mock: Restarting device"
        $this.MockConfig.PowerState = "On"
        $this.MockConfig.AppRunning = $false
    }

    [hashtable] GetDeviceStatus() {
        Write-Debug "Mock: Getting device status"
        return @{
            Platform   = $this.Platform
            PowerState = $this.MockConfig.PowerState
            AppRunning = $this.MockConfig.AppRunning
            Status     = "Online"
            Timestamp  = Get-Date
        }
    }


    [hashtable] InstallApp([string]$PackagePath) {
        Write-Debug "Mock: Installing application package: $PackagePath"

        if (-not $PackagePath) {
            throw "PackagePath cannot be empty"
        }

        return @{
            Platform      = $this.Platform
            PackagePath   = $PackagePath
            InstalledAt   = Get-Date
            Status        = "Installed"
        }
    }

    [hashtable] RunApplication([string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "Mock: Running application $ExecutablePath with args: $Arguments"

        $this.MockConfig.AppRunning = $true
        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = Get-Date
            ProcessId      = 12345
            Status         = "Running"
        }
    }


    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "Mock: Getting device logs (type: $LogType, max: $MaxEntries)"

        $logs = @{$LogType = @() }
        for ($i = 0; $i -lt $MaxEntries; $i++) {
            $logs[$LogType] += @{
                Level     = @("Info", "Warning", "Error")[$i % 3]
                Message   = "Mock log entry $i for $($this.Platform)"
                Source    = "MockDevice"
                Timestamp = (Get-Date).AddSeconds(-$i)
            }
        }

        return $logs
    }

    [void] TakeScreenshot([string]$OutputPath) {
        Write-Debug "Mock: Taking screenshot to $OutputPath"

        # Create a mock screenshot file
        "Mock screenshot data" | Out-File -FilePath $OutputPath -Encoding UTF8
    }

    [object] GetRunningProcesses() {
        Write-Debug "Mock: Getting running processes"

        # Return mock process list as structured objects
        return @(
            [PSCustomObject]@{ Id = 123; Name = "C:\Windows\System32\svchost.exe" }
            [PSCustomObject]@{ Id = 456; Name = "C:\Windows\System32\explorer.exe" }
            [PSCustomObject]@{ Id = 1234; Name = "C:\Program Files\MockApp\app.exe" }
            [PSCustomObject]@{ Id = 5678; Name = "C:\Windows\System32\dwm.exe" }
            [PSCustomObject]@{ Id = 999; Name = "<unknown>" }
        )
    }


    # Mock configuration methods for testing
    [void] SetMockConfig([hashtable]$Config) {
        foreach ($key in $Config.Keys) {
            $this.MockConfig[$key] = $Config[$key]
        }
    }

    [hashtable] GetMockConfig() {
        return $this.MockConfig.Clone()
    }

    [string] GetDeviceIdentifier() {
        return "Mock-$($this.Platform)-192.168.1.100"
    }
}
