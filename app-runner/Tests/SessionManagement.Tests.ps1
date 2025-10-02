$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Clear any existing session before tests
    if (Get-ConsoleSession) {
        Disconnect-Console
    }
}

AfterAll {
    # Clean up any remaining session
    if (Get-ConsoleSession) {
        Disconnect-Console
    }
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Context 'Connect-Console' {
    It 'Should accept valid platform parameters' {
        $Function = Get-Command Connect-Console
        $PlatformParam = $Function.Parameters['Platform']
        $PlatformParam.Attributes.ValidValues | Should -Contain 'Xbox'
        $PlatformParam.Attributes.ValidValues | Should -Contain 'PlayStation5'
        $PlatformParam.Attributes.ValidValues | Should -Contain 'Switch'
    }

    It 'Should accept Target parameter for Xbox platform' {
        $Function = Get-Command Connect-Console
        $TargetParam = $Function.Parameters['Target']
        $TargetParam | Should -Not -Be $null
        $TargetParam.Attributes.Mandatory | Should -Be $false
    }

    It 'Should create a session when connecting' {
        $session = Connect-Console -Platform 'Mock'
        $session | Should -Not -Be $null
        $session.Platform | Should -Be 'Mock'
        $session.IsConnected | Should -Be $true
    }

    It 'Should disconnect existing session when connecting to new platform' {
        Connect-Console -Platform 'Mock'
        $session = Connect-Console -Platform 'Mock'
        $session.Platform | Should -Be 'Mock'
    }

    It 'Should reject invalid platform' {
        { Connect-Console -Platform 'InvalidPlatform' } | Should -Throw
    }

    It 'Should accept optional Target parameter for Xbox platform' {
        # Verify the parameter exists and is optional
        $Function = Get-Command Connect-Console
        $Function.Parameters.ContainsKey('Target') | Should -Be $true
        $TargetParam = $Function.Parameters['Target']
        $TargetParam.Attributes.Mandatory | Should -Be $false
    }
}

Context 'Get-ConsoleSession' {
    It 'Should return null when no session exists' {
        Disconnect-Console
        Get-ConsoleSession | Should -Be $null
    }

    It 'Should return session details when connected' {
        Connect-Console -Platform 'Mock'
        $session = Get-ConsoleSession
        $session | Should -Not -Be $null
        $session.Platform | Should -Be 'Mock'
        $session.Identifier | Should -Not -Be $null
        $session.ConnectedAt | Should -Not -Be $null
    }
}

Context 'Test-ConsoleConnection' {
    It 'Should return false when no session exists' {
        Disconnect-Console
        Test-ConsoleConnection | Should -Be $false
    }

    It 'Should return true when session exists' {
        Connect-Console -Platform 'Mock'
        Test-ConsoleConnection | Should -Be $true
    }
}

Context 'Test-ConsoleInternetConnection' {
    It 'Should require a console session' {
        Disconnect-Console
        { Test-ConsoleInternetConnection } | Should -Throw '*No active console session*'
    }

    It 'Should return a boolean value when session exists' {
        Connect-Console -Platform 'Mock'
        $result = Test-ConsoleInternetConnection
        $result | Should -BeOfType [bool]
    }

    It 'Should handle providers that do not implement internet testing' {
        Connect-Console -Platform 'Mock'
        # Mock provider returns false by default
        $result = Test-ConsoleInternetConnection
        $result | Should -Be $false
    }
}

Context 'Disconnect-Console' {
    It 'Should handle disconnection when no session exists' {
        Disconnect-Console
        { Disconnect-Console } | Should -Not -Throw
    }

    It 'Should clear session when disconnecting' {
        Connect-Console -Platform 'Mock'
        Disconnect-Console
        Get-ConsoleSession | Should -Be $null
    }
}

Context 'Invoke-ConsoleApp' {
    It 'Should require a console session' {
        Disconnect-Console
        { Invoke-ConsoleApp -ExecutablePath 'test.exe' } | Should -Throw '*No active console session*'
    }

    It 'Should accept executable path and arguments' {
        Connect-Console -Platform 'Mock'
        $result = Invoke-ConsoleApp -ExecutablePath 'MyGame.exe' -Arguments '--debug'
        $result | Should -Not -Be $null
        $result.ExecutablePath | Should -Be 'MyGame.exe'
        $result.Arguments | Should -Be '--debug'
        $result.Platform | Should -Be 'Mock'
    }

    It 'Should work with no arguments' {
        Connect-Console -Platform 'Mock'
        $result = Invoke-ConsoleApp -ExecutablePath 'MyGame.exe'
        $result.Arguments | Should -Be ''
    }
}
