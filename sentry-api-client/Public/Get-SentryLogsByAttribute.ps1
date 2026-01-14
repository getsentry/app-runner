function Get-SentryLogsByAttribute {
    <#
    .SYNOPSIS
    Retrieves logs filtered by a specific attribute.

    .DESCRIPTION
    Fetches Sentry structured logs that match a specific attribute name and value.
    This is a convenience wrapper around Get-SentryLogs for common use cases
    like filtering by test.id for integration testing.

    .PARAMETER AttributeName
    The name of the attribute to filter by (e.g., 'test.id', 'user.id', 'service.name').

    .PARAMETER AttributeValue
    The value of the attribute to match.

    .PARAMETER Limit
    Maximum number of logs to return. Default is 100.

    .PARAMETER StatsPeriod
    Relative time period (e.g., '24h', '7d'). Default is '24h'.

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'test.id' -AttributeValue 'integration-test-001'
    # Retrieves logs with test.id='integration-test-001'

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'user.id' -AttributeValue '12345' -StatsPeriod '7d'
    # Retrieves logs for user 12345 from the last 7 days

    .EXAMPLE
    Get-SentryLogsByAttribute -AttributeName 'service.name' -AttributeValue 'auth-service' -Limit 50
    # Retrieves up to 50 logs from the auth-service
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

    # Don't specify fields - let the API return the default set which includes all common fields
    return Get-SentryLogs -Query $Query -Limit $Limit -StatsPeriod $StatsPeriod
}
