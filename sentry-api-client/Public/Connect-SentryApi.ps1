function Connect-SentryApi {
    <#
    .SYNOPSIS
    Establishes a connection to the Sentry API.

    .DESCRIPTION
    Connects to Sentry API with authentication and organization/project configuration.
    Supports two modes: manual configuration or DSN-based auto-configuration.

    .PARAMETER ApiToken
    The Sentry API authentication token. If not specified, uses $env:SENTRY_AUTH_TOKEN.

    .PARAMETER Organization
    The Sentry organization slug or ID. Required when not using DSN.

    .PARAMETER Project
    The Sentry project slug or ID. Required when not using DSN.

    .PARAMETER DSN
    The Sentry DSN URL. Automatically extracts organization and project from the DSN.

    .PARAMETER BaseUrl
    The base URL for Sentry API. Default is 'https://sentry.io/api/0'.

    .EXAMPLE
    Connect-SentryApi -ApiToken "your-api-token" -Organization "your-org" -Project "your-project"
    # Connects using explicit organization and project

    .EXAMPLE
    Connect-SentryApi -DSN "https://PUBLIC_KEY@o123456.ingest.sentry.io/789"
    # Connects using DSN (requires $env:SENTRY_AUTH_TOKEN to be set)

    .EXAMPLE
    Connect-SentryApi -Organization "my-org" -Project "my-project"
    # Uses $env:SENTRY_AUTH_TOKEN for authentication
    #>
    [CmdletBinding(DefaultParameterSetName = 'Manual')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ApiToken = $env:SENTRY_AUTH_TOKEN,

        [Parameter(Mandatory = $true, ParameterSetName = 'Manual')]
        [string]$Organization,

        [Parameter(Mandatory = $true, ParameterSetName = 'Manual')]
        [string]$Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'DSN')]
        [string]$DSN,

        [Parameter(Mandatory = $false)]
        [string]$BaseUrl = 'https://sentry.io/api/0'
    )

    # If DSN is provided, parse it to extract organization and project IDs
    if ($PSCmdlet.ParameterSetName -eq 'DSN') {
        try {
            $uri = [System.Uri]$DSN
            $SentryHost = $uri.Host
            $ProjectId = $uri.AbsolutePath.TrimStart('/')
            
            # Extract organization ID from host (e.g., o447951.ingest.us.sentry.io -> 447951)
            if ($SentryHost -match '^o(\d+)\.') {
                $OrgId = $matches[1]
            } else {
                throw "Cannot extract organization ID from DSN host: $SentryHost"
            }
            
            # For Sentry.io hosted instances, use sentry.io as API host
            if ($SentryHost -like "*.sentry.io") {
                $BaseUrl = "https://sentry.io/api/0"
            } else {
                $BaseUrl = "https://$SentryHost/api/0"
            }
            
            $Organization = $OrgId
            $Project = $ProjectId
            
            Write-Debug "Parsed DSN: Organization ID = $OrgId, Project ID = $ProjectId"
        } catch {
            throw "Failed to parse DSN '$DSN': $($_.Exception.Message). Expected format: https://PUBLIC_KEY@oORG_ID.*.sentry.io/PROJECT_ID"
        }
    }

    $Script:SentryApiConfig.ApiToken = $ApiToken
    $Script:SentryApiConfig.Organization = $Organization
    $Script:SentryApiConfig.Project = $Project
    $Script:SentryApiConfig.BaseUrl = $BaseUrl
    $Script:SentryApiConfig.Headers = @{
        'Authorization' = "Bearer $ApiToken"
        'Content-Type' = 'application/json'
    }

    Write-Debug "Connected to Sentry API for organization: $Organization/$Project"
}
