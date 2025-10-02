function Get-SentryEventsByTag {
    <#
    .SYNOPSIS
    Retrieves events filtered by a specific tag.

    .DESCRIPTION
    Fetches Sentry events that match a specific tag name and value.
    Supports pagination and can return either summary or full event details.

    .PARAMETER TagName
    The name of the tag to filter by (e.g., 'environment', 'release', 'user.email').

    .PARAMETER TagValue
    The value of the tag to match.

    .PARAMETER Limit
    Maximum number of events to return. Default is 100.

    .PARAMETER Cursor
    Pagination cursor for retrieving subsequent pages of results.

    .PARAMETER Full
    If specified, returns full event details instead of summaries.

    .EXAMPLE
    Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'
    # Retrieves events from production environment

    .EXAMPLE
    Get-SentryEventsByTag -TagName 'user.email' -TagValue 'user@example.com' -Full
    # Retrieves full event details for a specific user

    .EXAMPLE
    Get-SentryEventsByTag -TagName 'release' -TagValue '1.0.0' -Limit 50 -Cursor 'next123'
    # Retrieves next page of events for release 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$TagValue,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100,

        [Parameter(Mandatory = $false)]
        [string]$Cursor,

        [Parameter(Mandatory = $false)]
        [switch]$Full
    )

    $QueryString = "$TagName`:$TagValue"
    
    $QueryParams = @{
        query = $QueryString
        full = if ($Full) { 'true' } else { 'false' }
        limit = $Limit
    }

    if ($Cursor) {
        $QueryParams.cursor = $Cursor
    }

    $QueryStringParams = Build-QueryString -Parameters $QueryParams
    $Uri = Get-SentryProjectUrl -Resource "events/" -QueryString $QueryStringParams

    try {
        $Response = Invoke-SentryApiRequest -Uri $Uri -Method 'GET'
        return $Response
    }
    catch {
        Write-Error "Failed to retrieve events for tag $TagName`:$TagValue - $_"
        throw
    }
}