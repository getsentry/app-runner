function Get-SentryReplayRecordingSegments {
    <#
    .SYNOPSIS
    Retrieves the recording segments of a session replay from Sentry.

    .DESCRIPTION
    Fetches the rrweb recording data of a Sentry session replay by its ID.
    The response is a JSON array with one entry per segment; each entry is the
    segment's list of rrweb events (video metadata, breadcrumbs, etc.).
    Automatically removes hyphens from GUID-formatted replay IDs.

    .PARAMETER ReplayId
    The unique identifier of the replay. Can be provided with or without hyphens.

    .EXAMPLE
    Get-SentryReplayRecordingSegments -ReplayId "7acc9c0d4a2e0a85187fe9b75e6b05ac"
    # Retrieves the rrweb events of all recording segments of the given replay
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayId
    )

    # Remove hyphens from GUID-formatted replay IDs
    $ReplayId = $ReplayId -replace '-', ''

    $Uri = Get-SentryProjectUrl -Resource "replays/$ReplayId/recording-segments/" -QueryString "download=true"

    # The endpoint returns an array with one entry per segment. Wrapping the
    # call in `@(...)` collects an empty response into an empty array rather
    # than `$null`. Pipeline enumeration collapses a single-segment response
    # into its inner rrweb event list on the way here, so detect that case
    # (elements are event dictionaries rather than segment lists) and re-wrap
    # it. The comma operator prevents the same unwrapping on return.
    $Segments = @(Invoke-SentryApiRequest -Uri $Uri -Method 'GET')
    if ($Segments.Count -gt 0 -and $Segments[0] -is [System.Collections.IDictionary]) {
        $Segments = , $Segments
    }

    return , $Segments
}
