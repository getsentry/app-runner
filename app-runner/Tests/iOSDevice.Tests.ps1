$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    $TestTargets = @()

    if ($IsMacOS -and (Get-Command 'xcrun' -ErrorAction SilentlyContinue)) {
        $jsonFile = New-TemporaryFile
        try {
            & xcrun devicectl list devices --filter "State == 'connected' OR State BEGINSWITH 'available'" --timeout 10 --json-output $jsonFile.FullName --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $devices = @((Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json).result.devices |
                        Where-Object {
                            $_.hardwareProperties.platform -eq 'iOS' -and
                            $_.connectionProperties.pairingState -eq 'paired' -and
                            $_.deviceProperties.developerModeStatus -eq 'enabled'
                        })
                if ($devices.Count -gt 0) {
                    $TestTargets += @{
                        Platform = 'iOSDevice'
                        Target   = $devices[0].identifier
                    }
                }
            }
        } finally {
            Remove-Item $jsonFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}
BeforeAll {
    Import-Module "$PSScriptRoot\..\SentryAppRunner.psm1" -Force
}

Describe 'iOSDevice' -Tag 'iOSDevice' -ForEach $TestTargets {
    AfterEach {
        if (Get-DeviceSession) {
            Disconnect-Device
        }
    }

    It 'connects to a selected physical device' {
        Connect-Device -Platform $Platform -Target $Target | Out-Null

        $session = Get-DeviceSession
        $session.Platform | Should -Be 'iOSDevice'
        $session.Identifier | Should -Be $Target
        $session.IsConnected | Should -BeTrue
    }

    It 'reports the selected physical device as online' {
        Connect-Device -Platform $Platform -Target $Target | Out-Null

        (Get-DeviceStatus).Status | Should -Be 'Online'
        Test-DeviceConnection | Should -BeTrue
    }

    It 'stays online while connected by CoreDevice' {
        Connect-Device -Platform $Platform -Target $Target | Out-Null
        $jsonFile = New-TemporaryFile
        try {
            & xcrun devicectl device info apps --device $Target --timeout 10 --json-output $jsonFile.FullName --quiet 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0

            (Get-DeviceStatus).Status | Should -Be 'Online'
            Test-DeviceConnection | Should -BeTrue
        } finally {
            Remove-Item $jsonFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}
