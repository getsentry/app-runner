$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Define test targets
    function Get-TestTarget {
        param(
            [string]$Platform,
            [string]$Target
        )

        $TargetName = if ($Target) {
            "$Platform-$Target"
        }
        else {
            $Platform
        }

        return @{
            Platform   = $Platform
            Target     = $Target
            TargetName = $TargetName
        }
    }

    $TestTargets = @()

    # Detect if running in CI environment
    $isCI = $env:CI -eq 'true'

    # Check for macOS platform and xcrun availability
    if ($IsMacOS) {
        if (Get-Command 'xcrun' -ErrorAction SilentlyContinue) {
            # Check if any simulators are available
            $simDevices = xcrun simctl list devices
            if ($simDevices -match '\(([0-9A-Fa-f\-]{36})\)') {
                $TestTargets += Get-TestTarget -Platform 'iOSSimulator'
            }
            else {
                $message = "No iOS simulators available"
                if ($isCI) {
                    throw "$message. This is required in CI."
                }
                else {
                    Write-Warning "$message. iOSSimulator tests will be skipped."
                }
            }
        }
        else {
            $message = "xcrun not found in PATH"
            if ($isCI) {
                throw "$message. This is required in CI."
            }
            else {
                Write-Warning "$message. iOSSimulator tests will be skipped."
            }
        }
    }
    else {
        $message = "iOSSimulator tests require macOS"
        if ($isCI -and $IsMacOS) {
            throw $message
        }
        else {
            Write-Warning "$message. iOSSimulator tests will be skipped."
        }
    }
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
        }
        catch {
            # Ignore cleanup errors
            Write-Debug "Cleanup failed: $_"
        }
    }
}

Describe '<Platform>' -Tag 'iOSSimulator' -ForEach $TestTargets {
    Context 'Device Connection Management' -Tag $TargetName {
        AfterEach {
            Invoke-TestCleanup
        }

        It 'Connect-Device establishes valid session' {
            { Connect-Device -Platform $Platform -Target $Target } | Should -Not -Throw

            $session = Get-DeviceSession
            $session | Should -Not -BeNullOrEmpty
            $session.Platform | Should -Be $Platform
            $session.IsConnected | Should -BeTrue
        }

        It 'Get-DeviceStatus returns status information' {
            Connect-Device -Platform $Platform -Target $Target

            $status = Get-DeviceStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Status | Should -Be 'Online'
        }

        It 'Connect-Device with "latest" target selects a simulator' {
            { Connect-Device -Platform $Platform -Target 'latest' } | Should -Not -Throw

            $session = Get-DeviceSession
            $session | Should -Not -BeNullOrEmpty
            $session.IsConnected | Should -BeTrue
        }
    }

    Context 'Application Management' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform -Target $Target

            # Path to test .app bundle (built by Build-SimulatorApp.ps1)
            $appPath = Join-Path $PSScriptRoot 'Fixtures' 'iOS' 'TestApp.app'
            if (-not (Test-Path $appPath)) {
                Set-ItResult -Skipped -Because "Test .app bundle not found at $appPath. Run Build-SimulatorApp.ps1 first."
            }
            $script:appPath = $appPath
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Install-DeviceApp installs .app bundle' {
            if (-not (Test-Path $script:appPath)) {
                Set-ItResult -Skipped -Because "Test .app bundle not found"
                return
            }

            { Install-DeviceApp -Path $script:appPath } | Should -Not -Throw
        }

        It 'Invoke-DeviceApp executes application' {
            if (-not (Test-Path $script:appPath)) {
                Set-ItResult -Skipped -Because "Test .app bundle not found"
                return
            }

            $bundleId = 'io.sentry.apprunner.TestApp'

            $result = Invoke-DeviceApp -ExecutablePath $bundleId -Arguments @('--test-mode', 'simulator')
            $result | Should -Not -BeNullOrEmpty
            $result.Output | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Screenshot Capture' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform -Target $Target
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Get-DeviceScreenshot captures screenshot' {
            $outputPath = Join-Path $TestDrive "test_screenshot_$Platform.png"

            try {
                { Get-DeviceScreenshot -OutputPath $outputPath } | Should -Not -Throw

                Test-Path $outputPath | Should -Be $true
                $fileInfo = Get-Item $outputPath
                $fileInfo.Length | Should -BeGreaterThan 0
            }
            finally {
                if (Test-Path $outputPath) {
                    Remove-Item $outputPath -Force
                }
            }
        }
    }
}
