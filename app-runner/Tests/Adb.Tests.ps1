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

    # Check for ADB availability for AdbProvider
    if (Get-Command 'adb' -ErrorAction SilentlyContinue) {
        # Check if any devices are connected
        $adbDevices = adb devices
        if ($adbDevices -match '\tdevice$') {
            $TestTargets += Get-TestTarget -Platform 'Adb'
        }
        else {
            Write-Warning "No Android devices connected via ADB. AdbProvider tests will be skipped."
        }
    }
    else {
        Write-Warning "ADB not found in PATH. AdbProvider tests will be skipped."
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

Describe '<Platform>' -Tag 'RequiresDevice', 'Android' -ForEach $TestTargets {
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
    }

    Context 'Application Management' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform -Target $Target

            # Path to test APK
            $apkPath = Join-Path $PSScriptRoot 'Fixtures' 'Android' 'TestApp.apk'
            if (-not (Test-Path $apkPath)) {
                Set-ItResult -Skipped -Because "Test APK not found at $apkPath"
            }
            $script:apkPath = $apkPath
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Install-DeviceApp installs APK' {
            if (-not (Test-Path $script:apkPath)) {
                Set-ItResult -Skipped -Because "Test APK not found"
                return
            }

            { Install-DeviceApp -Path $script:apkPath } | Should -Not -Throw
        }

        It 'Invoke-DeviceApp executes application' {
            if (-not (Test-Path $script:apkPath)) {
                Set-ItResult -Skipped -Because "Test APK not found"
                return
            }

            $package = 'com.sentry.test.minimal'
            $activity = '.MainActivity'
            $executable = "$package/$activity"

            $result = Invoke-DeviceApp -ExecutablePath $executable
            $result | Should -Not -BeNullOrEmpty
            $result.Output | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Diagnostics' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform -Target $Target
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Get-DeviceLogs retrieves logs' {
            $logs = Get-DeviceLogs -MaxEntries 10
            $logs | Should -Not -BeNullOrEmpty
            $logs.Logs | Should -Not -BeNullOrEmpty
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

                # Verify PNG magic bytes
                Get-Content $outputPath -AsByteStream -TotalCount 8 | Should -Be @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            }
            finally {
                if (Test-Path $outputPath) {
                    Remove-Item $outputPath -Force
                }
            }
        }
    }
}
