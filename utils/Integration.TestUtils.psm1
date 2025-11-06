# PowerShell module containing utility functions for Sentry console integration tests

function Invoke-CMakeBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Preset,

        [Parameter(Mandatory)]
        [string]$Target
    )

    Write-Host "Building $Target..." -ForegroundColor Yellow
    $buildResult = & cmake --build --preset $Preset --target $Target 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Build output:' -ForegroundColor Red
        $buildResult | Write-Host
        throw "Failed to build $Target. Exit code: $LASTEXITCODE"
    }
    Write-Host 'Build completed successfully.' -ForegroundColor Green

    # Validate test app exists after build
    if (-not (Test-Path $global:TestAppPath)) {
        throw "Test application not found at: $($global:TestAppPath) after build."
    }

    # "sentry-cli debug-files check" requires individual files (https://github.com/getsentry/sentryx-cli/issues/2033)
    # Invoke-SentryCLI -Version 'latest' debug-files check $global:TestAppDir 2>&1 | Out-File (Get-OutputFilePath 'debug-files-check.txt')

    Invoke-SentryCLI -Version 'latest' debug-files upload --include-sources --log-level=info $global:TestAppDir

}

function Get-OutputFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return "output/$timestamp-$Name"
}

function Get-EventIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AppOutput,

        [Parameter()]
        [int]$ExpectedCount = 1
    )

    $eventCapturedLines = $AppOutput | Where-Object { $_ -match 'EVENT_CAPTURED:' }

    # Provide detailed error message if count doesn't match
    if ($eventCapturedLines.Count -ne $ExpectedCount) {
        $errorMsg = "Expected $ExpectedCount EVENT_CAPTURED line(s) but found $($eventCapturedLines.Count).`n"
        $errorMsg += "`nSearched for lines matching: 'EVENT_CAPTURED:'`n"

        if ($eventCapturedLines.Count -gt 0) {
            $errorMsg += "`nFound lines:`n"
            $eventCapturedLines | ForEach-Object { $errorMsg += "  $_`n" }
        } else {
            $errorMsg += "`nNo EVENT_CAPTURED lines found in output.`n"

            # Show first and last few lines of output for debugging
            $outputArray = @($AppOutput)
            if ($outputArray.Count -gt 0) {
                $errorMsg += "`nApp output preview (first 10 lines):`n"
                $outputArray | Select-Object -First 10 | ForEach-Object { $errorMsg += "  $_`n" }

                if ($outputArray.Count -gt 20) {
                    $errorMsg += "`n  ... ($($outputArray.Count - 20) lines omitted) ...`n"
                }

                if ($outputArray.Count -gt 10) {
                    $errorMsg += "`nApp output preview (last 10 lines):`n"
                    $outputArray | Select-Object -Last 10 | ForEach-Object { $errorMsg += "  $_`n" }
                }
            } else {
                $errorMsg += "`nApp output was completely empty. The test app may have failed to run or produce output.`n"
            }
        }

        throw $errorMsg
    }

    [array]$eventIds = @()
    foreach ($eventLine in $eventCapturedLines) {
        $eventId = ($eventLine -split 'EVENT_CAPTURED: ')[1].Trim()
        $eventId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        $eventIds += $eventId
    }

    # Verify all event IDs are unique if more than one
    if ($ExpectedCount -gt 1) {
        ($eventIds | Select-Object -Unique).Count | Should -Be $ExpectedCount
    }

    return , $eventIds  # Comma operator ensures array is returned
}

function Get-SentryTestEvent {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$EventId,

        [Parameter()]
        [string]$TagName,

        [Parameter()]
        [string]$TagValue,

        [Parameter()]
        [int]$TimeoutSeconds = 300
    )

    if ($EventId) {
        Write-Host "Fetching Sentry event by ID: $EventId" -ForegroundColor Yellow
        $progressActivity = "Waiting for Sentry event $EventId"
    } elseif ($TagName -and $TagValue) {
        Write-Host "Fetching Sentry event by tag: $TagName=$TagValue" -ForegroundColor Yellow
        $progressActivity = "Waiting for Sentry event with tag $TagName=$TagValue"
    } else {
        throw 'Must specify either EventId or both TagName and TagValue'
    }

    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($TimeoutSeconds)
    $lastError = $null
    $elapsedSeconds = 0

    try {
        do {
            $sentryEvent = $null
            $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
            $percentComplete = [math]::Min(100, ($elapsedSeconds / $TimeoutSeconds) * 100)

            Write-Progress -Activity $progressActivity -Status "Elapsed: $elapsedSeconds/$TimeoutSeconds seconds" -PercentComplete $percentComplete

            try {
                if ($EventId) {
                    # Find by event ID
                    $sentryEvent = Get-SentryEvent -EventId $EventId
                } else {
                    # Find by tag
                    $result = Find-SentryEventByTag -TagName $TagName -TagValue $TagValue
                    $result.Count | Should -Be 1
                    $sentryEvent = $result[0]
                }
            } catch {
                $lastError = $_.Exception.Message
                # Event not found yet, continue waiting
                if ($EventId) {
                    Write-Debug "Event $EventId not found yet: $lastError"
                } else {
                    Write-Debug "Event with tag $TagName=$TagValue not found yet: $lastError"
                }
            }

            if ($sentryEvent) {
                Write-Host "Event $($sentryEvent.id) fetched from Sentry" -ForegroundColor Green
                $entries = $sentryEvent.entries
                $sentryEvent = $sentryEvent | Select-Object -ExcludeProperty 'entries'
                foreach ($entry in $entries) {
                    $sentryEvent | Add-Member -MemberType NoteProperty -Name $entry.type -Value $entry.data -Force
                }
                $sentryEvent | ConvertTo-Json -Depth 10 | Out-File -FilePath (Get-OutputFilePath "event-$($sentryEvent.id).json")
                return $sentryEvent
            }

            Start-Sleep -Milliseconds 500
            $currentTime = Get-Date
        } while ($currentTime -lt $endTime)
    } finally {
        Write-Progress -Activity $progressActivity -Completed
    }

    if ($EventId) {
        throw "Event $EventId not found in Sentry within $TimeoutSeconds seconds: $lastError"
    } else {
        throw "Event with tag $TagName=$TagValue not found in Sentry within $TimeoutSeconds seconds: $lastError"
    }
}

# Export module functions
Export-ModuleMember -Function Invoke-CMakeConfigure, Invoke-CMakeBuild, Get-OutputFilePath, Get-EventIds, Get-SentryTestEvent
