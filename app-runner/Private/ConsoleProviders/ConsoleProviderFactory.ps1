# Console Provider Factory
# Creates appropriate console provider instances based on platform

<#
.SYNOPSIS
Factory class for creating console providers.

.DESCRIPTION
This factory creates the appropriate console provider instance based on the specified platform.
It handles provider instantiation and ensures the correct provider is used for each console type.
#>
class ConsoleProviderFactory {
    <#
    .SYNOPSIS
    Creates a console provider for the specified platform.

    .PARAMETER Platform
    The console platform to create a provider for.

    .RETURNS
    An instance of the appropriate console provider.
    #>
    static [ConsoleProvider] CreateProvider([string]$Platform) {
        Write-Debug "ConsoleProviderFactory: Creating provider for platform: $Platform"

        switch ($Platform) {
            "Xbox" {
                Write-Debug "ConsoleProviderFactory: Creating XboxProvider"
                return [XboxProvider]::new()
            }
            "PlayStation5" {
                Write-Debug "ConsoleProviderFactory: Creating PlayStation5Provider"
                return [PlayStation5Provider]::new()
            }
            "Switch" {
                Write-Debug "ConsoleProviderFactory: Creating SwitchProvider"
                return [SwitchProvider]::new()
            }
            "Mock" {
                Write-Debug "ConsoleProviderFactory: Creating MockConsoleProvider"
                return [MockConsoleProvider]::new()
            }
            default {
                $errorMessage = "Unsupported console platform: $Platform. Supported platforms: Xbox, PlayStation5, Switch, Mock"
                Write-Error "ConsoleProviderFactory: $errorMessage"
                throw $errorMessage
            }
        }

        # This should never be reached due to throw above, but satisfies PowerShell compiler
        return $null
    }

    <#
    .SYNOPSIS
    Gets the list of supported console platforms.

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
        $supportedPlatforms = [ConsoleProviderFactory]::GetSupportedPlatforms()
        return $supportedPlatforms -contains $Platform
    }
}
