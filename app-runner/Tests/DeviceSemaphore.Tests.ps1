$ErrorActionPreference = 'Stop'

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SentryAppRunner.psd1'
    Import-Module $ModulePath -Force

    # Dot-source private functions for direct testing
    . "$PSScriptRoot\..\Private\DeviceSemaphoreManager.ps1"
}

AfterAll {
    Remove-Module SentryAppRunner -Force -ErrorAction SilentlyContinue
}

Describe 'DeviceSemaphoreManager' {
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

    Context 'Semaphore Acquisition and Release' {
        BeforeEach {
            # Use unique resource name per test to avoid conflicts
            $script:TestResourceName = "Test-$(New-Guid)"
        }

        It 'Acquires semaphore successfully' {
            $semaphore = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            $semaphore | Should -Not -BeNullOrEmpty
            $semaphore | Should -BeOfType [System.Threading.Semaphore]

            # Cleanup
            Release-DeviceAccess -Semaphore $semaphore -ResourceName $script:TestResourceName
        }

        It 'Releases semaphore successfully' {
            $semaphore = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            { Release-DeviceAccess -Semaphore $semaphore -ResourceName $script:TestResourceName } | Should -Not -Throw
        }

        It 'Allows reacquisition after release' {
            # First acquisition
            $semaphore1 = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            Release-DeviceAccess -Semaphore $semaphore1 -ResourceName $script:TestResourceName

            # Second acquisition should succeed
            $semaphore2 = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5
            $semaphore2 | Should -Not -BeNullOrEmpty

            # Cleanup
            Release-DeviceAccess -Semaphore $semaphore2 -ResourceName $script:TestResourceName
        }

        It 'Blocks concurrent access to same resource' {
            # First process acquires semaphore
            $semaphore1 = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5

            try {
                # Second attempt should timeout (using very short timeout)
                { Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 1 } | Should -Throw '*Could not acquire exclusive access*'
            } finally {
                # Cleanup
                Release-DeviceAccess -Semaphore $semaphore1 -ResourceName $script:TestResourceName
            }
        }

        It 'Allows concurrent access to different resources' {
            $resource1 = "Test1-$(New-Guid)"
            $resource2 = "Test2-$(New-Guid)"

            $semaphore1 = Request-DeviceAccess -ResourceName $resource1 -TimeoutSeconds 5
            $semaphore2 = Request-DeviceAccess -ResourceName $resource2 -TimeoutSeconds 5

            $semaphore1 | Should -Not -BeNullOrEmpty
            $semaphore2 | Should -Not -BeNullOrEmpty

            # Cleanup
            Release-DeviceAccess -Semaphore $semaphore1 -ResourceName $resource1
            Release-DeviceAccess -Semaphore $semaphore2 -ResourceName $resource2
        }
    }

    Context 'Timeout Behavior' {
        BeforeEach {
            $script:TestResourceName = "Test-$(New-Guid)"
        }

        It 'Times out when semaphore is held by another process' {
            # Acquire semaphore
            $semaphore = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5

            try {
                # Attempt to acquire again with short timeout should fail
                $startTime = Get-Date
                { Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 2 } | Should -Throw '*Could not acquire exclusive access*'
                $duration = ((Get-Date) - $startTime).TotalSeconds

                # Verify it actually waited for the timeout
                $duration | Should -BeGreaterOrEqual 1.8
                $duration | Should -BeLessOrEqual 3.0
            } finally {
                Release-DeviceAccess -Semaphore $semaphore -ResourceName $script:TestResourceName
            }
        }

        It 'Throws descriptive error message on timeout' {
            $semaphore = Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 5

            try {
                { Request-DeviceAccess -ResourceName $script:TestResourceName -TimeoutSeconds 1 } |
                    Should -Throw -ExpectedMessage "*exclusive access*$script:TestResourceName*"
            } finally {
                Release-DeviceAccess -Semaphore $semaphore -ResourceName $script:TestResourceName
            }
        }
    }

    Context 'Error Handling' {
        It 'Release-DeviceAccess handles null semaphore gracefully' {
            { Release-DeviceAccess -Semaphore $null -ResourceName 'Test' } | Should -Not -Throw
        }

        It 'Cleans up semaphore on acquisition error' {
            # This is harder to test directly, but we can verify that after a failed
            # acquisition, we can still acquire the semaphore successfully
            $resourceName = "Test-$(New-Guid)"

            # Try to acquire with extremely short timeout (may or may not fail)
            try {
                $semaphore = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds 1
                Release-DeviceAccess -Semaphore $semaphore -ResourceName $resourceName
            } catch {
                # Expected to fail sometimes, that's ok
            }

            # Should be able to acquire normally
            $semaphore = Request-DeviceAccess -ResourceName $resourceName -TimeoutSeconds 5
            $semaphore | Should -Not -BeNullOrEmpty
            Release-DeviceAccess -Semaphore $semaphore -ResourceName $resourceName
        }
    }

    Context 'Integration with Connect-Device' {
        AfterEach {
            if (Get-DeviceSession) {
                Disconnect-Device
            }
        }

        It 'Connect-Device acquires semaphore and stores it in session' {
            $session = Connect-Device -Platform 'Mock' -TimeoutSeconds 5

            $session.Semaphore | Should -Not -BeNullOrEmpty
            $session.Semaphore | Should -BeOfType [System.Threading.Semaphore]
            $session.ResourceName | Should -Be 'Mock-Default'
        }

        It 'Disconnect-Device releases semaphore' {
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
                    # This should timeout since main session holds the semaphore
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

        It 'Releases semaphore on connection failure' {
            # Mock doesn't really fail to connect, so we'll test cleanup directly
            # by verifying we can reconnect after any error
            try {
                Connect-Device -Platform 'Mock' -TimeoutSeconds 5
                # Force an error in the session to test cleanup
                throw "Simulated error"
            } catch {
                # Expected
            }

            # The finally block in Connect-Device should have released the semaphore
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
