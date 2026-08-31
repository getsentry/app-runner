$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Load the provider and its dependencies into the test session because the module does not export the class.
    . "$PSScriptRoot\..\Private\RetryPolicy.ps1"
    . "$PSScriptRoot\..\Private\HttpRetry.ps1"
    . "$PSScriptRoot\..\Private\DeviceProviders\SauceLabsProvider.ps1"

    function New-TestProvider {
        # Only fill in credentials that are missing, so a CI run carrying real SAUCE_* secrets is
        # left untouched. Invoke-WebRequest is mocked, so no request leaves the machine either way.
        $savedUsername = $env:SAUCE_USERNAME
        $savedAccessKey = $env:SAUCE_ACCESS_KEY
        $savedRegion = $env:SAUCE_REGION
        try {
            if (-not $env:SAUCE_USERNAME) { $env:SAUCE_USERNAME = 'test-user' }
            if (-not $env:SAUCE_ACCESS_KEY) { $env:SAUCE_ACCESS_KEY = 'test-key' }
            if (-not $env:SAUCE_REGION) { $env:SAUCE_REGION = 'us-west-1' }
            return [SauceLabsProvider]::new('Android')
        }
        finally {
            $env:SAUCE_USERNAME = $savedUsername
            $env:SAUCE_ACCESS_KEY = $savedAccessKey
            $env:SAUCE_REGION = $savedRegion
        }
    }

    function New-HttpErrorRecord {
        param([int]$StatusCode)

        $response = [System.Net.Http.HttpResponseMessage]::new([Enum]::ToObject([System.Net.HttpStatusCode], $StatusCode))
        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new(
            "Response status code does not indicate success: $StatusCode ($($response.ReasonPhrase)).", $response)
        return [System.Management.Automation.ErrorRecord]::new(
            $exception, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    }
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'SauceLabsProvider retry wiring' -Tag 'Unit' {

    Context 'InvokeSauceLabsApi' {
        It 'Retries a failing request and returns the eventual success' {
            $provider = New-TestProvider
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0
            $script:calls = 0
            Mock Invoke-WebRequest {
                $script:calls++
                if ($script:calls -lt 3) { throw (New-HttpErrorRecord -StatusCode 500) }
                return [pscustomobject]@{ Content = '{"value":{"sessionId":"abc"}}' }
            }

            $result = $provider.InvokeSauceLabsApi('POST', 'https://ondemand.example/wd/hub/session', @{ x = 1 }, $false, $null, $policy)

            $result.value.sessionId | Should -Be 'abc'
            Should -Invoke Invoke-WebRequest -Times 3 -Exactly
        }

        It 'Preserves the existing error message once retries are exhausted' {
            $provider = New-TestProvider
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 2 -BaseDelaySeconds 0 -JitterFactor 0
            Mock Invoke-WebRequest { throw (New-HttpErrorRecord -StatusCode 503) }

            {
                $provider.InvokeSauceLabsApi('GET', 'https://ondemand.example/wd/hub/session/x', $null, $false, $null, $policy)
            } | Should -Throw '*SauceLabs API request (GET https://ondemand.example/wd/hub/session/x) failed:*503*'

            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        }

        It 'Retries a multipart upload with a usable form on every attempt' {
            $provider = New-TestProvider
            $policy = New-RetryPolicy -Name 'test' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0
            $package = New-TemporaryFile
            Set-Content -Path $package -Value 'apk-bytes'
            $script:forms = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-WebRequest {
                $script:forms.Add($Form)
                if ($script:forms.Count -lt 3) { throw (New-HttpErrorRecord -StatusCode 503) }
                return [pscustomobject]@{ Content = '{"item":{"id":"storage-id"}}' }
            }

            try {
                $result = $provider.InvokeSauceLabsApi('POST', 'https://api.example/v1/storage/upload', $null, $true, $package.FullName, $policy)

                $result.item.id | Should -Be 'storage-id'
                $script:forms.Count | Should -Be 3
                foreach ($form in $script:forms) {
                    $form.name | Should -Be $package.Name
                    $form.payload.FullName | Should -Be $package.FullName
                    $form.payload.Exists | Should -BeTrue
                }
            }
            finally {
                Remove-Item $package -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Does not retry an authentication failure' {
            $provider = New-TestProvider
            Mock Invoke-WebRequest { throw (New-HttpErrorRecord -StatusCode 401) }

            {
                $provider.InvokeSauceLabsApi('GET', 'https://ondemand.example/x', $null, $false, $null, (Get-RetryPolicy 'sauce-session'))
            } | Should -Throw

            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }

        It 'Rejects a policy that did not come from New-RetryPolicy' {
            $provider = New-TestProvider

            {
                $provider.InvokeSauceLabsApi('GET', 'https://ondemand.example/x', $null, $false, $null, [pscustomobject]@{ MaxAttempts = 3 })
            } | Should -Throw '*must come from New-RetryPolicy or Get-RetryPolicy*'
        }
    }

    Context 'Call site policies' {
        It 'Does not retry the TestConnection health probe' {
            $provider = New-TestProvider
            $provider.SessionId = 'fake-session'
            Mock Invoke-WebRequest { throw (New-HttpErrorRecord -StatusCode 500) }

            $provider.TestConnection() | Should -BeFalse
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }

        It 'Resolves its policy from the registry at the call' {
            $provider = New-TestProvider
            $provider.SessionId = 'fake-session'
            Mock Invoke-WebRequest { throw (New-HttpErrorRecord -StatusCode 500) }
            $original = Get-RetryPolicy 'none'
            try {
                Register-RetryPolicy -Name 'none' -Policy (New-RetryPolicy -Name 'none' -MaxAttempts 3 -BaseDelaySeconds 0 -JitterFactor 0)

                $provider.TestConnection() | Should -BeFalse

                Should -Invoke Invoke-WebRequest -Times 3 -Exactly
            }
            finally {
                Register-RetryPolicy -Name 'none' -Policy $original
            }
        }

        It 'Names a registered policy at every call site' {
            $source = Get-Content "$PSScriptRoot\..\Private\DeviceProviders\SauceLabsProvider.ps1" -Raw
            $calls = [regex]::Matches($source, '\$this\.InvokeSauceLabsApi\(')
            $resolved = [regex]::Matches($source, "InvokeSauceLabsApi\([^\r\n]*Get-RetryPolicy '(?<name>[\w-]+)'")

            $resolved.Count | Should -Be $calls.Count
            foreach ($call in $resolved) {
                { Get-RetryPolicy $call.Groups['name'].Value } | Should -Not -Throw
            }
        }
    }

    Context 'Method signature' {
        It 'Declares exactly one InvokeSauceLabsApi taking six arguments' {
            # A class method parses a default value and then ignores it, so an inert default or a
            # second overload would silently let a new call site skip stating its intent.
            $overloads = [SauceLabsProvider].GetMethods() | Where-Object { $_.Name -eq 'InvokeSauceLabsApi' }

            $overloads.Count | Should -Be 1
            $overloads[0].GetParameters().Count | Should -Be 6
            $overloads[0].GetParameters()[5].Name | Should -Be 'RetryPolicy'
        }
    }
}
