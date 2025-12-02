$ErrorActionPreference = 'Stop'

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Dot-source AndroidHelpers for direct testing of internal functions
    . "$PSScriptRoot\..\Private\AndroidHelpers.ps1"
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'AndroidHelpers' -Tag 'Unit', 'Android' {

    Context 'ConvertFrom-AndroidActivityPath' {
        It 'Parses valid activity path with package and activity' {
            $result = ConvertFrom-AndroidActivityPath -ExecutablePath 'com.example.app/com.example.MainActivity'

            $result | Should -Not -BeNullOrEmpty
            $result.PackageName | Should -Be 'com.example.app'
            $result.ActivityName | Should -Be 'com.example.MainActivity'
        }

        It 'Parses activity path with relative activity name' {
            $result = ConvertFrom-AndroidActivityPath -ExecutablePath 'com.example.app/.MainActivity'

            $result.PackageName | Should -Be 'com.example.app'
            $result.ActivityName | Should -Be '.MainActivity'
        }

        It 'Handles complex package names' {
            $result = ConvertFrom-AndroidActivityPath -ExecutablePath 'io.sentry.unreal.sample/com.epicgames.unreal.GameActivity'

            $result.PackageName | Should -Be 'io.sentry.unreal.sample'
            $result.ActivityName | Should -Be 'com.epicgames.unreal.GameActivity'
        }

        It 'Throws on invalid format without slash' {
            { ConvertFrom-AndroidActivityPath -ExecutablePath 'com.example.app' } | Should -Throw '*must be in format*'
        }

        It 'Throws on empty string' {
            # PowerShell validates empty string before function runs
            { ConvertFrom-AndroidActivityPath -ExecutablePath '' } | Should -Throw
        }

        It 'Throws on null' {
            { ConvertFrom-AndroidActivityPath -ExecutablePath $null } | Should -Throw
        }

        It 'Handles multiple slashes (takes first as delimiter)' {
            $result = ConvertFrom-AndroidActivityPath -ExecutablePath 'com.example.app/.MainActivity/extra'

            $result.PackageName | Should -Be 'com.example.app'
            $result.ActivityName | Should -Be '.MainActivity/extra'
        }
    }

    Context 'Test-IntentExtrasFormat' {
        It 'Accepts valid Intent extras with -e flag' {
            { Test-IntentExtrasFormat -Arguments '-e key value' } | Should -Not -Throw
        }

        It 'Accepts valid Intent extras with -es flag' {
            { Test-IntentExtrasFormat -Arguments '-es stringKey stringValue' } | Should -Not -Throw
        }

        It 'Accepts valid Intent extras with -ez flag' {
            { Test-IntentExtrasFormat -Arguments '-ez boolKey true' } | Should -Not -Throw
        }

        It 'Accepts valid Intent extras with -ei flag' {
            { Test-IntentExtrasFormat -Arguments '-ei intKey 42' } | Should -Not -Throw
        }

        It 'Accepts valid Intent extras with -el flag' {
            { Test-IntentExtrasFormat -Arguments '-el longKey 1234567890' } | Should -Not -Throw
        }

        It 'Accepts multiple Intent extras' {
            { Test-IntentExtrasFormat -Arguments '-e key1 value1 -ez key2 false -ei key3 100' } | Should -Not -Throw
        }

        It 'Accepts empty string' {
            { Test-IntentExtrasFormat -Arguments '' } | Should -Not -Throw
        }

        It 'Accepts null' {
            { Test-IntentExtrasFormat -Arguments $null } | Should -Not -Throw
        }

        It 'Accepts whitespace-only string' {
            { Test-IntentExtrasFormat -Arguments '   ' } | Should -Not -Throw
        }

        It 'Throws on invalid format without flag' {
            { Test-IntentExtrasFormat -Arguments 'key value' } | Should -Throw '*Invalid Intent extras format*'
        }

        It 'Throws on invalid format with wrong prefix' {
            { Test-IntentExtrasFormat -Arguments '--key value' } | Should -Throw '*Invalid Intent extras format*'
        }

        It 'Throws on text without proper flag format' {
            { Test-IntentExtrasFormat -Arguments 'some random text' } | Should -Throw '*Invalid Intent extras format*'
        }
    }

    Context 'Get-ApkPackageName error handling' {
        It 'Throws when APK file does not exist' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent-file.apk'
            { Get-ApkPackageName -ApkPath $nonExistentPath } | Should -Throw '*APK file not found*'
        }

        It 'Throws when file is not an APK' {
            $txtFile = Join-Path $TestDrive 'notanapk.txt'
            'test content' | Out-File -FilePath $txtFile

            { Get-ApkPackageName -ApkPath $txtFile } | Should -Throw '*must be an .apk file*'
        }

        It 'Throws when file has no extension' {
            $noExtFile = Join-Path $TestDrive 'noextension'
            'test content' | Out-File -FilePath $noExtFile

            { Get-ApkPackageName -ApkPath $noExtFile } | Should -Throw '*must be an .apk file*'
        }

        It 'Throws when file has wrong extension' {
            $zipFile = Join-Path $TestDrive 'package.zip'
            'test content' | Out-File -FilePath $zipFile

            { Get-ApkPackageName -ApkPath $zipFile } | Should -Throw '*must be an .apk file*'
        }
    }

    Context 'Format-LogcatOutput' {
        It 'Formats array of log lines' {
            $logLines = @(
                '01-01 12:00:00.000  1234  5678 I MyApp: Starting application',
                '01-01 12:00:01.000  1234  5678 D MyApp: Debug message',
                '01-01 12:00:02.000  1234  5678 E MyApp: Error occurred'
            )

            $result = Format-LogcatOutput -LogcatOutput $logLines

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result[0] | Should -Be '01-01 12:00:00.000  1234  5678 I MyApp: Starting application'
            $result[1] | Should -Be '01-01 12:00:01.000  1234  5678 D MyApp: Debug message'
            $result[2] | Should -Be '01-01 12:00:02.000  1234  5678 E MyApp: Error occurred'
        }

        It 'Filters out empty lines' {
            $logLines = @(
                'Line 1',
                '',
                '   ',
                'Line 2',
                $null,
                'Line 3'
            )

            $result = Format-LogcatOutput -LogcatOutput $logLines

            $result.Count | Should -Be 3
            $result[0] | Should -Be 'Line 1'
            $result[1] | Should -Be 'Line 2'
            $result[2] | Should -Be 'Line 3'
        }

        It 'Returns empty array for null input' {
            $result = Format-LogcatOutput -LogcatOutput $null

            # Function returns empty array @() which may be $null in some contexts
            if ($null -eq $result) {
                $result = @()
            }
            $result.Count | Should -Be 0
        }

        It 'Returns empty array for empty input' {
            $result = Format-LogcatOutput -LogcatOutput @()

            $result.Count | Should -Be 0
        }

        It 'Converts non-string objects to strings' {
            $logLines = @(
                123,
                'String line',
                $true
            )

            $result = Format-LogcatOutput -LogcatOutput $logLines

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result | ForEach-Object { $_ | Should -BeOfType [string] }
            $result[0] | Should -Be '123'
            $result[1] | Should -Be 'String line'
            $result[2] | Should -Be 'True'
        }

        It 'Preserves multi-line log content' {
            $logLines = @(
                '01-01 12:00:00.000  1234  5678 I Tag: First message',
                '01-01 12:00:01.000  1234  5678 E Tag: Error with special chars: @#$%^&*()'
            )

            $result = Format-LogcatOutput -LogcatOutput $logLines

            $result.Count | Should -Be 2
            $result[0] | Should -Be '01-01 12:00:00.000  1234  5678 I Tag: First message'
            $result[1] | Should -Be '01-01 12:00:01.000  1234  5678 E Tag: Error with special chars: @#$%^&*()'
        }
    }
}
