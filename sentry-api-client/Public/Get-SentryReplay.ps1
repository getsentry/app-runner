function Get-SentryReplay {
    <#
    .SYNOPSIS
    Retrieves a specific session replay from Sentry.

    .DESCRIPTION
    Fetches detailed information about a specific Sentry session replay by its ID
    (duration, segment count, associated trace IDs, timestamps, etc.).
    Automatically removes hyphens from GUID-formatted replay IDs.

    .PARAMETER ReplayId
    The unique identifier of the replay to retrieve. Can be provided with or without hyphens.

    .EXAMPLE
    Get-SentryReplay -ReplayId "7acc9c0d4a2e0a85187fe9b75e6b05ac"
    # Retrieves the replay with the given ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayId
    )

    # Remove hyphens from GUID-formatted replay IDs
    $ReplayId = $ReplayId -replace '-', ''

    $Uri = Get-SentryProjectUrl -Resource "replays/$ReplayId/"

    $Response = Invoke-SentryApiRequest -Uri $Uri -Method 'GET'

    # The replay instance endpoint wraps the payload in a 'data' envelope
    if ($Response -is [hashtable] -and $Response.ContainsKey('data')) {
        return $Response.data
    }

    return $Response
}
