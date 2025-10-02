function Disconnect-SentryApi {
    <#
    .SYNOPSIS
    Disconnects from the Sentry API.

    .DESCRIPTION
    Clears the current Sentry API connection and configuration, removing stored
    authentication tokens and organization/project settings.

    .EXAMPLE
    Disconnect-SentryApi
    # Disconnects from the current Sentry API session
    #>
    [CmdletBinding()]
    param()

    $Script:SentryApiConfig.ApiToken = $null
    $Script:SentryApiConfig.Organization = $null
    $Script:SentryApiConfig.Project = $null
    $Script:SentryApiConfig.Headers = @{}

    Write-Debug "Disconnected from Sentry API"
}
