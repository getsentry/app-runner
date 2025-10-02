$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Clear any existing session before tests
    if (Get-DeviceSession) {
        Disconnect-Device
    }
}

AfterAll {
    # Clean up any remaining session
    if (Get-DeviceSession) {
        Disconnect-Device
    }
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Context 'Connect-Device' {
    It 'Should accept valid platform parameters' {
        $Function = Get-Command Connect-Device
        $PlatformParam = $Function.Parameters['Platform']
        $PlatformParam.Attributes.ValidValues | Should -Contain 'Xbox'
        $PlatformParam.Attributes.ValidValues | Should -Contain 'PlayStation5'
        $PlatformParam.Attributes.ValidValues | Should -Contain 'Switch'
    }

    It 'Should accept Target parameter for Xbox platform' {
        $Function = Get-Command Connect-Device
        $TargetParam = $Function.Parameters['Target']
        $TargetParam | Should -Not -Be $null
        $TargetParam.Attributes.Mandatory | Should -Be $false
    }

    It 'Should create a session when connecting' {
        $session = Connect-Device -Platform 'Mock'
        $session | Should -Not -Be $null
        $session.Platform | Should -Be 'Mock'
        $session.IsConnected | Should -Be $true
    }

    It 'Should disconnect existing session when connecting to new platform' {
        Connect-Device -Platform 'Mock'
        $session = Connect-Device -Platform 'Mock'
        $session.Platform | Should -Be 'Mock'
    }

    It 'Should reject invalid platform' {
        { Connect-Device -Platform 'InvalidPlatform' } | Should -Throw
    }

    It 'Should accept optional Target parameter for Xbox platform' {
        # Verify the parameter exists and is optional
        $Function = Get-Command Connect-Device
        $Function.Parameters.ContainsKey('Target') | Should -Be $true
        $TargetParam = $Function.Parameters['Target']
        $TargetParam.Attributes.Mandatory | Should -Be $false
    }
}

Context 'Get-DeviceSession' {
    It 'Should return null when no session exists' {
        Disconnect-Device
        Get-DeviceSession | Should -Be $null
    }

    It 'Should return session details when connected' {
        Connect-Device -Platform 'Mock'
        $session = Get-DeviceSession
        $session | Should -Not -Be $null
        $session.Platform | Should -Be 'Mock'
        $session.Identifier | Should -Not -Be $null
        $session.ConnectedAt | Should -Not -Be $null
    }
}

Context 'Test-DeviceConnection' {
    It 'Should return false when no session exists' {
        Disconnect-Device
        Test-DeviceConnection | Should -Be $false
    }

    It 'Should return true when session exists' {
        Connect-Device -Platform 'Mock'
        Test-DeviceConnection | Should -Be $true
    }
}

Context 'Test-DeviceInternetConnection' {
    It 'Should require a device session' {
        Disconnect-Device
        { Test-DeviceInternetConnection } | Should -Throw '*No active device session*'
    }

    It 'Should return a boolean value when session exists' {
        Connect-Device -Platform 'Mock'
        $result = Test-DeviceInternetConnection
        $result | Should -BeOfType [bool]
    }

    It 'Should handle providers that do not implement internet testing' {
        Connect-Device -Platform 'Mock'
        # Mock provider returns false by default
        $result = Test-DeviceInternetConnection
        $result | Should -Be $false
    }
}

Context 'Disconnect-Device' {
    It 'Should handle disconnection when no session exists' {
        Disconnect-Device
        { Disconnect-Device } | Should -Not -Throw
    }

    It 'Should clear session when disconnecting' {
        Connect-Device -Platform 'Mock'
        Disconnect-Device
        Get-DeviceSession | Should -Be $null
    }
}

Context 'Invoke-DeviceApp' {
    It 'Should require a device session' {
        Disconnect-Device
        { Invoke-DeviceApp -ExecutablePath 'test.exe' } | Should -Throw '*No active device session*'
    }

    It 'Should accept executable path and arguments' {
        Connect-Device -Platform 'Mock'
        $result = Invoke-DeviceApp -ExecutablePath 'MyGame.exe' -Arguments '--debug'
        $result | Should -Not -Be $null
        $result.ExecutablePath | Should -Be 'MyGame.exe'
        $result.Arguments | Should -Be '--debug'
        $result.Platform | Should -Be 'Mock'
    }

    It 'Should work with no arguments' {
        Connect-Device -Platform 'Mock'
        $result = Invoke-DeviceApp -ExecutablePath 'MyGame.exe'
        $result.Arguments | Should -Be ''
    }
}
