BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force
    
    # Import test helpers
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

AfterAll {
    Remove-Module SentryApiClient -Force -ErrorAction SilentlyContinue
}

Describe 'SentryApiClient Integration Tests' {
    Context 'Realistic API Scenarios' {
        BeforeAll {
            # Create test data
            $testEvents = @(
                New-MockSentryEvent -Id 'event001' -Message 'Database connection timeout' -Tags @(
                    @{ key = 'environment'; value = 'production' }
                    @{ key = 'database'; value = 'postgres' }
                    @{ key = 'severity'; value = 'high' }
                )
                New-MockSentryEvent -Id 'event002' -Message 'API rate limit exceeded' -Tags @(
                    @{ key = 'environment'; value = 'production' }
                    @{ key = 'service'; value = 'api-gateway' }
                    @{ key = 'severity'; value = 'medium' }
                )
                New-MockSentryEvent -Id 'event003' -Message 'Memory leak detected' -Tags @(
                    @{ key = 'environment'; value = 'staging' }
                    @{ key = 'service'; value = 'worker' }
                    @{ key = 'severity'; value = 'critical' }
                )
            )
            
            $testIssues = @(
                New-MockSentryIssue -Id 'issue001' -Title 'Database connection timeout' -Count 45 -LatestEventId 'event001'
                New-MockSentryIssue -Id 'issue002' -Title 'API rate limit exceeded' -Count 120 -LatestEventId 'event002'
                New-MockSentryIssue -Id 'issue003' -Title 'Memory leak in worker process' -Count 8 -LatestEventId 'event003'
            )
            
            # Create mock responder
            $mockResponder = New-MockSentryApiResponder -TestData @{
                Events = $testEvents
                Issues = $testIssues
            }

            # Wrap mock responder to return Invoke-WebRequest format
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)
                $result = & $mockResponder -Uri $Uri
                return @{ Content = ($result | ConvertTo-Json -Depth 20) }
            }

            # Setup connection
            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }
        
        It 'Should retrieve specific event by ID' {
            $result = Get-SentryEvent -EventId 'event001'
            
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be 'event001'
            $result.message | Should -Be 'Database connection timeout'
            $result.tags | Where-Object { $_.key -eq 'database' } | Select-Object -ExpandProperty value | Should -Be 'postgres'
        }
        
        It 'Should handle non-existent event gracefully' {
            { Get-SentryEvent -EventId 'nonexistent' } | Should -Throw "*404 Not Found*"
        }
        
        It 'Should filter events by tag' {
            $prodEvents = Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'
            
            $prodEvents | Should -HaveCount 2
            $prodEvents | ForEach-Object {
                $_.tags | Where-Object { $_.key -eq 'environment' } | Select-Object -ExpandProperty value | Should -Be 'production'
            }
        }
        
        It 'Should find issues by tag and retrieve associated events' {
            # Create a new mock that handles both issues and events
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                $result = if ($Uri -match '/events/[^/]+/') {
                    # Handle Get-SentryEvent calls - most specific first
                    $testEvents | Where-Object { $_.id -eq 'event001' }
                } elseif ($Uri -match '/issues/[^/]+/events/') {
                    # Return event summaries for the issue
                    @(
                        @{
                            eventID = 'event001'
                            id      = 'summary-id'
                            message = 'Event summary'
                        }
                    )
                } elseif ($Uri -match '/issues/.*query=') {
                    # Return issues that match the tag
                    $testIssues | Where-Object { $_.title -match 'Database' }
                } else {
                    throw 'Unexpected URI: $Uri'
                }

                return @{ Content = ($result | ConvertTo-Json -Depth 20) }
            }

            $result = Find-SentryEventByTag -TagName 'severity' -TagValue 'high'

            $result | Should -Not -BeNullOrEmpty
            # Function now returns events array directly
            if ($result.Count -gt 0) {
                $result[0].id | Should -Be 'event001'
            }
        }
    }
    
    Context 'Pagination and Limits' {
        BeforeAll {
            # Create a large dataset
            $largeEventSet = 1..150 | ForEach-Object {
                New-MockSentryEvent -Id "event$_" -Message "Error $_" -Tags @(
                    @{ key = 'batch'; value = 'large' }
                )
            }
            
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                $queryParams = @{}
                if ($Uri -match '\?(.+)$') {
                    $Matches[1] -split '&' | ForEach-Object {
                        $key, $value = $_ -split '=', 2
                        $queryParams[$key] = [System.Web.HttpUtility]::UrlDecode($value)
                    }
                }

                $limit = if ($queryParams['limit']) { [int]$queryParams['limit'] } else { 100 }

                $result = $largeEventSet | Select-Object -First $limit
                return @{ Content = ($result | ConvertTo-Json -Depth 20) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }
        
        It 'Should respect limit parameter' {
            $events = Get-SentryEventsByTag -TagName 'batch' -TagValue 'large' -Limit 25
            
            $events | Should -HaveCount 25
        }
        
        It 'Should use default limit when not specified' {
            $events = Get-SentryEventsByTag -TagName 'batch' -TagValue 'large'
            
            $events | Should -HaveCount 100
        }
    }
    
    Context 'Error Scenarios' {
        It 'Should handle rate limiting gracefully' {
            # Create test data with events that will be found
            $testData = @{
                Events = @(
                    New-MockSentryEvent -Id 'test1' -Message 'Test 1'
                    New-MockSentryEvent -Id 'test2' -Message 'Test 2'
                    New-MockSentryEvent -Id 'test3' -Message 'Test 3'
                )
                Issues = @()
            }
            
            $mockResponder = New-MockSentryApiResponder -TestData $testData -SimulateRateLimit -RateLimitAfterCalls 2

            # Wrap mock responder to return Invoke-WebRequest format
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)
                $result = & $mockResponder -Uri $Uri
                return @{ Content = ($result | ConvertTo-Json -Depth 20) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
            
            # First two calls should succeed
            { Get-SentryEvent -EventId 'test1' } | Should -Not -Throw
            { Get-SentryEvent -EventId 'test2' } | Should -Not -Throw
            
            # Third call should hit rate limit
            { Get-SentryEvent -EventId 'test3' } | Should -Throw "*429 Too Many Requests*"
        }
        
        It 'Should provide meaningful error for malformed responses' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                return @{ Content = 'Not a valid JSON response' }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'

            # The function should now throw an error for malformed JSON
            { Get-SentryEvent -EventId 'test' } | Should -Throw
        }
    }
    
    Context 'Complex Query Scenarios' {
        BeforeAll {
            $complexEvents = @(
                New-MockSentryEvent -Tags @(
                    @{ key = 'environment'; value = 'production' }
                    @{ key = 'region'; value = 'us-east-1' }
                    @{ key = 'service'; value = 'auth' }
                    @{ key = 'version'; value = '2.1.0' }
                )
                New-MockSentryEvent -Tags @(
                    @{ key = 'environment'; value = 'production' }
                    @{ key = 'region'; value = 'eu-west-1' }
                    @{ key = 'service'; value = 'auth' }
                    @{ key = 'version'; value = '2.1.0' }
                )
                New-MockSentryEvent -Tags @(
                    @{ key = 'environment'; value = 'staging' }
                    @{ key = 'region'; value = 'us-east-1' }
                    @{ key = 'service'; value = 'api' }
                    @{ key = 'version'; value = '2.2.0-beta' }
                )
            )
            
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                param($Uri)

                # Simple tag filtering logic for testing
                $result = if ($Uri -match 'query=(\w+)%3A(\w+)') {
                    $tagName = $Matches[1]
                    $tagValue = $Matches[2]

                    $complexEvents | Where-Object {
                        $_.tags | Where-Object { $_.key -eq $tagName -and $_.value -eq $tagValue }
                    }
                } else {
                    $complexEvents
                }

                return @{ Content = ($result | ConvertTo-Json -Depth 20) }
            }

            Connect-SentryApi -ApiToken 'test-token' -Organization 'test-org' -Project 'test-project'
        }
        
        It 'Should filter by environment tag' {
            $prodEvents = Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'
            
            $prodEvents | Should -HaveCount 2
            $prodEvents | ForEach-Object {
                $_.tags | Where-Object { $_.key -eq 'environment' } | 
                    Select-Object -ExpandProperty value | Should -Be 'production'
            }
        }
        
        It 'Should filter by service tag' {
            $authEvents = Get-SentryEventsByTag -TagName 'service' -TagValue 'auth'
            
            $authEvents | Should -HaveCount 2
            $authEvents | ForEach-Object {
                $_.tags | Where-Object { $_.key -eq 'service' } | 
                    Select-Object -ExpandProperty value | Should -Be 'auth'
            }
        }
    }
}