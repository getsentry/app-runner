function Get-SentrySpans {
    <#
    .SYNOPSIS
    Retrieves spans from Sentry.

    .DESCRIPTION
    Fetches Sentry spans matching specified criteria.
    Supports filtering by query, trace ID, and time range.
    Uses the Sentry Discover API with the 'spans' dataset.
    Transactions are spans with is_transaction=true.

    .PARAMETER Query
    Search query string using Sentry search syntax (e.g., 'span.op:http.client', 'is_transaction:true').

    .PARAMETER TraceId
    Filter spans by specific trace ID.

    .PARAMETER StatsPeriod
    Relative time period (e.g., '24h', '7d', '14d'). Default is '24h'.

    .PARAMETER Limit
    Maximum number of spans to return. Default is 100.

    .PARAMETER Cursor
    Pagination cursor for retrieving subsequent pages of results.

    .PARAMETER Fields
    Specific fields to return. Default includes: id, trace, span.op, span.description, span.duration, is_transaction, timestamp, transaction.event_id.

    .EXAMPLE
    Get-SentrySpans -TraceId 'abc123def456789012345678901234ab'

    .EXAMPLE
    Get-SentrySpans -TraceId 'abc123def456' -Query 'is_transaction:true'

    .EXAMPLE
    Get-SentrySpans -Query 'span.op:http.client' -StatsPeriod '7d'
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

    # Default fields for spans if not specified
    if (-not $Fields -or $Fields.Count -eq 0) {
        $Fields = @(
            'id',
            'trace',
            'span.op',
            'span.description',
            'span.duration',
            'is_transaction',
            'timestamp',
            'transaction.event_id'
        )
    }

    $QueryParams = @{
        dataset     = 'spans'
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
        Write-Error "Failed to retrieve spans - $_"
        throw
    }
}
