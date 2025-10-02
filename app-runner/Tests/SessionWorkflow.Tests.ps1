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

Context 'Comprehensive Session Requirements' {
    It 'Should enforce session requirement across all functions' {
        Disconnect-Console
        { Start-Console } | Should -Throw '*No active console session*'
        { Stop-Console } | Should -Throw '*No active console session*'
        { Get-ConsoleStatus } | Should -Throw '*No active console session*'
        { Get-ConsoleLogs } | Should -Throw '*No active console session*'
        { Get-ConsoleScreenshot -OutputPath 'test.local.png' } | Should -Throw '*No active console session*'
        { Get-ConsoleDiagnostics } | Should -Throw '*No active console session*'
    }

    It 'Should allow all functions to work with active session' {
        Connect-Console -Platform 'Mock'
        { Start-Console } | Should -Not -Throw
        { Get-ConsoleStatus } | Should -Not -Throw
        { Get-ConsoleLogs } | Should -Not -Throw
        { Get-ConsoleScreenshot -OutputPath 'test.local.png' } | Should -Not -Throw
        { Get-ConsoleDiagnostics } | Should -Not -Throw
        { Stop-Console } | Should -Not -Throw
    }

    It 'Should maintain session consistency across operations' {
        Connect-Console -Platform 'Mock'
        $originalSession = Get-ConsoleSession
        $originalConnectTime = $originalSession.ConnectedAt
        $originalIdentifier = $originalSession.Identifier

        # Perform multiple operations
        Start-Console
        Invoke-ConsoleApp -ExecutablePath 'test.exe'
        Get-ConsoleLogs -MaxEntries 3

        # Session should remain the same
        $currentSession = Get-ConsoleSession
        $currentSession.ConnectedAt | Should -Be $originalConnectTime
        $currentSession.Identifier | Should -Be $originalIdentifier
    }
}
