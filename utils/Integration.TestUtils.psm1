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

$script:OutputDir = "output"

function Set-OutputDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Validate that the path is a valid path name (doesn't have to exist)
    try {
        [System.IO.Path]::GetFullPath($Path) | Out-Null
    } catch {
        throw "Invalid path: $Path. $_"
    }

    $script:OutputDir = $Path
}

function Get-OutputFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $script:OutputDir "$timestamp-$Name"
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
        $eventId | Should -Match '^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$'
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

function Get-PackageAumid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath
    )

    if (Test-Path $PackagePath -PathType Container) {
        # PackagePath is a directory
        $manifest = Get-ChildItem -Path $PackagePath -Filter "*_appxmanifest.xml"
    } elseif (Test-Path $PackagePath -PathType Leaf) {
        # PackagePath is a file (e.g., .xvc package), will look for manifest alongside it
        $manifest = Get-Item "$([System.IO.Path]::GetFileNameWithoutExtension($PackagePath))_appxmanifest.xml"
    } else {
        throw "Package path not found: $PackagePath"
    }

    @($manifest).count | Should -Be 1 -Because "There must be a single appmanifest.xml for $PackagePath"

    if ($manifest.Name -match '^(.+)_\d+\.\d+\.\d+\.\d+_neutral__([^_]+)_') {
        $packageName = $matches[1]
        $familyNameHash = $matches[2]
    } else {
        throw "Unable to parse package family name from manifest filename: $($manifest.Name)"
    }

    [xml]$xml = Get-Content $manifest.FullName
    $appId = $xml.Package.Applications.Application.Id
    if (-not $appId) {
        throw "Unable to extract Application ID from manifest"
    }

    return "${packageName}_${familyNameHash}!${appId}"
}

function Get-SentryTestLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AttributeName,

        [Parameter(Mandatory = $true)]
        [string]$AttributeValue,

        [Parameter()]
        [int]$ExpectedCount = 1,

        [Parameter()]
        [int]$TimeoutSeconds = 120,

        [Parameter()]
        [string]$StatsPeriod = '24h',

        [Parameter()]
        [string[]]$Fields
    )

    Write-Host "Fetching Sentry logs by attribute: $AttributeName=$AttributeValue" -ForegroundColor Yellow
    $progressActivity = "Waiting for Sentry logs with $AttributeName=$AttributeValue"

    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($TimeoutSeconds)
    $lastError = $null
    $elapsedSeconds = 0

    try {
        do {
            $logs = @()
            $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
            $percentComplete = [math]::Min(100, ($elapsedSeconds / $TimeoutSeconds) * 100)

            Write-Progress -Activity $progressActivity -Status "Elapsed: $elapsedSeconds/$TimeoutSeconds seconds" -PercentComplete $percentComplete

            try {
                $response = Get-SentryLogsByAttribute -AttributeName $AttributeName -AttributeValue $AttributeValue -StatsPeriod $StatsPeriod -Fields $Fields
                if ($response.data -and $response.data.Count -ge $ExpectedCount) {
                    $logs = $response.data
                }
            } catch {
                $lastError = $_.Exception.Message
                Write-Debug "Logs with $AttributeName=$AttributeValue not found yet: $lastError"
            }

            if ($logs.Count -ge $ExpectedCount) {
                Write-Host "Found $($logs.Count) log(s) from Sentry" -ForegroundColor Green

                # Save logs to file for debugging
                $logsJson = $logs | ConvertTo-Json -Depth 10
                $logsJson | Out-File -FilePath (Get-OutputFilePath "logs-$AttributeName-$AttributeValue.json")

                # Use comma operator to ensure array is preserved (prevents PowerShell unwrapping single item)
                return , @($logs)
            }

            Start-Sleep -Milliseconds 500
            $currentTime = Get-Date
        } while ($currentTime -lt $endTime)
    } finally {
        Write-Progress -Activity $progressActivity -Completed
    }

    $foundCount = if ($logs) { $logs.Count } else { 0 }
    throw "Expected at least $ExpectedCount log(s) with $AttributeName=$AttributeValue but found $foundCount within $TimeoutSeconds seconds. Last error: $lastError"
}

# Export module functions
Export-ModuleMember -Function Invoke-CMakeConfigure, Invoke-CMakeBuild, Set-OutputDir, Get-OutputFilePath, Get-EventIds, Get-SentryTestEvent, Get-SentryTestLog, Get-PackageAumid
