BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force

    # Load test fixtures
    $FixturesPath = Join-Path $PSScriptRoot 'Fixtures' 'SentryLogsResponses.json'
    $Script:LogsFixtures = Get-Content $FixturesPath | ConvertFrom-Json -AsHashtable
}

AfterAll {
    Remove-Module SentryApiClient -Force
}

Describe 'SentryApiClient Logs Functions' {
    Context 'Module Export' {
        It 'Should export Get-SentryLogs function' {
            Get-Command Get-SentryLogs -Module SentryApiClient | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-SentryLogsByAttribute function' {
            Get-Command Get-SentryLogsByAttribute -Module SentryApiClient | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-SentryLogs' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:LogsFixtures.logs_list | ConvertTo-Json -Depth 10) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should retrieve logs from ourlogs dataset' {
            $result = Get-SentryLogs -Query 'test_id:test-001'

            $result | Should -Not -BeNullOrEmpty
            $result.data | Should -HaveCount 2

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'dataset=ourlogs' -and
                $Uri -match 'organizations/test-org/events/'
            }
        }
    }

    Context 'Get-SentryLogsByAttribute' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:LogsFixtures.logs_list | ConvertTo-Json -Depth 10) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should query by attribute and include it in response fields' {
            $result = Get-SentryLogsByAttribute -AttributeName 'test_id' -AttributeValue 'integration-test-001'

            $result | Should -Not -BeNullOrEmpty
            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=test_id%3Aintegration-test-001' -and
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

            { Get-SentryLogs } | Should -Throw '*Sentry API request*failed*'
        }
    }

    Context 'Connection Validation' {
        BeforeEach {
            Disconnect-SentryApi
        }

        It 'Should throw when organization is not configured' {
            { Get-SentryLogs } | Should -Throw '*Organization not configured*'
        }
    }
}
