# Example: Session-Only Console Workflow
# This example demonstrates the session-only workflow where all functions require an active session

# Import the module
Import-Module ./SentryAppRunner.psd1 -Force

Write-Host '=== Session-Only Console Workflow Example ===' -ForegroundColor Cyan

try {
    # Step 1: Connect to a console platform
    Write-Host "`n1. Connecting to Xbox console..." -ForegroundColor Green
    # Xbox can auto-discover or connect to specific devkit:
    Connect-Console -Platform 'Xbox'  # Auto-discovers available Xbox devkit
    # Connect-Console -Platform 'Xbox' -Target '192.168.1.100'  # Specific IP
    # Connect-Console -Platform 'Xbox' -Target 'NetHostName'   # Specific name

    # Other platforms also auto-discover devkits:
    # Connect-Console -Platform 'PlayStation5'
    # Connect-Console -Platform 'Switch'

    # Step 2: Check session status
    $session = Get-ConsoleSession
    Write-Host "   Connected to: $($session.Platform)" -ForegroundColor Yellow
    Write-Host "   Console: $($session.Identifier)" -ForegroundColor Yellow

    # Step 3: Test connection health (session-aware)
    Write-Host "`n2. Testing connection health..." -ForegroundColor Green
    if (Test-ConsoleConnection) {
        Write-Host '   Console connection is healthy' -ForegroundColor Green
    } else {
        Write-Host '   Console connection issues detected' -ForegroundColor Red
    }

    # Step 4: Console lifecycle operations (session-aware)
    Write-Host "`n3. Console lifecycle operations..." -ForegroundColor Green
    Get-ConsoleStatus

    # Step 5: Run an application (session-aware)
    Write-Host "`n4. Running application..." -ForegroundColor Green
    $result = Invoke-ConsoleApp -ExecutablePath 'MyTestGame.exe' -Arguments '--debug --level=verbose'
    Write-Host "   Application started successfully on $($result.Platform)" -ForegroundColor Green

    # Step 6: Collect diagnostics (all session-aware)
    Write-Host "`n5. Collecting diagnostics..." -ForegroundColor Green
    Get-ConsoleLogs -LogType 'Error' -MaxEntries 100

    Get-ConsoleScreenshot -OutputPath 'game_screenshot.png'

    Get-ConsoleDiagnostics -IncludePerformanceMetrics

} finally {
    # Step 7: Always disconnect when done
    Write-Host "`n6. Disconnecting from console..." -ForegroundColor Green
    Disconnect-Console
    Write-Host '   Workflow completed!' -ForegroundColor Green
}

# Demonstrate that functions fail without session
Write-Host "`n=== Demonstrating Session Requirements ===" -ForegroundColor Cyan
Write-Host 'Attempting to use functions without session (should fail)...' -ForegroundColor Yellow

$functionTests = @(
    'Get-ConsoleStatus',
    'Start-Console',
    'Get-ConsoleLogs',
    "Get-ConsoleScreenshot -OutputPath 'test.png'",
    "Invoke-ConsoleApp -ExecutablePath 'test.exe'"
)

foreach ($test in $functionTests) {
    try {
        Invoke-Expression $test
    } catch {
        Write-Host "   ✓ $test correctly failed: No active console session" -ForegroundColor Green
    }
}

# Example of switching between platforms
Write-Host "`n=== Platform Switching Example ===" -ForegroundColor Cyan

# Connect to PlayStation 5
Write-Host 'Connecting to PlayStation 5...' -ForegroundColor Green
Connect-Console -Platform 'PlayStation5'
Write-Host "   Now connected to: $((Get-ConsoleSession).Platform)" -ForegroundColor Yellow

# Switch to Switch console (disconnects automatically)
Write-Host 'Switching to Nintendo Switch...' -ForegroundColor Green
Connect-Console -Platform 'Switch'
Write-Host "   Now connected to: $((Get-ConsoleSession).Platform)" -ForegroundColor Yellow

# Clean up
Disconnect-Console
Write-Host "`nAll done! Session-only workflow demonstrated successfully." -ForegroundColor Green
