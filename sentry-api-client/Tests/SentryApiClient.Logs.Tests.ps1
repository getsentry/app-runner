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

    Context 'Get-SentryLogs with Mocked HTTP' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                switch -Regex ($Uri) {
                    'dataset=ourlogs' {
                        return @{ Content = ($Script:LogsFixtures.logs_list | ConvertTo-Json -Depth 10) }
                    }
                    default {
                        throw "Unexpected URI: $Uri"
                    }
                }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should retrieve logs successfully' {
            $result = Get-SentryLogs

            $result | Should -Not -BeNullOrEmpty
            $result.data | Should -HaveCount 4
        }

        It 'Should construct correct API URL with dataset parameter' {
            Get-SentryLogs -Query 'test.id:test-001'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'dataset=ourlogs'
            }
        }

        It 'Should use organization-level endpoint' {
            Get-SentryLogs

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'organizations/test-org/events/'
            }
        }

        It 'Should include query parameter when provided' {
            Get-SentryLogs -Query 'test.id:integration-test-001'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=test\.id%3Aintegration-test-001'
            }
        }

        It 'Should include statsPeriod parameter' {
            Get-SentryLogs -StatsPeriod '7d'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'statsPeriod=7d'
            }
        }

        It 'Should default statsPeriod to 24h' {
            Get-SentryLogs

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'statsPeriod=24h'
            }
        }

        It 'Should include per_page parameter for limit' {
            Get-SentryLogs -Limit 50

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'per_page=50'
            }
        }

        It 'Should default limit to 100' {
            Get-SentryLogs

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'per_page=100'
            }
        }

        It 'Should include cursor parameter when provided' {
            Get-SentryLogs -Cursor 'next123abc'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'cursor=next123abc'
            }
        }

        It 'Should include field parameters for default fields' {
            Get-SentryLogs

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=timestamp' -and
                $Uri -match 'field=message' -and
                $Uri -match 'field=sentry\.severity'
            }
        }

        It 'Should include custom fields when specified' {
            Get-SentryLogs -Fields @('timestamp', 'message', 'custom.field')

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'field=custom\.field'
            }
        }

        It 'Should include trace filter when TraceId is provided' {
            Get-SentryLogs -TraceId 'abc123def456'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=trace%3Aabc123def456'
            }
        }

        It 'Should combine Query and TraceId parameters' {
            Get-SentryLogs -Query 'test.id:test-001' -TraceId 'abc123'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=test\.id%3Atest-001.*trace%3Aabc123' -or
                $Uri -match 'query=.*test\.id.*trace'
            }
        }
    }

    Context 'Get-SentryLogsByAttribute' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                if ($Uri -match 'dataset=ourlogs') {
                    return @{ Content = ($Script:LogsFixtures.logs_list | ConvertTo-Json -Depth 10) }
                }
                throw "Unexpected URI: $Uri"
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should query by attribute name and value' {
            $result = Get-SentryLogsByAttribute -AttributeName 'test.id' -AttributeValue 'integration-test-001'

            $result | Should -Not -BeNullOrEmpty
            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=test\.id%3Aintegration-test-001'
            }
        }

        It 'Should pass Limit parameter to Get-SentryLogs' {
            Get-SentryLogsByAttribute -AttributeName 'test.id' -AttributeValue 'test-001' -Limit 25

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'per_page=25'
            }
        }

        It 'Should pass StatsPeriod parameter to Get-SentryLogs' {
            Get-SentryLogsByAttribute -AttributeName 'test.id' -AttributeValue 'test-001' -StatsPeriod '7d'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'statsPeriod=7d'
            }
        }

        It 'Should handle attribute names with dots' {
            Get-SentryLogsByAttribute -AttributeName 'service.name' -AttributeValue 'auth-service'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=service\.name%3Aauth-service'
            }
        }

        It 'Should handle attribute values with special characters' {
            Get-SentryLogsByAttribute -AttributeName 'user.email' -AttributeValue 'test@example.com'

            Assert-MockCalled -ModuleName SentryApiClient Invoke-WebRequest -ParameterFilter {
                $Uri -match 'query=user\.email%3Atest%40example\.com'
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

        It 'Should handle empty response' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:LogsFixtures.logs_empty | ConvertTo-Json -Depth 10) }
            }

            $result = Get-SentryLogs
            $result.data | Should -HaveCount 0
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

    Context 'Response Data Structure' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = ($Script:LogsFixtures.logs_list | ConvertTo-Json -Depth 10) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }

        It 'Should return logs with expected fields' {
            $result = Get-SentryLogs

            $firstLog = $result.data[0]
            $firstLog.timestamp | Should -Not -BeNullOrEmpty
            $firstLog.message | Should -Not -BeNullOrEmpty
            $firstLog.'sentry.severity' | Should -Not -BeNullOrEmpty
            $firstLog.'sentry.item_id' | Should -Not -BeNullOrEmpty
        }

        It 'Should return logs with custom attributes' {
            $result = Get-SentryLogs

            $firstLog = $result.data[0]
            $firstLog.'test.id' | Should -Be 'integration-test-001'
        }

        It 'Should include meta information in response' {
            $result = Get-SentryLogs

            $result.meta | Should -Not -BeNullOrEmpty
            $result.meta.fields | Should -Not -BeNullOrEmpty
        }
    }
}
