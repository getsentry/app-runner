# Target Management Tests
# Tests the DetectAndSetDefaultTarget() state machine functionality
# Uses MockDeviceProvider to simulate various target detection scenarios

$ErrorActionPreference = 'Stop'

BeforeAll {
    # Import the device providers directly for unit testing
    . "$PSScriptRoot\..\Private\DeviceProviders\DeviceProvider.ps1"
    . "$PSScriptRoot\..\Private\DeviceProviders\MockDeviceProvider.ps1"
}

Describe 'DetectAndSetDefaultTarget' {
    Context 'State 0: Default Target Already Set' {
        It 'Should exit immediately when default target is already set' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('DefaultSet')

            # Should not throw and should exit immediately
            { $mock.DetectAndSetDefaultTarget() } | Should -Not -Throw

            # Verify default target is still set
            $config = $mock.GetMockConfig()
            $config.Targets.DefaultTarget | Should -Not -BeNullOrEmpty
            $config.Targets.DefaultTarget.IpAddress | Should -Be '192.168.1.100'
        }
    }

    Context 'State 1: One Registered Target' {
        It 'Should set the registered target as default' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('OneRegistered')

            # Verify initial state
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.RegisteredTargets.Count | Should -Be 1
            $initialConfig.Targets.DefaultTarget | Should -BeNullOrEmpty

            # Run state machine
            { $mock.DetectAndSetDefaultTarget() } | Should -Not -Throw

            # Verify the registered target was set as default
            $finalConfig = $mock.GetMockConfig()
            $finalConfig.Targets.DefaultTarget | Should -Not -BeNullOrEmpty
            $finalConfig.Targets.DefaultTarget.IpAddress | Should -Be '192.168.1.100'
        }
    }

    Context 'State 1: Multiple Registered Targets' {
        It 'Should throw when multiple targets are registered' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('MultipleRegistered')

            # Verify initial state
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.RegisteredTargets.Count | Should -Be 2

            # Should throw due to ambiguity
            { $mock.DetectAndSetDefaultTarget() } | Should -Throw '*Multiple*existing targets found*cannot auto-detect*'
        }
    }

    Context 'State 2: One Detectable Target' {
        It 'Should detect, register, and set the target as default' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('OneDetectable')

            # Verify initial state
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.RegisteredTargets.Count | Should -Be 0
            $initialConfig.Targets.DetectableTargets.Count | Should -Be 1
            $initialConfig.Targets.DefaultTarget | Should -BeNullOrEmpty

            # Run state machine
            { $mock.DetectAndSetDefaultTarget() } | Should -Not -Throw

            # Verify the target was detected, registered, and set as default
            $finalConfig = $mock.GetMockConfig()
            $finalConfig.Targets.RegisteredTargets.Count | Should -Be 1
            $finalConfig.Targets.DefaultTarget | Should -Not -BeNullOrEmpty
            $finalConfig.Targets.DefaultTarget.IpAddress | Should -Be '192.168.1.100'
        }
    }

    Context 'State 2: Multiple Detectable Targets' {
        It 'Should throw when multiple targets are detected' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('MultipleDetectable')

            # Verify initial state
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.DetectableTargets.Count | Should -Be 3

            # Should throw due to ambiguity
            { $mock.DetectAndSetDefaultTarget() } | Should -Throw '*Multiple*targets detected*cannot auto-detect*'
        }
    }

    Context 'State 2: No Targets Available' {
        It 'Should throw when no targets are detected' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('NoTargets')

            # Verify initial state
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.DetectableTargets.Count | Should -Be 0

            # Should throw with helpful message
            { $mock.DetectAndSetDefaultTarget() } | Should -Throw '*No targets detected*Please add a target manually*'
        }
    }

    Context 'Target Command Behavior' {
        It 'get-default-target returns null when no default is set' {
            $mock = [MockDeviceProvider]::new()
            $mock.ResetTargetState()

            $result = $mock.InvokeCommand('get-default-target', @())
            $result | Should -BeNullOrEmpty
        }

        It 'get-default-target returns JSON when default is set' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('DefaultSet')

            $result = $mock.InvokeCommand('get-default-target', @())
            $result | Should -Not -BeNullOrEmpty

            # Should be valid JSON
            $parsed = $result | ConvertFrom-Json
            $parsed.IpAddress | Should -Be '192.168.1.100'
        }

        It 'list-target returns empty array when no targets registered' {
            $mock = [MockDeviceProvider]::new()
            $mock.ResetTargetState()

            $result = $mock.InvokeCommand('list-target', @())
            # Should return empty array directly (not JSON)
            @($result).Count | Should -Be 0
        }

        It 'list-target returns array of targets when targets are registered' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('OneRegistered')

            $result = $mock.InvokeCommand('list-target', @())
            # Should return objects directly (not JSON)
            @($result).Count | Should -Be 1
            $result[0].IpAddress | Should -Be '192.168.1.100'
        }

        It 'detect-target returns available targets as objects' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('OneDetectable')

            $result = $mock.InvokeCommand('detect-target', @())
            # Should return objects directly (not JSON)
            @($result).Count | Should -Be 1
            $result[0].IpAddress | Should -Be '192.168.1.100'
        }

        It 'register-target adds target to registered list' {
            $mock = [MockDeviceProvider]::new()
            $mock.ResetTargetState()

            # Initially no registered targets
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.RegisteredTargets.Count | Should -Be 0

            # Register a target
            { $mock.InvokeCommand('register-target', '192.168.1.100') } | Should -Not -Throw

            # Verify target was registered
            $finalConfig = $mock.GetMockConfig()
            $finalConfig.Targets.RegisteredTargets.Count | Should -Be 1
            $finalConfig.Targets.RegisteredTargets[0].IpAddress | Should -Be '192.168.1.100'
        }

        It 'register-target throws when target is not detectable' {
            $mock = [MockDeviceProvider]::new()
            $mock.ResetTargetState()

            # Try to register a target that doesn't exist in detectable targets
            { $mock.InvokeCommand('register-target', '192.168.1.999') } | Should -Throw '*not found in detectable targets*'
        }

        It 'set-default-target sets the default from registered targets' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('OneRegistered')

            # Initially no default
            $initialConfig = $mock.GetMockConfig()
            $initialConfig.Targets.DefaultTarget | Should -BeNullOrEmpty

            # Set default
            { $mock.InvokeCommand('set-default-target', '192.168.1.100') } | Should -Not -Throw

            # Verify default was set
            $finalConfig = $mock.GetMockConfig()
            $finalConfig.Targets.DefaultTarget | Should -Not -BeNullOrEmpty
            $finalConfig.Targets.DefaultTarget.IpAddress | Should -Be '192.168.1.100'
        }

        It 'set-default-target throws when target is not registered' {
            $mock = [MockDeviceProvider]::new()
            $mock.ResetTargetState()

            # Try to set default for unregistered target
            { $mock.InvokeCommand('set-default-target', '192.168.1.100') } | Should -Throw '*not found in registered targets*'
        }
    }

    Context 'Target Scenario Configuration' {
        It 'SetTargetScenario resets state before applying scenario' {
            $mock = [MockDeviceProvider]::new()

            # Set to one scenario
            $mock.SetTargetScenario('DefaultSet')
            $config1 = $mock.GetMockConfig()
            $config1.Targets.DefaultTarget | Should -Not -BeNullOrEmpty

            # Switch to another scenario - should reset first
            $mock.SetTargetScenario('OneDetectable')
            $config2 = $mock.GetMockConfig()
            $config2.Targets.DefaultTarget | Should -BeNullOrEmpty
            $config2.Targets.RegisteredTargets.Count | Should -Be 0
            $config2.Targets.DetectableTargets.Count | Should -Be 1
        }

        It 'ResetTargetState restores initial state' {
            $mock = [MockDeviceProvider]::new()

            # Modify state
            $mock.SetTargetScenario('DefaultSet')

            # Reset
            $mock.ResetTargetState()

            # Should be back to initial state
            $config = $mock.GetMockConfig()
            $config.Targets.DefaultTarget | Should -BeNullOrEmpty
            $config.Targets.RegisteredTargets.Count | Should -Be 0
            $config.Targets.DetectableTargets.Count | Should -Be 1
            $config.Targets.DetectableTargets[0].IpAddress | Should -Be '192.168.1.100'
        }

        It 'Unknown scenario throws error' {
            $mock = [MockDeviceProvider]::new()

            { $mock.SetTargetScenario('InvalidScenario') } | Should -Throw '*Unknown target scenario*'
        }
    }

    Context 'Full State Machine Flow' {
        It 'Complete flow: detect -> register -> set default' {
            $mock = [MockDeviceProvider]::new()
            $mock.ResetTargetState()

            # Initial state: no default, no registered, one detectable
            $state0 = $mock.GetMockConfig()
            $state0.Targets.DefaultTarget | Should -BeNullOrEmpty
            $state0.Targets.RegisteredTargets.Count | Should -Be 0
            $state0.Targets.DetectableTargets.Count | Should -Be 1

            # Run the state machine
            { $mock.DetectAndSetDefaultTarget() } | Should -Not -Throw

            # Final state: target detected, registered, and set as default
            $stateFinal = $mock.GetMockConfig()
            $stateFinal.Targets.DefaultTarget | Should -Not -BeNullOrEmpty
            $stateFinal.Targets.RegisteredTargets.Count | Should -Be 1
            $stateFinal.Targets.DefaultTarget.IpAddress | Should -Be $stateFinal.Targets.RegisteredTargets[0].IpAddress
        }

        It 'Idempotent: running twice with default set is safe' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetTargetScenario('DefaultSet')

            # Run twice
            { $mock.DetectAndSetDefaultTarget() } | Should -Not -Throw
            $firstConfig = $mock.GetMockConfig()

            { $mock.DetectAndSetDefaultTarget() } | Should -Not -Throw
            $secondConfig = $mock.GetMockConfig()

            # State should be identical
            $firstConfig.Targets.DefaultTarget.IpAddress | Should -Be $secondConfig.Targets.DefaultTarget.IpAddress
        }
    }

    Context 'Error Scenarios' {
        It 'Handles command failures gracefully' {
            $mock = [MockDeviceProvider]::new()
            $mock.SetMockConfig(@{ ShouldFailCommands = $true })

            # Should throw when commands fail
            { $mock.DetectAndSetDefaultTarget() } | Should -Throw
        }
    }
}
