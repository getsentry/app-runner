BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force

    # Load test fixtures
    $FixturesPath = Join-Path $PSScriptRoot 'Fixtures' 'SentryMetricsResponses.json'
    $Script:MetricsFixtures = Get-Content $FixturesPath | ConvertFrom-Json -AsHashtable
}

AfterAll {
    Remove-Module SentryApiClient -Force
}

Describe 'SentryApiClient Metrics Functions' {
    Context 'Module Export' {
        It 'Should export Get-SentryMetrics function' {
            Get-Command Get-SentryMetrics -Module SentryApiClient | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-SentryMetricsByAttribute function' {
            Get-Command Get-SentryMetricsByAttribute -Module SentryApiClient | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-SentryMetrics' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:MetricsFixtures.metrics_list | ConvertTo-Json -Depth 10) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should retrieve metrics from tracemetrics dataset' {
            $result = Get-SentryMetrics -Query 'metric.name:test.integration.counter'

            $result | Should -Not -BeNullOrEmpty
            $result.data | Should -HaveCount 2

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'dataset=tracemetrics' -and
                $Uri -match 'organizations/test-org/events/'
            }
        }

        It 'Should include default fields when none specified' {
            Get-SentryMetrics -Query 'metric.name:test.integration.counter'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=id' -and
                $Uri -match 'field=metric\.name' -and
                $Uri -match 'field=metric\.type' -and
                $Uri -match 'field=value' -and
                $Uri -match 'field=timestamp'
            }
        }

        It 'Should use custom fields when specified' {
            Get-SentryMetrics -Query 'metric.name:test.counter' -Fields @('id', 'value', 'custom_field')

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=id' -and
                $Uri -match 'field=value' -and
                $Uri -match 'field=custom_field'
            }
        }

        It 'Should pass stats period parameter' {
            Get-SentryMetrics -Query 'metric.name:test.counter' -StatsPeriod '7d'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'statsPeriod=7d'
            }
        }
    }

    Context 'Get-SentryMetricsByAttribute' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:MetricsFixtures.metrics_list | ConvertTo-Json -Depth 10) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should query by metric name and attribute' {
            $result = Get-SentryMetricsByAttribute -MetricName 'test.integration.counter' -AttributeName 'test_id' -AttributeValue 'metrics-test-001'

            $result | Should -Not -BeNullOrEmpty
            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=metric\.name%3Atest\.integration\.counter' -and
                $Uri -match 'test_id%3Ametrics-test-001'
            }
        }

        It 'Should include the filter attribute in response fields' {
            Get-SentryMetricsByAttribute -MetricName 'test.counter' -AttributeName 'test_id' -AttributeValue 'abc-123'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=test_id'
            }
        }

        It 'Should merge additional fields with defaults' {
            Get-SentryMetricsByAttribute -MetricName 'test.counter' -AttributeName 'test_id' -AttributeValue 'abc-123' -Fields @('extra_field')

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=extra_field' -and
                $Uri -match 'field=metric\.name' -and
                $Uri -match 'field=test_id'
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

            { Get-SentryMetrics } | Should -Throw '*Sentry API request*failed*'
        }
    }

    Context 'Connection Validation' {
        BeforeEach {
            Disconnect-SentryApi
        }

        It 'Should throw when organization is not configured' {
            { Get-SentryMetrics } | Should -Throw '*Organization not configured*'
        }
    }
}
