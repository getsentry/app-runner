# Retry Policies
# Named, reusable retry settings for the module's HTTP callers.

$script:RetryPolicyRegistry = @{}

# Sauce Labs documents these as configuration errors that retries cannot resolve.
# See <https://docs.saucelabs.com/dev/error-messages/> for the complete error catalog.
# Only fatal: add a message only after confirming that retrying cannot resolve it.
$script:SauceLabsFatalSessionMessages = @(
    "we couldn't find a matching device in our data center",
    "sauce labs virtual machine failed to start the browser or device"
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
Maximum server-requested Retry-After delay to honor. A response requesting a longer delay fails without another attempt.

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

# Do not retry transport failures because the session may have been created before its response was lost.
# Another attempt could allocate a second device and leave the first session orphaned.
# Known permanent failures are not retried; unknown messages are retried.
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
            if ($Context.Detail -ilike "*$pattern*") {
                return $false
            }
        }

        return $true
    })

# Each attempt burns a slot against Sauce Labs' 100-per-15-minutes limit, so keep the budget small.
# Transport failures still retry, unlike session and launch: a lost upload only orphans a storage
# version, while not retrying would fail the job on a blip during a large transfer.
Register-RetryPolicy -Name 'upload' -Policy (New-RetryPolicy -Name 'upload' `
        -MaxAttempts 3 -BaseDelaySeconds 5.0 -MaxDelaySeconds 30.0 -MaxRetryAfterSeconds 120.0)

# A transport retry after a launch that landed would run the test app twice and rewrite its log.
Register-RetryPolicy -Name 'launch' -Policy (New-RetryPolicy -Name 'launch' `
        -MaxAttempts 3 -BaseDelaySeconds 2.0 -RetryTransport $false)

# Best-effort teardown: a generous budget would add minutes to cleanup during an outage.
Register-RetryPolicy -Name 'quick' -Policy (New-RetryPolicy -Name 'quick' `
        -MaxAttempts 2 -BaseDelaySeconds 1.0 -MaxDelaySeconds 5.0 -MaxRetryAfterSeconds 10.0)

Register-RetryPolicy -Name 'none' -Policy (New-RetryPolicy -Name 'none' -MaxAttempts 1)
