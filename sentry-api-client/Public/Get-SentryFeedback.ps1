function Get-SentryFeedback {
    <#
    .SYNOPSIS
    Retrieves user feedback from Sentry.

    .DESCRIPTION
    Fetches user feedback submissions, which are stored as issue-platform occurrences
    with the 'feedback' category. Supports narrowing the results with a free-text query
    (which matches the feedback message) and optionally enriches each result with the
    associated event ID resolved from the feedback issue's latest event.

    .PARAMETER Query
    Optional free-text query appended to 'issue.category:feedback'. Matches the feedback
    message, so a unique token embedded in the message can be used to locate a single
    submission.

    .PARAMETER StatsPeriod
    Relative time period (e.g. '24h', '7d', '14d'). Default is '24h'.

    .PARAMETER Limit
    Maximum number of feedback submissions to return. Default is 100.

    .PARAMETER Cursor
    Pagination cursor for retrieving subsequent pages of results.

    .PARAMETER IncludeAssociatedEvent
    If specified, resolves each feedback issue's latest event and attaches an
    'associatedEventId' property (from contexts.feedback.associated_event_id).

    .EXAMPLE
    Get-SentryFeedback -Query 'integration-test-abc123'

    .EXAMPLE
    Get-SentryFeedback -Query 'integration-test-abc123' -IncludeAssociatedEvent
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
        [switch]$IncludeAssociatedEvent
    )

    $QueryParts = @('issue.category:feedback')
    if ($Query) {
        $QueryParts += $Query
    }

    $QueryParams = @{
        query       = $QueryParts -join ' '
        statsPeriod = $StatsPeriod
        limit       = $Limit
    }

    if ($Cursor) {
        $QueryParams.cursor = $Cursor
    }

    $QueryString = Build-QueryString -Parameters $QueryParams
    $Uri = Get-SentryOrganizationUrl -Resource "issues/" -QueryString $QueryString

    try {
        $Response = Invoke-SentryApiRequest -Uri $Uri -Method 'GET'
    }
    catch {
        Write-Error "Failed to retrieve feedback - $_"
        throw
    }

    if ($IncludeAssociatedEvent) {
        foreach ($item in $Response) {
            $associatedEventId = $null
            try {
                $LatestUri = Get-SentryOrganizationUrl -Resource "issues/$($item.id)/events/latest/"
                $LatestEvent = Invoke-SentryApiRequest -Uri $LatestUri -Method 'GET'
                $associatedEventId = $LatestEvent.contexts.feedback.associated_event_id
            }
            catch {
                Write-Debug "Failed to resolve latest event for feedback $($item.id) - $_"
            }
            $item | Add-Member -MemberType NoteProperty -Name 'associatedEventId' -Value $associatedEventId -Force
        }
    }

    return $Response
}
