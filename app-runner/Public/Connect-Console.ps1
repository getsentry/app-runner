function Connect-Console {
    <#
    .SYNOPSIS
    Establishes a connection to a console devkit by platform.

    .DESCRIPTION
    Connects to a console devkit for the specified platform. The target manager
    automatically handles devkit selection and IP address resolution.

    .PARAMETER Platform
    The console platform to connect to. Valid values: Xbox, PlayStation5, Switch

    .PARAMETER Target
    For Xbox platform, specifies the target to connect to. Can be either a name or IP address.
    If not specified, the system will auto-discover an available Xbox target.

    .EXAMPLE
    Connect-Console -Platform "Xbox"
    # Auto-discovers an available Xbox devkit

    .EXAMPLE
    Connect-Console -Platform "Xbox" -Target "192.168.1.100"
    # Connects to a specific Xbox target by IP

    .EXAMPLE
    Connect-Console -Platform "Xbox" -Target "NetHostName"
    # Connects to a specific Xbox target by name

    .EXAMPLE
    Connect-Console -Platform "PlayStation5"
    # Auto-discovers an available PS5 devkit
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Xbox", "PlayStation5", "Switch", "Mock")]
        [string]$Platform,

        [Parameter(Mandatory = $false)]
        [string]$Target
    )

    Write-Debug "Connecting to console platform: $Platform"

    # Validate platform is supported
    if (-not [ConsoleProviderFactory]::IsPlatformSupported($Platform)) {
        throw "Unsupported console platform: $Platform. Supported platforms: $([ConsoleProviderFactory]::GetSupportedPlatforms() -join ', ')"
    }

    # Disconnect existing session if present
    if ($script:CurrentSession) {
        Write-Warning "Disconnecting from existing session: $($script:CurrentSession.Platform)"
        Disconnect-Console
    }

    # Create provider for the specified platform
    $provider = [ConsoleProviderFactory]::CreateProvider($Platform)

    # Connect using the provider
    if ($Platform -eq "Xbox" -and $Target) {
        $sessionInfo = $provider.Connect($Target)
    } else {
        $sessionInfo = $provider.Connect()
    }

    # Store the provider instance with the session
    $script:CurrentSession = $sessionInfo
    $script:CurrentSession.Provider = $provider

    Write-Debug "Successfully connected to $Platform console (Console: $($script:CurrentSession.Identifier))"

    return $script:CurrentSession
}
