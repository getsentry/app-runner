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

Context 'Start-Console' {
    It 'Should require console session' {
        Disconnect-Console
        { Start-Console } | Should -Throw '*No active console session*'
    }

    It 'Should work with active session' {
        Connect-Console -Platform 'Mock'
        { Start-Console } | Should -Not -Throw
    }
}

Context 'Stop-Console' {
    It 'Should require console session' {
        Disconnect-Console
        { Stop-Console } | Should -Throw '*No active console session*'
    }

    It 'Should work with active session' {
        Connect-Console -Platform 'Mock'
        { Stop-Console } | Should -Not -Throw
    }
}

Context 'Get-ConsoleStatus' {
    It 'Should require console session' {
        Disconnect-Console
        { Get-ConsoleStatus } | Should -Throw '*No active console session*'
    }

    It 'Should work with active session' {
        Connect-Console -Platform 'Mock'
        { Get-ConsoleStatus } | Should -Not -Throw
    }

    It 'Should return status object with expected properties' {
        Connect-Console -Platform 'Mock'
        $status = Get-ConsoleStatus
        $status | Should -Not -Be $null
        $status.Platform | Should -Be 'Mock'
        $status.Status | Should -Not -Be $null
        $status.Timestamp | Should -Not -Be $null
    }
}
