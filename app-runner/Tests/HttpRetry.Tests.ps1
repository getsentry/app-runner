$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Dot-source the retry internals for direct testing
    . "$PSScriptRoot\..\Private\RetryPolicy.ps1"
    . "$PSScriptRoot\..\Private\HttpRetry.ps1"

    function New-HttpErrorRecord {
        param(
            [int]$StatusCode,
            [string]$RetryAfter,
            [string]$Body = '{}'
        )

        # ToObject, not a cast: PowerShell rejects status codes with no named enum member.
        $response = [System.Net.Http.HttpResponseMessage]::new([Enum]::ToObject([System.Net.HttpStatusCode], $StatusCode))
        $response.Content = [System.Net.Http.StringContent]::new($Body, [Text.Encoding]::UTF8, 'application/json')
        if ($RetryAfter) {
            $null = $response.Headers.TryAddWithoutValidation('Retry-After', $RetryAfter)
        }

        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new(
            "Response status code does not indicate success: $StatusCode ($($response.ReasonPhrase)).", $response)
        $record = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body)
        return $record
    }

    function New-TransportErrorRecord {
        $exception = [System.Net.Http.HttpRequestException]::new(
            'Connection refused', [System.Net.Sockets.SocketException]::new(111))
        $record = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($exception.Message)
        return $record
    }
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-HttpWithRetry' -Tag 'Unit' {

    Context 'Attempt loop' {
        It 'Returns the result without sleeping when the first attempt succeeds' {
            $slept = [System.Collections.Generic.List[double]]::new()

            $result = Invoke-HttpWithRetry -Operation 'GET /ok' -Policy (Get-RetryPolicy 'default') `
                -SleepAction { param($Seconds) $slept.Add($Seconds) } -ScriptBlock { 'ok' }

            $result | Should -Be 'ok'
            $slept.Count | Should -Be 0
        }

        It 'Returns the result of a later attempt' {
            $script:attempts = 0

            $result = Invoke-HttpWithRetry -Operation 'POST /session' -Policy (Get-RetryPolicy 'default') `
                -SleepAction {} -ScriptBlock {
                $script:attempts++
                if ($script:attempts -lt 3) { throw (New-HttpErrorRecord -StatusCode 500) }
                'created'
            }

            $result | Should -Be 'created'
            $script:attempts | Should -Be 3
        }

        It 'Rethrows the original exception once the budget is spent' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0
            $captured = $null

            try {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 503)
                }
            }
            catch {
                $captured = $_
            }

            $script:attempts | Should -Be 3
            $captured.Exception | Should -BeOfType [Microsoft.PowerShell.Commands.HttpResponseException]
            $captured.Exception.Message | Should -BeLike '*503*'
        }
    }

    Context 'Declarative classification' {
        It 'Fails in one attempt on a status the policy does not retry' {
            $script:attempts = 0

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy (Get-RetryPolicy 'default') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 401)
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }

        It 'Retries a transport failure when RetryTransport is set' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0 -RetryTransport $true

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-TransportErrorRecord)
                }
            } | Should -Throw

            $script:attempts | Should -Be 3
        }

        It 'Fails in one attempt on a transport failure when RetryTransport is clear' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0 -RetryTransport $false

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-TransportErrorRecord)
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }

        It 'Never retries a non-HTTP exception' {
            $script:attempts = 0

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy (Get-RetryPolicy 'default') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw [System.InvalidOperationException]::new('bad argument')
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }
    }

    Context 'Delays' {
        It 'Sleeps for the Retry-After delta rather than the backoff' {
            $slept = [System.Collections.Generic.List[double]]::new()
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 2 -BaseDelaySeconds 30 -MaxDelaySeconds 30 -JitterFactor 0

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy `
                    -SleepAction { param($Seconds) $slept.Add($Seconds) } -ScriptBlock {
                    throw (New-HttpErrorRecord -StatusCode 429 -RetryAfter '5')
                }
            } | Should -Throw

            $slept | Should -Be @(5)
        }

        It 'Sleeps for a Retry-After given as an HTTP date' {
            $slept = [System.Collections.Generic.List[double]]::new()
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 2 -BaseDelaySeconds 30 -MaxDelaySeconds 30 -JitterFactor 0
            $when = [DateTimeOffset]::UtcNow.AddSeconds(7).ToString('R')

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy `
                    -SleepAction { param($Seconds) $slept.Add($Seconds) } -ScriptBlock {
                    throw (New-HttpErrorRecord -StatusCode 503 -RetryAfter $when)
                }
            } | Should -Throw

            $slept[0] | Should -BeGreaterThan 5
            $slept[0] | Should -BeLessOrEqual 8
        }

        It 'Fails fast when Retry-After exceeds the policy cap' {
            $script:attempts = 0
            $slept = [System.Collections.Generic.List[double]]::new()
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 5 -MaxRetryAfterSeconds 10 -JitterFactor 0

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy `
                    -SleepAction { param($Seconds) $slept.Add($Seconds) } -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 429 -RetryAfter '60')
                }
            } | Should -Throw '*above*policy cap*'

            $script:attempts | Should -Be 1
            $slept.Count | Should -Be 0
        }

        It 'Backs off exponentially up to MaxDelaySeconds' {
            $slept = [System.Collections.Generic.List[double]]::new()
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 5 -BaseDelaySeconds 10 -MaxDelaySeconds 25 -JitterFactor 0

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy `
                    -SleepAction { param($Seconds) $slept.Add($Seconds) } -ScriptBlock {
                    throw (New-HttpErrorRecord -StatusCode 500)
                }
            } | Should -Throw

            $slept | Should -Be @(10, 20, 25, 25)
        }

        It 'Keeps a jittered delay within JitterFactor of the backoff' {
            $slept = [System.Collections.Generic.List[double]]::new()
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 8 -BaseDelaySeconds 10 -MaxDelaySeconds 10 -JitterFactor 0.5

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy `
                    -SleepAction { param($Seconds) $slept.Add($Seconds) } -ScriptBlock {
                    throw (New-HttpErrorRecord -StatusCode 500)
                }
            } | Should -Throw

            $slept.Count | Should -Be 7
            foreach ($delay in $slept) {
                $delay | Should -BeGreaterOrEqual 5
                $delay | Should -BeLessOrEqual 10
            }
        }
    }

    Context 'ShouldRetry override' {
        It 'Retries a status outside RetryStatusCodes when ShouldRetry says so' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0 `
                -RetryStatusCodes @(500) -ShouldRetry { param($Context) $Context.StatusCode -eq 418 }

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 418)
                }
            } | Should -Throw

            $script:attempts | Should -Be 3
        }

        It 'Skips a status inside RetryStatusCodes when ShouldRetry says not to' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0 `
                -RetryStatusCodes @(500) -ShouldRetry { param($Context) $Context.StatusCode -eq 418 }

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 500)
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }

        It 'Passes a populated context to ShouldRetry' {
            $seen = [System.Collections.Generic.List[object]]::new()
            $body = '{"value":{"error":"session not created","message":"No device matching the query was found"}}'
            $policy = New-RetryPolicy -Name 'inspector' -MaxAttempts 3 -ShouldRetry {
                param($Context)
                $seen.Add($Context)
                return $false
            }

            {
                Invoke-HttpWithRetry -Operation 'POST /session' -Policy $policy -SleepAction {} -ScriptBlock {
                    throw (New-HttpErrorRecord -StatusCode 500 -Body $body)
                }
            } | Should -Throw

            $seen.Count | Should -Be 1
            $seen[0].Attempt | Should -Be 1
            $seen[0].StatusCode | Should -Be 500
            $seen[0].Body | Should -Be $body
            $seen[0].ParsedBody.value.error | Should -Be 'session not created'
            $seen[0].Detail | Should -Be 'No device matching the query was found'
            $seen[0].Exception | Should -BeOfType [Microsoft.PowerShell.Commands.HttpResponseException]
            $seen[0].Policy.Name | Should -Be 'inspector'
        }

        It 'Reaches the helper through the registry' {
            $script:attempts = 0
            Register-RetryPolicy -Name 'teapot' -Policy (New-RetryPolicy -Name 'teapot' -MaxAttempts 4 `
                    -BaseDelaySeconds 0 -JitterFactor 0 -ShouldRetry { param($Context) $Context.StatusCode -eq 418 })

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy (Get-RetryPolicy 'teapot') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 418)
                }
            } | Should -Throw

            $script:attempts | Should -Be 4
        }

        It 'Takes the last object when ShouldRetry also writes to the output stream' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'noisy' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0 -ShouldRetry {
                param($Context)
                $stray = [System.Collections.ArrayList]::new()
                $stray.Add($Context)
                return $false
            }

            {
                Invoke-HttpWithRetry -Operation 'GET /x' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 500)
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }
    }

    Context 'Response body unpacking' {
        It 'Extracts the WebDriver message' {
            $record = New-HttpErrorRecord -StatusCode 500 -Body '{"value":{"error":"session not created","message":"No device matching the query was found"}}'

            $context = New-RetryContext -Attempt 1 -ErrorRecord $record -Policy (Get-RetryPolicy 'default')

            $context.Detail | Should -Be 'No device matching the query was found'
        }

        It 'Collapses the whitespace of an HTML error page' {
            # Invoke-WebRequest strips the markup before it reaches ErrorDetails, leaving the
            # page's text and its original line breaks.
            $record = New-HttpErrorRecord -StatusCode 500 -Body "`n  500`n  Gateway Error`n"

            $context = New-RetryContext -Attempt 1 -ErrorRecord $record -Policy (Get-RetryPolicy 'default')

            $context.Detail | Should -Be '500 Gateway Error'
        }

        It 'Truncates a body too long to log' {
            $record = New-HttpErrorRecord -StatusCode 500 -Body ('x' * 900)

            $context = New-RetryContext -Attempt 1 -ErrorRecord $record -Policy (Get-RetryPolicy 'default')

            $context.Detail | Should -Be (('x' * 500) + '...')
            $context.Body.Length | Should -Be 900
        }

        It 'Reports an empty body' {
            $record = New-HttpErrorRecord -StatusCode 500 -Body ''

            $context = New-RetryContext -Attempt 1 -ErrorRecord $record -Policy (Get-RetryPolicy 'default')

            $context.Detail | Should -Be '<empty body>'
        }

        It 'Falls back to plain text' {
            $record = New-HttpErrorRecord -StatusCode 500 -Body 'not json at all'

            $context = New-RetryContext -Attempt 1 -ErrorRecord $record -Policy (Get-RetryPolicy 'default')

            $context.Detail | Should -Be 'not json at all'
        }

        It 'Falls back to the raw body when the JSON is not WebDriver-shaped' {
            $record = New-HttpErrorRecord -StatusCode 500 -Body '{"error":"nope"}'

            $context = New-RetryContext -Attempt 1 -ErrorRecord $record -Policy (Get-RetryPolicy 'default')

            $context.Detail | Should -Be '{"error":"nope"}'
        }

        It 'Reports a transport failure as carrying no status' {
            $context = New-RetryContext -Attempt 1 -ErrorRecord (New-TransportErrorRecord) -Policy (Get-RetryPolicy 'default')

            $context.StatusCode | Should -BeNullOrEmpty
            $context.RetryAfterSeconds | Should -BeNullOrEmpty
            $context.Detail | Should -Be 'Connection refused'
        }
    }

    Context 'Session policy classification' {
        It 'Retries a session failure whose message is not recognised' {
            $script:attempts = 0

            {
                Invoke-HttpWithRetry -Operation 'POST /session' -Policy (Get-RetryPolicy 'session') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 500 -Body '{"value":{"message":"something nobody has seen yet"}}')
                }
            } | Should -Throw

            $script:attempts | Should -Be 5
        }

        It 'Does not retry a device query that matches nothing' {
            $script:attempts = 0

            {
                Invoke-HttpWithRetry -Operation 'POST /session' -Policy (Get-RetryPolicy 'session') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 500 -Body '{"value":{"message":"No device matching the query was found"}}')
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }

        It 'Does not retry a transport failure' {
            $script:attempts = 0

            {
                Invoke-HttpWithRetry -Operation 'POST /session' -Policy (Get-RetryPolicy 'session') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-TransportErrorRecord)
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }

        It 'Honours RetryTransport when a derived policy turns it back on' {
            $script:attempts = 0
            $policy = New-RetryPolicy -Name 'derived' -BasedOn (Get-RetryPolicy 'session') `
                -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0 -RetryTransport $true

            {
                Invoke-HttpWithRetry -Operation 'POST /session' -Policy $policy -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-TransportErrorRecord)
                }
            } | Should -Throw

            $script:attempts | Should -Be 3
        }

        It 'Does not retry an authentication failure' {
            $script:attempts = 0

            {
                Invoke-HttpWithRetry -Operation 'POST /session' -Policy (Get-RetryPolicy 'session') -SleepAction {} -ScriptBlock {
                    $script:attempts++
                    throw (New-HttpErrorRecord -StatusCode 401 -Body 'Unauthorized')
                }
            } | Should -Throw

            $script:attempts | Should -Be 1
        }
    }
}
