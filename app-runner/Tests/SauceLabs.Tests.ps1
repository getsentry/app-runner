
# SauceLabs Provider Tests
# Tests the generic SauceLabsProvider for both Android and iOS platforms.

BeforeDiscovery {
    $TestTargets = @()

    # Check for SauceLabs credentials
    if ($env:SAUCE_USERNAME -and $env:SAUCE_ACCESS_KEY -and $env:SAUCE_REGION) {
        
        # Check Android Fixture
        $androidFixture = Join-Path $PSScriptRoot 'Fixtures' 'Android' 'TestApp.apk'
        if (Test-Path $androidFixture) {
            $TestTargets += @{
                Platform    = 'AndroidSauceLabs'
                Target      = 'Samsung_Galaxy_S23_15_real_sjc1'
                FixturePath = $androidFixture
                ExePath     = 'com.sentry.test.minimal/.MainActivity'
                Arguments   = '-e sentry test'
            }
        }
        else {
            Write-Warning "Android fixture not found at $androidFixture. AndroidSauceLabs tests will be skipped."
        }

        # Check iOS Fixture
        $iosFixture = Join-Path $PSScriptRoot 'Fixtures' 'iOS' 'TestApp.ipa'
        if (Test-Path $iosFixture) {
            $TestTargets += @{
                Platform    = 'iOSSauceLabs'
                Target      = 'iPhone 13 Pro'
                FixturePath = $iosFixture
                ExePath     = 'com.saucelabs.mydemoapp.ios'
                Arguments   = '--test-arg value'
            }
        }
        else {
            # Optional: Warning for iOS if we expect it, or just silent skip if it's not main focus yet
            Write-Warning "iOS fixture not found at $iosFixture. iOSSauceLabs tests will be skipped."
        }
    }
    else {
        Write-Warning "SauceLabs credentials not found. SauceLabs tests will be skipped."
    }
}

BeforeAll {
    Import-Module "$PSScriptRoot/../SentryAppRunner.psm1" -Force
}

Describe "SauceLabsProvider Integration Tests" -ForEach $TestTargets {
    
    Context "Provider Contract Tests for <Platform>" {
        It "Should pass contract tests" {
            # 1. Connect
            $session = Connect-Device -Platform $Platform -Target $Target
            $session | Should -Not -BeNullOrEmpty
            $session.Provider | Should -Not -BeNullOrEmpty
            $session.IsConnected | Should -BeTrue
            $session.Provider.Platform | Should -Be $Platform

            # 2. Install App
            $installResult = $session.Provider.InstallApp($FixturePath)
            $installResult | Should -Not -BeNullOrEmpty
            $installResult.SessionId | Should -Not -BeNullOrEmpty

            # 3. Run Application
            $runResult = $session.Provider.RunApplication($ExePath, $Arguments)
            $runResult | Should -Not -BeNullOrEmpty
            $runResult.Output | Should -Not -BeNullOrEmpty

            # 4. Disconnect
            Disconnect-Device
        }
    }
}

