BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryApiClient.psd1'
    Import-Module $ModulePath -Force
}

AfterAll {
    Remove-Module SentryApiClient -Force
}

Describe 'Get-SentryCLI - Unit Tests' {
    Context 'Function Availability' {
        It 'Should be exported by the module' {
            $module = Get-Module SentryApiClient
            $module.ExportedFunctions.Keys | Should -Contain 'Get-SentryCLI'
        }

        It 'Should have correct parameters' {
            $command = Get-Command Get-SentryCLI
            $command.Parameters.Keys | Should -Contain 'Version'
            $command.Parameters.Keys | Should -Contain 'DownloadDirectory'

            # Check parameter defaults
            $command.Parameters['Version'].Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute]}).DefaultValue | Should -BeNullOrEmpty
            $command.Parameters['DownloadDirectory'].Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute]}).DefaultValue | Should -BeNullOrEmpty
        }
    }

    Context 'Download URL Construction' {
        BeforeEach {
            # Track the URL that would be used
            $script:capturedUrl = $null

            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                $script:capturedUrl = $Uri
                throw "Mock download - testing URL construction only"
            }
        }

        It 'Should construct URL with latest version by default' {
            { Get-SentryCLI } | Should -Throw "*Mock download*"
            $script:capturedUrl | Should -BeLike "*release-registry.services.sentry.io/apps/sentry-cli/latest*"
        }

        It 'Should include specific version in URL' {
            { Get-SentryCLI -Version '2.50.1' } | Should -Throw "*Mock download*"
            $script:capturedUrl | Should -BeLike "*release-registry.services.sentry.io/apps/sentry-cli/2.50.1*"
        }

        It 'Should include required query parameters' {
            { Get-SentryCLI } | Should -Throw "*Mock download*"
            $script:capturedUrl | Should -BeLike "*response=download*"
            $script:capturedUrl | Should -BeLike "*package=sentry-cli*"
            $script:capturedUrl | Should -BeLike "*platform=*"
            $script:capturedUrl | Should -BeLike "*arch=*"
        }
    }

    Context 'Error Handling' {
        It 'Should provide meaningful error on download failure' {
            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                throw "Network connection failed"
            }

            { Get-SentryCLI } | Should -Throw "*Failed to download Sentry CLI*"
        }

        It 'Should handle missing directory gracefully' {
            $invalidPath = Join-Path $TestDrive 'non-existent-dir' 'deep' 'path'

            Mock -ModuleName SentryApiClient Invoke-WebRequest {
                # Check that the directory gets created
                $parentDir = Split-Path $OutFile -Parent
                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }
                Set-Content -Path $OutFile -Value "mock"
                throw "Mock - directory test"
            }

            { Get-SentryCLI -DownloadDirectory $invalidPath } | Should -Throw "*Mock - directory test*"
        }
    }
}

Describe 'Get-SentryCLI - Integration Tests' {
    BeforeEach {
        $script:testDir = Join-Path $TestDrive 'integration-test'
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }

    Context 'Live Download Test' {
        It 'Should successfully download and verify sentry-cli' {
            $result = Get-SentryCLI -DownloadDirectory $script:testDir -Version 'latest'

            # Verify file exists
            Test-Path $result | Should -Be $true

            # Verify it's executable (basic check)
            $fileInfo = Get-Item $result
            $fileInfo.Length | Should -BeGreaterThan 1000000  # Should be > 1MB

            # Verify the path returned
            $result | Should -BeLike "$script:testDir*sentry-cli*"

            & $fileInfo.FullName --version | Should -Match "sentry-cli \d+\.\d+\.\d+"
        }
    }
}
