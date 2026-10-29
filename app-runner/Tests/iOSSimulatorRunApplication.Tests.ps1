$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    $skip = -not $IsMacOS -or -not (Get-Command 'xcrun' -ErrorAction SilentlyContinue)
}

BeforeAll {
    . "$PSScriptRoot\..\Private\DeviceProviders\DeviceProvider.ps1"
    . "$PSScriptRoot\..\Private\DeviceProviders\iOSSimulatorProvider.ps1"

    Invoke-Expression @'
class FakeiOSSimulatorProvider : iOSSimulatorProvider {
    [System.Collections.Generic.List[string]]$Calls = [System.Collections.Generic.List[string]]::new()
    [bool]$TerminateHangs = $false
    [bool]$Booted = $false

    FakeiOSSimulatorProvider() : base() {
        $this.SimulatorUUID = 'E952A9B0-CC78-435C-BF08-06AD47FE1076'
    }

    [bool] InvokeXcrun([string[]]$arguments, [int]$timeoutSeconds) {
        $this.Calls.Add($arguments[1])
        return -not ($this.TerminateHangs -and $arguments[1] -eq 'terminate')
    }

    [object] InvokeCommand([string]$action, [object[]]$parameters) {
        $this.Calls.Add($action)
        switch ($action) {
            'boot' {
                if ($this.Booted) { throw 'Command (boot) failed with exit code 149' }
                $this.Booted = $true
            }
            'shutdown' { $this.Booted = $false }
            'list-devices' {
                $state = if ($this.Booted) { 'Booted' } else { 'Shutdown' }
                return @('-- iOS 26.0 --', "    iPhone 17 Pro ($($this.SimulatorUUID)) ($state)")
            }
        }
        return $null
    }

    [int] TerminateCount() {
        return @($this.Calls | Where-Object { $_ -eq 'terminate' }).Count
    }
}
'@
}

Describe 'iOSSimulatorProvider.PrepareLaunch' -Tag 'Unit' -Skip:$skip {
    It 'Skips terminate on the first launch after a boot only' {
        $provider = [FakeiOSSimulatorProvider]::new()
        $provider.StartDevice() | Out-Null

        $provider.PrepareLaunch('com.example.app') | Should -BeNullOrEmpty
        $provider.TerminateCount() | Should -Be 0

        $provider.PrepareLaunch('com.example.app') | Should -BeNullOrEmpty
        $provider.TerminateCount() | Should -Be 1
    }

    It 'Skips terminate again after the simulator was restarted' {
        $provider = [FakeiOSSimulatorProvider]::new()
        $provider.StartDevice() | Out-Null
        $provider.PrepareLaunch('com.example.app') | Out-Null
        $provider.PrepareLaunch('com.example.app') | Out-Null

        $provider.RestartDevice()
        $provider.PrepareLaunch('com.example.app') | Out-Null

        $provider.TerminateCount() | Should -Be 1
    }

    It 'Keeps the fresh boot when the simulator is started again' {
        $provider = [FakeiOSSimulatorProvider]::new()
        $provider.StartDevice() | Out-Null
        $provider.StartDevice() | Out-Null

        $provider.PrepareLaunch('com.example.app') | Out-Null

        $provider.TerminateCount() | Should -Be 0
    }

    It 'Terminates on the first launch when the simulator was already booted' {
        $provider = [FakeiOSSimulatorProvider]::new()
        $provider.Booted = $true
        $provider.Connect($provider.SimulatorUUID) | Out-Null

        $provider.PrepareLaunch('com.example.app') | Out-Null

        $provider.TerminateCount() | Should -Be 1
    }

    It 'Forgets the fresh boot on disconnect' {
        $provider = [FakeiOSSimulatorProvider]::new()
        $provider.StartDevice() | Out-Null

        $provider.Disconnect()

        $provider.FreshlyBooted | Should -BeFalse
    }

    It 'Lets launch terminate the app when terminate does not finish' {
        $provider = [FakeiOSSimulatorProvider]::new()
        $provider.TerminateHangs = $true

        $options = $provider.PrepareLaunch('com.example.app') 3>$null

        $options | Should -Be @('--terminate-running-process')
    }
}

Describe 'iOSSimulatorProvider.InvokeXcrun' -Tag 'Unit' -Skip:$skip {
    It 'Stops a command that does not exit in time' {
        $provider = [iOSSimulatorProvider]::new()
        $start = Get-Date

        $provider.InvokeXcrun(@('sleep', '30'), 1) | Should -BeFalse

        ((Get-Date) - $start).TotalSeconds | Should -BeLessThan 10
    }

    It 'Returns true when the command exits, whatever its exit code' {
        $provider = [iOSSimulatorProvider]::new()

        $provider.InvokeXcrun(@('false'), 10) | Should -BeTrue
    }
}
