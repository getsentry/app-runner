function Get-SentryLogs {
    <#
    .SYNOPSIS
    Retrieves structured logs from Sentry.

    .DESCRIPTION
    Fetches Sentry structured logs matching specified criteria.
    Supports filtering by query, severity levels, trace ID, and time range.
    Uses the Sentry Discover API with the 'ourlogs' dataset.

    .PARAMETER Query
    Search query string using Sentry search syntax (e.g., 'test_id:abc123', 'severity:error').

    .PARAMETER TraceId
    Filter logs by specific trace ID.

    .PARAMETER StatsPeriod
    Relative time period (e.g., '24h', '7d', '14d'). Default is '24h'.

    .PARAMETER Limit
    Maximum number of logs to return. Default is 100.

    .PARAMETER Cursor
    Pagination cursor for retrieving subsequent pages of results.

    .PARAMETER Fields
    Specific fields to return. Default includes: id, trace, severity, timestamp, message.

    .EXAMPLE
    Get-SentryLogs -Query 'test_id:integration-test-001'

    .EXAMPLE
    Get-SentryLogs -Query 'severity:error' -StatsPeriod '7d'

    .EXAMPLE
    Get-SentryLogs -TraceId 'abc123def456' -Limit 50
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [string]$TraceId,

        [Parameter(Mandatory = $false)]
        [string]$StatsPeriod = '24h',

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100,

        [Parameter(Mandatory = $false)]
        [string]$Cursor,

        [Parameter(Mandatory = $false)]
        [string[]]$Fields
    )

    # Build the query string combining Query and TraceId if provided
    $QueryParts = @()
    if ($Query) {
        $QueryParts += $Query
    }
    if ($TraceId) {
        $QueryParts += "trace:$TraceId"
    }
    $FinalQuery = $QueryParts -join ' '

    # Default fields for logs if not specified (matching API format)
    if (-not $Fields -or $Fields.Count -eq 0) {
        $Fields = @(
            'id',
            'trace',
            'severity',
            'timestamp',
            'message'
        )
    }

    $QueryParams = @{
        dataset     = 'ourlogs'
        statsPeriod = $StatsPeriod
        per_page    = $Limit
        field       = $Fields
    }

    if ($FinalQuery) {
        $QueryParams.query = $FinalQuery
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
        Write-Error "Failed to retrieve logs - $_"
        throw
    }
}
