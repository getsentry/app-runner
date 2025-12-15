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

Context 'Test-IntentExtrasArray' {
    It 'Accepts valid Intent extras array with -e flag' {
        { Test-IntentExtrasArray -Arguments @('-e', 'key', 'value') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with -es flag' {
        { Test-IntentExtrasArray -Arguments @('-es', 'stringKey', 'stringValue') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with --es flag' {
        { Test-IntentExtrasArray -Arguments @('--es', 'stringKey', 'stringValue') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with -ez flag and true' {
        { Test-IntentExtrasArray -Arguments @('-ez', 'boolKey', 'true') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with -ez flag and false' {
        { Test-IntentExtrasArray -Arguments @('-ez', 'boolKey', 'false') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with --ez flag and true' {
        { Test-IntentExtrasArray -Arguments @('--ez', 'boolKey', 'true') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with --ez flag and false' {
        { Test-IntentExtrasArray -Arguments @('--ez', 'boolKey', 'false') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with -ei flag' {
        { Test-IntentExtrasArray -Arguments @('-ei', 'intKey', '42') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with -el flag' {
        { Test-IntentExtrasArray -Arguments @('-el', 'longKey', '1234567890') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with --ei flag' {
        { Test-IntentExtrasArray -Arguments @('--ei', 'intKey', '42') } | Should -Not -Throw
    }

    It 'Accepts valid Intent extras array with --el flag' {
        { Test-IntentExtrasArray -Arguments @('--el', 'longKey', '1234567890') } | Should -Not -Throw
    }

    It 'Accepts multiple Intent extras in array' {
        { Test-IntentExtrasArray -Arguments @('-e', 'key1', 'value1', '-ez', 'key2', 'false', '-ei', 'key3', '100') } | Should -Not -Throw
    }

    It 'Accepts empty array' {
        { Test-IntentExtrasArray -Arguments @() } | Should -Not -Throw
    }

    It 'Accepts null' {
        { Test-IntentExtrasArray -Arguments $null } | Should -Not -Throw
    }

    It 'Accepts keys and values with spaces' {
        { Test-IntentExtrasArray -Arguments @('-e', 'key with spaces', 'value with spaces') } | Should -Not -Throw
    }

    It 'Accepts unknown arguments without throwing' {
        { Test-IntentExtrasArray -Arguments @('key', 'value') } | Should -Not -Throw
    }

    It 'Accepts unknown flags by ignoring validation' {
        { Test-IntentExtrasArray -Arguments @('--new-flag', 'key', 'value') } | Should -Not -Throw
    }

    It 'Throws on incomplete known flag without key and value' {
        { Test-IntentExtrasArray -Arguments @('-e') } | Should -Throw '*must be followed by key and value*'
    }

    It 'Throws on known flag with only key, missing value' {
        { Test-IntentExtrasArray -Arguments @('-e', 'key') } | Should -Throw '*must be followed by key and value*'
    }

    It 'Throws on boolean flag with invalid value' {
        { Test-IntentExtrasArray -Arguments @('-ez', 'boolKey', 'invalid') } | Should -Throw '*requires ''true'' or ''false'' value*'
    }

    It 'Throws on double-dash boolean flag with invalid value' {
        { Test-IntentExtrasArray -Arguments @('--ez', 'boolKey', 'invalid') } | Should -Throw '*requires ''true'' or ''false'' value*'
    }

    It 'Accepts mixed known and unknown flags' {
        { Test-IntentExtrasArray -Arguments @('-e', 'key1', 'value1', '--new-flag', 'key2', 'value2', '-ez', 'bool', 'true') } | Should -Not -Throw
    }

    It 'Accepts single-token arguments like --grant-read-uri-permission' {
        { Test-IntentExtrasArray -Arguments @('--grant-read-uri-permission') } | Should -Not -Throw
    }

    It 'Accepts mixed single tokens and unknown arguments' {
        { Test-IntentExtrasArray -Arguments @('not-a-flag', 'value', '--activity-clear-task') } | Should -Not -Throw
    }
}
