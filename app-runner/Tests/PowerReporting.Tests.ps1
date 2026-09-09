$ErrorActionPreference = 'Stop'

BeforeAll {
    Import-Module "$PSScriptRoot\..\SentryAppRunner.psd1" -Force
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'Device power reporting' -Tag 'Unit' {
    BeforeEach {
        $script:provider = [PSCustomObject]@{
            StartResult = $null
            StopResult = $null
            Disconnected = $false
        }
        $script:provider | Add-Member ScriptMethod StartDevice { return $this.StartResult }
        $script:provider | Add-Member ScriptMethod StopDevice { return $this.StopResult }
        $script:provider | Add-Member ScriptMethod TestConnection { return $true }
        $script:provider | Add-Member ScriptMethod Disconnect { $this.Disconnected = $true }

        & (Get-Module SentryAppRunner) {
            param($provider)
            $script:CurrentSession = @{
                Provider = $provider
                Platform = 'Test'
                Identifier = 'test device'
                Mutex = $null
            }
        } $script:provider
    }

    AfterEach {
        & (Get-Module SentryAppRunner) { $script:CurrentSession = $null }
    }

    It 'Reports <Name> power operations' -TestCases @(
        @{
            Name = 'failed'; StartResult = 'Failed'; StopResult = 'Failed'
            StartMessage = 'Device power on failed.'; StopMessage = 'Device power off failed.'
            OutputType = [System.Management.Automation.WarningRecord]
        }
        @{
            Name = 'unsupported'; StartResult = 'NotSupported'; StopResult = 'NotSupported'
            StartMessage = 'Device power on not supported. Skipped.'; StopMessage = 'Device power off not supported. Skipped.'
            OutputType = [string]
        }
        @{
            Name = 'successful'; StartResult = 'PoweredOn'; StopResult = 'PoweredOff'
            StartMessage = 'Device started successfully'; StopMessage = 'Device powered off'
            OutputType = [string]
        }
    ) {
        param($StartResult, $StopResult, $StartMessage, $StopMessage, $OutputType)

        & (Get-Module SentryAppRunner) {
            param($StartResult, $StopResult)
            $script:CurrentSession.Provider.StartResult = [DevicePowerResult]$StartResult
            $script:CurrentSession.Provider.StopResult = [DevicePowerResult]$StopResult
        } $StartResult $StopResult

        $startOutput = @(Start-Device 3>&1)
        $startOutput.Count | Should -Be 1
        $startOutput[0] | Should -BeOfType $OutputType
        "$($startOutput[0])" | Should -Be $StartMessage

        $stopOutput = @(Disconnect-Device -PowerOff 3>&1)
        $stopOutput.Count | Should -Be 2
        $stopOutput[0] | Should -BeOfType $OutputType
        "$($stopOutput[0])" | Should -Be $StopMessage
        $stopOutput[1] | Should -Be 'Disconnected from device'
        $script:provider.Disconnected | Should -BeTrue
        Get-DeviceSession | Should -BeNullOrEmpty
    }
}
