function Connect-Device {
    <#
    .SYNOPSIS
    Establishes a connection to a device devkit by platform.

    .DESCRIPTION
    Connects to a device devkit for the specified platform. The target manager
    automatically handles devkit selection and IP address resolution.

    .PARAMETER Platform
    The platform to connect to. Valid values: Xbox, PlayStation5, Switch

    .PARAMETER Target
    For Xbox platform, specifies the target to connect to. Can be either a name or IP address.
    If not specified, the system will auto-discover an available Xbox target.

    .PARAMETER TimeoutSeconds
    Maximum time to wait for exclusive device access. Default is 1800 seconds (30 minutes).
    Progress messages are displayed every minute during long waits.

    .EXAMPLE
    Connect-Device -Platform "Xbox"
    # Auto-discovers an available Xbox devkit

    .EXAMPLE
    Connect-Device -Platform "Xbox" -Target "192.168.1.100"
    # Connects to a specific Xbox target by IP

    .EXAMPLE
    Connect-Device -Platform "Xbox" -Target "NetHostName"
    # Connects to a specific Xbox target by name

    .EXAMPLE
    Connect-Device -Platform "PlayStation5"
    # Auto-discovers an available PS5 devkit
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Xbox', 'PlayStation5', 'Switch', 'Mock')]
        [string]$Platform,

        [Parameter(Mandatory = $false)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 1800
    )

    Write-Debug "Connecting to device platform: $Platform"

    # Validate platform is supported
    if (-not [DeviceProviderFactory]::IsPlatformSupported($Platform)) {
        throw "Unsupported platform: $Platform. Supported platforms: $([DeviceProviderFactory]::GetSupportedPlatforms() -join ', ')"
    }

    # Disconnect existing session if present
    if ($script:CurrentSession) {
        Write-Warning "Disconnecting from existing session: $($script:CurrentSession.Platform)"
        Disconnect-Device
    }

    # Build resource name for semaphore coordination
    $resourceName = New-DeviceResourceName -Platform $Platform -Target $Target
    Write-Debug "Device resource name: $resourceName"

    # Acquire exclusive access to the device resource
    # Default 30-minute timeout with progress messages every minute
    $semaphore = $null
    try {
        $semaphore = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds $TimeoutSeconds -ProgressIntervalSeconds 60
        Write-Output "Acquired exclusive access to device: $resourceName"

        # Create provider for the specified platform
        $provider = [DeviceProviderFactory]::CreateProvider($Platform)

        # Connect using the provider
        $sessionInfo = $provider.Connect($Target)

        # Store the provider instance and semaphore with the session
        $script:CurrentSession = $sessionInfo
        $script:CurrentSession.Provider = $provider
        $script:CurrentSession.Semaphore = $semaphore
        $script:CurrentSession.ResourceName = $resourceName

        Write-Debug "Successfully connected to $Platform device (Device: $($script:CurrentSession.Identifier))"

        return $script:CurrentSession
    } catch {
        # If connection failed after acquiring semaphore, release it
        if ($semaphore) {
            Write-Debug "Connection failed, releasing semaphore for resource: $resourceName"
            Release-DeviceAccess -Semaphore $semaphore -ResourceName $resourceName
        }
        throw
    }
}
