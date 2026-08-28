# Retry Policies
# Structured, extensible retry configuration shared by the module's HTTP callers.
#
# A policy is a [pscustomobject] rather than a class because PowerShell classes defined in
# dot-sourced private files are unreachable outside the module, which would stop callers from
# defining policies of their own.

$script:RetryPolicyRegistry = @{}

# Sauce Labs session-creation failures that are configuration errors rather than transient faults.
# https://docs.saucelabs.com/dev/error-messages/
$script:SauceLabsFatalSessionMessages = @(
    'No device matching the query',
    'desired capabilities are invalid',
    'Failed to Start the Browser or Device'
)

<#
.SYNOPSIS
Creates a retry policy.

.DESCRIPTION
Returns a policy object tagged 'SentryAppRunner.RetryPolicy' for use with Invoke-HttpWithRetry.
Unspecified fields come from -BasedOn when given, otherwise from the module defaults.

.PARAMETER Name
Identifies the policy in log lines and error messages.

.PARAMETER BasedOn
An existing policy to inherit every unspecified field from.

.PARAMETER MaxAttempts
Total attempts including the first. 1 disables retrying.

.PARAMETER BaseDelaySeconds
The first backoff step. Each further attempt doubles it.

.PARAMETER MaxDelaySeconds
Upper bound on the computed backoff.

.PARAMETER MaxRetryAfterSeconds
Upper bound on a server-requested Retry-After delay. A longer request fails immediately.

.PARAMETER JitterFactor
Fraction of the backoff, 0 to 1, randomly shaved off each delay.

.PARAMETER RetryStatusCodes
HTTP status codes to retry.

.PARAMETER RetryTransport
Whether to retry a transport failure, which carries no response and may have landed on the server.

.PARAMETER ShouldRetry
Replaces the declarative classification entirely. Receives a context object with Attempt,
Exception, StatusCode, Body, ParsedBody, Detail, RetryAfterSeconds and Policy, and returns
whether to retry.

.EXAMPLE
New-RetryPolicy -Name 'patient-session' -BasedOn (Get-RetryPolicy 'session') -MaxAttempts 10
#>
function New-RetryPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [PSTypeName('SentryAppRunner.RetryPolicy')]$BasedOn,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxAttempts,

        [ValidateRange(0.0, [double]::MaxValue)]
        [double]$BaseDelaySeconds,

        [ValidateRange(0.0, [double]::MaxValue)]
        [double]$MaxDelaySeconds,

        [ValidateRange(0.0, [double]::MaxValue)]
        [double]$MaxRetryAfterSeconds,

        [ValidateRange(0.0, 1.0)]
        [double]$JitterFactor,

        [int[]]$RetryStatusCodes,

        [bool]$RetryTransport,

        [scriptblock]$ShouldRetry
    )

    $fields = [ordered]@{
        PSTypeName           = 'SentryAppRunner.RetryPolicy'
        Name                 = $Name
        MaxAttempts          = 3
        BaseDelaySeconds     = 1.0
        MaxDelaySeconds      = 15.0
        MaxRetryAfterSeconds = 60.0
        JitterFactor         = 0.2
        RetryStatusCodes     = @(408, 429, 500, 502, 503, 504)
        RetryTransport       = $true
        ShouldRetry          = $null
    }

    foreach ($key in @($fields.Keys)) {
        if ($key -eq 'PSTypeName' -or $key -eq 'Name') {
            continue
        }
        if ($PSBoundParameters.ContainsKey($key)) {
            $fields[$key] = $PSBoundParameters[$key]
        }
        elseif ($BasedOn) {
            $fields[$key] = $BasedOn.$key
        }
    }

    if ($fields['MaxDelaySeconds'] -lt $fields['BaseDelaySeconds']) {
        throw "Retry policy '$Name': MaxDelaySeconds ($($fields['MaxDelaySeconds'])) must not be below BaseDelaySeconds ($($fields['BaseDelaySeconds']))."
    }

    return [pscustomobject]$fields
}

<#
.SYNOPSIS
Registers a retry policy under a name, replacing any policy already registered under it.

.DESCRIPTION
Overriding a built-in name changes the behaviour of every call site that resolves that name,
which is how a test run tunes retrying without touching the providers.

.EXAMPLE
Register-RetryPolicy -Name 'session' -Policy (New-RetryPolicy -Name 'session' -BasedOn (Get-RetryPolicy 'session') -MaxAttempts 10)
#>
function Register-RetryPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [PSTypeName('SentryAppRunner.RetryPolicy')]$Policy
    )

    $script:RetryPolicyRegistry[$Name] = $Policy
}

<#
.SYNOPSIS
Resolves a registered retry policy by name.

.DESCRIPTION
Throws an error listing the known names when the name is not registered.

.EXAMPLE
Get-RetryPolicy 'session'
#>
function Get-RetryPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    if (-not $script:RetryPolicyRegistry.ContainsKey($Name)) {
        $known = ($script:RetryPolicyRegistry.Keys | Sort-Object) -join ', '
        throw "Unknown retry policy '$Name'. Known: $known"
    }

    return $script:RetryPolicyRegistry[$Name]
}

Register-RetryPolicy -Name 'default' -Policy (New-RetryPolicy -Name 'default')

# Session creation is the failure this whole mechanism exists for, so it gets the largest budget.
# A transport failure is never retried: the POST may have landed and allocating a second device
# would leak the first one.
Register-RetryPolicy -Name 'session' -Policy (New-RetryPolicy -Name 'session' `
        -MaxAttempts 5 -BaseDelaySeconds 3.0 -MaxDelaySeconds 30.0 -MaxRetryAfterSeconds 120.0 `
        -JitterFactor 0.3 -RetryTransport $false -ShouldRetry {
        param($Context)

        if ($null -eq $Context.StatusCode) {
            return $Context.Policy.RetryTransport
        }

        if ($Context.StatusCode -notin $Context.Policy.RetryStatusCodes) {
            return $false
        }

        foreach ($pattern in $script:SauceLabsFatalSessionMessages) {
            if ($Context.Detail -like "*$pattern*") {
                return $false
            }
        }

        # Every session-creation failure is a 500, so the status code carries no information and
        # an unrecognised body has to be assumed transient. Refusing to retry here would
        # reintroduce the failure this policy exists for.
        return $true
    })

# Each upload attempt burns a slot against Sauce Labs' documented 100-per-15-minutes limit.
# Transport failures are retried here, unlike for session and launch, because a landed-but-lost
# upload only orphans a storage version that expires on its own, while refusing to retry would
# hard-fail the job on a blip during the multi-megabyte transfer most likely to see one.
Register-RetryPolicy -Name 'upload' -Policy (New-RetryPolicy -Name 'upload' `
        -MaxAttempts 3 -BaseDelaySeconds 5.0 -MaxDelaySeconds 30.0 -MaxRetryAfterSeconds 120.0)

# A transport retry after a launch that landed would run the test app twice and rewrite its log.
Register-RetryPolicy -Name 'launch' -Policy (New-RetryPolicy -Name 'launch' `
        -MaxAttempts 3 -BaseDelaySeconds 2.0 -RetryTransport $false)

# Best-effort teardown: a generous budget would add minutes to cleanup during an outage.
Register-RetryPolicy -Name 'quick' -Policy (New-RetryPolicy -Name 'quick' `
        -MaxAttempts 2 -BaseDelaySeconds 1.0 -MaxDelaySeconds 5.0 -MaxRetryAfterSeconds 10.0)

Register-RetryPolicy -Name 'none' -Policy (New-RetryPolicy -Name 'none' -MaxAttempts 1)
