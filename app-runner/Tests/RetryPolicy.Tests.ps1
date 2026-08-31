$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'RetryPolicy' -Tag 'Unit' {

    Context 'New-RetryPolicy' {
        It 'Tags the returned object so PSTypeName validation accepts it' {
            $policy = New-RetryPolicy -Name 'plain'

            $policy.PSObject.TypeNames[0] | Should -Be 'SentryAppRunner.RetryPolicy'
            $policy.Name | Should -Be 'plain'
        }

        It 'Falls back to the default policy values' {
            $policy = New-RetryPolicy -Name 'plain'
            $default = Get-RetryPolicy 'default'

            foreach ($property in $default.PSObject.Properties.Name | Where-Object { $_ -ne 'Name' }) {
                $policy.$property | Should -Be $default.$property
            }
        }

        It 'Rejects MaxAttempts below one' {
            { New-RetryPolicy -Name 'bad' -MaxAttempts 0 } | Should -Throw
        }

        It 'Rejects a negative BaseDelaySeconds' {
            { New-RetryPolicy -Name 'bad' -BaseDelaySeconds -1 } | Should -Throw
        }


        It 'Rejects a JitterFactor above one' {
            { New-RetryPolicy -Name 'bad' -JitterFactor 1.5 } | Should -Throw
        }

        It 'Rejects a MaxDelaySeconds below BaseDelaySeconds' {
            { New-RetryPolicy -Name 'bad' -BaseDelaySeconds 10 -MaxDelaySeconds 5 } | Should -Throw '*must not be below BaseDelaySeconds*'
        }

        It 'Rejects an untagged object as -BasedOn' {
            { New-RetryPolicy -Name 'bad' -BasedOn ([pscustomobject]@{ MaxAttempts = 3 }) } | Should -Throw
        }

        It 'Copies every unspecified field from -BasedOn and overrides the rest' {
            $base = New-RetryPolicy -Name 'base' -MaxAttempts 4 -BaseDelaySeconds 7.0 -RetryStatusCodes @(418) -RetryTransport $false
            $derived = New-RetryPolicy -Name 'derived' -BasedOn $base -MaxAttempts 9

            $derived.Name | Should -Be 'derived'
            $derived.MaxAttempts | Should -Be 9
            $derived.BaseDelaySeconds | Should -Be 7.0
            $derived.RetryStatusCodes | Should -Be @(418)
            $derived.RetryTransport | Should -BeFalse
        }

        It 'Carries a ShouldRetry scriptblock through -BasedOn' {
            $base = New-RetryPolicy -Name 'base' -ShouldRetry { param($Context) $Context.Attempt -lt 2 }
            $derived = New-RetryPolicy -Name 'derived' -BasedOn $base

            $derived.ShouldRetry | Should -Not -BeNullOrEmpty
            (& $derived.ShouldRetry ([pscustomobject]@{ Attempt = 1 })) | Should -BeTrue
        }
    }

    Context 'Registry' {
        It 'Round-trips a registered policy' {
            Register-RetryPolicy -Name 'round-trip' -Policy (New-RetryPolicy -Name 'round-trip' -MaxAttempts 42)

            (Get-RetryPolicy 'round-trip').MaxAttempts | Should -Be 42
        }

        It 'Rejects an untagged object as -Policy' {
            { Register-RetryPolicy -Name 'bogus' -Policy ([pscustomobject]@{ Name = 'bogus' }) } | Should -Throw
        }

        It 'Throws listing the known names on an unknown name' {
            { Get-RetryPolicy 'nope' } | Should -Throw "*Unknown retry policy 'nope'. Known: *session*"
        }

        It 'Lets a registration override a built-in' {
            $original = Get-RetryPolicy 'default'
            try {
                Register-RetryPolicy -Name 'default' -Policy (New-RetryPolicy -Name 'default' -BasedOn $original -MaxAttempts 99)

                (Get-RetryPolicy 'default').MaxAttempts | Should -Be 99
            }
            finally {
                Register-RetryPolicy -Name 'default' -Policy $original
            }
        }

        It 'Registers every built-in policy' {
            foreach ($name in 'default', 'session', 'upload', 'launch', 'quick', 'none') {
                (Get-RetryPolicy $name).Name | Should -Be $name
            }
        }

        It 'Never retries under the none policy' {
            (Get-RetryPolicy 'none').MaxAttempts | Should -Be 1
        }

        It 'Never retries a transport failure for session or launch' {
            (Get-RetryPolicy 'session').RetryTransport | Should -BeFalse
            (Get-RetryPolicy 'launch').RetryTransport | Should -BeFalse
        }
    }
}
