# https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest
@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'SentryAppRunner.psm1'

    # Version number of this module.
    ModuleVersion        = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID                 = '8f9a7b2c-4d5e-6f8a-9b0c-1d2e3f4a5b6c'

    # Author of this module
    Author               = 'Sentry'

    # Company or vendor of this module
    CompanyName          = 'Sentry'

    # Copyright statement for this module
    Copyright            = '(c) Sentry. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'PowerShell module for automating device lifecycle management, app deployment, and diagnostics collection for Sentry SDK testing across multiple platforms.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion    = '5.1'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport    = @(
        'Connect-Device',
        'Copy-DeviceItem',
        'Disconnect-Device',
        'Get-DeviceDiagnostics',
        'Get-DeviceLogs',
        'Get-DeviceScreenshot',
        'Get-DeviceSession',
        'Get-DeviceStatus',
        'Install-DeviceApp',
        'Invoke-DeviceApp',
        'Restart-Device',
        'Start-Device',
        'Stop-Device',
        'Test-DeviceConnection',
        'Test-DeviceInternetConnection'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport      = @()

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules      = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('Sentry', 'Device', 'Platform', 'Automation', 'Testing', 'PSEdition_Core', 'Windows', 'Mobile', 'Desktop')

            # A URL to the license for this module.
            LicenseUri   = 'https://raw.githubusercontent.com/getsentry/app-runner/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/getsentry/app-runner'

            # A URL to an icon representing this module.
            IconUri      = 'https://raw.githubusercontent.com/getsentry/platformicons/4e407e832f1a2a95d77ca8ca0ea2a195a38eec24/svg/sentry.svg'

            # ReleaseNotes of this module
            ReleaseNotes = 'https://raw.githubusercontent.com/getsentry/app-runner/main/CHANGELOG.md'

            # Prerelease string of this module
            Prerelease   = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}
