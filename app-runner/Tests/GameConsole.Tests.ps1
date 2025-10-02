# Provider Public API Tests
# Tests the PowerShell module's public API against all real console providers
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

    $TestTargets = @(
        New-TestTarget -Platform 'Switch'
        New-TestTarget -Platform 'PlayStation5'
    )

    if ($env:CI -eq 'true') {
        $TestTargets += New-TestTarget -Platform 'Xbox' -Target $env:DEVKIT_XBOXONE_IP
        $TestTargets += New-TestTarget -Platform 'Xbox' -Target $env:DEVKIT_SCARLETT_IP
    } else {
        $TestTargets += New-TestTarget -Platform 'Xbox'
    }

    $global:DebugPreference = 'Continue'
}

BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\SentryAppRunner.psm1" -Force

    # Helper function for cleanup
    function Invoke-TestCleanup {
        try {
            if (Get-ConsoleSession) {
                Disconnect-Console
            }
        } catch {
            # Ignore cleanup errors
        }
    }

    # Helper function to connect to console with proper parameters
    function Connect-TestConsole {
        param(
            [string]$Platform,
            [string]$Target
        )

        if ($Target) {
            Connect-Console -Platform $Platform -Target $Target
        } else {
            Connect-Console -Platform $Platform
        }
    }
}

Describe '<TargetName>' -Tag 'RequiresConsole' -ForEach $TestTargets {
    Context 'Session State Consistency' -Tag $TargetName {
        It 'Session state remains consistent across operations' {
            # Initial connection
            $initialSession = Connect-TestConsole -Platform $Platform -Target $Target

            Get-ConsoleStatus | Out-Null
            $sessionAfterStatus = Get-ConsoleSession
            $sessionAfterStatus.SessionId | Should -Be $initialSession.SessionId

            Get-ConsoleDiagnostics | Out-Null
            $sessionAfterDiagnostics = Get-ConsoleSession
            $sessionAfterDiagnostics.SessionId | Should -Be $initialSession.SessionId
        }
    }

    Context 'Console Connection Management' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Connect-Console establishes valid session' {
            { Connect-TestConsole -Platform $Platform -Target $Target } | Should -Not -Throw

            $session = Get-ConsoleSession
            $session | Should -Not -BeNullOrEmpty
            $session.Platform | Should -Be $Platform
            $session.Identifier | Should -Not -BeNullOrEmpty
            $session.IsConnected | Should -BeTrue
        }

        It 'Test-ConsoleConnection returns true when connected' {
            Connect-TestConsole -Platform $Platform -Target $Target
            Test-ConsoleConnection | Should -Be $true
        }

        It 'Test-ConsoleConnection returns false when not connected' {
            # Ensure no active session
            try { Disconnect-Console } catch { }

            Test-ConsoleConnection | Should -Be $false
        }

        It 'Disconnect-Console cleans up session' {
            Connect-TestConsole -Platform $Platform -Target $Target
            { Disconnect-Console } | Should -Not -Throw

            Get-ConsoleSession | Should -BeNullOrEmpty
            Test-ConsoleConnection | Should -Be $false
        }

        It 'Multiple Connect-Console calls replace session' {
            Connect-TestConsole -Platform $Platform -Target $Target
            $firstConnectTime = (Get-ConsoleSession).ConnectedAt

            Start-Sleep -Milliseconds 100
            Connect-TestConsole -Platform $Platform -Target $Target
            $secondConnectTime = (Get-ConsoleSession).ConnectedAt

            $secondConnectTime | Should -BeGreaterThan $firstConnectTime
        }
    }

    Context 'Console Lifecycle Management' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Get-ConsoleStatus returns status information' {
            Connect-TestConsole -Platform $Platform -Target $Target

            $status = Get-ConsoleStatus
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
            Connect-TestConsole -Platform $Platform -Target $Target
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Invoke-ConsoleApp executes application' -Skip:$shouldSkip {
            $result = Invoke-ConsoleApp -ExecutablePath $testApp -Arguments ''
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'Output'
            $result.Output | Should -Contain 'Sample: OK'
            $result.ExitCode | Should -Be 0
        }

        It 'Invoke-ConsoleApp with arguments works' -Skip:$shouldSkip {
            $result = Invoke-ConsoleApp -ExecutablePath $testApp -Arguments 'error'
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
            Connect-TestConsole -Platform $Platform -Target $Target
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Test-ConsoleInternetConnection returns boolean when connected' {
            $result = Test-ConsoleInternetConnection
            $result | Should -BeOfType [bool]

            # For Switch, we expect this to work and return true/false based on actual connectivity
            # For other platforms, it should return false with a warning (not implemented)
            if ($Platform -eq 'Switch') {
                # The actual result depends on the console's internet connectivity
                Write-Host "Internet connection test for $Platform returned: $result"
            } else {
                Test-ConsoleInternetConnection | Should -BeFalse
            }
        }

        It 'Get-ConsoleScreenshot captures screenshot' {
            $outputPath = Join-Path $env:TEMP "test_screenshot_$Platform.png"

            try {
                { Get-ConsoleScreenshot -OutputPath $outputPath } | Should -Not -Throw

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

        It 'Get-ConsoleLogs retrieves log data' -Skip:($Platform -eq 'Xbox') {
            $logs = Get-ConsoleLogs
            $logs | Should -Not -BeNullOrEmpty
            $logs | Should -BeOfType [hashtable]

            # Each log entry should have required fields
            $logs['System'][0].Keys | Should -Contain 'Timestamp'
            $logs['System'][0].Keys | Should -Contain 'Message'
        }

        It 'Get-ConsoleLogs with parameters works' -Skip:($Platform -eq 'Xbox') {
            $logs = Get-ConsoleLogs -LogType 'System' -MaxEntries 10
            $logs | Should -Not -BeNullOrEmpty
            $logs.Count | Should -BeLessOrEqual 10
        }
    }

    Context 'Error Handling Consistency' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Commands fail gracefully when no session exists' {
            # Ensure no active session
            try { Disconnect-Console } catch { }

            { Get-ConsoleStatus } | Should -Throw '*No active console session*'
            { Invoke-ConsoleApp -ExecutablePath 'test.exe' } | Should -Throw '*No active console session*'
            { Get-ConsoleDiagnostics } | Should -Throw '*No active console session*'
            { Test-ConsoleInternetConnection } | Should -Throw '*No active console session*'
        }

        It 'Invalid parameters are handled consistently' {
            Connect-TestConsole -Platform $Platform -Target $Target

            # Test invalid file paths
            { Get-ConsoleScreenshot -OutputPath '' } | Should -Throw
            { Invoke-ConsoleApp -ExecutablePath '' } | Should -Throw

            # Test invalid log parameters
            { Get-ConsoleLogs -MaxEntries -1 } | Should -Throw
            { Get-ConsoleLogs -MaxEntries 0 } | Should -Throw
        }
    }
}
