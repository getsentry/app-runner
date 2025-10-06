# Provider Public API Tests
# Tests the PowerShell module's public API against all real device providers
# Ensures consistent behavior across Xbox, PlayStation5, and Switch
$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Define test targets with platform and target (devkit) information
    # Helper to create test target objects with computed test names
    function New-TestTarget {
        param(
            [string]$Platform,
            [string]$Target
        )

        $TargetName = if ($Target) {
            "$Platform-$Target"
        } else {
            $Platform
        }

        return @{
            Platform   = $Platform
            Target     = $Target
            TargetName = $TargetName
        }
    }

    # Helper to check if a platform SDK is available
    function Test-PlatformSdkAvailable {
        param([string]$Platform)

        switch ($Platform) {
            'Xbox' {
                # Check for Xbox GDK environment variable or xbconnect.exe in PATH
                if ($env:GameDK) { return $true }
                return $null -ne (Get-Command 'xbconnect.exe' -ErrorAction SilentlyContinue)
            }
            'PlayStation5' {
                # Check for PlayStation SDK environment variable or prospero-ctrl.exe in PATH
                if ($env:SCE_ROOT_DIR) { return $true }
                return $null -ne (Get-Command 'prospero-ctrl.exe' -ErrorAction SilentlyContinue)
            }
            'Switch' {
                # Check for Nintendo SDK environment variable or ControlTarget.exe in PATH
                if ($env:NINTENDO_SDK_ROOT) { return $true }
                return $null -ne (Get-Command 'ControlTarget.exe' -ErrorAction SilentlyContinue)
            }
            default {
                return $true
            }
        }
    }

    # Conditionally add test targets based on SDK availability
    $TestTargets = @()

    if (Test-PlatformSdkAvailable -Platform 'Switch') {
        $TestTargets += New-TestTarget -Platform 'Switch'
    }

    if (Test-PlatformSdkAvailable -Platform 'PlayStation5') {
        $TestTargets += New-TestTarget -Platform 'PlayStation5'
    }

    if (Test-PlatformSdkAvailable -Platform 'Xbox') {
        if ($env:CI -eq 'true') {
            # In CI, use specific devkit IPs if provided
            if ($env:DEVKIT_XBOXONE_IP) {
                $TestTargets += New-TestTarget -Platform 'Xbox' -Target $env:DEVKIT_XBOXONE_IP
            }
            if ($env:DEVKIT_SCARLETT_IP) {
                $TestTargets += New-TestTarget -Platform 'Xbox' -Target $env:DEVKIT_SCARLETT_IP
            }
        } else {
            # Locally, use default Xbox connection
            $TestTargets += New-TestTarget -Platform 'Xbox'
        }
    }

    # Inform user if no platforms are available
    if ($TestTargets.Count -eq 0) {
        Write-Warning "No platform SDKs detected. Device integration tests will be skipped."
        Write-Warning "To run device tests, install at least one platform SDK:"
        Write-Warning "  - Xbox: Set `$env:GameDK or add xbconnect.exe to PATH"
        Write-Warning "  - PlayStation5: Set `$env:SCE_ROOT_DIR or add prospero-ctrl.exe to PATH"
        Write-Warning "  - Switch: Set `$env:NINTENDO_SDK_ROOT or add ControlTarget.exe to PATH"
    }

    $global:DebugPreference = 'Continue'
}

BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\SentryAppRunner.psm1" -Force

    # Helper function for cleanup
    function Invoke-TestCleanup {
        try {
            if (Get-DeviceSession) {
                Disconnect-Device
            }
        } catch {
            # Ignore cleanup errors
        }
    }

    # Helper function to connect to device with proper parameters
    function Connect-TestDevice {
        param(
            [string]$Platform,
            [string]$Target
        )

        if ($Target) {
            Connect-Device -Platform $Platform -Target $Target
        } else {
            Connect-Device -Platform $Platform
        }
    }
}

Describe '<TargetName>' -Tag 'RequiresDevice' -ForEach $TestTargets {
    Context 'Session State Consistency' -Tag $TargetName {
        It 'Session state remains consistent across operations' {
            # Initial connection
            $initialSession = Connect-TestDevice -Platform $Platform -Target $Target

            Get-DeviceStatus | Out-Null
            $sessionAfterStatus = Get-DeviceSession
            $sessionAfterStatus.SessionId | Should -Be $initialSession.SessionId

            Push-Location $TestDrive
            try {
                Get-DeviceDiagnostics | Out-Null
            } finally {
                Pop-Location
            }
            $sessionAfterDiagnostics = Get-DeviceSession
            $sessionAfterDiagnostics.SessionId | Should -Be $initialSession.SessionId
        }
    }

    Context 'Device Connection Management' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Connect-Device establishes valid session' {
            { Connect-TestDevice -Platform $Platform -Target $Target } | Should -Not -Throw

            $session = Get-DeviceSession
            $session | Should -Not -BeNullOrEmpty
            $session.Platform | Should -Be $Platform
            $session.Identifier | Should -Not -BeNullOrEmpty
            $session.IsConnected | Should -BeTrue
        }

        It 'Test-DeviceConnection returns true when connected' {
            Connect-TestDevice -Platform $Platform -Target $Target
            Test-DeviceConnection | Should -Be $true
        }

        It 'Test-DeviceConnection returns false when not connected' {
            # Ensure no active session
            try { Disconnect-Device } catch { }

            Test-DeviceConnection | Should -Be $false
        }

        It 'Disconnect-Device cleans up session' {
            Connect-TestDevice -Platform $Platform -Target $Target
            { Disconnect-Device } | Should -Not -Throw

            Get-DeviceSession | Should -BeNullOrEmpty
            Test-DeviceConnection | Should -Be $false
        }

        It 'Multiple Connect-Device calls replace session' {
            Connect-TestDevice -Platform $Platform -Target $Target
            $firstConnectTime = (Get-DeviceSession).ConnectedAt

            Start-Sleep -Milliseconds 100
            Connect-TestDevice -Platform $Platform -Target $Target
            $secondConnectTime = (Get-DeviceSession).ConnectedAt

            $secondConnectTime | Should -BeGreaterThan $firstConnectTime
        }
    }

    Context 'Device Lifecycle Management' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Get-DeviceStatus returns status information' {
            Connect-TestDevice -Platform $Platform -Target $Target

            $status = Get-DeviceStatus
            $status | Should -Not -BeNullOrEmpty
            $status | Should -BeOfType [hashtable]
            $status.Keys | Should -Contain 'StatusData'
            $status.Keys | Should -Contain 'Timestamp'
            $status.StatusData | Should -BeOfType PSCustomObject
        }
    }

    Context 'Application Management' -Tag $TargetName {
        BeforeDiscovery {
            # Use a minimal test executable path that should exist on the platform
            $testApp = switch ($Platform) {
                'Xbox' { 'xbox' }
                'PlayStation5' { 'playstation5/TestApp.elf' }
                'Switch' { 'switch/TestApp.nsp' }
            }

            $testApp = "$PSScriptRoot/Fixtures/$testApp"
            $shouldSkip = $false

            # These tests require a simple test application to be present in the Fixtures folder.
            # The application must take an optional argument 'error' to simulate failure.
            # The application should print "Sample: OK" on success and "Sample: ERROR" on failure.
            if (-not (Test-Path $testApp)) {
                Write-Warning "Test application not found at: $testApp. Please add a test application to run Application Management tests."
                $shouldSkip = $true
            }
        }

        BeforeAll {
            Connect-TestDevice -Platform $Platform -Target $Target
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Invoke-DeviceApp executes application' -Skip:$shouldSkip {
            $result = Invoke-DeviceApp -ExecutablePath $testApp -Arguments ''
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'Output'
            $result.Output | Should -Contain 'Sample: OK'
            $result.ExitCode | Should -Be 0
        }

        It 'Invoke-DeviceApp with arguments works' -Skip:$shouldSkip {
            $result = Invoke-DeviceApp -ExecutablePath $testApp -Arguments 'error'
            $result | Should -Not -BeNullOrEmpty
            $result.Output | Should -Contain 'Sample: ERROR'
            if ($Platform -ne 'Switch') {
                $result.ExitCode | Should -Be 1
            } else {
                # Switch doesn't return different exit codes
                $result.ExitCode | Should -Be 0
            }
        }
    }

    Context 'Diagnostics and Monitoring' -Tag $TargetName {
        BeforeAll {
            Connect-TestDevice -Platform $Platform -Target $Target
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Test-DeviceInternetConnection returns boolean when connected' {
            $result = Test-DeviceInternetConnection
            $result | Should -BeOfType [bool]

            # For Switch, we expect this to work and return true/false based on actual connectivity
            # For other platforms, it should return false with a warning (not implemented)
            if ($Platform -eq 'Switch') {
                # The actual result depends on the device's internet connectivity
                Write-Host "Internet connection test for $Platform returned: $result"
            } else {
                Test-DeviceInternetConnection | Should -BeFalse
            }
        }

        It 'Get-DeviceScreenshot captures screenshot' {
            $outputPath = Join-Path $env:TEMP "test_screenshot_$Platform.png"

            try {
                { Get-DeviceScreenshot -OutputPath $outputPath } | Should -Not -Throw

                Test-Path $outputPath | Should -Be $true
                $fileInfo = Get-Item $outputPath
                $fileInfo.Length | Should -BeGreaterThan 0

                # check file format by reading the magic bytes
                Get-Content $outputPath -AsByteStream -TotalCount 8 | Should -Be @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            } finally {
                # Clean up test file
                if (Test-Path $outputPath) {
                    Remove-Item $outputPath -Force
                }
            }
        }

        It 'Get-DeviceLogs retrieves log data' -Skip:($Platform -eq 'Xbox') {
            $logs = Get-DeviceLogs
            $logs | Should -Not -BeNullOrEmpty
            $logs | Should -BeOfType [hashtable]

            # Each log entry should have required fields
            $logs['System'][0].Keys | Should -Contain 'Timestamp'
            $logs['System'][0].Keys | Should -Contain 'Message'
        }

        It 'Get-DeviceLogs with parameters works' -Skip:($Platform -eq 'Xbox') {
            $logs = Get-DeviceLogs -LogType 'System' -MaxEntries 10
            $logs | Should -Not -BeNullOrEmpty
            $logs.Count | Should -BeLessOrEqual 10
        }

        It 'Get-DeviceDiagnostics collects diagnostic files' {
            # Convert TestDrive to actual path since native SDK tools don't support PSDrive paths
            $outputDir = Join-Path $TestDrive "diagnostics"

            { Get-DeviceDiagnostics -OutputDirectory $outputDir } | Should -Not -Throw

            # Verify output directory exists
            Test-Path $outputDir | Should -Be $true

            # Verify diagnostic files were created
            $files = Get-ChildItem $outputDir
            $files.Count | Should -BeGreaterThan 0

            # Verify file naming format (yyyyMMdd-HHmmss-subject.ext)
            $datePrefix = Get-Date -Format 'yyyyMMdd'
            foreach ($file in $files) {
                $file.Name | Should -Match "^$datePrefix-\d{6}-.*\.\w+$"
            }

            # Verify expected diagnostic files exist
            $fileNames = $files | Select-Object -ExpandProperty Name
            $fileNames | Where-Object { $_ -like '*-device-status.json' } | Should -Not -BeNullOrEmpty
            $fileNames | Where-Object { $_ -like '*-system-info.txt' } | Should -Not -BeNullOrEmpty
            # Screenshot may fail with TestDrive: path on some platforms, so it's optional

            # Verify device status file has valid JSON
            $statusFile = $files | Where-Object { $_.Name -like '*-device-status.json' } | Select-Object -First 1
            { Get-Content $statusFile.FullName -Raw | ConvertFrom-Json } | Should -Not -Throw

            # Verify screenshot file if it exists (optional, may fail with TestDrive paths)
            $screenshotFile = $files | Where-Object { $_.Name -like '*-screenshot.png' } | Select-Object -First 1
            if ($screenshotFile) {
                $screenshotFile.Length | Should -BeGreaterThan 0
            }

            # Verify system info file has content
            $sysInfoFile = $files | Where-Object { $_.Name -like '*-system-info.txt' } | Select-Object -First 1
            $content = Get-Content $sysInfoFile.FullName -Raw
            $content | Should -Match "Platform: $Platform"
        }

        It 'Get-DeviceDiagnostics returns result object with file paths' {
            # Convert TestDrive to actual path since native SDK tools don't support PSDrive paths
            $outputDir = Join-Path $TestDrive "diagnostics2"

            $result = Get-DeviceDiagnostics -OutputDirectory $outputDir

            # Verify result structure
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be 'Hashtable'
            $result.Keys | Should -Contain 'Platform'
            $result.Keys | Should -Contain 'Timestamp'
            $result.Keys | Should -Contain 'Files'

            # Verify result values
            $result.Platform | Should -Be $Platform
            $result.Timestamp | Should -BeOfType [datetime]
            $result.Files | Should -Not -BeNullOrEmpty
            $result.Files.Count | Should -BeGreaterThan 0

            # Verify all file paths in result exist
            foreach ($filePath in $result.Files) {
                Test-Path $filePath | Should -Be $true
            }
        }
    }

    Context 'Error Handling Consistency' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Commands fail gracefully when no session exists' {
            # Ensure no active session
            try { Disconnect-Device } catch { }

            { Get-DeviceStatus } | Should -Throw '*No active device session*'
            { Invoke-DeviceApp -ExecutablePath 'test.exe' } | Should -Throw '*No active device session*'
            { Get-DeviceDiagnostics } | Should -Throw '*No active device session*'
            { Test-DeviceInternetConnection } | Should -Throw '*No active device session*'
        }

        It 'Invalid parameters are handled consistently' {
            Connect-TestDevice -Platform $Platform -Target $Target

            # Test invalid file paths
            { Get-DeviceScreenshot -OutputPath '' } | Should -Throw
            { Invoke-DeviceApp -ExecutablePath '' } | Should -Throw

            # Test invalid log parameters
            { Get-DeviceLogs -MaxEntries -1 } | Should -Throw
            { Get-DeviceLogs -MaxEntries 0 } | Should -Throw
        }
    }
}
