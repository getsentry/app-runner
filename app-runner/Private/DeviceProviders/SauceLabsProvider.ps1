# SauceLabs Provider Implementation
# Provides device management for devices on SauceLabs Real Device Cloud (Android/iOS)

# Load the base provider
. "$PSScriptRoot\DeviceProvider.ps1"

# Load Android helpers (conditionally needed, but safe to load)
. "$PSScriptRoot\..\AndroidHelpers.ps1"

<#
.SYNOPSIS
Device provider for mobile devices on SauceLabs Real Device Cloud.

.DESCRIPTION
This provider implements device operations using SauceLabs Appium API.
It supports testing on real Android and iOS devices in the SauceLabs cloud infrastructure.

Key features:
- App upload to SauceLabs storage
- Appium session management (create, reuse, delete)
- App execution with state monitoring
- Logcat/Syslog retrieval via Appium
- On-device log file retrieval (optional override with fallback to Logcat/Syslog)
- Screenshot capture

Requirements:
- SauceLabs account with Real Device Cloud access
- Environment variables:
  - SAUCE_USERNAME - SauceLabs username
  - SAUCE_ACCESS_KEY - SauceLabs access key
  - SAUCE_REGION - SauceLabs region (e.g., us-west-1, eu-central-1)
  - SAUCE_DEVICE_NAME - Device name (optional if using -Target parameter)
  - SAUCE_SESSION_NAME - Session name for SauceLabs dashboard (optional, defaults to "App Runner Test")

Note: Device name must match a device available in the specified region.

Example usage:
  # Option 1: Use SAUCE_DEVICE_NAME environment variable
  Connect-Device -Platform AndroidSauceLabs

  # Option 2: Explicitly specify device name
  Connect-Device -Platform AndroidSauceLabs -Target "Samsung_Galaxy_S23_15_real_sjc1"
#>
class SauceLabsProvider : DeviceProvider {
    [string]$SessionId = $null
    [string]$StorageId = $null
    [string]$Region = $null
    [string]$DeviceName = $null
    [string]$Username = $null
    [string]$AccessKey = $null
    [string]$SessionName = $null
    [string]$CurrentPackageName = $null
    [string]$MobilePlatform = $null # 'Android' or 'iOS'

    SauceLabsProvider([string]$MobilePlatform) {
        if ($MobilePlatform -notin @('Android', 'iOS')) {
            throw "SauceLabsProvider: Unsupported mobile platform '$MobilePlatform'. Must be 'Android' or 'iOS'."
        }
        $this.MobilePlatform = $MobilePlatform
        $this.Platform = "${MobilePlatform}SauceLabs"

        # Read credentials and configuration from environment
        $this.Username = $env:SAUCE_USERNAME
        $this.AccessKey = $env:SAUCE_ACCESS_KEY
        $this.Region = $env:SAUCE_REGION
        $this.DeviceName = $env:SAUCE_DEVICE_NAME  # Optional: can be overridden via -Target

        # Read optional session name (with default)
        $this.SessionName = if ($env:SAUCE_SESSION_NAME) {
            $env:SAUCE_SESSION_NAME
        }
        else {
            "App Runner $MobilePlatform Test"
        }

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
            'upload'        = 600  # App upload can take time
            'session'       = 300  # Session creation
            'launch'        = 300  # App launch on cloud device
            'run-timeout'   = 300  # Maximum time to wait for app execution
            'poll-interval' = 2    # Interval between app state checks
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
        throw 'Connect() requires a target device name for SauceLabsProvider. Use Connect($target) instead.'
    }

    [hashtable] Connect([string]$target) {
        # If no target specified, fall back to SAUCE_DEVICE_NAME env var
        if ([string]::IsNullOrEmpty($target)) {
            $target = $env:SAUCE_DEVICE_NAME
            if ([string]::IsNullOrEmpty($target)) {
                throw "$($this.Platform) requires a device name. Set SAUCE_DEVICE_NAME environment variable or use Connect-Device -Platform $($this.Platform) -Target 'DeviceName'"
            }
            Write-Debug "$($this.Platform): Connecting with device name from env: $($this.DeviceName)"
        } else {
            Write-Debug "$($this.Platform): Connecting with explicit device name: $target"
        }

        # Store the device name for session creation
        $this.DeviceName = $target

        # Note: App upload and session creation happen in InstallApp
        # because we need the App path before creating an Appium session

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
        Write-Debug "$($this.Platform): Installing App: $PackagePath"

        # Validate App file
        if (-not (Test-Path $PackagePath)) {
            throw "App file not found: $PackagePath"
        }

        $extension = [System.IO.Path]::GetExtension($PackagePath).ToLower()
        if ($this.MobilePlatform -eq 'Android' -and $extension -ne '.apk') {
            throw "Package must be an .apk file for Android. Got: $PackagePath"
        }
        if ($this.MobilePlatform -eq 'iOS' -and $extension -ne '.ipa') {
            throw "Package must be an .ipa file for iOS. Got: $PackagePath"
        }


        # Upload App to SauceLabs Storage
        Write-Host "Uploading App to SauceLabs Storage..." -ForegroundColor Yellow
        $uploadUri = "https://api.$($this.Region).saucelabs.com/v1/storage/upload"

        $uploadResponse = $this.InvokeSauceLabsApi('POST', $uploadUri, $null, $true, $PackagePath)

        if (-not $uploadResponse.item.id) {
            throw "Failed to upload App: No storage ID in response"
        }

        $this.StorageId = $uploadResponse.item.id
        Write-Host "App uploaded successfully. Storage ID: $($this.StorageId)" -ForegroundColor Green

        # Create Appium session with uploaded App
        Write-Host "Creating SauceLabs Appium session..." -ForegroundColor Yellow
        $sessionUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session"

        $capabilities = @{
            capabilities = @{
                alwaysMatch = @{
                    platformName            = $this.MobilePlatform
                    'appium:app'            = "storage:$($this.StorageId)"
                    'appium:deviceName'     = $this.DeviceName
                    'appium:automationName' = if ($this.MobilePlatform -eq 'Android') { 'UiAutomator2' } else { 'XCUITest' }
                    'appium:noReset'        = $true
                    'appium:autoLaunch'     = $false
                    'sauce:options'         = @{
                        name          = $this.SessionName
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

    [hashtable] RunApplication([string]$ExecutablePath, [string[]]$Arguments, [string]$LogFilePath = $null) {
        Write-Debug "$($this.Platform): Running application: $ExecutablePath"

        if (-not $this.SessionId) {
            throw "No active SauceLabs session. Call InstallApp first to create a session."
        }

        $timeoutSeconds = $this.Timeouts['run-timeout']
        $pollIntervalSeconds = $this.Timeouts['poll-interval']
        $startTime = Get-Date
        $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"

        if ($this.MobilePlatform -eq 'Android') {
            # Parse ExecutablePath: "package.name/activity.name"
            $parsed = ConvertFrom-AndroidActivityPath -ExecutablePath $ExecutablePath
            $packageName = $parsed.PackageName
            $activityName = $parsed.ActivityName
            $this.CurrentPackageName = $packageName

            # Validate Intent extras format
            if ($Arguments -and $Arguments.Count -gt 0) {
                Test-IntentExtrasArray -Arguments $Arguments | Out-Null
            }

            # Launch activity with Intent extras
            Write-Host "Launching: $packageName/$activityName" -ForegroundColor Cyan

            $argumentsString = ConvertTo-ArgumentString $Arguments
            if ($argumentsString) {
                Write-Host "  Arguments: $argumentsString" -ForegroundColor Cyan
            }

            $launchBody = @{
                appPackage      = $packageName
                appActivity     = $activityName
                appWaitActivity = '*'
                intentAction    = 'android.intent.action.MAIN'
                intentCategory  = 'android.intent.category.LAUNCHER'
            }

            if ($argumentsString) {
                $launchBody['optionalIntentArguments'] = $argumentsString
            }

            try {
                Write-Debug "Launching activity with arguments: $argumentsString"
                $launchResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/appium/device/start_activity", $launchBody, $false, $null)
                Write-Debug "Launch response: $($launchResponse | ConvertTo-Json)"
            }
            catch {
                throw "Failed to launch activity: $_"
            }
        }
        elseif ($this.MobilePlatform -eq 'iOS') {
            # For iOS, ExecutablePath is typically the Bundle ID
            $bundleId = $ExecutablePath
            $this.CurrentPackageName = $bundleId

            Write-Host "Launching: $bundleId" -ForegroundColor Cyan
            if ($Arguments) {
                Write-Host "  Arguments: $Arguments" -ForegroundColor Cyan
            }

            $launchBody = @{
                bundleId = $bundleId
            }

            if ($Arguments) {
                $launchBody['arguments'] = $Arguments
            }

            try {
                # Use mobile: launchApp for iOS
                $scriptBody = @{
                    script = "mobile: launchApp"
                    args   = $launchBody
                }
                $launchResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/execute/sync", $scriptBody, $false, $null)
                Write-Debug "Launch response: $($launchResponse | ConvertTo-Json)"
            }
            catch {
                throw "Failed to launch app: $_"
            }
        }

        # Wait a moment for app to start
        Start-Sleep -Seconds 3

        # Monitor app state until it exits (generic approach - no app-specific checking)
        Write-Host "Monitoring app execution..." -ForegroundColor Yellow
        $completed = $false

        while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($timeoutSeconds)) {
            # Query app state using Appium's mobile: queryAppState
            # Use correct parameter name based on platform: appId for Android, bundleId for iOS
            $appParameter = if ($this.MobilePlatform -eq 'Android') { 'appId' } else { 'bundleId' }
            $stateBody = @{
                script = 'mobile: queryAppState'
                args   = @(
                    @{ $appParameter = $this.CurrentPackageName } # Use stored package/bundle ID
                )
            }

            try {
                $stateResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/execute/sync", $stateBody, $false, $null)
                $appState = $stateResponse.value

                Write-Debug "App state: $appState (elapsed: $([int]((Get-Date) - $startTime).TotalSeconds)s)"

                # State 1 = not running, 0 = not installed (Android)
                # iOS: 1 = not running, 0 = unknown/not installed?
                # Appium docs: 0 is not installed. 1 is not running. 2 is running in background or suspended. 3 is running in background. 4 is running in foreground.
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

        # Retrieve logs - try log file first if provided, otherwise use system logs
        Write-Host "Retrieving logs..." -ForegroundColor Yellow

        $formattedLogs = @()

        # Try log file if path provided
        if (-not [string]::IsNullOrWhiteSpace($LogFilePath)) {
            try {
                Write-Host "Attempting to retrieve log file: $LogFilePath" -ForegroundColor Cyan
                $tempLogFile = [System.IO.Path]::GetTempFileName()

                try {
                    $this.CopyDeviceItem($LogFilePath, $tempLogFile)
                    $logFileContent = Get-Content -Path $tempLogFile -Raw

                    if ($logFileContent) {
                        $formattedLogs = $logFileContent -split "`n" | Where-Object { $_.Trim() -ne "" }
                        Write-Host "Retrieved log file with $($formattedLogs.Count) lines" -ForegroundColor Green
                    }
                } finally {
                    Remove-Item $tempLogFile -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Warning "Failed to retrieve log file: $($_.Exception.Message)"
                Write-Host "Falling back to system logs..." -ForegroundColor Yellow
            }
        }

        # Fallback to system logs if log file not retrieved
        if (-not $formattedLogs) {
            $logType = if ($this.MobilePlatform -eq 'iOS') { 'syslog' } else { 'logcat' }
            $logResponse = $this.InvokeSauceLabsApi('POST', "$baseUri/log", @{ type = $logType }, $false, $null)

            if ($logResponse.value) {
                Write-Host "Retrieved $($logResponse.value.Count) system log lines" -ForegroundColor Cyan
                $logCache = $logResponse.value | ForEach-Object {
                    "$($_.timestamp) $($_.level) $($_.message)"
                } | Where-Object { $_ }

                $formattedLogs = if ($this.MobilePlatform -eq 'Android') {
                    Format-LogcatOutput -LogcatOutput $logCache
                } else {
                    $logCache
                }
            }
        }

        return @{
            Platform       = $this.Platform
            ExecutablePath = $ExecutablePath
            Arguments      = $Arguments
            StartedAt      = $startTime
            FinishedAt     = Get-Date
            Output         = $formattedLogs
            ExitCode       = 0  # Mobile platforms don't reliably report exit codes here
        }
    }

    [hashtable] GetDeviceLogs([string]$LogType, [int]$MaxEntries) {
        Write-Debug "$($this.Platform): Getting device logs"

        if (-not $this.SessionId) {
            throw "No active session"
        }

        $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"

        # Default log type based on platform if not specified
        if ([string]::IsNullOrEmpty($LogType)) {
            $LogType = if ($this.MobilePlatform -eq 'iOS') { 'syslog' } else { 'logcat' }
        }

        $logBody = @{ type = $LogType }
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

        # Validate response before decoding
        if (-not $response) {
            throw "$($this.Platform): Screenshot API returned no response"
        }

        if (-not $response.value) {
            throw "$($this.Platform): Screenshot API response missing 'value' field"
        }

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

    <#
    .SYNOPSIS
    Checks if the current app supports file sharing capability on iOS devices.

    .DESCRIPTION
    Uses Appium's mobile: listApps command to retrieve app information and check
    if UIFileSharingEnabled is set for the current app bundle.

    .OUTPUTS
    Hashtable with app capability information including Found, FileSharingEnabled, and AllApps.
    #>
    [hashtable] CheckAppFileSharingCapability() {
        if (-not $this.SessionId) {
            throw "No active SauceLabs session. Call InstallApp first to create a session."
        }

        try {
            $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"
            $scriptBody = @{ script = 'mobile: listApps'; args = @() }

            $response = $this.InvokeSauceLabsApi('POST', "$baseUri/execute/sync", $scriptBody, $false, $null)

            if ($response -and $response.value) {
                $apps = $response.value
                $bundleIds = $apps.Keys | Where-Object { $_ }

                if ($apps.ContainsKey($this.CurrentPackageName)) {
                    $targetApp = $apps[$this.CurrentPackageName]
                    return @{
                        Found = $true
                        BundleId = $this.CurrentPackageName
                        FileSharingEnabled = [bool]$targetApp.UIFileSharingEnabled
                        Name = $(
                            if ($targetApp.CFBundleDisplayName) { $targetApp.CFBundleDisplayName }
                            elseif ($targetApp.CFBundleName) { $targetApp.CFBundleName }
                            else { "Unknown" }
                        )
                        AllApps = $bundleIds
                    }
                }

                return @{
                    Found = $false
                    BundleId = $this.CurrentPackageName
                    FileSharingEnabled = $false
                    AllApps = $bundleIds
                }
            }

            return @{ Found = $false; BundleId = $this.CurrentPackageName; FileSharingEnabled = $false; AllApps = @() }
        }
        catch {
            return @{ Found = $false; BundleId = $this.CurrentPackageName; FileSharingEnabled = $false; AllApps = @(); Error = $_.Exception.Message }
        }
    }

    <#
    .SYNOPSIS
    Copies a file from the SauceLabs device to the local machine.

    .DESCRIPTION
    Retrieves files from iOS/Android devices via Appium's pull_file API.

    .PARAMETER DevicePath
    Path to the file on the device:
    - iOS: Bundle format @bundle.id:documents/file.log
    - Android: Absolute path /data/data/package.name/files/logs/file.log (requires debuggable=true)

    .PARAMETER Destination
    Local destination path where the file should be saved.

    .NOTES
    iOS Requirements:
    - App must have UIFileSharingEnabled=true in info.plist
    - Files must be in the app's Documents directory

    Android Requirements:
    - Internal storage paths are only accessible for debuggable apps
    - App must be built with android:debuggable="true" in AndroidManifest.xml
    #>
    [void] CopyDeviceItem([string]$DevicePath, [string]$Destination) {
        if (-not $this.SessionId) {
            throw "No active SauceLabs session. Call InstallApp first to create a session."
        }

        try {
            # Pull file from device via Appium API
            $baseUri = "https://ondemand.$($this.Region).saucelabs.com/wd/hub/session/$($this.SessionId)"
            $response = $this.InvokeSauceLabsApi('POST', "$baseUri/appium/device/pull_file", @{ path = $DevicePath }, $false, $null)

            if (-not $response -or -not $response.value) {
                throw "No file content returned from device"
            }

            # Prepare destination path
            if (-not [System.IO.Path]::IsPathRooted($Destination)) {
                $Destination = Join-Path (Get-Location) $Destination
            }

            $destinationDir = Split-Path $Destination -Parent
            if ($destinationDir -and -not (Test-Path $destinationDir)) {
                New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
            }

            if (Test-Path $Destination) {
                Remove-Item $Destination -Force -ErrorAction SilentlyContinue
            }

            # Decode and save file
            $fileBytes = [System.Convert]::FromBase64String($response.value)
            [System.IO.File]::WriteAllBytes($Destination, $fileBytes)

            Write-Host "Successfully copied file from device: $DevicePath -> $Destination" -ForegroundColor Green
        }
        catch {
            $this.HandleCopyDeviceItemError($_, $DevicePath)
        }
    }

    <#
    .SYNOPSIS
    Handles errors from CopyDeviceItem with helpful diagnostic information.
    #>
    [void] HandleCopyDeviceItemError([System.Management.Automation.ErrorRecord]$Error, [string]$DevicePath) {
        $errorMsg = "Failed to copy file from device: $DevicePath. Error: $($Error.Exception.Message)"

        # Add platform-specific troubleshooting for server errors
        if ($Error.Exception.Message -match "500|Internal Server Error") {
            $errorMsg += "`n`nTroubleshooting $($this.MobilePlatform) file access:"
            $errorMsg += "`n- App Package/Bundle ID: '$($this.CurrentPackageName)'"
            $errorMsg += "`n- Requested path: '$DevicePath'"

            if ($this.MobilePlatform -eq 'iOS') {
                try {
                    $appInfo = $this.CheckAppFileSharingCapability()
                    if ($appInfo.AllApps -and $appInfo.AllApps.Count -gt 0) {
                        $errorMsg += "`n- Available apps: $($appInfo.AllApps -join ', ')"
                        if ($appInfo.Found -and -not $appInfo.FileSharingEnabled) {
                            $errorMsg += "`n- App found but UIFileSharingEnabled=false"
                        }
                    }
                } catch {
                    $errorMsg += "`n- Could not check app capabilities: $($_.Exception.Message)"
                }

                $errorMsg += "`n`nCommon iOS causes:"
                $errorMsg += "`n1. App missing UIFileSharingEnabled=true in info.plist"
                $errorMsg += "`n2. File doesn't exist on device"
                $errorMsg += "`n3. Incorrect path format - must use @bundle.id:documents/relative_path"

                if ($this.CurrentPackageName) {
                    $errorMsg += "`n`nRequired iOS format: @$($this.CurrentPackageName):documents/relative_path"
                }
            }
            elseif ($this.MobilePlatform -eq 'Android') {
                $errorMsg += "`n`nMost likely cause: App not built with debuggable flag"
                $errorMsg += "`n"
                $errorMsg += "`nFor Android internal storage access (/data/data/...), the app MUST be built with:"
                $errorMsg += "`n  android:debuggable='true' in AndroidManifest.xml"
                $errorMsg += "`n"
                $errorMsg += "`nOther possible causes:"
                $errorMsg += "`n2. File doesn't exist on device (less likely)"
                $errorMsg += "`n3. Incorrect path format or permissions"

                if ($this.CurrentPackageName) {
                    $errorMsg += "`n`nWorking path formats:"
                    $errorMsg += "`n- Internal storage: /data/data/$($this.CurrentPackageName)/files/app.log (needs debuggable=true)"
                    $errorMsg += "`n- App-relative: @$($this.CurrentPackageName)/files/app.log (needs debuggable=true)"
                }
            }
        }

        Write-Warning $errorMsg
        throw
    }

    # Override DetectAndSetDefaultTarget - not needed for SauceLabs
    [void] DetectAndSetDefaultTarget() {
        Write-Debug "$($this.Platform): Target detection not needed for SauceLabs"
        # No-op: Device name is specified via Connect($deviceName)
    }
}
