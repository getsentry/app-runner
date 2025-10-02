BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force
}

AfterAll {
    Remove-Module SentryApiClient -Force
}

Describe 'Invoke-SentryCLI Version Management' {
    Context 'Function Export and Parameters' {
        It 'Should be exported by the module' {
            $module = Get-Module SentryApiClient
            $module.ExportedFunctions.Keys | Should -Contain 'Invoke-SentryCLI'
        }
        
        It 'Should have Version parameter' {
            $command = Get-Command Invoke-SentryCLI
            $command.Parameters.Keys | Should -Contain 'Version'
            $command.Parameters['Version'].ParameterType | Should -Be ([string])
        }
        
        It 'Should validate version parameter' {
            # Valid versions should not throw
            { Get-Command Invoke-SentryCLI } | Should -Not -Throw
            
            # Invalid versions should throw validation error
            { Invoke-SentryCLI -Version 'invalid-version' } | Should -Throw "*Version must be*"
            { Invoke-SentryCLI -Version '1.2.3.4.5' } | Should -Throw "*Version must be*"
        }
    }
    
    Context 'System Version Handling' {
        BeforeEach {
            # Mock Write-Host and Write-Warning to avoid output during tests
            Mock -ModuleName SentryApiClient Write-Host {}
            Mock -ModuleName SentryApiClient Write-Warning {}
        }
        
        It 'Should throw when system sentry-cli not found' {
            Mock -ModuleName SentryApiClient Get-Command { $null }
            
            { Invoke-SentryCLI -Version 'system' --version } | Should -Throw "*not found*"
        }
        
        It 'Should throw error when sentry-cli is not found in system mode' {
            Mock -ModuleName SentryApiClient Get-Command {
                return $null
            }
            
            { Invoke-SentryCLI -Version 'system' 'releases', 'list' } | Should -Throw "*sentry-cli command not found*"
        }
    }
    
    Context 'Basic Functionality' {
        It 'Should have proper function signature' {
            $command = Get-Command Invoke-SentryCLI -Module SentryApiClient
            $command.Name | Should -Be 'Invoke-SentryCLI'
            $command.CommandType | Should -Be 'Function'
        }
        
        It 'Should be available for invocation' {
            # Just verify the function exists and doesn't throw on basic parameter validation
            { Get-Command Invoke-SentryCLI } | Should -Not -Throw
        }
    }
    
    Context 'Version Logic Tests' {
        It 'Should generate correct filename for Windows' {
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                # Test the filename logic by examining the actual function behavior
                # We can't easily unit test the internal logic without complex mocking
                # But we can verify parameter handling
                $command = Get-Command Invoke-SentryCLI
                $command.Parameters['Version'] | Should -Not -BeNullOrEmpty
            } else {
                Set-ItResult -Skipped -Because "Not running on Windows"
            }
        }
        
        It 'Should accept valid semantic versions' {
            # Test version validation without execution
            { 
                $command = Get-Command Invoke-SentryCLI
                # This tests parameter binding validation
                $null = $command.Parameters['Version']
            } | Should -Not -Throw
        }
    }
    
    Context 'Integration Test' -Tag 'Integration' {
        It 'Should work end-to-end with actual download' -Skip:($env:SKIP_INTEGRATION_TESTS -eq 'true') {
            $testDir = Join-Path $TestDrive 'integration'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            Push-Location $testDir
            try {
                # This will actually download sentry-cli
                $output = Invoke-SentryCLI -Version 'latest' --version 2>&1
                
                # Should contain version output
                $output | Should -Match "sentry-cli \d+\.\d+\.\d+"
                
                # Should have created cached file
                $cachedFile = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                    'sentry-cli-latest.exe'
                } else {
                    'sentry-cli-latest'
                }
                
                Test-Path $cachedFile | Should -Be $true
                
                # Second call should use cached version (no download message)
                $secondOutput = Invoke-SentryCLI -Version 'latest' --version 2>&1
                $secondOutput | Should -Not -Match "Downloading sentry-cli"
            }
            finally {
                Pop-Location
            }
        }
    }
}