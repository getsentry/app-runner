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

Context 'Comprehensive Session Requirements' {
    It 'Should enforce session requirement across all functions' {
        Disconnect-Device
        { Start-Device } | Should -Throw '*No active device session*'
        { Stop-Device } | Should -Throw '*No active device session*'
        { Get-DeviceStatus } | Should -Throw '*No active device session*'
        { Get-DeviceLogs } | Should -Throw '*No active device session*'
        { Get-DeviceScreenshot -OutputPath 'test.local.png' } | Should -Throw '*No active device session*'
        { Get-DeviceDiagnostics } | Should -Throw '*No active device session*'
    }

    It 'Should allow all functions to work with active session' {
        Connect-Device -Platform 'Mock'
        { Start-Device } | Should -Not -Throw
        { Get-DeviceStatus } | Should -Not -Throw
        { Get-DeviceLogs } | Should -Not -Throw
        { Get-DeviceScreenshot -OutputPath 'test.local.png' } | Should -Not -Throw
        { Get-DeviceDiagnostics -OutputDirectory $TestDrive } | Should -Not -Throw
        { Stop-Device } | Should -Not -Throw
    }

    It 'Should maintain session consistency across operations' {
        Connect-Device -Platform 'Mock'
        $originalSession = Get-DeviceSession
        $originalConnectTime = $originalSession.ConnectedAt
        $originalIdentifier = $originalSession.Identifier

        # Perform multiple operations
        Start-Device
        Invoke-DeviceApp -ExecutablePath 'test.exe'
        Get-DeviceLogs -MaxEntries 3

        # Session should remain the same
        $currentSession = Get-DeviceSession
        $currentSession.ConnectedAt | Should -Be $originalConnectTime
        $currentSession.Identifier | Should -Be $originalIdentifier
    }
}
