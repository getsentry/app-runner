# Xbox Console Provider Implementation
# Unified provider for Xbox One and Xbox Series X/S development kits


# Load the base provider
. "$PSScriptRoot\ConsoleProvider.ps1"

<#
.SYNOPSIS
Console provider for Xbox development kits (Xbox One and Xbox Series X/S).

.DESCRIPTION
This provider implements Xbox specific console operations using the Xbox development CLI tools.
It supports both Xbox One and Xbox Series X/S development kits through the same interface.
#>
class XboxProvider : ConsoleProvider {
    [string]$ConnectTool = 'xbconnect.exe'
    [string]$PowerTool = 'xbreboot.exe'

    XboxProvider() {
        $this.Platform = 'Xbox'

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
            'connect'    = @($this.ConnectTool, '')
            'setTarget'  = @($this.ConnectTool, '/N "{0}"')
            'disconnect' = $null
            'powerState' = @($this.PowerTool, '/Q')
            'poweron'    = @($this.PowerTool, '/W') # Wake up
            'poweroff'   = @($this.PowerTool, '/P') # Sleep
            'reset'      = @($this.PowerTool, '')
            'getstatus'  = @($this.ConnectTool, '')
            'screenshot' = @('xbcapture.exe', '"{0}/{1}"')
            'diaginfo'   = @('xbdiaginfo.exe', '')
            'xbcopy'     = @('xbcopy.exe', '"{0}" "{1}" /mirror')
            'launch'     = @('xbrun.exe', '/O /D:"{0}" "{1}" {2}')
        }
    }

    # Helper method to invoke poweron with retry logic for connected standby timeout
    [void] InvokePowerOn() {
        $maxRetries = 2
        $attempt = 1
        $success = $false

        while ($attempt -le $maxRetries -and -not $success) {
            try {
                Write-Debug "$($this.Platform): Power-on attempt $attempt of $maxRetries"
                $this.InvokeCommand('poweron', @())
                $success = $true
            } catch {
                # Check if it's the known connected standby timeout (0x80070102)
                if ($_.Exception.Message -match '0x80070102|wait operation timed out' -and $attempt -lt $maxRetries) {
                    Write-Warning "$($this.Platform): Connected standby wake timeout detected. Retrying..."
                    $attempt++
                } else {
                    throw
                }
            }
        }

        if (-not $success) {
            throw "Failed to power on console after $maxRetries attempts"
        }
    }

    [hashtable] Connect() {
        Write-Debug "$($this.Platform): Connecting to console"
        $this.InvokePowerOn() # Wakes up the console - needs to run before connect.
        $this.InvokeCommand('connect', @())
        return $this.CreateSessionInfo()
    }

    # Override Connect to support target parameter
    [hashtable] Connect([string]$target) {
        Write-Debug "$($this.Platform): Setting target console: $target"
        $this.InvokeCommand('setTarget', @($target))
        return $this.Connect()
    }

    # Override StartConsole to use retry logic for connected standby
    [void] StartConsole() {
        Write-Debug "$($this.Platform): Starting console"
        $this.InvokePowerOn()
    }

    # Override GetConsoleLogs to provide Switch specific log retrieval
    [hashtable] GetConsoleLogs([string]$LogType, [int]$MaxEntries) {
        Write-Warning 'GetConsoleLogs is not available for Xbox consoles.'
        return @{}
    }

    # Application management
    [hashtable] RunApplication([string]$AppDir, [string]$Arguments) {
        $appExecutableName = Get-ChildItem -Path $AppDir -File -Filter '*.exe' | Select-Object -First 1 -ExpandProperty Name
        $appNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($appExecutableName)
        $xboxTempDir = "d:\temp\$appNameWithoutExt"

        Write-Host "Mirroring directory $AppDir to Xbox devkit $xboxTempDir..."
        $this.InvokeCommand('xbcopy', @($AppDir, "x$xboxTempDir"))

        $command = $this.BuildCommand('launch', @($xboxTempDir, "$xboxTempDir\$appExecutableName", $Arguments))
        return $this.InvokeApplicationCommand($command, $appExecutableName, $Arguments)
    }

    [string] GetConsoleIdentifier() {
        $status = $this.GetConsoleStatus()
        $statusData = $status.StatusData

        # parse IP address or host name from:
        # Connections at 10.0.9.226, client build 10.0.26100.4061:
        $matchingLine = $statusData | Where-Object { $_ -match 'Connections at ([^, ]+)' }
        if ($matchingLine) {
            return $matches[1]
        } else {
            Write-Warning 'Could not parse console identifier from status data.'
            return 'Unknown'
        }
    }
}
