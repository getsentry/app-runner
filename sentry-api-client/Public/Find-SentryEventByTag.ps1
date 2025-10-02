function Find-SentryEventByTag
{
    <#
    .SYNOPSIS
    Finds issues and their associated events filtered by a tag.

    .DESCRIPTION
    Searches for Sentry issues matching a specific tag and retrieves the associated
    events. Returns structured data with both issues and events. This function first
    finds matching issues, then fetches events for each issue.

    .PARAMETER TagName
    The name of the tag to filter by (e.g., 'environment', 'release', 'browser').

    .PARAMETER TagValue
    The value of the tag to match.

    .PARAMETER Limit
    Maximum number of events to return across all matching issues. Default is 100.

    .PARAMETER Cursor
    Pagination cursor for retrieving subsequent pages of results.

    .PARAMETER Sort
    Sort order for issues. Valid values: 'date', 'new', 'freq', 'user', 'trends', 'inbox'.
    Default is 'date'.

    .EXAMPLE
    Find-SentryEventByTag -TagName 'environment' -TagValue 'production'
    # Finds all issues and events from production environment

    .EXAMPLE
    Find-SentryEventByTag -TagName 'browser' -TagValue 'Chrome' -Sort 'date' -Limit 50
    # Finds up to 50 events from Chrome browser, sorted by date

    .EXAMPLE
    $result = Find-SentryEventByTag -TagName 'release' -TagValue 'v1.0.0'
    $result | ForEach-Object { $_.id }
    # Gets all event IDs for release v1.0.0
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
        [ValidateSet('date', 'new', 'freq', 'user', 'trends', 'inbox')]
        [string]$Sort = 'date'
    )

    $QueryString = "$TagName`:$TagValue"

    $QueryParams = @{
        query = $QueryString
        limit = $Limit
        sort  = $Sort
    }

    if ($Cursor)
    {
        $QueryParams.cursor = $Cursor
    }

    $QueryStringParams = Build-QueryString -Parameters $QueryParams
    $Uri = Get-SentryProjectUrl -Resource 'issues/' -QueryString $QueryStringParams

    $Response = Invoke-SentryApiRequest -Uri $Uri -Method 'GET'

    # Ensure we have an array of issues
    $Issues = if ($Response -is [Array]) { $Response } else { @($Response) }
    $AllEvents = @()

    Write-Debug "Found $($Issues.Count) issues matching tag '$TagName`:$TagValue'. Fetching events..."

    foreach ($Issue in $Issues)
    {
        try
        {
            # Use the organization issues events endpoint with tag filtering
            $EventsQueryParams = @{
                query = $QueryString
                full  = $true
            }

            if ($Limit)
            {
                # Distribute limit across issues, minimum 1 per issue
                $EventsPerIssue = [Math]::Max(1, [Math]::Floor($Limit / $Issues.Count))
                $EventsQueryParams.limit = $EventsPerIssue
            }

            $EventsQueryStringParams = Build-QueryString -Parameters $EventsQueryParams
            $EventsUri = Get-SentryOrganizationUrl -Resource "issues/$($Issue.id)/events/" -QueryString $EventsQueryStringParams

            $IssueEvents = Invoke-SentryApiRequest -Uri $EventsUri -Method 'GET'
            $IssueEventsArray = if ($IssueEvents -is [Array]) { $IssueEvents } else { @($IssueEvents) }
            Write-Debug "Found $($IssueEvents.Count) events for issue $($Issue.id) matching tag '$TagName`:$TagValue', fetching actual event content."

            # The response from the API above differs from the Get-SentryEvent so we just grab event IDs and fetch directly.
            foreach ($_event in $IssueEventsArray)
            {
                $_event = Get-SentryEvent -EventId $_event.eventID
                $AllEvents += $_event
            }

        }
        catch
        {
            Write-Error "Failed to retrieve events for issue $($Issue.id): $_"
        }
    }

    # Always return an array, even if empty
    return Write-Output -NoEnumerate $AllEvents
}
