# Device Lock Manager
# Manages exclusive access to devices using system-wide locks (mutexes)


<#
.SYNOPSIS
Builds a unique resource name for device lock coordination.

.DESCRIPTION
Creates a system-wide unique identifier based on platform and target.
Uses this format: {Platform}-{Target|Default}

.PARAMETER Platform
The device platform (Xbox, PlayStation5, Switch, Mock)

.PARAMETER Target
Optional target identifier (IP address or name). If not specified, uses "Default".

.EXAMPLE
New-DeviceResourceName -Platform "Xbox" -Target "192.168.1.100"
Returns: "Xbox-192.168.1.100"

.EXAMPLE
New-DeviceResourceName -Platform "PlayStation5"
Returns: "PlayStation5-Default"
#>
function New-DeviceResourceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Platform,

        [Parameter(Mandatory = $false)]
        [string]$Target
    )

    $targetName = if ($Target) { $Target } else { 'Default' }

    # Validate mutex name characters for cross-platform compatibility
    # On Unix systems, mutex names map to filenames where forward slash (/) is invalid
    # NUL character is also invalid but unlikely in practice
    if ($targetName -match '[/\x00]') {
        throw "Invalid characters in target name '$targetName'. Forward slash (/) and NUL are not allowed in mutex names on Unix systems."
    }

    $resourceName = "$Platform-$targetName"

    Write-Debug "Built device resource name: $resourceName"
    return $resourceName
}


<#
.SYNOPSIS
Acquires exclusive access to a device resource using a named mutex.

.DESCRIPTION
Attempts to acquire a system-wide named mutex for the specified resource.
Blocks until the mutex is available or the timeout expires.
Uses the Global\ namespace for system-wide coordination across PowerShell sessions.
Automatically handles abandoned mutexes (from crashed processes).
For long timeouts, displays periodic progress messages to inform the user.

.PARAMETER ResourceName
The unique resource name for the device.

.PARAMETER TimeoutSeconds
Maximum time to wait for mutex acquisition. Default is 30 seconds.

.PARAMETER ProgressIntervalSeconds
How often to display progress messages while waiting. Default is 60 seconds.

.OUTPUTS
System.Threading.Mutex object that must be released when done.

.EXAMPLE
$mutex = Request-DeviceAccess -ResourceName "Xbox-192.168.1.100" -TimeoutSeconds 1800
try {
    # Use device
} finally {
    Release-DeviceAccess -Mutex $mutex -ResourceName "Xbox-192.168.1.100"
}
#>
function Request-DeviceAccess {
    [CmdletBinding()]
    [OutputType([System.Threading.Mutex])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30,

        [Parameter(Mandatory = $false)]
        [int]$ProgressIntervalSeconds = 60
    )

    $mutexName = "Global\SentryAppRunner-Device-$ResourceName"

    Write-Debug "Attempting to acquire device access for resource: $ResourceName (timeout: ${TimeoutSeconds}s)"

    # Try to open existing mutex first to avoid permission issues when multiple processes
    # try to create the same mutex concurrently with initial ownership.
    $createdNew = $false
    $mutex = $null

    try {
        # Try to open existing mutex first
        $mutex = [System.Threading.Mutex]::OpenExisting($mutexName)
        Write-Debug "Opened existing mutex: $mutexName"
    } catch [System.Threading.WaitHandleCannotBeOpenedException] {
        # Mutex doesn't exist yet, create it without requesting initial ownership
        # We'll acquire it separately with WaitOne() to handle race conditions properly
        Write-Debug "Mutex doesn't exist, creating: $mutexName"
        $mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)
        Write-Debug "Created new mutex: $mutexName (createdNew: $createdNew)"
    } catch [System.UnauthorizedAccessException] {
        throw "Access denied when accessing mutex '$mutexName'. This may require elevated privileges. Error: $($_.Exception.Message)"
    } catch {
        throw "Failed to open or create mutex '$mutexName': $($_.Exception.Message)"
    }

    # Now acquire the mutex (whether we just created it or opened existing)
    try {
        Write-Debug "Attempting to acquire mutex: $mutexName"

        # Try to acquire mutex with periodic progress messages
        $startTime = Get-Date
        $elapsedSeconds = 0
        $acquired = $false

        Write-Debug "Waiting to acquire mutex at $(Get-Date -Format 'HH:mm:ss.fff')..."

        while ($elapsedSeconds -lt $TimeoutSeconds) {
            # Calculate remaining time for this wait interval
            $remainingSeconds = $TimeoutSeconds - $elapsedSeconds
            $waitSeconds = [Math]::Min($ProgressIntervalSeconds, $remainingSeconds)
            $waitMs = $waitSeconds * 1000

            # Try to acquire with this interval
            try {
                $acquired = $mutex.WaitOne($waitMs)
            } catch [System.Threading.AbandonedMutexException] {
                # Previous owner crashed - WaitOne() throws this exception BUT we now own the mutex
                # The exception is a notification that the device state may be inconsistent
                Write-Warning "Detected abandoned mutex for '$ResourceName' (previous process crashed). Mutex has been acquired, but device may be in an inconsistent state."
                $acquired = $true
            }

            if ($acquired) {
                # Successfully acquired
                $waitDuration = ((Get-Date) - $startTime).TotalSeconds
                Write-Debug "Mutex acquired for $ResourceName (waited $([math]::Round($waitDuration, 2))s)"
                return $mutex
            }

            # Not acquired yet, update elapsed time
            $elapsedSeconds += $waitSeconds

            # Log progress if we haven't timed out yet
            if ($elapsedSeconds -lt $TimeoutSeconds) {
                $remainingMinutes = [Math]::Ceiling(($TimeoutSeconds - $elapsedSeconds) / 60)
                Write-Warning "Still waiting for exclusive access to '$ResourceName' (${elapsedSeconds}s elapsed, ~${remainingMinutes} minute(s) remaining)..."
            }
        }

        # Timeout occurred
        throw "Could not acquire exclusive access to device resource '$ResourceName'. The device may be in use by another process. Timeout after ${TimeoutSeconds}s."
    } catch {
        # Clean up mutex on any error
        if ($mutex) {
            $mutex.Dispose()
        }
        throw
    }
}


<#
.SYNOPSIS
Releases exclusive access to a device resource.

.DESCRIPTION
Releases and disposes the device mutex, allowing other processes to acquire it.
Always logs warnings instead of throwing errors to ensure disconnect operations complete.

.PARAMETER Mutex
The mutex object to release.

.PARAMETER ResourceName
The resource name (used for logging/debugging only).

.EXAMPLE
Release-DeviceAccess -Mutex $mutex -ResourceName "Xbox-192.168.1.100"
#>
function Release-DeviceAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Threading.Mutex]$Mutex,

        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    if (-not $Mutex) {
        Write-Debug "No mutex to release for resource: $ResourceName"
        return
    }

    try {
        $Mutex.ReleaseMutex()
        Write-Debug "Mutex released for resource: $ResourceName at $(Get-Date -Format 'HH:mm:ss.fff')"
    } catch {
        # Don't throw - log warning and continue
        # This ensures Disconnect-Device always succeeds from user perspective
        Write-Warning "Failed to release mutex for resource '$ResourceName': $($_.Exception.Message)"
    } finally {
        try {
            $Mutex.Dispose()
            Write-Debug "Mutex disposed for resource: $ResourceName"
        } catch {
            Write-Warning "Failed to dispose mutex for resource '$ResourceName': $($_.Exception.Message)"
        }
    }
}
