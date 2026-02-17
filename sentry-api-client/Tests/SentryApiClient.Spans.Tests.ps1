BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force

    # Load test fixtures
    $FixturesPath = Join-Path $PSScriptRoot 'Fixtures' 'SentrySpansResponses.json'
    $Script:SpansFixtures = Get-Content $FixturesPath | ConvertFrom-Json -AsHashtable
}

AfterAll {
    Remove-Module SentryApiClient -Force
}

Describe 'SentryApiClient Spans Functions' {
    Context 'Module Export' {
        It 'Should export Get-SentrySpans function' {
            Get-Command Get-SentrySpans -Module SentryApiClient | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-SentrySpans' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:SpansFixtures.spans_list | ConvertTo-Json -Depth 10) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should retrieve spans from spans dataset' {
            $result = Get-SentrySpans -TraceId '140df6870c0f406faf87cff1f0d9e280'

            $result | Should -Not -BeNullOrEmpty
            $result.data | Should -HaveCount 2

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'dataset=spans' -and
                $Uri -match 'organizations/test-org/events/'
            }
        }

        It 'Should include default fields when none specified' {
            Get-SentrySpans -TraceId '140df6870c0f406faf87cff1f0d9e280'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=id' -and
                $Uri -match 'field=trace' -and
                $Uri -match 'field=span\.op' -and
                $Uri -match 'field=span\.description' -and
                $Uri -match 'field=span\.duration' -and
                $Uri -match 'field=is_transaction' -and
                $Uri -match 'field=timestamp' -and
                $Uri -match 'field=transaction\.event_id'
            }
        }

        It 'Should use custom fields when specified' {
            Get-SentrySpans -Query 'span.op:http.client' -Fields @('id', 'trace', 'custom_field')

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=id' -and
                $Uri -match 'field=trace' -and
                $Uri -match 'field=custom_field'
            }
        }

        It 'Should append trace filter to query' {
            Get-SentrySpans -TraceId '140df6870c0f406faf87cff1f0d9e280'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=trace%3A140df6870c0f406faf87cff1f0d9e280'
            }
        }

        It 'Should combine query and trace ID' {
            Get-SentrySpans -Query 'is_transaction:true' -TraceId '140df6870c0f406faf87cff1f0d9e280'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=is_transaction%3Atrue' -and
                $Uri -match 'trace%3A140df6870c0f406faf87cff1f0d9e280'
            }
        }

        It 'Should pass stats period parameter' {
            Get-SentrySpans -TraceId '140df6870c0f406faf87cff1f0d9e280' -StatsPeriod '7d'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'statsPeriod=7d'
            }
        }
    }

    Context 'Error Handling' {
        BeforeAll {
            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should handle API errors gracefully' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                throw [System.Net.WebException]::new('401 Unauthorized')
            }

            { Get-SentrySpans } | Should -Throw '*Sentry API request*failed*'
        }
    }

    Context 'Connection Validation' {
        BeforeEach {
            Disconnect-SentryApi
        }

        It 'Should throw when organization is not configured' {
            { Get-SentrySpans } | Should -Throw '*Organization not configured*'
        }
    }
}
