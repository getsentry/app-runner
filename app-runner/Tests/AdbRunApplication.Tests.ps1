$ErrorActionPreference = 'Stop'

BeforeAll {
    . "$PSScriptRoot\..\Private\DeviceProviders\DeviceProvider.ps1"
    . "$PSScriptRoot\..\Private\DeviceProviders\AdbProvider.ps1"

    Invoke-Expression @'
class FakeAdbProvider : AdbProvider {
    [System.Collections.Generic.List[string]]$Calls = [System.Collections.Generic.List[string]]::new()
    [bool]$Hangs = $false
    [bool]$ForceStopFails = $false
    [int]$PidofCalls = 0

    FakeAdbProvider() : base() {
        $this.DeviceSerial = 'emulator-5554'
        $this.Timeouts['run-timeout'] = 1
        $this.Timeouts['pid-retry'] = 1
        $this.Timeouts['process-check-interval'] = 0
    }

    [object] InvokeCommand([string]$action, [object[]]$parameters) {
        $this.Calls.Add($action)
        switch ($action) {
            'force-stop' { if ($this.ForceStopFails) { throw 'adb: device offline' } }
            'launch' { return 'Status: ok' }
            'pidof' {
                $this.PidofCalls++
                if ($this.Hangs -or $this.PidofCalls -eq 1) { return '4056' }
                return $null
            }
            'logcat-pid' { return @('10-20 08:14:04.782  4056  4056 I IL2CPP  : JNI_OnLoad') }
        }
        return $null
    }
}
'@
}

Describe 'AdbProvider.RunApplication' -Tag 'Unit' {
    It 'Force-stops the package before launching it' {
        $provider = [FakeAdbProvider]::new()

        $provider.RunApplication('com.example.app/.MainActivity', @(), $null, $null) | Out-Null

        $provider.Calls[0] | Should -Be 'force-stop'
        $provider.Calls.IndexOf('force-stop') | Should -BeLessThan $provider.Calls.IndexOf('launch')
        @($provider.Calls | Where-Object { $_ -eq 'force-stop' }).Count | Should -Be 1
    }

    It 'Force-stops the package after a run timeout, once its logs are read' {
        $provider = [FakeAdbProvider]::new()
        $provider.Hangs = $true

        $result = $provider.RunApplication('com.example.app/.MainActivity', @(), $null, $null)

        $provider.Calls[-1] | Should -Be 'force-stop'
        $provider.Calls[-2] | Should -Be 'logcat-pid'
        $result.Output | Should -Contain '10-20 08:14:04.782  4056  4056 I IL2CPP  : JNI_OnLoad'
    }

    It 'Still launches when force-stop fails' {
        $provider = [FakeAdbProvider]::new()
        $provider.ForceStopFails = $true

        $provider.RunApplication('com.example.app/.MainActivity', @(), $null, $null) 3>$null | Out-Null

        $provider.Calls | Should -Contain 'launch'
    }
}
