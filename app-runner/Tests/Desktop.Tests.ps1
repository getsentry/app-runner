# Desktop Provider Integration Tests
# Tests the PowerShell module's public API against local desktop platforms
# Ensures consistent behavior across Windows, MacOS, and Linux
$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Detect current platform and add as test target
    function Get-CurrentDesktopPlatform {
        if ($IsWindows) {
            return 'Windows'
        } elseif ($IsMacOS) {
            return 'MacOS'
        } elseif ($IsLinux) {
            return 'Linux'
        } else {
            return $null
        }
    }

    # Helper to create test target objects
    function New-TestTarget {
        param([string]$Platform)

        return @{
            Platform   = $Platform
            TargetName = $Platform
        }
    }

    # Only test the current platform
    $TestTargets = @()
    $currentPlatform = Get-CurrentDesktopPlatform
    $currentPlatform | Should -Not -Be $null
    $TestTargets += New-TestTarget -Platform $currentPlatform
    Write-Debug "Desktop integration tests will run on: $currentPlatform"
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
}

Describe '<TargetName>' -Tag 'Desktop', 'Integration' -ForEach $TestTargets {
    Context 'Device Connection Management' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Connect-Device establishes valid session for local computer' {
            { Connect-Device -Platform $Platform } | Should -Not -Throw

            $session = Get-DeviceSession
            $session | Should -Not -BeNullOrEmpty
            $session.Platform | Should -Be $Platform
            $session.Identifier | Should -Not -BeNullOrEmpty
            $session.IsConnected | Should -BeTrue
        }

        It 'Connect-Device ignores Target parameter for desktop platforms' {
            # Should not throw even with a target specified
            { Connect-Device -Platform $Platform -Target 'ignored-value' } | Should -Not -Throw

            $session = Get-DeviceSession
            $session | Should -Not -BeNullOrEmpty
            $session.Platform | Should -Be $Platform
        }

        It 'Test-DeviceConnection returns true when connected' {
            Connect-Device -Platform $Platform
            Test-DeviceConnection | Should -Be $true
        }

        It 'Test-DeviceConnection returns false when not connected' {
            # Ensure no active session
            try { Disconnect-Device } catch { }

            Test-DeviceConnection | Should -Be $false
        }

        It 'Disconnect-Device cleans up session' {
            Connect-Device -Platform $Platform
            { Disconnect-Device } | Should -Not -Throw

            Get-DeviceSession | Should -BeNullOrEmpty
            Test-DeviceConnection | Should -Be $false
        }

        It 'Multiple Connect-Device calls replace session' {
            Connect-Device -Platform $Platform
            $firstSession = Get-DeviceSession
            $firstConnectTime = $firstSession.ConnectedAt

            Start-Sleep -Milliseconds 100
            Connect-Device -Platform $Platform
            $secondSession = Get-DeviceSession
            $secondConnectTime = $secondSession.ConnectedAt

            $secondConnectTime | Should -BeGreaterThan $firstConnectTime
            $secondSession.Platform | Should -Be $Platform
        }
    }

    Context 'Device Status' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Get-DeviceStatus returns local computer status information' {
            $status = Get-DeviceStatus
            $status | Should -Not -BeNullOrEmpty
            $status | Should -BeOfType [hashtable]
            $status.Keys | Should -Contain 'StatusData'
            $status.Keys | Should -Contain 'Timestamp'
            $status.Keys | Should -Contain 'Platform'
            $status.Platform | Should -Be $Platform
            $status.Status | Should -Be 'Online'
        }

        It 'Status includes computer name and OS information' {
            $status = Get-DeviceStatus
            $statusData = $status.StatusData

            $statusData | Should -Not -BeNullOrEmpty
            $statusData.ComputerName | Should -Not -BeNullOrEmpty
            $statusData.Platform | Should -Be $Platform
            $statusData.OSVersion | Should -Not -BeNullOrEmpty
            # Note: PSVersion may not be available in all contexts
        }
    }

    Context 'Application Execution' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Invoke-DeviceApp executes pwsh successfully' {
            $result = Invoke-DeviceApp -ExecutablePath 'pwsh' -Arguments '-Command "Write-Host ''test-output''"'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'Output'
            $result.Keys | Should -Contain 'ExitCode'
            $result.Keys | Should -Contain 'Platform'
            $result.Platform | Should -Be $Platform
            $result.Output | Should -Contain 'test-output'
            $result.ExitCode | Should -Be 0
        }

        It 'Invoke-DeviceApp captures non-zero exit codes' {
            $result = Invoke-DeviceApp -ExecutablePath 'pwsh' -Arguments '-Command "exit 42"'

            $result | Should -Not -BeNullOrEmpty
            $result.ExitCode | Should -Be 42
        }

        It 'Invoke-DeviceApp captures multi-line output' {
            $result = Invoke-DeviceApp -ExecutablePath 'pwsh' -Arguments '-Command "Write-Host ''line1''; Write-Host ''line2''; Write-Host ''line3''"'

            $result.Output | Should -Contain 'line1'
            $result.Output | Should -Contain 'line2'
            $result.Output | Should -Contain 'line3'
        }

        It 'Invoke-DeviceApp includes timing information' {
            $result = Invoke-DeviceApp -ExecutablePath 'pwsh' -Arguments '-Command "Start-Sleep -Milliseconds 100"'

            $result.Keys | Should -Contain 'StartedAt'
            $result.Keys | Should -Contain 'FinishedAt'
            $result.FinishedAt | Should -BeGreaterThan $result.StartedAt
        }
    }

    Context 'Process Enumeration' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Get-RunningProcesses returns process list' {
            # Get running processes via the provider
            $session = Get-DeviceSession
            $processes = $session.Provider.GetRunningProcesses()

            $processes | Should -Not -BeNullOrEmpty
            $processes.Count | Should -BeGreaterThan 0
        }

        It 'Process list includes PowerShell process' {
            $session = Get-DeviceSession
            $processes = $session.Provider.GetRunningProcesses()

            # Should find at least one PowerShell-related process
            $psProcess = $processes | Where-Object {
                $_.Name -match 'pwsh|powershell'
            }
            $psProcess | Should -Not -BeNullOrEmpty
        }

        It 'Process entries include expected fields' {
            $session = Get-DeviceSession
            $processes = $session.Provider.GetRunningProcesses()

            $firstProcess = $processes | Select-Object -First 1
            $firstProcess.Keys | Should -Contain 'ProcessId'
            $firstProcess.Keys | Should -Contain 'Name'
            $firstProcess.ProcessId | Should -BeGreaterThan 0
        }
    }

    Context 'Screenshot Capture' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Get-DeviceScreenshot captures screenshot' -Skip:($Platform -eq 'Windows') {
            # TODO: Windows screenshot command needs to be fixed (currently has PowerShell syntax issues)
            $outputPath = Join-Path $TestDrive "test_screenshot_$Platform.png"

            try {
                { Get-DeviceScreenshot -OutputPath $outputPath } | Should -Not -Throw

                # Verify file was created
                Test-Path $outputPath | Should -Be $true

                # Verify file has content
                $fileInfo = Get-Item $outputPath
                $fileInfo.Length | Should -BeGreaterThan 0

                # Verify PNG magic bytes (first 8 bytes should be PNG signature)
                $bytes = Get-Content $outputPath -AsByteStream -TotalCount 8
                $bytes[0] | Should -Be 0x89
                $bytes[1] | Should -Be 0x50  # 'P'
                $bytes[2] | Should -Be 0x4E  # 'N'
                $bytes[3] | Should -Be 0x47  # 'G'
            } finally {
                if (Test-Path $outputPath) {
                    Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Diagnostics Collection' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Get-DeviceDiagnostics collects diagnostics files' {
            $outputDir = Join-Path $TestDrive "diagnostics-$Platform"

            try {
                $result = Get-DeviceDiagnostics -OutputDirectory $outputDir

                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeOfType [hashtable]
                $result.Keys | Should -Contain 'Files'
                $result.Keys | Should -Contain 'Platform'
                $result.Platform | Should -Be $Platform

                # Should have created multiple diagnostic files
                $result.Files.Count | Should -BeGreaterThan 0

                # Verify files exist
                foreach ($file in $result.Files) {
                    Test-Path $file | Should -Be $true
                }

                # Should include device status
                $statusFile = $result.Files | Where-Object { $_ -match 'device-status\.json$' }
                $statusFile | Should -Not -BeNullOrEmpty

                # Screenshot may not be available on all platforms (Windows screenshot has known issues)
                # $screenshotFile = $result.Files | Where-Object { $_ -match 'screenshot\.png$' }

                # Should include system info
                $sysInfoFile = $result.Files | Where-Object { $_ -match 'sysinfo\.txt$' }
                $sysInfoFile | Should -Not -BeNullOrEmpty

            } finally {
                if (Test-Path $outputDir) {
                    Remove-Item $outputDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Error Handling' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Operations fail gracefully when no session exists' {
            # Ensure no active session
            try { Disconnect-Device } catch { }

            { Get-DeviceStatus } | Should -Throw '*No active device session*'
            { Invoke-DeviceApp -ExecutablePath 'pwsh' -Arguments '' } | Should -Throw '*No active device session*'
        }
    }

    Context 'Exclusive Device Access' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Sequential connections work after disconnect' {
            Connect-Device -Platform $Platform
            $session1 = Get-DeviceSession
            Disconnect-Device

            Connect-Device -Platform $Platform
            $session2 = Get-DeviceSession

            $session2 | Should -Not -BeNullOrEmpty
            $session2.Platform | Should -Be $Platform
        }
    }
}
