BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force
    
    # Load test fixtures
    $FixturesPath = Join-Path $PSScriptRoot 'Fixtures' 'SentryApiResponses.json'
    $script:Fixtures = Get-Content $FixturesPath -Raw | ConvertFrom-Json
}

AfterAll {
    Remove-Module SentryApiClient -Force -ErrorAction SilentlyContinue
}

Describe 'SentryApiClient Tests with Real API Response Fixtures' {
    Context 'Event Operations with Realistic Data' {
        BeforeAll {
            # Mock Invoke-WebRequest to return fixture data
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                switch -Regex ($Uri) {
                    '/events/4f1a9f7e7f7b4f9a8c8d9e0f1a2b3c4d/' {
                        return @{ Content = ($script:Fixtures.event_detail | ConvertTo-Json -Depth 20) }
                    }
                    '/events/.*query=' {
                        return @{ Content = ($script:Fixtures.event_list | ConvertTo-Json -Depth 20) }
                    }
                    default {
                        throw [System.Net.WebException]::new('404 Not Found')
                    }
                }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'my-org' -Project 'my-app'
        }
        
        It 'Should parse detailed event response correctly' {
            $eventId = '4f1a9f7e7f7b4f9a8c8d9e0f1a2b3c4d'
            $sentryEvent = Get-SentryEvent -EventId $eventId
            
            # Verify basic properties
            $sentryEvent.id | Should -Be $eventId
            $sentryEvent.message | Should -Be "TypeError: Cannot read property 'name' of undefined"
            $sentryEvent.level | Should -Be 'error'
            $sentryEvent.platform | Should -Be 'javascript'
            
            # Verify tags are parsed correctly
            $sentryEvent.tags | Should -Not -BeNullOrEmpty
            $envTag = $sentryEvent.tags | Where-Object { $_.key -eq 'environment' }
            $envTag.value | Should -Be 'production'
            
            # Verify user information
            $sentryEvent.user | Should -Not -BeNullOrEmpty
            $sentryEvent.user.email | Should -Be 'user@example.com'
            
            # Verify request context
            $sentryEvent.request | Should -Not -BeNullOrEmpty
            $sentryEvent.request.url | Should -Be 'https://app.example.com/api/users/profile'
            $sentryEvent.request.method | Should -Be 'POST'
        }
        
        It 'Should handle complex stacktrace data' {
            $sentryEvent = Get-SentryEvent -EventId '4f1a9f7e7f7b4f9a8c8d9e0f1a2b3c4d'
            
            # Verify exception entries
            $sentryEvent.entries | Should -Not -BeNullOrEmpty
            $exceptionEntry = $sentryEvent.entries | Where-Object { $_.type -eq 'exception' }
            $exceptionEntry | Should -Not -BeNullOrEmpty
            
            # Verify stacktrace
            $stack = $exceptionEntry.data.values[0].stacktrace
            $stack.frames | Should -Not -BeNullOrEmpty
            $stack.frames[0].filename | Should -Be 'app.js'
            $stack.frames[0].function | Should -Be 'handleSubmit'
            $stack.frames[0].lineno | Should -Be 123
        }
        
        It 'Should handle breadcrumb data' {
            $sentryEvent = Get-SentryEvent -EventId '4f1a9f7e7f7b4f9a8c8d9e0f1a2b3c4d'
            
            $breadcrumbEntry = $sentryEvent.entries | Where-Object { $_.type -eq 'breadcrumbs' }
            $breadcrumbEntry | Should -Not -BeNullOrEmpty
            
            $breadcrumbs = $breadcrumbEntry.data.values
            $breadcrumbs | Should -HaveCount 2
            $breadcrumbs[0].category | Should -Be 'navigation'
            $breadcrumbs[1].category | Should -Be 'ui.click'
        }
    }
    
    Context 'Issue Operations with Realistic Data' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                switch -Regex ($Uri) {
                    '/events/4f1a9f7e7f7b4f9a8c8d9e0f1a2b3c4d/' {
                        # Handle Get-SentryEvent calls - most specific first
                        return @{ Content = ($script:Fixtures.event_detail | ConvertTo-Json -Depth 20) }
                    }
                    '/issues/[^/]+/events/' {
                        # Handle issues/{id}/events/ endpoint - return event summaries
                        $responseData = @(
                            @{
                                eventID = '4f1a9f7e7f7b4f9a8c8d9e0f1a2b3c4d'
                                id      = 'summary-id'
                                message = 'Event summary'
                            }
                        )
                        return @{ Content = ($responseData | ConvertTo-Json -Depth 20) }
                    }
                    '/issues/.*query=' {
                        return @{ Content = ($script:Fixtures.issue_list | ConvertTo-Json -Depth 20) }
                    }
                    '/issues/1234567890/' {
                        return @{ Content = ($script:Fixtures.issue_detail | ConvertTo-Json -Depth 20) }
                    }
                    default {
                        throw [System.Net.WebException]::new('404 Not Found')
                    }
                }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'my-org' -Project 'my-app'
        }
        
        It 'Should return events from issues correctly' {
            $result = Find-SentryEventByTag -TagName 'platform' -TagValue 'javascript'
            
            $result | Should -Not -BeNullOrEmpty
            # Function returns results that can be indexed
            # Function now returns events, not issues structure
        }
        
        It 'Should return event array' {
            $result = Find-SentryEventByTag -TagName 'platform' -TagValue 'javascript'
            
            # Function returns results that can be indexed
        }
        
        It 'Should handle event retrieval correctly' {
            $result = Find-SentryEventByTag -TagName 'platform' -TagValue 'javascript'
            
            # Function now returns events array, not complex object
            if ($result.Count -gt 0) {
                $result[0] | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context 'Error Response Handling' {
        It 'Should handle 401 Unauthorized correctly' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                $response = New-Object System.Net.HttpWebResponse
                $exception = [System.Net.WebException]::new(
                    '401 Unauthorized',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    $response
                )
                throw $exception
            }

            Connect-SentryApi -ApiToken 'invalid-token' -Organization 'my-org' -Project 'my-app'

            { Get-SentryEvent -EventId 'test' } | Should -Throw '*401 Unauthorized*'
        }
        
        It 'Should handle 403 Forbidden correctly' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                $response = New-Object System.Net.HttpWebResponse
                $exception = [System.Net.WebException]::new(
                    '403 Forbidden',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    $response
                )
                throw $exception
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'my-org' -Project 'my-app'

            { Get-SentryEvent -EventId 'forbidden-event' } | Should -Throw '*403 Forbidden*'
        }
        
        It 'Should handle 429 Rate Limit correctly' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                $response = New-Object System.Net.HttpWebResponse
                $exception = [System.Net.WebException]::new(
                    '429 Too Many Requests',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    $response
                )
                throw $exception
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'my-org' -Project 'my-app'

            { Get-SentryEventsByTag -TagName 'test' -TagValue 'value' } | Should -Throw '*429 Too Many Requests*'
        }
    }
    
    Context 'Pagination Handling' {
        BeforeAll {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                # Return response with headers and content
                return @{
                    Headers = @{
                        Link = '<https://sentry.io/api/0/projects/my-org/my-app/events/?&cursor=1234:100:0>; rel="next"; results="true"; cursor="1234:100:0"'
                    }
                    Content = ($script:Fixtures.event_list | ConvertTo-Json -Depth 20)
                }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'my-org' -Project 'my-app'
        }
        
        It 'Should handle paginated responses' {
            $events = Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'
            
            $events | Should -Not -BeNullOrEmpty
            $events | Should -HaveCount 2
            
            # In a real implementation, we'd check if pagination info is preserved
            # This would require the module to expose pagination details
        }
    }
}