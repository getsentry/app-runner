function Get-SentryEventAttachments {
    <#
    .SYNOPSIS
    Retrieves attachments for a specific event from Sentry.

    .DESCRIPTION
    Fetches the list of attachments associated with a specific Sentry event by its ID.
    Automatically removes hyphens from GUID-formatted event IDs.

    .PARAMETER EventId
    The unique identifier of the event whose attachments to retrieve.

    .EXAMPLE
    Get-SentryEventAttachments -EventId "abc123def456"
    # Returns an array of attachment objects for the event
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventId
    )

    # Remove hyphens from GUID-formatted event IDs
    $EventId = $EventId -replace '-', ''

    $Uri = Get-SentryProjectUrl -Resource "events/$EventId/attachments/"

    # The API returns a top-level JSON array. ConvertFrom-Json -AsHashtable unwraps
    # single-element arrays into a hashtable, so wrap in @() to ensure array output.
    return , @(Invoke-SentryApiRequest -Uri $Uri -Method 'GET')
}
