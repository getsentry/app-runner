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
    BeforeEach {
        $TestOutputDir = Join-Path $TestDrive "diagnostics-$(Get-Random)"
    }

    It 'Should require device session' {
        Disconnect-Device
        { Get-DeviceDiagnostics -OutputDirectory $TestOutputDir } | Should -Throw '*No active device session*'
    }

    It 'Should accept OutputDirectory parameter' {
        $Function = Get-Command Get-DeviceDiagnostics
        $Function.Parameters.Keys | Should -Contain 'OutputDirectory'
    }

    It 'Should work with active session' {
        Connect-Device -Platform 'Mock'
        { Get-DeviceDiagnostics -OutputDirectory $TestOutputDir } | Should -Not -Throw
    }

    It 'Should return diagnostics object with expected properties' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir
        $diagnostics | Should -Not -Be $null
        $diagnostics.Platform | Should -Be 'Mock'
        $diagnostics.Timestamp | Should -Not -Be $null
        $diagnostics.Files | Should -Not -Be $null
    }

    It 'Should create diagnostic files in the output directory' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir
        $TestOutputDir | Should -Exist
        $diagnostics.Files.Count | Should -BeGreaterThan 0

        foreach ($file in $diagnostics.Files) {
            $file | Should -Exist
        }
    }

    It 'Should create files with correct naming format (yyyyMMdd-HHmmss-subject.ext)' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir
        $datePrefix = Get-Date -Format "yyyyMMdd"

        foreach ($file in $diagnostics.Files) {
            $filename = Split-Path $file -Leaf
            $filename | Should -Match "^$datePrefix-\d{6}-.*\.\w+$"
        }
    }

    It 'Should use current directory when OutputDirectory not specified' {
        Connect-Device -Platform 'Mock'
        New-Item -Path $TestOutputDir -ItemType Directory -Force | Out-Null
        Push-Location $TestOutputDir
        try {
            $diagnostics = Get-DeviceDiagnostics
            $diagnostics.Files | Should -Not -Be $null
            $diagnostics.Files.Count | Should -BeGreaterThan 0
        } finally {
            Pop-Location
        }
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
