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

Context 'Module Loading' {
    It 'Should import the module without errors' {
        { Import-Module $ModulePath -Force } | Should -Not -Throw
    }

    It 'Should export expected functions' {
        $ExportedFunctions = Get-Command -Module SentryAppRunner
        $ExpectedFunctions = @(
            # Session Management
            'Connect-Console',
            'Disconnect-Console',
            'Get-ConsoleSession',
            'Test-ConsoleConnection',
            'Test-ConsoleInternetConnection',
            'Invoke-ConsoleApp',

            # Console Lifecycle
            'Start-Console',
            'Stop-Console',
            'Restart-Console',
            'Get-ConsoleStatus',

            # Diagnostics & Monitoring
            'Get-ConsoleLogs',
            'Get-ConsoleScreenshot',
            'Get-ConsoleDiagnostics'
        )

        foreach ($Function in $ExpectedFunctions) {
            $ExportedFunctions.Name | Should -Contain $Function
        }
    }
}
