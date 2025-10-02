# Device Provider Factory
# Creates appropriate device provider instances based on platform

<#
.SYNOPSIS
Factory class for creating device providers.

.DESCRIPTION
This factory creates the appropriate device provider instance based on the specified platform.
It handles provider instantiation and ensures the correct provider is used for each device type.
#>
class DeviceProviderFactory {
    <#
    .SYNOPSIS
    Creates a device provider for the specified platform.

    .PARAMETER Platform
    The platform to create a provider for.

    .RETURNS
    An instance of the appropriate device provider.
    #>
    static [DeviceProvider] CreateProvider([string]$Platform) {
        Write-Debug "DeviceProviderFactory: Creating provider for platform: $Platform"

        switch ($Platform) {
            "Xbox" {
                Write-Debug "DeviceProviderFactory: Creating XboxProvider"
                return [XboxProvider]::new()
            }
            "PlayStation5" {
                Write-Debug "DeviceProviderFactory: Creating PlayStation5Provider"
                return [PlayStation5Provider]::new()
            }
            "Switch" {
                Write-Debug "DeviceProviderFactory: Creating SwitchProvider"
                return [SwitchProvider]::new()
            }
            "Mock" {
                Write-Debug "DeviceProviderFactory: Creating MockDeviceProvider"
                return [MockDeviceProvider]::new()
            }
            default {
                $errorMessage = "Unsupported platform: $Platform. Supported platforms: Xbox, PlayStation5, Switch, Mock"
                Write-Error "DeviceProviderFactory: $errorMessage"
                throw $errorMessage
            }
        }

        # This should never be reached due to throw above, but satisfies PowerShell compiler
        return $null
    }

    <#
    .SYNOPSIS
    Gets the list of supported platforms.

    .RETURNS
    An array of supported platform names.
    #>
    static [string[]] GetSupportedPlatforms() {
        return @("Xbox", "PlayStation5", "Switch", "Mock")
    }

    <#
    .SYNOPSIS
    Validates that a platform is supported.

    .PARAMETER Platform
    The platform name to validate.

    .RETURNS
    True if the platform is supported, false otherwise.
    #>
    static [bool] IsPlatformSupported([string]$Platform) {
        $supportedPlatforms = [DeviceProviderFactory]::GetSupportedPlatforms()
        return $supportedPlatforms -contains $Platform
    }
}
