function Get-SentryLogsByAttribute {
    <#
    .SYNOPSIS
    Retrieves logs filtered by a specific attribute.

    .DESCRIPTION
    Fetches Sentry structured logs that match a specific attribute name and value.
    This is a convenience wrapper around Get-SentryLogs for common use cases
    like filtering by test_id for integration testing.

    .PARAMETER AttributeName
    The name of the attribute to filter by (e.g., 'test_id', 'user_id', 'service_name').

    .PARAMETER AttributeValue
    The value of the attribute to match.

    .PARAMETER Limit
    Maximum number of logs to return. Default is 100.

    .PARAMETER StatsPeriod
    Relative time period (e.g., '24h', '7d'). Default is '24h'.

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'test_id' -AttributeValue 'integration-test-001'

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'user_id' -AttributeValue '12345' -StatsPeriod '7d'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AttributeName,

        [Parameter(Mandatory = $true)]
        [string]$AttributeValue,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100,

        [Parameter(Mandatory = $false)]
        [string]$StatsPeriod = '24h'
    )

    $Query = "$AttributeName`:$AttributeValue"

    # Include default fields plus the attribute we're filtering by
    $Fields = @(
        'id',
        'trace',
        'severity',
        'timestamp',
        'message',
        $AttributeName
    )

    return Get-SentryLogs -Query $Query -Limit $Limit -StatsPeriod $StatsPeriod -Fields $Fields
}
