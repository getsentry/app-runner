function Connect-Device {
    <#
    .SYNOPSIS
    Establishes a connection to a device devkit by platform.

    .DESCRIPTION
    Connects to a device devkit for the specified platform. The target manager
    automatically handles devkit selection and IP address resolution.

    .PARAMETER Platform
    The platform to connect to. Valid values: Xbox, PlayStation5, Switch, Windows, MacOS, Linux, Local (auto-detects current OS)

    .PARAMETER Target
    For Xbox platform, specifies the target to connect to. Can be either a name or IP address.
    If not specified, the system will auto-discover an available Xbox target.

    .PARAMETER TimeoutSeconds
    Maximum time to wait for exclusive device access. Default is 3600 seconds (60 minutes).
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

    .EXAMPLE
    Connect-Device -Platform "Local"
    # Connects to the local computer (auto-detects Windows, MacOS, or Linux)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Xbox', 'PlayStation5', 'Switch', 'Windows', 'MacOS', 'Linux', 'AndroidAdb', 'AndroidSauceLabs', 'iOSSauceLabs', 'Local', 'Mock')]
        [string]$Platform,

        [Parameter(Mandatory = $false)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3600
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

    # Determine if mutex should be used for this platform
    # Android platforms don't need mutex (ADB can manage multiple connections, SauceLabs sessions are isolated)
    $useMutex = $Platform -notin @('AndroidAdb', 'AndroidSauceLabs')

    # Build resource name for mutex coordination (if needed)
    # Xbox requires platform-level mutex (not per-target) because xb*.exe commands
    # operate on the "current" target set via xbconnect, which is global to the system.
    # Multiple processes with different target mutexes would still conflict.
    $mutex = $null
    $resourceName = $null

    if ($useMutex) {
        $mutexTarget = if ($Platform -eq 'Xbox') { $null } else { $Target }
        $resourceName = New-DeviceResourceName -Platform $Platform -Target $mutexTarget
        Write-Debug "Device resource name: $resourceName"
    } else {
        Write-Debug "Skipping mutex for platform: $Platform"
    }

    try {
        # Acquire exclusive access to the device resource (if needed)
        if ($useMutex) {
            $mutex = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds $TimeoutSeconds -ProgressIntervalSeconds 60
            Write-Output "Acquired exclusive access to device: $resourceName"
        }

        # Create provider for the specified platform
        $provider = [DeviceProviderFactory]::CreateProvider($Platform)

        # Connect using the provider
        $sessionInfo = $provider.Connect($Target)

        # Store the provider instance and mutex with the session
        $script:CurrentSession = $sessionInfo
        $script:CurrentSession.Provider = $provider
        $script:CurrentSession.Mutex = $mutex
        $script:CurrentSession.ResourceName = $resourceName

        Write-Debug "Successfully connected to $Platform device (Device: $($script:CurrentSession.Identifier))"

        return $script:CurrentSession
    } catch {
        # If connection failed after acquiring mutex, release it
        if ($mutex) {
            Write-Debug "Connection failed, releasing mutex for resource: $resourceName"
            Release-DeviceAccess -Mutex $mutex -ResourceName $resourceName
        }
        throw
    }
}
