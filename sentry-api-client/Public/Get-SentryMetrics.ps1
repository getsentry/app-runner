function Get-SentryMetrics {
    <#
    .SYNOPSIS
    Retrieves metrics from Sentry.

    .DESCRIPTION
    Fetches Sentry metrics matching specified criteria.
    Supports filtering by query, time range, and custom fields.
    Uses the Sentry Discover API with the 'tracemetrics' dataset.

    .PARAMETER Query
    Search query string using Sentry search syntax (e.g., 'metric.name:my.counter', 'metric.type:counter').

    .PARAMETER StatsPeriod
    Relative time period (e.g., '24h', '7d', '14d'). Default is '24h'.

    .PARAMETER Limit
    Maximum number of metrics to return. Default is 100.

    .PARAMETER Cursor
    Pagination cursor for retrieving subsequent pages of results.

    .PARAMETER Fields
    Specific fields to return. Default includes: id, metric.name, metric.type, value, timestamp.

    .EXAMPLE
    Get-SentryMetrics -Query 'metric.name:my.counter'

    .EXAMPLE
    Get-SentryMetrics -Query 'metric.name:my.counter test_id:abc123' -StatsPeriod '7d'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [string]$StatsPeriod = '24h',

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100,

        [Parameter(Mandatory = $false)]
        [string]$Cursor,

        [Parameter(Mandatory = $false)]
        [string[]]$Fields
    )

    # Default fields for metrics if not specified
    if (-not $Fields -or $Fields.Count -eq 0) {
        $Fields = @(
            'id',
            'metric.name',
            'metric.type',
            'value',
            'timestamp'
        )
    }

    $QueryParams = @{
        dataset     = 'tracemetrics'
        statsPeriod = $StatsPeriod
        per_page    = $Limit
        field       = $Fields
    }

    if ($Query) {
        $QueryParams.query = $Query
    }

    if ($Cursor) {
        $QueryParams.cursor = $Cursor
    }

    $QueryString = Build-QueryString -Parameters $QueryParams
    $Uri = Get-SentryOrganizationUrl -Resource "events/" -QueryString $QueryString

    try {
        $Response = Invoke-SentryApiRequest -Uri $Uri -Method 'GET'
        return $Response
    }
    catch {
        Write-Error "Failed to retrieve metrics - $_"
        throw
    }
}
