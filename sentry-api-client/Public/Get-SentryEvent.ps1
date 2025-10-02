function Get-SentryEvent {
    <#
    .SYNOPSIS
    Retrieves a specific event from Sentry.

    .DESCRIPTION
    Fetches detailed information about a specific Sentry event by its ID.
    Automatically removes hyphens from GUID-formatted event IDs.

    .PARAMETER EventId
    The unique identifier of the event to retrieve. Can be provided with or without hyphens.

    .EXAMPLE
    Get-SentryEvent -EventId "abc123def456"
    # Retrieves the event with ID abc123def456

    .EXAMPLE
    Get-SentryEvent -EventId "abc123de-f456-7890-1234-567890abcdef"
    # Retrieves the event (hyphens are automatically removed)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventId
    )

    # Remove hyphens from GUID-formatted event IDs
    $EventId = $EventId -replace '-', ''

    $Uri = Get-SentryProjectUrl -Resource "events/$EventId/"

    return Invoke-SentryApiRequest -Uri $Uri -Method 'GET'
}
