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

Context 'Module Loading' {
    It 'Should import the module without errors' {
        { Import-Module $ModulePath -Force } | Should -Not -Throw
    }

    It 'Should export expected functions' {
        $ExportedFunctions = Get-Command -Module SentryAppRunner
        $ExpectedFunctions = @(
            # Session Management
            'Connect-Device',
            'Disconnect-Device',
            'Get-DeviceSession',
            'Test-DeviceConnection',
            'Test-DeviceInternetConnection',
            'Invoke-DeviceApp',

            # Device Lifecycle
            'Start-Device',
            'Stop-Device',
            'Restart-Device',
            'Get-DeviceStatus',

            # Diagnostics & Monitoring
            'Get-DeviceLogs',
            'Get-DeviceScreenshot',
            'Get-DeviceDiagnostics'
        )

        foreach ($Function in $ExpectedFunctions) {
            $ExportedFunctions.Name | Should -Contain $Function
        }
    }
}
