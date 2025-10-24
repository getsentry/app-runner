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

    It 'Should create output directory if it does not exist' {
        Connect-Device -Platform 'Mock'
        $NonExistentDir = Join-Path $TestDrive "new-directory-$(Get-Random)"

        # Verify directory doesn't exist
        $NonExistentDir | Should -Not -Exist

        # Should not throw and should create the directory
        { Get-DeviceDiagnostics -OutputDirectory $NonExistentDir } | Should -Not -Throw

        # Directory should now exist
        $NonExistentDir | Should -Exist

        # Files should be created in the new directory
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $NonExistentDir
        $diagnostics.Files.Count | Should -BeGreaterThan 0

        foreach ($file in $diagnostics.Files) {
            $file | Should -Exist
            Split-Path $file -Parent | Should -Be $NonExistentDir
        }
    }

    It 'Should collect process list when supported by platform' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir

        # Find the process-list.json file
        $processListFile = $diagnostics.Files | Where-Object { $_ -like '*process-list.json' }
        $processListFile | Should -Not -BeNullOrEmpty
        $processListFile | Should -Exist
    }

    It 'Should create process list file with structured JSON format' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir

        # Find and read the process-list.json file
        $processListFile = $diagnostics.Files | Where-Object { $_ -like '*process-list.json' }
        $content = Get-Content $processListFile -Raw | ConvertFrom-Json

        # Verify content is an array
        $content | Should -Not -BeNullOrEmpty
        $content.Count | Should -BeGreaterThan 0

        # Verify each process has Id and Name properties
        foreach ($process in $content) {
            $process.Id | Should -Not -BeNullOrEmpty
            $process.Name | Should -Not -BeNullOrEmpty
            # Id can be either [int] or [long] after JSON deserialization
            $process.Id | Should -BeOfType [System.ValueType]
            $process.Name | Should -BeOfType [string]
        }
    }

    It 'Should parse process list with expected data structure' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir

        # Find and read the process-list.json file
        $processListFile = $diagnostics.Files | Where-Object { $_ -like '*process-list.json' }
        $processes = Get-Content $processListFile -Raw | ConvertFrom-Json

        # Verify we have the expected mock processes
        $processes.Count | Should -Be 5

        # Verify specific process entries
        $firstProcess = $processes[0]
        $firstProcess.Id | Should -Be 123
        $firstProcess.Name | Should -Be 'C:\Windows\System32\svchost.exe'
    }

    It 'Should include all expected diagnostic files' {
        Connect-Device -Platform 'Mock'
        $diagnostics = Get-DeviceDiagnostics -OutputDirectory $TestOutputDir

        # Expected file patterns
        $expectedFiles = @(
            '*device-status.json'
            '*screenshot.png'
            '*device-logs.json'
            '*system-info.txt'
            '*process-list.json'
        )

        foreach ($pattern in $expectedFiles) {
            $matchingFile = $diagnostics.Files | Where-Object { $_ -like $pattern }
            $matchingFile | Should -Not -BeNullOrEmpty -Because "Expected to find file matching pattern: $pattern"
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
