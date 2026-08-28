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
                    Write-Host "${Operation}: giving up after $attempt attempt(s) [$label] $($context.Detail)"
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

            Write-Host "${Operation}: attempt $attempt/$($Policy.MaxAttempts) failed [$label] $($context.Detail). Retrying in $([Math]::Round($delay, 1)) s."
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

    # The body may be a WebDriver error, a gateway HTML page, plain text or empty, because the
    # 500 comes from the Sauce Labs broker upstream of Appium.
    $collapsed = if ($raw) { ($raw -replace '\s+', ' ').Trim() } else { '' }
    $detail = if ($parsed.value.message) { [string]$parsed.value.message }
    elseif ($collapsed) { $collapsed }
    else { '<empty body>' }

    # A gateway page runs to kilobytes and would flood the log once per attempt. The whole body
    # stays available as Body for a policy that needs to match on more than the opening line.
    if ($detail.Length -gt 500) {
        $detail = $detail.Substring(0, 500) + '...'
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

    # Classify by exception type, never by probing for a .Response property: on a transport
    # failure it does not exist at all, and under the module's Stop preference an incidental
    # error would then masquerade as a retryable fault. HttpResponseException derives from
    # HttpRequestException, so it has to be tested first.
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
