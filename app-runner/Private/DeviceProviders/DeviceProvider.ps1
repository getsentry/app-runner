# Device Provider Base Class
# Provides shared functionality for all device providers


<#
.SYNOPSIS
Base device provider with shared implementation for all platforms.

.DESCRIPTION
This base class implements common patterns shared across all device providers,
reducing code duplication and providing consistent behavior. Platform-specific
providers inherit from this base and override only what's different.
#>
class DeviceProvider {
    # Platform identification
    [string]$Platform

    [hashtable]$Commands
    [string]$SdkPath

    DeviceProvider() {
        $this.Commands = @{}
        $this.SdkPath = $null
    }

    # Shared helper methods
    [string] GetToolPath([string]$toolName) {
        $toolPath = $toolName
        $isAvailable = if ($this.SdkPath) {
            $toolPath = Join-Path $this.SdkPath $toolName
            Test-Path $toolPath
        } else {
            Get-Command $toolPath -ErrorAction SilentlyContinue
        }


        if (-not $isAvailable) {
            throw "Tool not found: $toolPath. Please verify SDK installation."
        }

        return $toolPath
    }

    [object] BuildCommand([string]$action, [object[]]$parameters) {
        if (-not $this.Commands.ContainsKey($action)) {
            throw "Command '$action' not configured for platform '$($this.Platform)'"
        }

        $commandObj = $this.Commands[$action]
        if ($null -eq $commandObj) {
            Write-Warning "Command '$action' is not available for platform '$($this.Platform)'"
            return $null
        }

        $executablePath = $this.GetToolPath($commandObj[0])

        $arguments = $commandObj[1]
        if ($parameters -and $parameters.Count -gt 0) {
            $arguments = $arguments -f $parameters
        }
        return "& '$executablePath' $arguments 2>&1"
    }


    [void] LogNotImplemented([string]$operation) {
        Write-Warning "$($this.Platform) $operation not yet implemented"
    }

    [object] InvokeCommand([string]$action, [object[]]$parameters) {
        $command = $this.BuildCommand($action, $parameters)
        if ($null -eq $command) {
            return $null
        }

        try {
            $PSNativeCommandUseErrorActionPreference = $false
            Write-Debug "$($this.Platform): Invoking ($action) command $command"
            $result = Invoke-Expression $command
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Command ($action) failed with exit code $($LASTEXITCODE) $($result.Length -gt 0 ? 'and output:' : '')"
                $result | ForEach-Object { Write-Warning $_ }
                throw "Command ($action) failed with exit code $($LASTEXITCODE)"
            }
            return $result
        } finally {
            $PSNativeCommandUseErrorActionPreference = $true
        }
    }

    [hashtable] CreateSessionInfo() {
        $status = $this.GetDeviceStatus()
        return @{
            Provider    = $this
            Platform    = $this.Platform
            ConnectedAt = Get-Date
            Identifier  = $this.GetDeviceIdentifier()
            IsConnected = $true
            StatusData  = $status.StatusData
        }
    }

    # Connection management (shared implementation)
    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Connecting to device"

        $this.InvokeCommand('connect', @())
        $this.InvokeCommand('poweron', @())
        return $this.CreateSessionInfo()
    }

    [hashtable] Connect([string]$target) {
        Write-Debug "$($this.Platform): Connecting to device with target: $target"

        # Default implementation just calls Connect() - platforms that support targets should override
        return $this.Connect()
    }

    [void] Disconnect() {
        Write-Debug "$($this.Platform): Disconnecting from device"

        $this.InvokeCommand('disconnect', @())
    }

    [bool] TestConnection() {
        Write-Debug "$($this.Platform): Testing connection to device"

        $this.InvokeCommand('getstatus', @())
        return $true
    }

    # Device lifecycle management (shared implementation)
    [void] StartDevice() {
        Write-Debug "$($this.Platform): Starting device"

        $this.InvokeCommand('poweron', @())
    }

    [void] StopDevice() {
        Write-Debug "$($this.Platform): Stopping device"

        Write-Output $this.InvokeCommand('poweroff', @())
    }

    [void] RestartDevice() {
        Write-Debug "$($this.Platform): Restarting device"

        $this.InvokeCommand('reset', @())
    }

    [hashtable] GetDeviceStatus() {
        Write-Debug "$($this.Platform): Getting device status"

        $result = $this.InvokeCommand('getstatus', @())
        return @{
            Platform   = $this.Platform
            Status     = 'Online'
            StatusData = $result
            Timestamp  = Get-Date
        }
    }

    # Application management (shared implementation)
    [hashtable] RunApplication([string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "$($this.Platform): Running application: $ExecutablePath with arguments: $Arguments"

        $command = $this.BuildCommand('launch', @($ExecutablePath, $Arguments))
        return $this.InvokeApplicationCommand($command, $ExecutablePath, $Arguments)
    }

    [hashtable] InvokeApplicationCommand([string]$command, [string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "$($this.Platform): Invoking $command"

        $result = $null
        $exitCode = $null
        $startDate = Get-Date
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $result = Invoke-Expression $command
            $exitCode = $LASTEXITCODE
        } finally {
            $PSNativeCommandUseErrorActionPreference = $true
        }

        # Filter out empty lines from the output
        if ($result) {
            $result = $result | Where-Object { 
                if ($_ -is [string]) {
                    return $_ -and $_.Trim()
                } else {
                    return $true  # Keep non-string objects
                }
            }
        }

        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startDate
            FinishedAt     = Get-Date
            Output         = $result
            ExitCode       = $exitCode
        }
    }

    [void] TakeScreenshot([string]$OutputPath) {
        # If the output path includes a directory, split it up, otherwise use current directory
        $directory = Split-Path $OutputPath -Parent
        $filename = Split-Path $OutputPath -Leaf
        if (-not $directory) {
            $directory = Get-Location
        }

        Write-Debug "$($this.Platform): Taking screenshot (directory: $directory, file: $filename)"

        $this.InvokeCommand('screenshot', @($directory, $filename))

        $size = (Get-Item $OutputPath).Length
        Write-Debug "Screenshot saved to $OutputPath ($size bytes)"
    }

    [hashtable] GetDiagnostics([bool]$IncludePerformanceMetrics) {
        Write-Debug "$($this.Platform): Getting diagnostics (include performance: $IncludePerformanceMetrics)"
        # TODO screenshot, logs, etc.
        return @{}
    }

    [string] GetDeviceIdentifier() {
        $status = $this.GetDeviceStatus()
        $statusData = $status.StatusData

        # Handle null or empty status data
        if (-not $statusData) {
            return "$($this.Platform) ($(Get-Date -Format 'HH:mm:ss'))"
        }

        # Try to extract IP address from raw status text
        if ($statusData -match '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' -and $matches -and $matches[0]) {
            return $matches[0]
        }

        # Try to extract device name/ID from status text
        if ($statusData -match '(?:Target|Console|Name|DevKit):\s*(\w+)' -and $matches -and $matches[1]) {
            return $matches[1]
        }

        return "$($this.Platform) ($(Get-Date -Format 'HH:mm:ss'))"
    }

    [bool] TestInternetConnection() {
        Write-Debug "$($this.Platform): Testing internet connection"
        $this.LogNotImplemented('TestInternetConnection')
        return $false
    }

}
