# https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest
@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'SentryApiClient.psm1'

    # Version number of this module.
    ModuleVersion        = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID                 = 'e7b8c2f4-5a3d-4e2b-9d1a-8c6f2b7e4a1c'

    # Author of this module
    Author               = 'Sentry'

    # Company or vendor of this module
    CompanyName          = 'Sentry'

    # Copyright statement for this module
    Copyright            = '(c) Sentry. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'PowerShell module for interacting with Sentry REST APIs'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion    = '5.1'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport    = @(
        'Connect-SentryApi',
        'Disconnect-SentryApi',
        'Find-SentryEventByTag',
        'Get-SentryCLI',
        'Get-SentryEvent',
        'Get-SentryEventsByTag',
        'Get-SentryLogs',
        'Get-SentryLogsByAttribute',
        'Get-SentryMetrics',
        'Get-SentryMetricsByAttribute',
        'Invoke-SentryCLI'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport      = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('Sentry', 'API', 'REST', 'Monitoring', 'Error-Tracking', 'PSEdition_Core', 'Windows')

            # A URL to the license for this module.
            LicenseUri   = 'https://raw.githubusercontent.com/getsentry/app-runner/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/getsentry/app-runner'

            # A URL to an icon representing this module.
            IconUri      = 'https://raw.githubusercontent.com/getsentry/platformicons/4e407e832f1a2a95d77ca8ca0ea2a195a38eec24/svg/sentry.svg'

            # ReleaseNotes of this module
            # ReleaseNotes = 'https://raw.githubusercontent.com/getsentry/app-runner/main/CHANGELOG.md'

            # Prerelease string of this module
            Prerelease   = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}
