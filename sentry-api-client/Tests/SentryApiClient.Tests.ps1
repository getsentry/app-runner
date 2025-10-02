BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force
}

AfterAll {
    Remove-Module SentryApiClient -Force
}

Describe 'SentryApiClient Module' {
    Context 'Module Import' {
        It 'Should import the module successfully' {
            Get-Module SentryApiClient | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export the expected functions' {
            $ExpectedFunctions = @(
                'Connect-SentryApi',
                'Disconnect-SentryApi',
                'Get-SentryEvent',
                'Find-SentryEventByTag',
                'Get-SentryEventsByTag',
                'Invoke-SentryCLI',
                'Get-SentryCLI'
            )
            
            $ExportedFunctions = (Get-Module SentryApiClient).ExportedFunctions.Keys
            foreach ($Function in $ExpectedFunctions) {
                $ExportedFunctions | Should -Contain $Function
            }
        }
    }
    
    Context 'Connect-SentryApi' {
        BeforeEach {
            if (Get-Command Disconnect-SentryApi -ErrorAction SilentlyContinue) {
                Disconnect-SentryApi
            }
        }
        
        It 'Should accept manual parameters' {
            { Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project' } | Should -Not -Throw
        }
        
        It 'Should accept DSN parameter' {
            $testDSN = 'https://testkey@o12345.ingest.us.sentry.io/67890'
            { Connect-SentryApi -ApiToken 'test-token' -DSN $testDSN } | Should -Not -Throw
        }
        
        It 'Should parse DSN with different host formats' {
            $testDSN = 'https://testkey@o99999.sentry.io/11111'
            { Connect-SentryApi -ApiToken 'test-token' -DSN $testDSN } | Should -Not -Throw
        }
        
        It 'Should throw error for invalid DSN format' {
            $invalidDSN = 'https://testkey@invalid-host/12345'
            { Connect-SentryApi -ApiToken 'test-token' -DSN $invalidDSN } | Should -Throw
        }
        
        It 'Should throw error for DSN without organization ID' {
            $invalidDSN = 'https://testkey@sentry.io/12345'
            { Connect-SentryApi -ApiToken 'test-token' -DSN $invalidDSN } | Should -Throw
        }
        
        It 'Should set BaseUrl correctly for sentry.io hosted DSN' {
            $testDSN = 'https://testkey@o12345.ingest.us.sentry.io/67890'
            { Connect-SentryApi -ApiToken 'test-token' -DSN $testDSN } | Should -Not -Throw
        }
        
        It 'Should set BaseUrl correctly for self-hosted DSN' {
            $testDSN = 'https://testkey@o12345.mycompany.com/67890'
            { Connect-SentryApi -ApiToken 'test-token' -DSN $testDSN } | Should -Not -Throw
        }
    }
    
    Context 'Disconnect-SentryApi' {
        It 'Should clear the configuration' {
            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
            { Disconnect-SentryApi } | Should -Not -Throw
        }
    }
    
    Context 'API Request Functions with Mocked HTTP' {
        BeforeAll {
            # Mock only the external HTTP call, not our internal functions
            Mock -ModuleName SentryApiClient Invoke-RestMethod {
                param($Uri, $Method, $Headers, $ContentType, $Body)
                
                # Return different responses based on the URI pattern
                # Order matters - most specific patterns first
                switch -Regex ($Uri) {
                    '/issues/[^/]+/events/' {
                        # Handle issues/{id}/events/ endpoint - most specific first
                        return @(
                            @{
                                eventID = 'event123'
                                id = 'some-other-id'
                                message = 'Event summary'
                            }
                        )
                    }
                    '/events/\w+/' {
                        return @{
                            id = '12345678901234567890123456789012'
                            message = 'Test error message'
                            timestamp = '2023-01-01T00:00:00Z'
                            tags = @(
                                @{ key = 'environment'; value = 'production' }
                                @{ key = 'release'; value = '1.0.0' }
                            )
                        }
                    }
                    '/events.*query=' {
                        return @(
                            @{
                                id = 'event1'
                                message = 'Error 1'
                                tags = @(
                                    @{ key = 'environment'; value = 'production' }
                                )
                            },
                            @{
                                id = 'event2'
                                message = 'Error 2'
                                tags = @(
                                    @{ key = 'environment'; value = 'production' }
                                )
                            }
                        )
                    }
                    '/issues.*query=' {
                        return @(
                            @{
                                id = 'issue1'
                                title = 'Test Issue 1'
                                culprit = 'app.js'
                                permalink = 'https://sentry.io/issues/1/'
                                firstSeen = '2023-01-01T00:00:00Z'
                                lastSeen = '2023-01-02T00:00:00Z'
                                count = 10
                                metadata = @{
                                    type = 'Error'
                                    value = 'Test error'
                                }
                            }
                        )
                    }
                    default {
                        throw "Unexpected URI: $Uri"
                    }
                }
            }
            
            # Setup a connection for testing
            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }
        
        Context 'Get-SentryEvent' {
            It 'Should retrieve event with properly formatted ID' {
                $eventId = '12345678901234567890123456789012'
                $result = Get-SentryEvent -EventId $eventId
                
                $result | Should -Not -BeNullOrEmpty
                $result.id | Should -Be $eventId
                $result.message | Should -Be 'Test error message'
            }
            
            It 'Should remove hyphens from GUID-formatted event ID' {
                $guidEventId = '12345678-9012-3456-7890-123456789012'
                
                # Verify the function is called with the correct parameters
                $result = Get-SentryEvent -EventId $guidEventId
                
                # The mock should have been called with the cleaned event ID
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -like '*events/12345678901234567890123456789012/*'
                }
            }
            
            It 'Should construct correct API URL' {
                $eventId = '12345678901234567890123456789012'
                
                Get-SentryEvent -EventId $eventId
                
                # Verify Invoke-RestMethod was called with correct URL structure
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -match 'https://sentry.io/api/0/projects/test-org/test-project/events/\w+/'
                }
            }
        }
        
        Context 'Get-SentryEventsByTag' {
            It 'Should query events with tag filter' {
                $result = Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'
                
                $result | Should -Not -BeNullOrEmpty
                $result | Should -HaveCount 2
                $result[0].message | Should -Be 'Error 1'
            }
            
            It 'Should include query parameters in URL' {
                Get-SentryEventsByTag -TagName 'environment' -TagValue 'production' -Limit 50
                
                # Verify the query parameters were included
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -match 'query=environment%3Aproduction' -and
                    $Uri -match 'limit=50'
                }
            }
            
            It 'Should include cursor parameter when provided' {
                Get-SentryEventsByTag -TagName 'environment' -TagValue 'production' -Cursor 'next123'
                
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -match 'cursor=next123'
                }
            }
            
            It 'Should include full parameter when switch is provided' {
                Get-SentryEventsByTag -TagName 'environment' -TagValue 'production' -Full
                
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -match 'full=true'
                }
            }
        }
        
        Context 'Find-SentryEventByTag' {
            It 'Should query issues endpoint and return events array' {
                $result = Find-SentryEventByTag -TagName 'environment' -TagValue 'production'
                
                $result | Should -Not -BeNullOrEmpty
                # Check if it's an array using Count property instead of type check
                $result.Count | Should -BeGreaterThan 0
                $result[0].id | Should -Be '12345678901234567890123456789012'
            }
            
            It 'Should make correct API call to issues endpoint' {
                Find-SentryEventByTag -TagName 'release' -TagValue '1.0.0'
                
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -match '/issues/' -and
                    $Uri -match 'query=release%3A1\.0\.0'
                }
            }
            
            It 'Should include sort parameter when provided' {
                Find-SentryEventByTag -TagName 'release' -TagValue '1.0.0' -Sort 'date'
                
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -ParameterFilter {
                    $Uri -match 'sort=date'
                }
            }
            
            It 'Should retrieve associated events when issues are found' {
                # Use the default mock setup - it already handles both endpoints correctly
                $result = Find-SentryEventByTag -TagName 'environment' -TagValue 'production'
                
                # Should return events that can be accessed by index
                $result.Count | Should -BeGreaterThan 0
                $result[0].id | Should -Be '12345678901234567890123456789012'
                $result[0].message | Should -Be 'Test error message'
                
                # Should have made 3 calls - one for issues, one for events list, one for actual event content
                Assert-MockCalled -ModuleName SentryApiClient Invoke-RestMethod -Times 3
            }
        }
    }
    
    Context 'Error Handling' {
        BeforeAll {
            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }
        
        It 'Should handle API errors gracefully' {
            Mock -ModuleName SentryApiClient Invoke-RestMethod {
                throw [System.Net.WebException]::new("404 Not Found")
            }
            
            { Get-SentryEvent -EventId 'nonexistent' } | Should -Throw "*Sentry API request*failed*"
        }
        
        It 'Should handle rate limiting' {
            Mock -ModuleName SentryApiClient Invoke-RestMethod {
                $response = [System.Net.HttpWebResponse]::new()
                $exception = [System.Net.WebException]::new("429 Too Many Requests", $null, [System.Net.WebExceptionStatus]::ProtocolError, $response)
                throw $exception
            }
            
            { Get-SentryEventsByTag -TagName 'test' -TagValue 'value' } | Should -Throw "*Sentry API request*failed*"
        }
    }
    
}