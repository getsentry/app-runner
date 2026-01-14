# Test Helpers for SentryApiClient Module

function New-MockSentryEvent {
    param(
        [string]$Id = (New-Guid).ToString().Replace('-', ''),
        [string]$Message = 'Test error message',
        [string]$Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'),
        [hashtable[]]$Tags = @(
            @{ key = 'environment'; value = 'production' },
            @{ key = 'release'; value = '1.0.0' }
        ),
        [string]$Platform = 'javascript',
        [hashtable]$User = @{ id = 'user123'; email = 'test@example.com' },
        [hashtable]$Request = @{
            url = 'https://example.com/api/test'
            method = 'POST'
            headers = @{ 'User-Agent' = 'Mozilla/5.0' }
        }
    )
    
    return @{
        id = $Id
        message = $Message
        timestamp = $Timestamp
        tags = $Tags
        platform = $Platform
        user = $User
        request = $Request
        level = 'error'
        logger = 'javascript'
        environment = ($Tags | Where-Object { $_.key -eq 'environment' }).value
        release = ($Tags | Where-Object { $_.key -eq 'release' }).value
    }
}

function New-MockSentryIssue {
    param(
        [string]$Id = 'issue' + (Get-Random -Maximum 9999),
        [string]$Title = 'Test Issue',
        [string]$Culprit = 'app.js in handleError',
        [int]$Count = 10,
        [string]$LastSeen = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'),
        [string]$FirstSeen = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'),
        [string]$LatestEventId = (New-Guid).ToString().Replace('-', '')
    )
    
    return @{
        id = $Id
        title = $Title
        culprit = $Culprit
        permalink = "https://sentry.io/organizations/test-org/issues/$Id/"
        logger = $null
        level = 'error'
        status = 'unresolved'
        statusDetails = @{}
        isPublic = $false
        platform = 'javascript'
        project = @{
            id = '123456'
            name = 'test-project'
            slug = 'test-project'
        }
        type = 'error'
        metadata = @{
            type = 'Error'
            value = $Title
        }
        numComments = 0
        assignedTo = $null
        isBookmarked = $false
        isSubscribed = $true
        subscriptionDetails = @{ reason = 'unknown' }
        hasSeen = $false
        annotations = @()
        count = $Count.ToString()
        userCount = [Math]::Floor($Count * 0.7)
        firstSeen = $FirstSeen
        lastSeen = $LastSeen
        stats = @{
            '24h' = @(@{ timestamp = (Get-Date).ToUniversalTime().ToString(); count = 5 })
        }
        latestEventId = $LatestEventId
    }
}

function New-MockHttpResponse {
    param(
        [int]$StatusCode = 200,
        [string]$StatusDescription = 'OK',
        [hashtable]$Headers = @{},
        $Content = @{}
    )
    
    $response = @{
        StatusCode = $StatusCode
        StatusDescription = $StatusDescription
        Headers = $Headers
        Content = $Content | ConvertTo-Json -Depth 10
    }
    
    return $response
}

function New-MockSentryApiResponder {
    <#
    .SYNOPSIS
    Creates a scriptblock that mocks Invoke-RestMethod for Sentry API responses
    
    .DESCRIPTION
    This function creates a sophisticated mock responder that simulates
    realistic Sentry API behavior including pagination, filtering, and error responses
    #>
    
    param(
        [hashtable]$TestData = @{
            Events = @()
            Issues = @()
        },
        [switch]$SimulateRateLimit,
        [int]$RateLimitAfterCalls = 10
    )
    
    $script:CallCount = 0
    
    return {
        param($Uri, $Method, $Headers, $ContentType, $Body)
        
        $script:CallCount++
        
        # Simulate rate limiting if enabled
        if ($SimulateRateLimit -and $script:CallCount -gt $RateLimitAfterCalls) {
            $response = [System.Net.HttpWebResponse]::new()
            $exception = [System.Net.WebException]::new(
                "429 Too Many Requests", 
                $null, 
                [System.Net.WebExceptionStatus]::ProtocolError, 
                $response
            )
            throw $exception
        }
        
        # Parse the URI to determine the endpoint
        $uriParts = $Uri -split '\?'
        $endpoint = $uriParts[0]
        $queryString = if ($uriParts.Length -gt 1) { $uriParts[1] } else { '' }
        
        # Parse query parameters
        $queryParams = @{}
        if ($queryString) {
            $queryString -split '&' | ForEach-Object {
                $key, $value = $_ -split '=', 2
                $queryParams[$key] = [System.Web.HttpUtility]::UrlDecode($value)
            }
        }
        
        # Route to appropriate handler based on endpoint
        switch -Regex ($endpoint) {
            '/events/(\w+)/$' {
                # Single event endpoint
                $eventId = $Matches[1]
                $sentryEvent = $TestData.Events | Where-Object { $_.id -eq $eventId } | Select-Object -First 1
                
                if ($sentryEvent) {
                    return $sentryEvent
                } else {
                    throw [System.Net.WebException]::new("404 Not Found")
                }
            }
            
            '/events/' {
                # Events list endpoint
                $events = $TestData.Events
                
                # Apply query filter if present
                if ($queryParams['query']) {
                    $tagFilter = $queryParams['query'] -split ':'
                    if ($tagFilter.Length -eq 2) {
                        $tagName = $tagFilter[0]
                        $tagValue = $tagFilter[1]
                        
                        $events = $events | Where-Object {
                            $_.tags | Where-Object { $_.key -eq $tagName -and $_.value -eq $tagValue }
                        }
                    }
                }
                
                # Apply limit
                $limit = if ($queryParams['limit']) { [int]$queryParams['limit'] } else { 100 }
                $events = $events | Select-Object -First $limit
                
                return $events
            }
            
            '/issues/' {
                # Issues endpoint
                $issues = $TestData.Issues
                
                # Apply query filter if present
                if ($queryParams['query']) {
                    $tagFilter = $queryParams['query'] -split ':'
                    if ($tagFilter.Length -eq 2) {
                        $tagName = $tagFilter[0]
                        $tagValue = $tagFilter[1]
                        
                        # For issues, we'd typically filter by issue metadata or tags
                        # This is a simplified version
                        $issues = $issues | Where-Object {
                            $_.metadata.value -match $tagValue
                        }
                    }
                }
                
                # Apply sort
                if ($queryParams['sort']) {
                    switch ($queryParams['sort']) {
                        'date' { $issues = $issues | Sort-Object -Property lastSeen -Descending }
                        'new' { $issues = $issues | Sort-Object -Property firstSeen -Descending }
                        'freq' { $issues = $issues | Sort-Object -Property count -Descending }
                    }
                }
                
                # Apply limit
                $limit = if ($queryParams['limit']) { [int]$queryParams['limit'] } else { 100 }
                $issues = $issues | Select-Object -First $limit
                
                return $issues
            }
            
            default {
                throw [System.Net.WebException]::new("404 Not Found - Unknown endpoint: $endpoint")
            }
        }
    }.GetNewClosure()
}

function New-MockSentryLog {
    param(
        [string]$ItemId = "log-$(New-Guid)",
        [string]$Message = 'Test log message',
        [string]$Severity = 'info',
        [int]$SeverityNumber = 9,
        [string]$TraceId = (New-Guid).ToString().Replace('-', ''),
        [string]$Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'),
        [hashtable]$Attributes = @{}
    )

    $log = @{
        'sentry.item_id' = $ItemId
        'message' = $Message
        'sentry.severity' = $Severity
        'sentry.severity_number' = $SeverityNumber
        'trace' = $TraceId
        'timestamp' = $Timestamp
    }

    # Merge custom attributes
    foreach ($key in $Attributes.Keys) {
        $log[$key] = $Attributes[$key]
    }

    return $log
}

function New-MockSentryLogsResponse {
    param(
        [array]$Logs = @(),
        [hashtable]$Meta = @{
            fields = @{
                timestamp = 'date'
                message = 'string'
                'sentry.severity' = 'string'
            }
            units = @{}
        }
    )

    return @{
        data = $Logs
        meta = $Meta
    }
}

# Functions are automatically available when dot-sourced