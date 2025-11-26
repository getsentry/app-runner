# Android SauceLabs Provider Implementation
# Provides device management for Android devices on SauceLabs Real Device Cloud

# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

# Load Android helpers
. "$PSScriptRoot\..\AndroidHelpers.ps1"

<#
.SYNOPSIS
Device provider for Android devices on SauceLabs Real Device Cloud.

.DESCRIPTION
This provider implements Android-specific device operations using SauceLabs Appium API.
It supports testing on real Android devices in the SauceLabs cloud infrastructure.

Key features:
- APK upload to SauceLabs storage
- Appium session management (create, reuse, delete)
- App execution with state monitoring
- Logcat retrieval via Appium
- Screenshot capture

Requirements:
- SauceLabs account with Real Device Cloud access
- Environment variables:
  - SAUCE_USERNAME - SauceLabs username
  - SAUCE_ACCESS_KEY - SauceLabs access key
  - SAUCE_REGION - SauceLabs region (e.g., us-west-1, eu-central-1)
  - SAUCE_DEVICE_NAME - Device name (optional if using -Target parameter)

Note: Device name must match a device available in the specified region.

Example usage:
  # Option 1: Use SAUCE_DEVICE_NAME environment variable
  Connect-Device -Platform AndroidSauceLabs

  # Option 2: Explicitly specify device name
  Connect-Device -Platform AndroidSauceLabs -Target "Samsung_Galaxy_S23_15_real_sjc1"
#>
class AndroidSauceLabsProvider : DeviceProvider {
    [string]$SessionId = $null
    [string]$StorageId = $null
    [string]$Region = $null
    [string]$DeviceName = $null
    [string]$Username = $null
    [string]$AccessKey = $null
    [string]$CurrentPackageName = $null

    AndroidSauceLabsProvider() {
        $this.Platform = 'AndroidSauceLabs'

        # Read credentials and configuration from environment
        $this.Username = $env:SAUCE_USERNAME
        $this.AccessKey = $env:SAUCE_ACCESS_KEY
        $this.Region = $env:SAUCE_REGION
        $this.DeviceName = $env:SAUCE_DEVICE_NAME  # Optional: can be overridden via -Target

        # Validate required credentials
        if (-not $this.Username -or -not $this.AccessKey) {
            throw "SAUCE_USERNAME and SAUCE_ACCESS_KEY environment variables must be set"
        }

        if (-not $this.Region) {
            throw "SAUCE_REGION environment variable must be set"
        }

        # DeviceName is optional here - will be validated in Connect()
        # Can come from either SAUCE_DEVICE_NAME env var or -Target parameter

        # No SDK path needed - uses HTTP API
        $this.SdkPath = $null

        # Configure timeouts for cloud operations
        $this.Timeouts = @{
            'upload'  = 600  # APK upload can take time
            'session' = 300  # Session creation
            'launch'  = 300  # App launch on cloud device
        }
    }

    <#
    .SYNOPSIS
    Invokes SauceLabs API requests with authentication.

    .DESCRIPTION
    Helper method for making authenticated HTTP requests to SauceLabs API.
    Follows app-runner pattern: Invoke-WebRequest + explicit ConvertFrom-Json.
    #>
    [hashtable] InvokeSauceLabsApi([string]$Method, [string]$Uri, [hashtable]$Body, [bool]$IsMultipart, [string]$FilePath) {
        if (-not $this.Username -or -not $this.AccessKey) {
            throw "SauceLabs credentials not set"
        }

        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($this.Username):$($this.AccessKey)"))
        $headers = @{
            'Authorization' = "Basic $base64Auth"
        }

        try {
            if ($IsMultipart) {
                # Use -Form parameter for multipart uploads (PowerShell Core 7+)
                $form = @{
                    payload = Get-Item -Path $FilePath
                    name    = (Split-Path $FilePath -Leaf)
                }
                $webResponse = Invoke-WebRequest -Uri $Uri -Method $Method -Headers $headers -Form $form
            }
            else {
                $params = @{
                    Uri     = $Uri
                    Method  = $Method
                    Headers = $headers
                }

                if ($Body) {
                    $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
                    $params['ContentType'] = 'application/json'
                }

                $webResponse = Invoke-WebRequest @params
            }

            # Explicit JSON parsing for better error visibility
            if ($webResponse.Content) {
                return $webResponse.Content | ConvertFrom-Json -AsHashtable
            }
            return $null
        }
        catch {
            $ErrorMessage = "SauceLabs API request ($Method $Uri) failed: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $StatusCode = $_.Exception.Response.StatusCode
                $ErrorMessage += " (Status: $StatusCode)"
            }
            throw $ErrorMessage
        }
    }

    [hashtable] Connect() {
        # Use device name from SAUCE_DEVICE_NAME environment variable
        if (-not $this.DeviceName) {
            throw "$($this.Platform) requires a device name. Set SAUCE_DEVICE_NAME environment variable or use Connect-Device -Platform AndroidSauceLabs -Target 'DeviceName'"
        }

        Write-Debug "$($this.Platform): Connecting with device name from env: $($this.DeviceName)"

        # Note: APK upload and session creation happen in InstallApp
        # because we need the APK path before creating an Appium session

        return @{
            Provider    = $this
            Platform    = $this.Platform
            ConnectedAt = Get-Date
            Identifier  = $this.DeviceName
            IsConnected = $true
            StatusData  = @{
                DeviceName = $this.DeviceName
                Region     = $this.Region
                Username   = $this.Username
            }
        }
    }

    [hashtable] Connect([string]$target) {
        # Explicit target provided - use it directly (no fallback)
        if (-not $target) {
            throw "$($this.Platform): Connect() called with empty target parameter"
        }

        Write-Debug "$($this.Platform): Connecting with explicit device name: $target"

        # Store the device name for session creation
        $this.DeviceName = $target

        # Note: APK upload and session creation happen in InstallApp
        # because we need the APK path before creating an Appium session

        return @{
            Provider    = $this
            Platform    = $this.Platform
            ConnectedAt = Get-Date
            Identifier  = $target
            IsConnected = $true
            StatusData  = @{
                DeviceName = $target
                Region     = $this.Region
                Username   = $this.Username
            }
        }
    }

    [void] Disconnect() {
        Write-Debug "$($this.Platform): Disconnecting"

        if ($this.SessionId) {
            Write-Host "Ending SauceLabs session..." -ForegroundColor Yellow
            try {
                $sessionUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"
                $this.InvokeSauceLabsApi('DELETE', $sessionUri, $null, $false, $null)
                Write-Host "Session ended successfully" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to end session: $_"
            }
            $this.SessionId = $null
        }

        $this.StorageId = $null
        $this.DeviceName = $null
        $this.CurrentPackageName = $null
    }

    [bool] TestConnection() {
        Write-Debug "$($this.Platform): Testing connection"

        # Check if we have valid credentials and session
        if ($this.SessionId) {
            try {
                $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"
                $response = $this.InvokeSauceLabsApi('GET', $baseUri, $null, $false, $null)
                return $null -ne $response
            }
            catch {
                return $false
            }
        }

        return $null -ne $this.Username -and $null -ne $this.AccessKey
    }

    [hashtable] InstallApp([string]$PackagePath) {
        Write-Debug "$($this.Platform): Installing APK: $PackagePath"

        # Validate APK file
        if (-not (Test-Path $PackagePath)) {
            throw "APK file not found: $PackagePath"
        }

        if ($PackagePath -notlike '*.apk') {
            throw "Package must be an .apk file. Got: $PackagePath"
        }

        # Upload APK to SauceLabs Storage
        Write-Host "Uploading APK to SauceLabs Storage..." -ForegroundColor Yellow
        $uploadUri = "https://api.$($this.Region).saucelabs.com/v1/storage/upload"

        $uploadResponse = $this.InvokeSauceLabsApi('POST', $uploadUri, $null, $true, $PackagePath)

        if (-not $uploadResponse.item.id) {
            throw "Failed to upload APK: No storage ID in response"
        }

        $this.StorageId = $uploadResponse.item.id
        Write-Host "APK uploaded successfully. Storage ID: $($this.StorageId)" -ForegroundColor Green

        # Create Appium session with uploaded APK
        Write-Host "Creating SauceLabs Appium session..." -ForegroundColor Yellow
        $sessionUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session"

        $capabilities = @{
            capabilities = @{
                alwaysMatch = @{
                    platformName            = 'Android'
                    'appium:app'            = "storage:$($this.StorageId)"
                    'appium:deviceName'     = $this.DeviceName
                    'appium:automationName' = 'UiAutomator2'
                    'appium:noReset'        = $true
                    'appium:autoLaunch'     = $false
                    'sauce:options'         = @{
                        name          = "App Runner Android Test"
                        appiumVersion = 'latest'
                    }
                }
            }
        }

        $sessionResponse = $this.InvokeSauceLabsApi('POST', $sessionUri, $capabilities, $false, $null)

        # Extract session ID (response format varies)
        $this.SessionId = $sessionResponse.value.sessionId
        if (-not $this.SessionId) {
            $this.SessionId = $sessionResponse.sessionId
        }

        if (-not $this.SessionId) {
            throw "Failed to create session: No session ID in response"
        }

        Write-Host "Session created successfully. Session ID: $($this.SessionId)" -ForegroundColor Green

        return @{
            StorageId   = $this.StorageId
            SessionId   = $this.SessionId
            PackagePath = $PackagePath
            DeviceName  = $this.DeviceName
        }
    }

    [hashtable] RunApplication([string]$ExecutablePath, [string]$Arguments) {
        Write-Debug "$($this.Platform): Running application: $ExecutablePath"

        if (-not $this.SessionId) {
            throw "No active SauceLabs session. Call InstallApp first to create a session."
        }

        # Parse ExecutablePath: "package.name/activity.name"
        $parsed = Parse-AndroidActivity -ExecutablePath $ExecutablePath
        $packageName = $parsed.PackageName
        $activityName = $parsed.ActivityName
        $this.CurrentPackageName = $packageName

        # Validate Intent extras format
        if ($Arguments) {
            Test-IntentExtrasFormat -Arguments $Arguments | Out-Null
        }

        # Configuration
        $timeoutSeconds = 300
        $pollIntervalSeconds = 2

        $startTime = Get-Date
        $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"

        # Launch activity with Intent extras
        Write-Host "Launching: $packageName/$activityName" -ForegroundColor Cyan
        if ($Arguments) {
            Write-Host "  Arguments: $Arguments" -ForegroundColor Cyan
        }

        $launchBody = @{
            appPackage      = $packageName
            appActivity     = $activityName
            appWaitActivity = '*'
            intentAction    = 'android.intent.action.MAIN'
            intentCategory  = 'android.intent.category.LAUNCHER'
        }

        if ($Arguments) {
            $launchBody['optionalIntentArguments'] = $Arguments
        }

        try {
            $launchResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/appium/device/start_activity", $launchBody, $false, $null)
            Write-Debug "Launch response: $($launchResponse | ConvertTo-Json)"
        }
        catch {
            throw "Failed to launch activity: $_"
        }

        # Wait a moment for app to start
        Start-Sleep -Seconds 3

        # Monitor app state until it exits (generic approach - no app-specific checking)
        Write-Host "Monitoring app execution..." -ForegroundColor Yellow
        $completed = $false

        while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($timeoutSeconds)) {
            # Query app state using Appium's mobile: queryAppState
            $stateBody = @{
                script = 'mobile: queryAppState'
                args   = @(
                    @{ appId = $packageName }
                )
            }

            try {
                $stateResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/execute/sync", $stateBody, $false, $null)
                $appState = $stateResponse.value

                Write-Debug "App state: $appState (elapsed: $([int]((Get-Date) - $startTime).TotalSeconds)s)"

                # State 1 = not running, 0 = not installed
                if ($appState -eq 1 -or $appState -eq 0) {
                    Write-Host "App finished/crashed (state: $appState)" -ForegroundColor Green
                    $completed = $true
                    break
                }
            }
            catch {
                Write-Warning "Failed to query app state: $_"
            }

            Start-Sleep -Seconds $pollIntervalSeconds
        }

        if (-not $completed) {
            Write-Host "Warning: App did not exit within timeout" -ForegroundColor Yellow
        }

        # Retrieve logs after app completion
        Write-Host "Retrieving logs..." -ForegroundColor Yellow
        $logBody = @{ type = 'logcat' }
        $logResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/log", $logBody, $false, $null)

        [array]$allLogs = @()
        if ($logResponse.value -and $logResponse.value.Count -gt 0) {
            $allLogs = @($logResponse.value)
            Write-Host "Retrieved $($allLogs.Count) log lines" -ForegroundColor Cyan
        }

        # Convert SauceLabs log format to text (matching ADB output format)
        $logCache = @()
        if ($allLogs -and $allLogs.Count -gt 0) {
            $logCache = $allLogs | ForEach-Object {
                if ($_) {
                    $timestamp = if ($_.timestamp) { $_.timestamp } else { '' }
                    $level = if ($_.level) { $_.level } else { '' }
                    $message = if ($_.message) { $_.message } else { '' }
                    "$timestamp $level $message"
                }
            } | Where-Object { $_ }  # Filter out any nulls
        }

        # Format logs consistently
        $formattedLogs = Format-LogcatOutput -LogcatOutput $logCache

        # Return result matching app-runner pattern
        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startTime
            FinishedAt     = Get-Date
            Output         = $formattedLogs
            ExitCode       = 0  # Android doesn't report exit codes
        }
    }

    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "$($this.Platform): Getting device logs"

        if (-not $this.SessionId) {
            throw "No active session"
        }

        $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"
        $logBody = @{ type = 'logcat' }
        $response = $this.InvokeSauceLabsApi('POST', "$baseUri/log", $logBody, $false, $null)

        [array]$logs = @()
        if ($response.value -and $response.value.Count -gt 0) {
            $logs = @($response.value)
        }

        if ($MaxEntries -gt 0) {
            $logs = $logs | Select-Object -First $MaxEntries
        }

        return @{
            Platform  = $this.Platform
            LogType   = $LogType
            Logs      = $logs
            Count     = $logs.Count
            Timestamp = Get-Date
        }
    }

    [void] TakeScreenshot([string]$OutputPath) {
        Write-Debug "$($this.Platform): Taking screenshot to: $OutputPath"

        if (-not $this.SessionId) {
            throw "No active session"
        }

        # Ensure output directory exists
        $directory = Split-Path $OutputPath -Parent
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"
        $response = $this.InvokeSauceLabsApi('GET', "$baseUri/screenshot", $null, $false, $null)

        # Response contains base64 encoded PNG
        [System.IO.File]::WriteAllBytes($OutputPath, [Convert]::FromBase64String($response.value))

        $size = (Get-Item $OutputPath).Length
        Write-Debug "$($this.Platform): Screenshot saved ($size bytes)"
    }

    [hashtable] GetDeviceStatus() {
        Write-Debug "$($this.Platform): Getting device status"

        return @{
            Platform   = $this.Platform
            Status     = if ($this.SessionId) { 'Online' } else { 'Disconnected' }
            StatusData = @{
                SessionId  = $this.SessionId
                StorageId  = $this.StorageId
                DeviceName = $this.DeviceName
                Region     = $this.Region
            }
            Timestamp  = Get-Date
        }
    }

    [string] GetDeviceIdentifier() {
        if ($this.SessionId) {
            return "$($this.DeviceName) (Session: $($this.SessionId))"
        }
        return $this.DeviceName
    }

    [void] StartDevice() {
        Write-Warning "$($this.Platform): StartDevice is not applicable for SauceLabs cloud devices"
    }

    [void] StopDevice() {
        Write-Warning "$($this.Platform): StopDevice is not applicable for SauceLabs cloud devices"
    }

    [void] RestartDevice() {
        Write-Warning "$($this.Platform): RestartDevice is not applicable for SauceLabs cloud devices"
    }

    [bool] TestInternetConnection() {
        Write-Debug "$($this.Platform): TestInternetConnection not implemented for SauceLabs"
        # Cloud devices always have internet connectivity
        return $true
    }

    [object] GetRunningProcesses() {
        Write-Debug "$($this.Platform): GetRunningProcesses not implemented for SauceLabs"
        return @()
    }

    [void] CopyDeviceItem([string]$DevicePath, [string]$Destination) {
        Write-Warning "$($this.Platform): CopyDeviceItem is not supported for SauceLabs cloud devices"
    }

    # Override DetectAndSetDefaultTarget - not needed for SauceLabs
    [void] DetectAndSetDefaultTarget() {
        Write-Debug "$($this.Platform): Target detection not needed for SauceLabs"
        # No-op: Device name is specified via Connect($deviceName)
    }
}
