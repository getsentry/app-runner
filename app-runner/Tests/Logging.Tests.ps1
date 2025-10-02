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

Context 'Get-ConsoleLogs' {
    It 'Should require console session' {
        Disconnect-Console
        { Get-ConsoleLogs } | Should -Throw '*No active console session*'
    }

    It 'Should validate LogType parameter' {
        $Function = Get-Command Get-ConsoleLogs
        $LogTypeParam = $Function.Parameters['LogType']
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'System'
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'Application'
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'Error'
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'All'
    }

    It 'Should work with active session' {
        Connect-Console -Platform 'Mock'
        { Get-ConsoleLogs } | Should -Not -Throw
    }

    It 'Should return log objects with expected properties' {
        Connect-Console -Platform 'Mock'
        $logs = Get-ConsoleLogs -LogType 'Error' -MaxEntries 3
        $logs | Should -Not -Be $null
        $logs.Error.Count | Should -BeGreaterThan 0
        foreach ($log in $logs.Error) {
            $log.Timestamp | Should -Not -Be $null
            $log.Message | Should -Not -Be $null
        }
    }
}
