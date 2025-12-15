$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    . "$PSScriptRoot\..\Private\Conversions.ps1"
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Context 'ConvertTo-ArgumentString' {
    It 'Handles empty array' {
        $result = ConvertTo-ArgumentString @()
        $result | Should -Be ""
    }

    It 'Handles null array' {
        $result = ConvertTo-ArgumentString $null
        $result | Should -Be ""
    }

    It 'Handles simple arguments without spaces' {
        $result = ConvertTo-ArgumentString @('--debug', '--verbose')
        $result | Should -Be "--debug --verbose"
    }

    It 'Handles arguments with spaces using single quotes' {
        $result = ConvertTo-ArgumentString @('--config', 'my config.txt')
        $result | Should -Be "--config 'my config.txt'"
    }

    It 'Handles arguments with single quotes using PowerShell escaping' {
        $result = ConvertTo-ArgumentString @('--message', "It's working")
        $result | Should -Be "--message 'It''s working'"
    }

    It 'Handles arguments with double quotes by escaping them' {
        $result = ConvertTo-ArgumentString @('--text', 'He said "hello"')
        $result | Should -Be '--text ''He said "hello"'''
    }

    It 'Handles arguments with special characters' {
        $result = ConvertTo-ArgumentString @('--regex', '[a-z]+')
        $result | Should -Be '--regex [a-z]+'
    }

    It 'Handles PowerShell commands with single quotes' {
        $result = ConvertTo-ArgumentString @('-Command', "Write-Host 'test-output'")
        $result | Should -Be "-Command 'Write-Host ''test-output'''"
    }

    It 'Handles PowerShell commands with semicolons' {
        $result = ConvertTo-ArgumentString @('-Command', "Write-Host 'line1'; Write-Host 'line2'")
        $result | Should -Be "-Command 'Write-Host ''line1''; Write-Host ''line2'''"
    }

    It 'Handles pipe characters' {
        $result = ConvertTo-ArgumentString @('--command', 'echo hello | grep hi')
        $result | Should -Be "--command 'echo hello | grep hi'"
    }

    It 'Handles ampersand characters' {
        $result = ConvertTo-ArgumentString @('--url', 'http://example.com?a=1&b=2')
        $result | Should -Be "--url 'http://example.com?a=1&b=2'"
    }

    It 'Handles empty string arguments' {
        $result = ConvertTo-ArgumentString @('--flag', '', 'value')
        $result | Should -Be '--flag  value'
    }

    It 'Handles arguments with redirections' {
        $result = ConvertTo-ArgumentString @('--output', 'file > /dev/null')
        $result | Should -Be "--output 'file > /dev/null'"
    }
}
