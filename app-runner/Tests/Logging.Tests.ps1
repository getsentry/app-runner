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

Context 'Get-DeviceLogs' {
    It 'Should require device session' {
        Disconnect-Device
        { Get-DeviceLogs } | Should -Throw '*No active device session*'
    }

    It 'Should validate LogType parameter' {
        $Function = Get-Command Get-DeviceLogs
        $LogTypeParam = $Function.Parameters['LogType']
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'System'
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'Application'
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'Error'
        $LogTypeParam.Attributes.ValidValues | Should -Contain 'All'
    }

    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Get-DeviceLogs } | Should -Not -Throw
    }

    It 'Should return log objects with expected properties' {
        Connect-Device -Platform 'Mock'
        $logs = Get-DeviceLogs -LogType 'Error' -MaxEntries 3
        $logs | Should -Not -Be $null
        $logs.Error.Count | Should -BeGreaterThan 0
        foreach ($log in $logs.Error) {
            $log.Timestamp | Should -Not -Be $null
            $log.Message | Should -Not -Be $null
        }
    }
}
