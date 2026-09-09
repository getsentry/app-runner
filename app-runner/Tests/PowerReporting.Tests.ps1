$ErrorActionPreference = 'Stop'

BeforeAll {
    Import-Module "$PSScriptRoot\..\SentryAppRunner.psd1" -Force
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'Device power reporting' -Tag 'Unit' {
    BeforeEach {
        $script:savedExitCode = $global:LASTEXITCODE
        & (Get-Module SentryAppRunner) {
            $provider = [DeviceProvider]::new()
            $provider.Platform = 'Test'
            $provider.Commands = @{
                poweron = [BuiltCommand]::NoOp()
                poweroff = [BuiltCommand]::NoOp()
                getstatus = [BuiltCommand]::NoOp()
                disconnect = [BuiltCommand]::NoOp()
            }
            $script:CurrentSession = @{
                Provider = $provider
                Platform = 'Test'
                Identifier = 'test device'
                Mutex = $null
            }
        }
    }

    AfterEach {
        & (Get-Module SentryAppRunner) { $script:CurrentSession = $null }
        $global:LASTEXITCODE = $script:savedExitCode
    }

    It 'Reports skipped power-on for an explicit no-op' {
        $output = @(Start-Device 3>&1)
        $output | Should -Be @('Device power on not supported. Skipped.')
    }

    It 'Reports skipped power-off for an explicit no-op and still disconnects' {
        $output = @(Disconnect-Device -PowerOff 3>&1)
        $output | Should -Be @('Device power off not supported. Skipped.', 'Disconnected from device')
        Get-DeviceSession | Should -BeNullOrEmpty
    }

    It 'Reports unavailable power commands without duplicate warnings' {
        & (Get-Module SentryAppRunner) {
            $script:CurrentSession.Provider.Commands['poweron'] = $null
            $script:CurrentSession.Provider.Commands['poweroff'] = $null
        }

        @(Start-Device 3>&1) | Should -Be @('Device power on not supported. Skipped.')
        @(Disconnect-Device -PowerOff 3>&1) | Should -Be @('Device power off not supported. Skipped.', 'Disconnected from device')
    }

    It 'Reports successful power commands after executing them' {
        & (Get-Module SentryAppRunner) {
            $command = [BuiltCommand]::new('& { $global:LASTEXITCODE = 0 }', $null)
            $script:CurrentSession.Provider.Commands['poweron'] = $command
            $script:CurrentSession.Provider.Commands['poweroff'] = $command
        }

        @(Start-Device) | Should -Be @('Device started successfully')
        @(Disconnect-Device -PowerOff) | Should -Be @('Device powered off', 'Disconnected from device')
    }

    It 'Propagates power-command failures and still clears the session on disconnect' {
        & (Get-Module SentryAppRunner) {
            $command = [BuiltCommand]::new('& { throw "Power command failed" }', $null)
            $script:CurrentSession.Provider.Commands['poweron'] = $command
            $script:CurrentSession.Provider.Commands['poweroff'] = $command
        }

        { Start-Device } | Should -Throw '*Power command failed*'
        { Disconnect-Device -PowerOff } | Should -Throw '*Power command failed*'
        Get-DeviceSession | Should -BeNullOrEmpty
    }

    It 'Reports Xbox sleep instead of power-off' {
        & (Get-Module SentryAppRunner) {
            $provider = & { [XboxProvider]::new() } 3>$null
            $provider.TimeoutSeconds = 0
            $provider.Commands['powerState'] = [BuiltCommand]::new('& { $global:LASTEXITCODE = 0; "Allows Instant On" }', $null)
            $provider.Commands['sleep'] = [BuiltCommand]::new('& { $global:LASTEXITCODE = 0 }', $null)
            $script:CurrentSession.Provider = $provider
        }

        $output = @(Disconnect-Device -PowerOff 3>&1)
        $output | Should -Be @('Device put to sleep', 'Disconnected from device')
    }

    It 'Reports unsupported Xbox power-off when Instant On is unavailable' {
        & (Get-Module SentryAppRunner) {
            $provider = & { [XboxProvider]::new() } 3>$null
            $provider.TimeoutSeconds = 0
            $provider.Commands['powerState'] = [BuiltCommand]::new('& { $global:LASTEXITCODE = 0; "Energy saving" }', $null)
            $script:CurrentSession.Provider = $provider
        }

        $output = @(Disconnect-Device -PowerOff 3>&1)
        $output | Should -Be @('Device power off not supported. Skipped.', 'Disconnected from device')
        Get-DeviceSession | Should -BeNullOrEmpty
    }

    It 'Reports unsupported ADB power operations from its method overrides' {
        & (Get-Module SentryAppRunner) {
            $provider = [AdbProvider]::new()
            $provider.Commands['getstatus'] = [BuiltCommand]::NoOp()
            $script:CurrentSession.Provider = $provider
        }

        $startOutput = @(Start-Device 3>&1)
        $stopOutput = @(Disconnect-Device -PowerOff 3>&1)
        $startOutput | Should -Be @('Device power on not supported. Skipped.')
        $stopOutput | Should -Be @('Device power off not supported. Skipped.', 'Disconnected from device')
    }

    It 'Identifies failed power operations alongside the missing-simulator warning' {
        Mock Assert-DeviceSession -ModuleName SentryAppRunner {}
        & (Get-Module SentryAppRunner) {
            $provider = [System.Runtime.CompilerServices.RuntimeHelpers]::GetUninitializedObject([iOSSimulatorProvider])
            $provider.Platform = 'iOSSimulator'
            $script:CurrentSession.Provider = $provider
        }

        $startOutput = @(Start-Device 3>&1 | ForEach-Object { "$_" })
        $stopOutput = @(Disconnect-Device -PowerOff 3>&1 | ForEach-Object { "$_" })
        $startOutput | Should -Be @(
            'iOSSimulator: No simulator selected. Call Connect() first.'
            'Device power on failed.'
        )
        $stopOutput | Should -Be @(
            'iOSSimulator: No simulator selected. Call Connect() first.'
            'Device power off failed.'
            'Disconnected from device'
        )
    }

    It 'Reports power-off failure alongside the simulator shutdown error' {
        & (Get-Module SentryAppRunner) {
            # Bypass host and SDK checks to exercise failure reporting without a simulator.
            $provider = [System.Runtime.CompilerServices.RuntimeHelpers]::GetUninitializedObject([iOSSimulatorProvider])
            $provider.Platform = 'iOSSimulator'
            $provider.SimulatorUUID = 'test-simulator'
            $provider.Commands = @{ shutdown = [BuiltCommand]::new('& { throw "Shutdown failed" }', $null) }
            $provider.Timeouts = @{}
            $script:CurrentSession.Provider = $provider
        }

        $output = @(Disconnect-Device -PowerOff 3>&1)
        $output[0] | Should -BeOfType ([System.Management.Automation.WarningRecord])
        "$($output[0])" | Should -BeLike '*Shutdown failed*'
        $output[1] | Should -BeOfType ([System.Management.Automation.WarningRecord])
        "$($output[1])" | Should -Be 'Device power off failed.'
        $output | Should -Not -Contain 'Device powered off'
        $output | Should -Not -Contain 'Device power off not supported. Skipped.'
        Get-DeviceSession | Should -BeNullOrEmpty
    }
}
