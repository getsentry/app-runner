# Device Semaphore Manager
# Manages exclusive access to devices using named semaphores


<#
.SYNOPSIS
Builds a unique resource name for device semaphore coordination.

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

    $targetName = if ($Target) { $Target } else { "Default" }
    $resourceName = "$Platform-$targetName"

    Write-Debug "Built device resource name: $resourceName"
    return $resourceName
}


<#
.SYNOPSIS
Acquires exclusive access to a device resource using a named semaphore.

.DESCRIPTION
Attempts to acquire a system-wide named semaphore for the specified resource.
Blocks until the semaphore is available or the timeout expires.
Uses the Global\ namespace for system-wide coordination across PowerShell sessions.
For long timeouts, displays periodic progress messages to inform the user.

.PARAMETER ResourceName
The unique resource name for the device.

.PARAMETER TimeoutSeconds
Maximum time to wait for semaphore acquisition. Default is 30 seconds.

.PARAMETER ProgressIntervalSeconds
How often to display progress messages while waiting. Default is 60 seconds.

.OUTPUTS
System.Threading.Semaphore object that must be released when done.

.EXAMPLE
$semaphore = Request-DeviceAccess -ResourceName "Xbox-192.168.1.100" -TimeoutSeconds 1800
try {
    # Use device
} finally {
    Release-DeviceAccess -Semaphore $semaphore -ResourceName "Xbox-192.168.1.100"
}
#>
function Request-DeviceAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30,

        [Parameter(Mandatory = $false)]
        [int]$ProgressIntervalSeconds = 60
    )

    $semaphoreName = "Global\SentryAppRunner-Device-$ResourceName"
    $semaphore = $null

    try {
        Write-Debug "Attempting to acquire device access for resource: $ResourceName (timeout: ${TimeoutSeconds}s)"

        # Try to open existing semaphore or create new one
        try {
            $semaphore = [System.Threading.Semaphore]::OpenExisting($semaphoreName)
            Write-Debug "Opened existing semaphore: $semaphoreName"
        }
        catch [System.Threading.WaitHandleCannotBeOpenedException] {
            # Semaphore doesn't exist, create it with max count = 1 for exclusive access
            $semaphore = New-Object System.Threading.Semaphore(1, 1, $semaphoreName)
            Write-Debug "Created new semaphore with exclusive access: $semaphoreName"
        }

        # Try to acquire semaphore with periodic progress messages
        $startTime = Get-Date
        $elapsedSeconds = 0
        $acquired = $false

        Write-Debug "Waiting to acquire semaphore at $(Get-Date -Format 'HH:mm:ss.fff')..."

        while ($elapsedSeconds -lt $TimeoutSeconds) {
            # Calculate remaining time for this wait interval
            $remainingSeconds = $TimeoutSeconds - $elapsedSeconds
            $waitSeconds = [Math]::Min($ProgressIntervalSeconds, $remainingSeconds)
            $waitMs = $waitSeconds * 1000

            # Try to acquire with this interval
            $acquired = $semaphore.WaitOne($waitMs)

            if ($acquired) {
                # Successfully acquired
                $waitDuration = ((Get-Date) - $startTime).TotalSeconds
                Write-Debug "Semaphore acquired for $ResourceName (waited $([math]::Round($waitDuration, 2))s)"
                return $semaphore
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
        $semaphore.Dispose()
        throw "Could not acquire exclusive access to device resource '$ResourceName'. The device may be in use by another process. Timeout after ${TimeoutSeconds}s."
    }
    catch {
        # Clean up semaphore on any error
        if ($semaphore) {
            $semaphore.Dispose()
        }
        throw
    }
}


<#
.SYNOPSIS
Releases exclusive access to a device resource.

.DESCRIPTION
Releases and disposes the device semaphore, allowing other processes to acquire it.
Always logs warnings instead of throwing errors to ensure disconnect operations complete.

.PARAMETER Semaphore
The semaphore object to release.

.PARAMETER ResourceName
The resource name (used for logging/debugging only).

.EXAMPLE
Release-DeviceAccess -Semaphore $semaphore -ResourceName "Xbox-192.168.1.100"
#>
function Release-DeviceAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Threading.Semaphore]$Semaphore,

        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    if (-not $Semaphore) {
        Write-Debug "No semaphore to release for resource: $ResourceName"
        return
    }

    try {
        $Semaphore.Release()
        Write-Debug "Semaphore released for resource: $ResourceName at $(Get-Date -Format 'HH:mm:ss.fff')"
    }
    catch {
        # Don't throw - log warning and continue
        # This ensures Disconnect-Device always succeeds from user perspective
        Write-Warning "Failed to release semaphore for resource '$ResourceName': $($_.Exception.Message)"
    }
    finally {
        try {
            $Semaphore.Dispose()
            Write-Debug "Semaphore disposed for resource: $ResourceName"
        }
        catch {
            Write-Warning "Failed to dispose semaphore for resource '$ResourceName': $($_.Exception.Message)"
        }
    }
}
