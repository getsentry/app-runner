function Get-SentryMetricsByAttribute {
    <#
    .SYNOPSIS
    Retrieves metrics filtered by metric name and a specific attribute.

    .DESCRIPTION
    Fetches Sentry metrics that match a specific metric name and attribute
    name/value pair. This is a convenience wrapper around Get-SentryMetrics
    for common use cases like filtering by test_id for integration testing.

    .PARAMETER MetricName
    The name of the metric to filter by (e.g., 'test.integration.counter').

    .PARAMETER AttributeName
    The name of the attribute to filter by (e.g., 'test_id').

    .PARAMETER AttributeValue
    The value of the attribute to match.

    .PARAMETER Limit
    Maximum number of metrics to return. Default is 100.

    .PARAMETER StatsPeriod
    Relative time period (e.g., '24h', '7d'). Default is '24h'.

    .PARAMETER Fields
    Additional fields to include in the response. These are merged with default fields
    (id, metric.name, metric.type, value, timestamp) and the filter attribute.

    .EXAMPLE
    Get-SentryMetricsByAttribute -MetricName 'test.integration.counter' -AttributeName 'test_id' -AttributeValue 'abc-123'

    .EXAMPLE
    Get-SentryMetricsByAttribute -MetricName 'my.counter' -AttributeName 'user_id' -AttributeValue '12345' -StatsPeriod '7d'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MetricName,

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

    $Query = "metric.name:$MetricName $AttributeName`:$AttributeValue"

    # Include default fields plus the attribute we're filtering by
    $DefaultFields = @(
        'id',
        'metric.name',
        'metric.type',
        'value',
        'timestamp',
        $AttributeName
    )

    if ($Fields) {
        $AllFields = @($DefaultFields + $Fields) | Select-Object -Unique
    } else {
        $AllFields = $DefaultFields
    }

    return Get-SentryMetrics -Query $Query -Limit $Limit -StatsPeriod $StatsPeriod -Fields $AllFields
}
