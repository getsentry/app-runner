# Xbox Device Provider Implementation
# Unified provider for Xbox One and Xbox Series X/S development kits


# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

<#
.SYNOPSIS
Device provider for Xbox development kits (Xbox One and Xbox Series X/S).

.DESCRIPTION
This provider implements Xbox specific device operations using the Xbox development CLI tools.
It supports both Xbox One and Xbox Series X/S development kits through the same interface.
#>
class XboxProvider : DeviceProvider {
    [string]$ConnectTool = 'xbconnect.exe'
    [string]$PowerTool = 'xbreboot.exe'
    [string]$AppTool = 'xbapp.exe'

    XboxProvider() {
        $this.Platform = 'Xbox'

        # Enable timeout handling with 2-minute default timeout
        $this.TimeoutSeconds = 120
        $this.MaxRetryAttempts = 2

        # Set SDK path if GameDK environment variable is available
        $gameDkRoot = $env:GameDK
        if ($gameDkRoot) {
            $this.SdkPath = Join-Path $gameDkRoot 'bin'
        } else {
            Write-Warning 'GameDK environment variable not set. Assuming Xbox GDK tools are in PATH.'
            $this.SdkPath = $null
        }

        # Configure Xbox specific commands using Command objects
        $this.Commands = @{
            'connect'            = @($this.ConnectTool, '')
            'setTarget'          = @($this.ConnectTool, '/N "{0}"')
            'disconnect'         = $null
            # Xbox has two "powermode" values: "energysaving" which is basically always on or "instanton" which support sleep/wakeup
            'powerState'         = @($this.PowerTool, '/Q')
            'wakeup'             = @($this.PowerTool, '/W') # Wake up
            'sleep'              = @($this.PowerTool, '/P') # Sleep
            'poweron'            = $null
            'poweroff'           = $null # Xbox cannot recover from full power-off via CLI, so we don't implement power off.
            'reset'              = @($this.PowerTool, '')
            'getstatus'          = @($this.ConnectTool, '')
            'screenshot'         = @('xbcapture.exe', '"{0}/{1}"')
            'diaginfo'           = @('xbdiaginfo.exe', '')
            'xbtlist'            = @('xbtlist.exe', '')
            'xbcopy'             = @('xbcopy.exe', '"{0}" "{1}" /mirror')
            'launch'             = @('xbrun.exe', '/O /D:"{0}" "{1}" {2}')
            'get-installed-apps' = @($this.AppTool, 'list /JSON')
            'install-app'        = @($this.AppTool, 'install {0}')
            'uninstall-app'      = @($this.AppTool, 'uninstall {0}')
            'stop-app'           = @($this.AppTool, 'terminate {0}')
            'launch-app'         = @($this.AppTool, 'launch /O "{0}" {1}')
        }

        # Configure action-specific timeouts (app launch commands need more time)
        $this.Timeouts = @{
            'launch'     = 300  # 5 minutes for loose executable launch
            'launch-app' = 300  # 5 minutes for packaged app launch
        }
    }

    # Helper method to invoke poweron with retry logic for connected standby timeout
    [void] InvokePowerOn() {
        $powerState = $this.InvokeCommand('powerState', @())

        if ($powerState -match 'Allows Instant On' -and $powerState -match 'Connected Standby') {
            Write-Debug "$($this.Platform): Waking up device from Connected Standby"
            $this.InvokeCommand('wakeup', @())
        }
    }

    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Connecting to device"
        $this.InvokePowerOn() # Wakes up the device - needs to run before connect.
        $this.InvokeCommand('connect', @())
        return $this.CreateSessionInfo()
    }

    # Override Connect to support target parameter
    [hashtable] Connect([string]$target) {
        Write-Debug "$($this.Platform): Setting target device: $target"
        $this.InvokeCommand('setTarget', @($target))
        return $this.Connect()
    }

    # Override StartDevice to support connected standby
    [void] StartDevice() {
        Write-Debug "$($this.Platform): Starting device"
        $this.InvokePowerOn()
    }

    # Override StopDevice to support connected standby
    [void] StopDevice() {
        $powerState = $this.InvokeCommand('powerState', @())
        if ($powerState -match 'Allows Instant On') {
            $this.InvokeCommand('sleep', @())
        } else {
            $this.InvokeCommand('poweroff', @())
        }
    }

    # Override RestartDevice to implement proper wait-for-ready sequence
    [void] RestartDevice() {
        $this.InvokeCommand('reset', @())

        # Wait for device to become ready after reboot
        $maxWaitSeconds = 120
        $pollIntervalSeconds = 5
        $elapsedSeconds = 0
        $isReady = $false

        Write-Debug "$($this.Platform): Waiting for device to become ready after reboot..."

        while ($elapsedSeconds -lt $maxWaitSeconds -and -not $isReady) {
            Start-Sleep -Seconds $pollIntervalSeconds
            $elapsedSeconds += $pollIntervalSeconds

            try {
                # Try to get device status
                $status = $this.GetDeviceStatus()
                if ($null -ne $status) {
                    $isReady = $true
                    Write-Debug "$($this.Platform): Device is ready after $elapsedSeconds seconds"
                }
            } catch {
                # Device not ready yet, continue waiting
                Write-Debug "$($this.Platform): Device not ready yet, waiting... ($elapsedSeconds/$maxWaitSeconds seconds)"
            }
        }

        if (-not $isReady) {
            throw "Device did not become ready after $maxWaitSeconds seconds"
        }
    }

    # Override GetDeviceLogs to provide Xbox specific log retrieval
    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Warning 'GetDeviceLogs is not available for Xbox devices.'
        return @{}
    }

    # Override GetRunningProcesses to provide Xbox process list via xbtlist
    # Returns array of objects with Id, Name, ParentPid (null), and Path (null) properties
    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): Collecting running processes via xbtlist"
        $output = $this.InvokeCommand('xbtlist', @())

        # Parse xbtlist output into structured objects
        # Format: "  PID Executable" or "  PID <unknown>"
        # Note: xbtlist doesn't provide ParentPid or separate Path, so Name is used for both
        $processes = @()
        foreach ($line in $output) {
            if ($line -match '^\s*(\d+)\s+(.+)$') {
                $processes += [PSCustomObject]@{
                    Id        = [int]$matches[1]
                    Name      = $matches[2].Trim()
                    ParentPid = $null  # Not available from xbtlist
                    Path      = $matches[2].Trim()  # xbtlist combines name and path
                }
            }
        }

        return $processes
    }

    # Helper method to find an installed package by base name
    # Returns the package object if found, null otherwise
    [object] GetInstalledPackage([string]$packageBaseName) {
        $listOutput = $this.InvokeCommand('get-installed-apps', @())
        $installedPackages = $listOutput | ConvertFrom-Json
        return $installedPackages.Packages | Where-Object -Property FullName -Match $packageBaseName | Select-Object -First 1
    }

    # Install a packaged application (.xvc)
    [hashtable] InstallApp([string]$PackagePath) {
        if (-not (Test-Path $PackagePath)) {
            throw "Package file not found: $PackagePath"
        }

        if ($PackagePath -notlike '*.xvc') {
            throw "Package must be a .xvc file. Got: $PackagePath"
        }

        # Extract package base name for matching
        $packageBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PackagePath) -split '\.' | Select-Object -First 1

        # Uninstall existing package to ensure clean state
        Write-Debug "$($this.Platform): Checking for existing package matching '$packageBaseName'"
        $existingPackage = $this.GetInstalledPackage($packageBaseName)
        if ($existingPackage) {
            Write-Host "Uninstalling existing package: $($existingPackage.FullName)" -ForegroundColor Yellow
            $this.InvokeCommand('stop-app', @($existingPackage.FullName))
            $this.InvokeCommand('uninstall-app', @($existingPackage.FullName))
        }

        # Install package
        Write-Host 'Installing package to Xbox...' -ForegroundColor Yellow
        $this.InvokeCommand('install-app', @($PackagePath))

        # Verify package installation with retry logic (wait up to 60 seconds)
        Write-Host 'Verifying package installation...' -ForegroundColor Yellow
        $timeout = 60
        $checkInterval = 2
        $elapsed = 0

        while ($elapsed -lt $timeout) {
            $installedPackage = $this.GetInstalledPackage($packageBaseName)

            if ($installedPackage) {
                Write-Host "Package verified to be installed on device: $($installedPackage.FullName)" -ForegroundColor Green
                return @{}
            }

            Write-Host "Package not yet visible, waiting... ($elapsed/$timeout seconds)" -ForegroundColor Gray
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval
        }

        # Installation verification failed - gather diagnostics
        Write-Warning "The package doesn't appear to be installed after $timeout seconds. Installed packages:"
        $listOutput = $this.InvokeCommand('get-installed-apps', @())
        $installedPackages = $listOutput | ConvertFrom-Json
        $installedPackages.Packages | ForEach-Object { Write-Warning " - $($_.FullName)" }
        throw "Failed to verify package installation: $packageBaseName"
    }

    # Launch an already-installed packaged application
    [hashtable] LaunchInstalledApp([string]$PackageIdentity, [string]$Arguments) {
        # Not giving the argument here stops any foreground app
        $this.InvokeCommand('stop-app', @(''))

        $command = $this.BuildCommand('launch-app', @($PackageIdentity, $Arguments))
        return $this.InvokeApplicationCommand($command, $PackageIdentity, $Arguments)
    }

    # Application management
    # AppPath can be either:
    # - A directory containing loose .exe files (uses xbrun)
    # - A package identifier (AUMID string) for already-installed packages (uses xbapp launch)
    # - A .xvc file path (ERROR - user must use Install-DeviceApp first)
    [hashtable] RunApplication([string]$AppPath, [string]$Arguments) {
        if (Test-Path $AppPath -PathType Container) {
            # It's a directory - use loose executable flow (xbrun)
            $appExecutableName = Get-ChildItem -Path $AppPath -File -Filter '*.exe' | Select-Object -First 1 -ExpandProperty Name
            $appNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($appExecutableName)
            $xboxTempDir = "d:\temp\$appNameWithoutExt"

            Write-Host "Mirroring directory $AppPath to Xbox devkit $xboxTempDir..."
            $this.InvokeCommand('xbcopy', @($AppPath, "x$xboxTempDir"))

            $command = $this.BuildCommand('launch', @($xboxTempDir, "$xboxTempDir\$appExecutableName", $Arguments))
            return $this.InvokeApplicationCommand($command, $appExecutableName, $Arguments)
        } elseif (Test-Path $AppPath -PathType Leaf) {
            # It's a file - check if it's a .xvc package
            if ($AppPath -like '*.xvc') {
                throw "Cannot run .xvc package directly. Please use 'Install-DeviceApp -Path `"$AppPath`"' first, then 'Invoke-DeviceApp -ExecutablePath `"PackageName_Hash!ExecutableId`" -Arguments ...'"
            } else {
                throw "Unsupported file type: $AppPath. Expected directory with .exe files or package identifier (AUMID)."
            }
        } else {
            # Not a path - assume it's a package identifier (AUMID)
            Write-Debug "Treating as package identifier (AUMID): $AppPath"
            return $this.LaunchInstalledApp($AppPath, $Arguments)
        }
    }

    [string] GetDeviceIdentifier() {
        $status = $this.GetDeviceStatus()
        $statusData = $status.StatusData

        # parse IP address or host name from:
        # Connections at 10.0.9.226, client build 10.0.26100.4061:
        $matchingLine = $statusData | Where-Object { $_ -match 'Connections at ([^, ]+)' }
        if ($matchingLine) {
            return $matches[1]
        } else {
            Write-Warning 'Could not parse device identifier from status data.'
            return 'Unknown'
        }
    }
}
