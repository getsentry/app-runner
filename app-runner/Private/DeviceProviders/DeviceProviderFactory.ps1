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
    Detects the current operating system platform.

    .RETURNS
    The detected platform name (Windows, MacOS, or Linux).
    #>
    static [string] DetectLocalPlatform() {
        # Use PowerShell automatic variables to detect OS
        if ($global:IsWindows) {
            return 'Windows'
        }
        elseif ($global:IsMacOS) {
            return 'MacOS'
        }
        elseif ($global:IsLinux) {
            return 'Linux'
        }
        else {
            throw "Unable to detect local platform. Platform is not Windows, MacOS, or Linux."
        }
    }

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

        # Handle "Local" alias by auto-detecting the current platform
        if ($Platform -eq 'Local') {
            $Platform = [DeviceProviderFactory]::DetectLocalPlatform()
            Write-Debug "DeviceProviderFactory: 'Local' resolved to $Platform"
        }

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
            "Windows" {
                Write-Debug "DeviceProviderFactory: Creating WindowsProvider"
                return [WindowsProvider]::new()
            }
            "MacOS" {
                Write-Debug "DeviceProviderFactory: Creating MacOSProvider"
                return [MacOSProvider]::new()
            }
            "Linux" {
                Write-Debug "DeviceProviderFactory: Creating LinuxProvider"
                return [LinuxProvider]::new()
            }
            "AndroidAdb" {
                Write-Debug "DeviceProviderFactory: Creating AndroidAdbProvider"
                return [AndroidAdbProvider]::new()
            }
            "AndroidSauceLabs" {
                Write-Debug "DeviceProviderFactory: Creating SauceLabsProvider (Android)"
                return [SauceLabsProvider]::new('Android')
            }
            "iOSSauceLabs" {
                Write-Debug "DeviceProviderFactory: Creating SauceLabsProvider (iOS)"
                return [SauceLabsProvider]::new('iOS')
            }
            "Mock" {
                Write-Debug "DeviceProviderFactory: Creating MockDeviceProvider"
                return [MockDeviceProvider]::new()
            }
            default {
                $errorMessage = "Unsupported platform: $Platform. Supported platforms: Xbox, PlayStation5, Switch, Windows, MacOS, Linux, AndroidAdb, AndroidSauceLabs, Local, Mock"
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
        return @("Xbox", "PlayStation5", "Switch", "Windows", "MacOS", "Linux", "AndroidAdb", "AndroidSauceLabs", "iOSSauceLabs", "Local", "Mock")
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
