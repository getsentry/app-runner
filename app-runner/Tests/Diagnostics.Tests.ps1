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

Context 'Get-ConsoleDiagnostics' {
    It 'Should require console session' {
        Disconnect-Console
        { Get-ConsoleDiagnostics } | Should -Throw '*No active console session*'
    }

    It 'Should accept IncludePerformanceMetrics switch' {
        $Function = Get-Command Get-ConsoleDiagnostics
        $Function.Parameters.Keys | Should -Contain 'IncludePerformanceMetrics'
    }

    It 'Should work with active session' {
        Connect-Console -Platform 'Mock'
        { Get-ConsoleDiagnostics } | Should -Not -Throw
    }

    It 'Should return diagnostics object with expected properties' {
        Connect-Console -Platform 'Mock'
        $diagnostics = Get-ConsoleDiagnostics -IncludePerformanceMetrics
        $diagnostics | Should -Not -Be $null
        $diagnostics.Platform | Should -Be 'Mock'
        $diagnostics.Timestamp | Should -Not -Be $null
    }
}

Context 'Get-ConsoleScreenshot' {
    It 'Should require console session' {
        Disconnect-Console
        { Get-ConsoleScreenshot -OutputPath 'test.local.png' } | Should -Throw '*No active console session*'
    }


    It 'Should work with active session' {
        Connect-Console -Platform 'Mock'
        { Get-ConsoleScreenshot -OutputPath 'test.local.png' } | Should -Not -Throw
    }
}
