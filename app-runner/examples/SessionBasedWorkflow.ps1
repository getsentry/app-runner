# Example: Session-Only Device Workflow
# This example demonstrates the session-only workflow where all functions require an active session

# Import the module
Import-Module ./SentryAppRunner.psd1 -Force

Write-Host '=== Session-Only Device Workflow Example ===' -ForegroundColor Cyan

try {
    # Step 1: Connect to a device platform
    Write-Host "`n1. Connecting to Xbox device..." -ForegroundColor Green
    # Xbox can auto-discover or connect to specific devkit:
    Connect-Device -Platform 'Xbox'  # Auto-discovers available Xbox devkit
    # Connect-Device -Platform 'Xbox' -Target '192.168.1.100'  # Specific IP
    # Connect-Device -Platform 'Xbox' -Target 'NetHostName'   # Specific name

    # Other platforms also auto-discover devkits:
    # Connect-Device -Platform 'PlayStation5'
    # Connect-Device -Platform 'Switch'

    # Step 2: Check session status
    $session = Get-DeviceSession
    Write-Host "   Connected to: $($session.Platform)" -ForegroundColor Yellow
    Write-Host "   Device: $($session.Identifier)" -ForegroundColor Yellow

    # Step 3: Test connection health (session-aware)
    Write-Host "`n2. Testing connection health..." -ForegroundColor Green
    if (Test-DeviceConnection) {
        Write-Host '   Device connection is healthy' -ForegroundColor Green
    } else {
        Write-Host '   Device connection issues detected' -ForegroundColor Red
    }

    # Step 4: Device lifecycle operations (session-aware)
    Write-Host "`n3. Device lifecycle operations..." -ForegroundColor Green
    Get-DeviceStatus

    # Step 5: Run an application (session-aware)
    Write-Host "`n4. Running application..." -ForegroundColor Green
    $result = Invoke-DeviceApp -ExecutablePath 'MyTestGame.exe' -Arguments @('--debug', '--level=verbose')
    Write-Host "   Application started successfully on $($result.Platform)" -ForegroundColor Green

    # Step 6: Collect diagnostics (all session-aware)
    Write-Host "`n5. Collecting diagnostics..." -ForegroundColor Green
    Get-DeviceDiagnostics

} finally {
    # Step 7: Always disconnect when done
    Write-Host "`n6. Disconnecting from device..." -ForegroundColor Green
    Disconnect-Device
    Write-Host '   Workflow completed!' -ForegroundColor Green
}

# Demonstrate that functions fail without session
Write-Host "`n=== Demonstrating Session Requirements ===" -ForegroundColor Cyan
Write-Host 'Attempting to use functions without session (should fail)...' -ForegroundColor Yellow

$functionTests = @(
    'Get-DeviceStatus',
    'Start-Device',
    'Get-DeviceLogs',
    "Get-DeviceScreenshot -OutputPath 'test.png'",
    "Invoke-DeviceApp -ExecutablePath 'test.exe'"
)

foreach ($test in $functionTests) {
    try {
        Invoke-Expression $test
    } catch {
        Write-Host "   ✓ $test correctly failed: No active device session" -ForegroundColor Green
    }
}

# Example of switching between platforms
Write-Host "`n=== Platform Switching Example ===" -ForegroundColor Cyan

# Connect to PlayStation 5
Write-Host 'Connecting to PlayStation 5...' -ForegroundColor Green
Connect-Device -Platform 'PlayStation5'
Write-Host "   Now connected to: $((Get-DeviceSession).Platform)" -ForegroundColor Yellow

# Switch to Switch device (disconnects automatically)
Write-Host 'Switching to Nintendo Switch...' -ForegroundColor Green
Connect-Device -Platform 'Switch'
Write-Host "   Now connected to: $((Get-DeviceSession).Platform)" -ForegroundColor Yellow

# Clean up
Disconnect-Device
Write-Host "`nAll done! Session-only workflow demonstrated successfully." -ForegroundColor Green
