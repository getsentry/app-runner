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
            "connect"            = @("echo", "'Mock connect'")
            "disconnect"         = @("echo", "'Mock disconnect'")
            "poweron"            = @("echo", "'Mock power on'")
            "poweroff"           = @("echo", "'Mock power off'")
            "reset"              = @("echo", "'Mock reset'")
            "getstatus"          = @("echo", "'Mock get status'")
            "launch"             = @("echo", "'Mock launch {0} {1}'")
            "screenshot"         = @("echo", "'Mock screenshot'")
            # Target management commands for testing DetectAndSetDefaultTarget()
            "get-default-target" = @("echo", "'Mock get-default-target'")
            "list-target"        = @("echo", "'Mock list-target'")
            "set-default-target" = @("echo", "'Mock set-default-target'")
            "detect-target"      = @("echo", "'Mock detect-target'")
            "register-target"    = @("echo", "'Mock register-target'")
        }

        # Configure mock behavior
        $this.MockConfig = @{
            ShouldFailConnection = $false
            ShouldFailCommands   = $false
            PowerState           = "Off"
            AppRunning           = $false
            # Target management state for testing
            Targets              = @{
                DefaultTarget    = $null  # Set to target object when a default is configured
                RegisteredTargets = @()   # Array of registered target objects
                DetectableTargets = @(    # Array of targets that can be detected on network
                    @{ IpAddress = "192.168.1.100"; Name = "MockDevice1" }
                )
            }
        }
    }

    # Override InvokeCommand to return mock responses instead of executing real commands
    [object] InvokeCommand([string]$action, [object[]]$parameters) {
        Write-Debug "Mock: Invoking $action with parameters: $($parameters -join ', ')"

        if ($this.MockConfig.ShouldFailCommands) {
            throw "Mock command execution failed"
        }

        # Handle target management commands - return objects directly (matching ConvertFrom-Yaml behavior)
        $result = switch ($action) {
            "get-default-target" {
                # Return the current default target object, or null if none set
                if ($this.MockConfig.Targets.DefaultTarget) {
                    # Return as JSON string to match prospero-ctrl behavior
                    $this.MockConfig.Targets.DefaultTarget | ConvertTo-Json -Compress
                } else {
                    $null
                }
            }
            "list-target" {
                # Return array of registered targets as objects (comma preserves empty arrays)
                , @($this.MockConfig.Targets.RegisteredTargets)
            }
            "set-default-target" {
                # Set the specified target as default
                $targetIp = $parameters[0]
                $target = $this.MockConfig.Targets.RegisteredTargets | Where-Object { $_.IpAddress -eq $targetIp } | Select-Object -First 1
                if ($target) {
                    $this.MockConfig.Targets.DefaultTarget = $target
                    Write-Debug "Mock: Set default target to $targetIp"
                    "Default target set to $targetIp"
                } else {
                    throw "Target with IP $targetIp not found in registered targets"
                }
            }
            "detect-target" {
                # Return array of detectable targets as objects (comma preserves empty arrays)
                , @($this.MockConfig.Targets.DetectableTargets)
            }
            "register-target" {
                # Add a target to the registered targets list
                $targetIp = $parameters[0]
                $target = $this.MockConfig.Targets.DetectableTargets | Where-Object { $_.IpAddress -eq $targetIp } | Select-Object -First 1
                if ($target) {
                    $this.MockConfig.Targets.RegisteredTargets += $target
                    Write-Debug "Mock: Registered target $targetIp"
                    "Target $targetIp registered"
                } else {
                    throw "Target with IP $targetIp not found in detectable targets"
                }
            }
            default {
                "Mock command executed successfully: $action"
            }
        }

        return $result
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

    [hashtable] RunApplication([string]$ExecutablePath, [string]$Arguments, [string]$LogFilePath = $null) {
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
        # Include optional properties (ParentPid, Path) to simulate different platform formats
        return @(
            [PSCustomObject]@{ Id = 123; Name = "C:\Windows\System32\svchost.exe"; ParentPid = 1; Path = "C:\Windows\System32\svchost.exe" }
            [PSCustomObject]@{ Id = 456; Name = "C:\Windows\System32\explorer.exe"; ParentPid = 123; Path = "C:\Windows\System32\explorer.exe" }
            [PSCustomObject]@{ Id = 1234; Name = "C:\Program Files\MockApp\app.exe"; ParentPid = 456; Path = "C:\Program Files\MockApp\app.exe" }
            [PSCustomObject]@{ Id = 5678; Name = "C:\Windows\System32\dwm.exe"; ParentPid = 1; Path = "C:\Windows\System32\dwm.exe" }
            [PSCustomObject]@{ Id = 999; Name = "<unknown>"; ParentPid = 0; Path = $null }
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

    # Helper methods for configuring target management test scenarios
    [void] ResetTargetState() {
        Write-Debug "Mock: Resetting target state"
        $this.MockConfig.Targets.DefaultTarget = $null
        $this.MockConfig.Targets.RegisteredTargets = @()
        $this.MockConfig.Targets.DetectableTargets = @(
            @{ IpAddress = "192.168.1.100"; Name = "MockDevice1" }
        )
    }

    [void] SetTargetScenario([string]$Scenario) {
        Write-Debug "Mock: Setting target scenario: $Scenario"
        $this.ResetTargetState()

        switch ($Scenario) {
            "NoTargets" {
                # No default, no registered, no detectable targets
                $this.MockConfig.Targets.DetectableTargets = @()
            }
            "OneDetectable" {
                # No default, no registered, one detectable (default scenario)
                # Already set by ResetTargetState()
            }
            "MultipleDetectable" {
                # No default, no registered, multiple detectable targets
                $this.MockConfig.Targets.DetectableTargets = @(
                    @{ IpAddress = "192.168.1.100"; Name = "MockDevice1" }
                    @{ IpAddress = "192.168.1.101"; Name = "MockDevice2" }
                    @{ IpAddress = "192.168.1.102"; Name = "MockDevice3" }
                )
            }
            "OneRegistered" {
                # No default, one registered, no detectable
                $target = @{ IpAddress = "192.168.1.100"; Name = "MockDevice1" }
                $this.MockConfig.Targets.RegisteredTargets = @($target)
                $this.MockConfig.Targets.DetectableTargets = @()
            }
            "MultipleRegistered" {
                # No default, multiple registered targets
                $this.MockConfig.Targets.RegisteredTargets = @(
                    @{ IpAddress = "192.168.1.100"; Name = "MockDevice1" }
                    @{ IpAddress = "192.168.1.101"; Name = "MockDevice2" }
                )
                $this.MockConfig.Targets.DetectableTargets = @()
            }
            "DefaultSet" {
                # Default target already set, one registered
                $target = @{ IpAddress = "192.168.1.100"; Name = "MockDevice1" }
                $this.MockConfig.Targets.RegisteredTargets = @($target)
                $this.MockConfig.Targets.DefaultTarget = $target
                $this.MockConfig.Targets.DetectableTargets = @()
            }
            default {
                throw "Unknown target scenario: $Scenario"
            }
        }
    }

    [string] GetDeviceIdentifier() {
        return "Mock-$($this.Platform)-192.168.1.100"
    }
}
