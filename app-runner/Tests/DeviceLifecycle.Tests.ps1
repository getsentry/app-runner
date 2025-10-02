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

Context 'Start-Device' {
    It 'Should require device session' {
        Disconnect-Device
        { Start-Device } | Should -Throw '*No active device session*'
    }

    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Start-Device } | Should -Not -Throw
    }
}

Context 'Stop-Device' {
    It 'Should require device session' {
        Disconnect-Device
        { Stop-Device } | Should -Throw '*No active device session*'
    }

    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Stop-Device } | Should -Not -Throw
    }
}

Context 'Get-DeviceStatus' {
    It 'Should require device session' {
        Disconnect-Device
        { Get-DeviceStatus } | Should -Throw '*No active device session*'
    }

    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Get-DeviceStatus } | Should -Not -Throw
    }

    It 'Should return status object with expected properties' {
        Connect-Device -Platform 'Mock'
        $status = Get-DeviceStatus
        $status | Should -Not -Be $null
        $status.Platform | Should -Be 'Mock'
        $status.Status | Should -Not -Be $null
        $status.Timestamp | Should -Not -Be $null
    }
}
