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

Context 'Get-DeviceDiagnostics' {
    It 'Should require device session' {
        Disconnect-Device
        { Get-DeviceDiagnostics } | Should -Throw '*No active device session*'
    }

    It 'Should accept IncludePerformanceMetrics switch' {
        $Function = Get-Command Get-DeviceDiagnostics
        $Function.Parameters.Keys | Should -Contain 'IncludePerformanceMetrics'
    }

    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Get-DeviceDiagnostics } | Should -Not -Throw
    }

    It 'Should return diagnostics object with expected properties' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -IncludePerformanceMetrics
        $diagnostics | Should -Not -Be $null
        $diagnostics.Platform | Should -Be 'Mock'
        $diagnostics.Timestamp | Should -Not -Be $null
    }
}

Context 'Get-DeviceScreenshot' {
    It 'Should require device session' {
        Disconnect-Device
        { Get-DeviceScreenshot -OutputPath 'test.local.png' } | Should -Throw '*No active device session*'
    }


    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Get-DeviceScreenshot -OutputPath 'test.local.png' } | Should -Not -Throw
    }
}
