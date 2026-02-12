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

    .PARAMETER Fields
    Additional fields to include in the response. These are merged with default fields
    (id, trace, severity, timestamp, message) and the filter attribute.

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'test_id' -AttributeValue 'integration-test-001'

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'user_id' -AttributeValue '12345' -StatsPeriod '7d'

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'test_id' -AttributeValue 'test-001' -Fields @('sentry.environment', 'custom_attr')
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
        [string]$StatsPeriod = '24h',

        [Parameter(Mandatory = $false)]
        [string[]]$Fields
    )

    $Query = "$AttributeName`:$AttributeValue"

    # Include default fields plus the attribute we're filtering by
    $DefaultFields = @(
        'id',
        'trace',
        'severity',
        'timestamp',
        'message',
        $AttributeName
    )

    if ($Fields) {
        $AllFields = @($DefaultFields + $Fields) | Select-Object -Unique
    } else {
        $AllFields = $DefaultFields
    }

    return Get-SentryLogs -Query $Query -Limit $Limit -StatsPeriod $StatsPeriod -Fields $AllFields
}
