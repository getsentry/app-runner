$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Define test targets
    function Get-TestTarget {
        param(
            [string]$Platform,
            [string]$Target,
            [string]$FixturePath,
            [string]$ExePath,
            [string]$Arguments
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
                -Arguments '-e sentry test'
        }
        else {
            Write-Warning "Android fixture not found at $androidFixture. AndroidSauceLabs tests will be skipped."
        }

        # Check iOS Fixture
        $iosFixture = Join-Path $PSScriptRoot 'Fixtures' 'iOS' 'TestApp.ipa'
        if (Test-Path $iosFixture) {
            $TestTargets += Get-TestTarget `
                -Platform 'iOSSauceLabs' `
                -Target 'iPhone 13 Pro' `
                -FixturePath $iosFixture `
                -ExePath 'com.saucelabs.mydemoapp.ios' `
                -Arguments '--test-arg value'
        }
        else {
            Write-Warning "iOS fixture not found at $iosFixture. iOSSauceLabs tests will be skipped."
        }
    }
    else {
        Write-Warning "SauceLabs credentials not found. SauceLabs tests will be skipped."
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

Describe '<Platform>' -Tag 'RequiresDevice', 'SauceLabs' -ForEach $TestTargets {
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
}
