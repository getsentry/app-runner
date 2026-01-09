$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Define test targets
    function Get-TestTarget {
        param(
            [string]$Platform,
            [string]$Target,
            [string]$FixturePath,
            [string]$ExePath,
            [string[]]$Arguments
        )

        $TargetName = "$Platform-$Target"

        return @{
            Platform    = $Platform
            Target      = $Target
            TargetName  = $TargetName
            FixturePath = $FixturePath
            ExePath     = $ExePath
            Arguments   = $Arguments
        }
    }

    $TestTargets = @()

    # Detect if running in CI environment
    $isCI = $env:CI -eq 'true'

    # Check for SauceLabs credentials
    if ($env:SAUCE_USERNAME -and $env:SAUCE_ACCESS_KEY -and $env:SAUCE_REGION) {
        # Check Android Fixture
        $androidFixture = Join-Path $PSScriptRoot 'Fixtures' 'Android' 'TestApp.apk'
        if (Test-Path $androidFixture) {
            $TestTargets += Get-TestTarget `
                -Platform 'AndroidSauceLabs' `
                -Target 'Samsung_Galaxy_S23_15_real_sjc1' `
                -FixturePath $androidFixture `
                -ExePath 'com.sentry.test.minimal/.MainActivity' `
                -Arguments @('-e', 'sentry', 'test')
        } else {
            $message = "Android fixture not found at $androidFixture"
            if ($isCI) {
                throw "$message. This is required in CI."
            } else {
                Write-Warning "$message. AndroidSauceLabs tests will be skipped."
            }
        }

        # Check iOS Fixture
        $iosFixture = Join-Path $PSScriptRoot 'Fixtures' 'iOS' 'TestApp.ipa'
        if (Test-Path $iosFixture) {
            $TestTargets += Get-TestTarget `
                -Platform 'iOSSauceLabs' `
                -Target 'iPhone_15_Pro_18_real_sjc1' `
                -FixturePath $iosFixture `
                -ExePath 'io.sentry.apprunner.TestApp' `
                -Arguments @('--test-mode', 'sentry')
        } else {
            $message = "iOS fixture not found at $iosFixture"
            if ($isCI) {
                throw "$message. This is required in CI."
            } else {
                Write-Warning "$message. iOSSauceLabs tests will be skipped."
            }
        }
    }
    else {
        $message = "SauceLabs credentials not found. Required environment variables: SAUCE_USERNAME, SAUCE_ACCESS_KEY, SAUCE_REGION"
        if ($isCI) {
            throw "$message. These are required in CI."
        } else {
            Write-Warning "$message. SauceLabs tests will be skipped."
        }
    }
}

BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot/../SentryAppRunner.psm1" -Force

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

Describe '<Platform>' -Tag 'SauceLabs' -ForEach $TestTargets {
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
    }

    Context 'Application Management' -Tag $TargetName {
        BeforeAll {
            Connect-Device -Platform $Platform -Target $Target

            # Set fixture path for tests
            if (-not (Test-Path $FixturePath)) {
                Set-ItResult -Skipped -Because "Test app not found at $FixturePath"
            }
            $script:FixturePath = $FixturePath
            $script:ExePath = $ExePath
            $script:Arguments = $Arguments
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'Install-DeviceApp installs application' {
            if (-not (Test-Path $script:FixturePath)) {
                Set-ItResult -Skipped -Because "Test app not found"
                return
            }

            { Install-DeviceApp -Path $script:FixturePath } | Should -Not -Throw
        }

        It 'Invoke-DeviceApp executes application' {
            if (-not (Test-Path $script:FixturePath)) {
                Set-ItResult -Skipped -Because "Test app not found"
                return
            }

            $result = Invoke-DeviceApp -ExecutablePath $script:ExePath -Arguments $script:Arguments
            $result | Should -Not -BeNullOrEmpty
            $result.Output | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Mobile File Operations' -Tag $TargetName {
        BeforeAll {
            if (-not (Test-Path $FixturePath)) {
                throw "Test app not found at $FixturePath. Mobile file operations tests require valid test fixtures."
            }

            Connect-Device -Platform $Platform -Target $Target

            $script:FixturePath = $FixturePath
            $script:ExePath = $ExePath
            $script:Arguments = $Arguments

            Install-DeviceApp -Path $script:FixturePath
            $result = Invoke-DeviceApp -ExecutablePath $script:ExePath -Arguments $script:Arguments
        }

        AfterAll {
            Invoke-TestCleanup
        }

        It 'CheckAppFileSharingCapability returns valid app information for iOS' {
            if ($Platform -ne 'iOSSauceLabs') {
                Set-ItResult -Skipped -Because "CheckAppFileSharingCapability is iOS-only"
                return
            }

            $session = Get-DeviceSession
            $result = $session.Provider.CheckAppFileSharingCapability()

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [hashtable]
            $result.ContainsKey('Found') | Should -BeTrue
            $result.ContainsKey('FileSharingEnabled') | Should -BeTrue
            $result.ContainsKey('AllApps') | Should -BeTrue

            $result.Found | Should -BeOfType [bool]
            $result.FileSharingEnabled | Should -BeOfType [bool]
            ($result.AllApps -is [array]) -or ($result.AllApps -is [string]) | Should -BeTrue
            $result.ContainsKey('BundleId') | Should -BeTrue
            $result.BundleId | Should -Not -BeNullOrEmpty
        }

        It 'CopyDeviceItem successfully copies test files from device' {
            $session = Get-DeviceSession
            $testPath = if ($Platform -eq 'iOSSauceLabs') {
                '@io.sentry.apprunner.TestApp:documents/test-file.txt'
            } else {
                '/storage/emulated/0/Android/data/com.sentry.test.minimal/files/test-file.txt'
            }

            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
               { $session.Provider.CopyDeviceItem($testPath, $tempFile) } | Should -Not -Throw

                # Verify file was copied and has content
                $tempFile | Should -Exist
                $content = Get-Content $tempFile -Raw
                $content | Should -Not -BeNullOrEmpty
                $content | Should -Match "Test file content"
            } finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'RunApplication with LogFilePath retrieves custom log files successfully' {
            $logPath = if ($Platform -eq 'iOSSauceLabs') {
                '@io.sentry.apprunner.TestApp:documents/test-file.txt'
            } else {
                '/storage/emulated/0/Android/data/com.sentry.test.minimal/files/test-file.txt'
            }

            # Should successfully retrieve custom log files (or fallback to system logs)
            $result = Invoke-DeviceApp -ExecutablePath $script:ExePath -Arguments $script:Arguments -LogFilePath $logPath

            # Should return results regardless of log source
            $result | Should -Not -BeNullOrEmpty
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It 'Verifies test app file sharing is now enabled' {
            if ($Platform -ne 'iOSSauceLabs') {
                Set-ItResult -Skipped -Because "File sharing verification is iOS-only"
                return
            }

            # Check iOS file sharing capability - should now be enabled
            $session = Get-DeviceSession
            $result = $session.Provider.CheckAppFileSharingCapability()
            $result.Found | Should -BeTrue -Because "Test app should be found on device"
            $result.FileSharingEnabled | Should -BeTrue -Because "Test app has UIFileSharingEnabled=true"
        }
    }
}
