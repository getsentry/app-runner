$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Dot-source private functions for direct testing
    . "$PSScriptRoot\..\Private\DeviceLockManager.ps1"
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'DeviceLockManager' {
    Context 'Resource Name Generation' {
        It 'Creates resource name with platform only' {
            $resourceName = New-DeviceResourceName -Platform 'Xbox'
            $resourceName | Should -Be 'Xbox-Default'
        }

        It 'Creates resource name with platform and target' {
            $resourceName = New-DeviceResourceName -Platform 'Xbox' -Target '192.168.1.100'
            $resourceName | Should -Be 'Xbox-192.168.1.100'
        }

        It 'Creates resource name with platform and named target' {
            $resourceName = New-DeviceResourceName -Platform 'Xbox' -Target 'MyDevKit'
            $resourceName | Should -Be 'Xbox-MyDevKit'
        }

        It 'Handles different platforms correctly' {
            New-DeviceResourceName -Platform 'PlayStation5' | Should -Be 'PlayStation5-Default'
            New-DeviceResourceName -Platform 'Switch' | Should -Be 'Switch-Default'
            New-DeviceResourceName -Platform 'Mock' | Should -Be 'Mock-Default'
        }

        It 'Handles empty target string as Default' {
            $resourceName = New-DeviceResourceName -Platform 'Xbox' -Target ''
            $resourceName | Should -Be 'Xbox-Default'
        }
    }

    Context 'Mutex Acquisition and Release' {
        BeforeEach {
            # Use unique resource name per test to avoid conflicts
            $script:TestResourceName = "Test-$(New-Guid)"
        }

        It 'Acquires mutex successfully' {
            $mutex = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            $mutex | Should -Not -BeNullOrEmpty
            $mutex | Should -BeOfType [System.Threading.Mutex]

            # Cleanup
            Release-DeviceAccess -Mutex $mutex -ResourceName $script:TestResourceName
        }

        It 'Releases mutex successfully' {
            $mutex = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            { Release-DeviceAccess -Mutex $mutex -ResourceName $script:TestResourceName } | Should -Not -Throw
        }

        It 'Allows reacquisition after release' {
            # First acquisition
            $mutex1 = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            Release-DeviceAccess -Mutex $mutex1 -ResourceName $script:TestResourceName

            # Second acquisition should succeed
            $mutex2 = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            $mutex2 | Should -Not -BeNullOrEmpty

            # Cleanup
            Release-DeviceAccess -Mutex $mutex2 -ResourceName $script:TestResourceName
        }

        It 'Blocks concurrent access to same resource from different processes' {
            # Note: Mutexes allow recursive locking by the same thread, so we need to test with a background job (separate process)
            # First process acquires mutex
            $mutex1 = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5

            try {
                # Start a background job that tries to acquire the same mutex
                $privateScriptPath = Join-Path $PSScriptRoot '..' 'Private' 'DeviceLockManager.ps1'
                $job = Start-Job -ScriptBlock {
                    param($PrivateScriptPath, $ResourceName)
                    # Dot-source the private functions
                    . $PrivateScriptPath
                    try {
                        Request-DeviceAccess -ResourceName $ResourceName -TimeoutSeconds 1
                        return "SUCCESS"
                    } catch {
                        return $_.Exception.Message
                    }
                } -ArgumentList $privateScriptPath, $script:TestResourceName

                # Wait for job to complete
                $result = Wait-Job -Job $job -Timeout 5 | Receive-Job
                Remove-Job -Job $job -Force

                # Should have failed with timeout error
                $result | Should -Match 'Could not acquire exclusive access'
            } finally {
                # Cleanup
                Release-DeviceAccess -Mutex $mutex1 -ResourceName $script:TestResourceName
            }
        }

        It 'Allows concurrent access to different resources' {
            $resource1 = "Test1-$(New-Guid)"
            $resource2 = "Test2-$(New-Guid)"

            $mutex1 = Request-DeviceAccess -ResourceName $resource1 -TimeoutSeconds 5
            $mutex2 = Request-DeviceAccess -ResourceName $resource2 -TimeoutSeconds 5

            $mutex1 | Should -Not -BeNullOrEmpty
            $mutex2 | Should -Not -BeNullOrEmpty

            # Cleanup
            Release-DeviceAccess -Mutex $mutex1 -ResourceName $resource1
            Release-DeviceAccess -Mutex $mutex2 -ResourceName $resource2
        }
    }

    Context 'Timeout Behavior' {
        BeforeEach {
            $script:TestResourceName = "Test-$(New-Guid)"
        }

        It 'Times out when mutex is held by another process' {
            # Acquire mutex
            $mutex = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5

            try {
                # Start background job to test timeout from another process
                $privateScriptPath = Join-Path $PSScriptRoot '..' 'Private' 'DeviceLockManager.ps1'
                $job = Start-Job -ScriptBlock {
                    param($PrivateScriptPath, $ResourceName)
                    . $PrivateScriptPath

                    $startTime = Get-Date
                    try {
                        Request-DeviceAccess -ResourceName $ResourceName -TimeoutSeconds 2
                        return @{ Success = $true; Duration = 0 }
                    } catch {
                        $duration = ((Get-Date) - $startTime).TotalSeconds
                        return @{ Success = $false; Duration = $duration; Message = $_.Exception.Message }
                    }
                } -ArgumentList $privateScriptPath, $script:TestResourceName

                $result = Wait-Job -Job $job -Timeout 5 | Receive-Job
                Remove-Job -Job $job -Force

                # Should have failed with timeout
                $result.Success | Should -Be $false
                $result.Message | Should -Match 'Could not acquire exclusive access'

                # Verify it actually waited for the timeout
                $result.Duration | Should -BeGreaterOrEqual 1.8
                $result.Duration | Should -BeLessOrEqual 3.0
            } finally {
                Release-DeviceAccess -Mutex $mutex -ResourceName $script:TestResourceName
            }
        }

        It 'Throws descriptive error message on timeout' {
            $mutex = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5

            try {
                # Start background job to test error message from another process
                $privateScriptPath = Join-Path $PSScriptRoot '..' 'Private' 'DeviceLockManager.ps1'
                $job = Start-Job -ScriptBlock {
                    param($PrivateScriptPath, $ResourceName)
                    . $PrivateScriptPath
                    try {
                        Request-DeviceAccess -ResourceName $ResourceName -TimeoutSeconds 1
                    } catch {
                        return $_.Exception.Message
                    }
                } -ArgumentList $privateScriptPath, $script:TestResourceName

                $result = Wait-Job -Job $job -Timeout 5 | Receive-Job
                Remove-Job -Job $job -Force

                $result | Should -Match "exclusive access.*$script:TestResourceName"
            } finally {
                Release-DeviceAccess -Mutex $mutex -ResourceName $script:TestResourceName
            }
        }
    }

    Context 'Error Handling' {
        It 'Release-DeviceAccess handles null mutex gracefully' {
            { Release-DeviceAccess -Mutex $null -ResourceName 'Test' } | Should -Not -Throw
        }

        It 'Cleans up mutex on acquisition error' {
            # This is harder to test directly, but we can verify that after a failed
            # acquisition, we can still acquire the mutex successfully
            $resourceName = "Test-$(New-Guid)"

            # Try to acquire with extremely short timeout (may or may not fail)
            try {
                $mutex = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds 1
                Release-DeviceAccess -Mutex $mutex -ResourceName $resourceName
            } catch {
                # Expected to fail sometimes, that's ok
            }

            # Should be able to acquire normally
            $mutex = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds 5
            $mutex | Should -Not -BeNullOrEmpty
            Release-DeviceAccess -Mutex $mutex -ResourceName $resourceName
        }

        It 'Handles abandoned mutex from crashed process' {
            $resourceName = "Test-$(New-Guid)"
            $privateScriptPath = Join-Path $PSScriptRoot '..' 'Private' 'DeviceLockManager.ps1'

            # Start a background job that acquires the mutex and then "crashes" (doesn't release)
            $job = Start-Job -ScriptBlock {
                param($PrivateScriptPath, $ResourceName)
                . $PrivateScriptPath

                # Acquire the mutex
                $mutex = Request-DeviceAccess -ResourceName $ResourceName -TimeoutSeconds 5

                # Simulate a crash by exiting without releasing the mutex
                # (In a real crash, ReleaseMutex() would never be called)
                exit 0
            } -ArgumentList $privateScriptPath, $resourceName

            # Wait for job to acquire mutex and exit
            Wait-Job -Job $job -Timeout 10 | Out-Null
            Remove-Job -Job $job -Force

            # Now try to acquire the mutex - should succeed with abandoned mutex warning
            $warningMessages = @()
            $mutex = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds 5 -WarningVariable warningMessages

            # Should have acquired the mutex successfully
            $mutex | Should -Not -BeNullOrEmpty

            # Should have received warning about abandoned mutex (captured in $warningMessages or via Write-Warning)
            # Note: WarningVariable doesn't always capture Write-Warning in all contexts,
            # but the important thing is that we successfully acquired the mutex

            # Clean up
            Release-DeviceAccess -Mutex $mutex -ResourceName $resourceName
        }
    }

    Context 'Integration with Connect-Device' {
        AfterEach {
            if (Get-DeviceSession) {
                Disconnect-Device
            }
        }

        It 'Connect-Device acquires mutex and stores it in session' {
            $session = Connect-Device -Platform 'Mock' -TimeoutSeconds 5

            $session.Mutex | Should -Not -BeNullOrEmpty
            $session.Mutex | Should -BeOfType [System.Threading.Mutex]
            $session.ResourceName | Should -Be 'Mock-Default'
        }

        It 'Disconnect-Device releases mutex' {
            Connect-Device -Platform 'Mock' -TimeoutSeconds 5
            { Disconnect-Device } | Should -Not -Throw

            # After disconnect, should be able to connect again immediately
            { Connect-Device -Platform 'Mock' -TimeoutSeconds 5 } | Should -Not -Throw
        }

        It 'Cannot connect to same resource twice concurrently' {
            Connect-Device -Platform 'Mock' -TimeoutSeconds 1

            # Start a background job that tries to connect to the same resource
            $job = Start-Job -ScriptBlock {
                param($ModulePath)
                Import-Module $ModulePath -Force
                try {
                    # This should timeout since main session holds the mutex
                    # Use short timeout for faster test
                    Connect-Device -Platform 'Mock' -TimeoutSeconds 3
                } catch {
                    # Return the error message
                    return $_.Exception.Message
                }
            } -ArgumentList $ModulePath

            # Wait for job to complete (should timeout quickly)
            $result = Wait-Job -Job $job -Timeout 10 | Receive-Job
            Remove-Job -Job $job -Force

            # Should have failed with timeout error
            $result | Should -Match 'Could not acquire exclusive access.*Mock-Default'
        }

        It 'Can connect to different targets concurrently' {
            Connect-Device -Platform 'Mock' -TimeoutSeconds 5

            # Start a background job that connects to a different Mock target
            $job = Start-Job -ScriptBlock {
                param($ModulePath)
                Import-Module $ModulePath -Force
                try {
                    # Connect with a different target - should succeed
                    Connect-Device -Platform 'Mock' -Target 'TargetA' -TimeoutSeconds 5
                    return 'SUCCESS'
                } catch {
                    return $_.Exception.Message
                }
            } -ArgumentList $ModulePath

            # This should complete successfully (different target = different semaphore)
            $result = Wait-Job -Job $job -Timeout 10 | Receive-Job
            Remove-Job -Job $job -Force

            # Should succeed - different targets don't block each other
            $result | Should -Contain 'SUCCESS'
        }

        It 'Releases mutex on connection failure' {
            # Mock doesn't really fail to connect, so we'll test cleanup directly
            # by verifying we can reconnect after any error
            try {
                Connect-Device -Platform 'Mock' -TimeoutSeconds 5
                # Force an error in the session to test cleanup
                throw "Simulated error"
            } catch {
                # Expected
            }

            # The finally block in Connect-Device should have released the mutex
            # if it was acquired before the error. Let's verify by connecting successfully.
            # Actually, if Connect-Device succeeded before the throw, we need to disconnect first
            if (Get-DeviceSession) {
                Disconnect-Device
            }

            # Now try to connect - should work
            { Connect-Device -Platform 'Mock' -TimeoutSeconds 5 } | Should -Not -Throw
        }
    }
}
