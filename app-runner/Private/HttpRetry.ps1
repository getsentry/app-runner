# HTTP Retry Helper
# Runs an HTTP call under a retry policy (see RetryPolicy.ps1).

<#
.SYNOPSIS
Invokes a scriptblock, retrying transient HTTP failures according to a retry policy.

.DESCRIPTION
Classifies each failure by exception type and, for a policy carrying a ShouldRetry scriptblock,
by the response body as well. Honours a server-sent Retry-After, backs off exponentially
otherwise, and rethrows the original error unchanged once the policy's budget is spent.

The scriptblock must perform a bare web request: any error handling inside it hides the exception
type the classifier needs.

.PARAMETER ScriptBlock
The HTTP call to run.

.PARAMETER Policy
A policy object from New-RetryPolicy or Get-RetryPolicy.

.PARAMETER Operation
Labels the operation in log lines.

.PARAMETER SleepAction
Invoked with the delay in seconds. Overridable so tests need not sleep.

.EXAMPLE
Invoke-HttpWithRetry -ScriptBlock { Invoke-WebRequest -Uri $uri } -Policy (Get-RetryPolicy 'session') -Operation "POST $uri"
#>
function Invoke-HttpWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $true)]
        [PSTypeName('SentryAppRunner.RetryPolicy')]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [scriptblock]$SleepAction = { param($Seconds) Start-Sleep -Seconds $Seconds }
    )

    $attempt = 0
    while ($true) {
        $attempt++

        try {
            return & $ScriptBlock
        }
        catch {
            $context = New-RetryContext -Attempt $attempt -ErrorRecord $_ -Policy $Policy
            $status = if ($null -ne $context.StatusCode) { $context.StatusCode } else { $context.Exception.GetType().Name }
            $label = "policy=$($Policy.Name) status=$status"

            # An HTML error page runs to kilobytes, so shorten it for the log only. Policies match
            # against the whole message.
            $logged = if ($context.Detail.Length -gt 500) { $context.Detail.Substring(0, 500) + '...' } else { $context.Detail }

            $retry = if ($Policy.ShouldRetry) {
                # Only the last object is the verdict. A scriptblock that incidentally writes to
                # the output stream would otherwise cast to $true and retry against its own answer.
                [bool]((& $Policy.ShouldRetry $context) | Select-Object -Last 1)
            }
            else {
                Test-RetryableError -Policy $Policy -Context $context
            }

            if (-not $retry -or $attempt -ge $Policy.MaxAttempts) {
                # A policy that never retries leaves reporting to the caller's own error handling.
                if ($Policy.MaxAttempts -gt 1) {
                    Write-Warning "${Operation}: giving up after $attempt attempt(s) [$label] $logged"
                }
                throw
            }

            if ($null -ne $context.RetryAfterSeconds) {
                # Not clamped to MaxDelaySeconds: sleeping less than the server asked for reliably
                # earns another rejection, so an over-long request fails instead.
                if ($context.RetryAfterSeconds -gt $Policy.MaxRetryAfterSeconds) {
                    throw "${Operation}: server asked to retry after $([Math]::Round($context.RetryAfterSeconds)) s, above the '$($Policy.Name)' policy cap of $($Policy.MaxRetryAfterSeconds) s. $($_.Exception.Message)"
                }
                $delay = [Math]::Max(0.0, $context.RetryAfterSeconds)
            }
            else {
                $delay = Get-RetryBackoffDelay -Policy $Policy -Attempt $attempt
            }

            Write-Warning "${Operation}: attempt $attempt/$($Policy.MaxAttempts) failed [$label] $logged. Retrying in $([Math]::Round($delay, 1)) s."
            & $SleepAction $delay
        }
    }
}

function New-RetryContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Attempt,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $true)]
        $Policy
    )

    $exception = $ErrorRecord.Exception
    $statusCode = $null
    $retryAfter = $null

    if ($exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
        $statusCode = [int]$exception.Response.StatusCode

        $header = $exception.Response.Headers.RetryAfter
        if ($null -ne $header.Delta) {
            $retryAfter = $header.Delta.TotalSeconds
        }
        elseif ($null -ne $header.Date) {
            $retryAfter = ($header.Date - [DateTimeOffset]::UtcNow).TotalSeconds
        }
    }

    # The body lives in ErrorDetails; $exception.Response.Content has already been disposed.
    $raw = $ErrorRecord.ErrorDetails.Message
    $parsed = $null
    if ($raw) {
        try { $parsed = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
    }

    # The 500 comes from the Sauce Labs broker, upstream of Appium, so the body may be a
    # WebDriver error, an HTML page, plain text, or empty.
    $detail = if ($parsed.value.message) { [string]$parsed.value.message }
    elseif ($raw) { $raw }
    else { '' }

    # WebDriver appends Build/System/Driver info on its own lines, so keep one failure to one line.
    $detail = ($detail -replace '\s+', ' ').Trim()
    if (-not $detail) {
        $detail = '<empty body>'
    }

    return [pscustomobject]@{
        Attempt           = $Attempt
        Exception         = $exception
        StatusCode        = $statusCode
        Body              = $raw
        ParsedBody        = $parsed
        Detail            = $detail
        RetryAfterSeconds = $retryAfter
        Policy            = $Policy
    }
}

function Test-RetryableError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,

        [Parameter(Mandatory = $true)]
        $Context
    )

    # Classify by exception type, not by probing for a .Response property: a transport failure
    # has no such property, so probing would misread it as retryable.
    # HttpResponseException derives from HttpRequestException, so check it first.
    if ($Context.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
        return $Context.StatusCode -in $Policy.RetryStatusCodes
    }

    if ($Context.Exception -is [System.Net.Http.HttpRequestException]) {
        return $Policy.RetryTransport
    }

    return $false
}

function Get-RetryBackoffDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,

        [Parameter(Mandatory = $true)]
        [int]$Attempt
    )

    $delay = [Math]::Min($Policy.BaseDelaySeconds * [Math]::Pow(2, $Attempt - 1), $Policy.MaxDelaySeconds)

    # Jitter only ever shortens the delay, so MaxDelaySeconds still holds.
    if ($Policy.JitterFactor -gt 0) {
        $delay = $delay * (1 - (Get-Random -Minimum 0.0 -Maximum $Policy.JitterFactor))
    }

    return $delay
}
