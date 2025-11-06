# Sentry PowerShell SDK wrapper module
# Provides graceful degradation when Sentry module is unavailable

# Default DSN for app-runner telemetry
# Override with $env:SENTRY_DSN or disable with $env:SENTRY_DSN = $null
$script:DefaultDsn = 'https://8e7867b699467018c4f8a64a5a0b5b43@o447951.ingest.us.sentry.io/4510317734854656'

# Track initialization state to avoid repeated attempts
$script:InitializationAttempted = $false
$script:SentryAvailable = $false

<#
.SYNOPSIS
Internal function to ensure Sentry SDK is ready for use.

.DESCRIPTION
Checks if Sentry is disabled, loads the module if needed, and initializes the SDK.
All failures are silent (Write-Debug only) to avoid breaking functionality.

.OUTPUTS
[bool] True if Sentry is ready to use, false otherwise.
#>
function Ensure-SentryReady {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Check if disabled via environment variable
    if ([string]::IsNullOrEmpty($env:SENTRY_DSN) -and $env:SENTRY_DSN -ne $null) {
        Write-Debug "Sentry disabled: SENTRY_DSN environment variable is explicitly set to empty"
        return $false
    }

    # Return cached result if we already attempted initialization
    if ($script:InitializationAttempted) {
        return $script:SentryAvailable
    }

    $script:InitializationAttempted = $true

    # Check if Sentry SDK type is available (module loaded)
    $sentryTypeAvailable = $false
    try {
        $null = [Sentry.SentrySdk]
        $sentryTypeAvailable = $true
        Write-Debug "Sentry SDK type already available"
    }
    catch {
        Write-Debug "Sentry SDK type not available, attempting to load module"
    }

    # Try to import Sentry module if type not available
    if (-not $sentryTypeAvailable) {
        try {
            Import-Module Sentry -ErrorAction Stop
            $null = [Sentry.SentrySdk]  # Verify type is now available
            Write-Debug "Sentry module imported successfully"
            $sentryTypeAvailable = $true
        }
        catch {
            Write-Debug "Failed to import Sentry module: $_"
            $script:SentryAvailable = $false
            return $false
        }
    }

    # Check if already initialized
    if ([Sentry.SentrySdk]::IsEnabled) {
        Write-Debug "Sentry SDK already initialized"
        $script:SentryAvailable = $true
        return $true
    }

    # Initialize Sentry SDK
    try {
        $dsn = if ($env:SENTRY_DSN) { $env:SENTRY_DSN } else { $script:DefaultDsn }

        if ([string]::IsNullOrEmpty($dsn) -or $dsn -eq 'https://TODO@TODO.ingest.sentry.io/TODO') {
            Write-Debug "Sentry DSN not configured, telemetry disabled"
            $script:SentryAvailable = $false
            return $false
        }

        Write-Debug "Initializing Sentry with DSN: $($dsn -replace '(?<=https://)([^@]+)(?=@)', '***')"

        Start-Sentry -Dsn $dsn

        if ([Sentry.SentrySdk]::IsEnabled) {
            Write-Debug "Sentry SDK initialized successfully"
            $script:SentryAvailable = $true
            return $true
        }
        else {
            Write-Debug "Sentry SDK initialization completed but IsEnabled is false"
            $script:SentryAvailable = $false
            return $false
        }
    }
    catch {
        Write-Debug "Failed to initialize Sentry SDK: $_"
        $script:SentryAvailable = $false
        return $false
    }
}

<#
.SYNOPSIS
Optionally initialize Sentry with module context and tags.

.DESCRIPTION
Ensures Sentry is ready and sets contextual tags like module name, version,
PowerShell version, and OS. This is optional - Sentry will auto-initialize
on first use of any Try* function if not already started.

.PARAMETER ModuleName
Name of the module using Sentry (e.g., 'SentryAppRunner').

.PARAMETER ModuleVersion
Version of the module.

.PARAMETER Tags
Additional custom tags to set on all events.

.EXAMPLE
TryStart-Sentry -ModuleName 'SentryAppRunner' -ModuleVersion '1.0.0'

.EXAMPLE
TryStart-Sentry -ModuleName 'MyModule' -ModuleVersion '2.1.0' -Tags @{
    environment = 'ci'
    build_id = '12345'
}

.OUTPUTS
[bool] True if Sentry was initialized successfully, false otherwise.
#>
function TryStart-Sentry {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [string]$ModuleVersion,

        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )

    if (-not (Ensure-SentryReady)) {
        return $false
    }

    try {
        # Set contextual tags
        Edit-SentryScope {
            if ($ModuleName) {
                $_.SetTag('module_name', $ModuleName)
            }

            if ($ModuleVersion) {
                $_.SetTag('module_version', $ModuleVersion)
            }

            # PowerShell version
            $_.SetTag('powershell_version', $PSVersionTable.PSVersion.ToString())

            # Operating system
            $_.SetTag('os', $PSVersionTable.OS ?? $PSVersionTable.Platform ?? 'Windows')

            # CI environment detection
            if ($env:CI) {
                $_.SetTag('ci', 'true')
            }

            # Custom tags
            foreach ($key in $Tags.Keys) {
                $_.SetTag($key, $Tags[$key])
            }
        }

        Write-Debug "Sentry context initialized with module: $ModuleName, version: $ModuleVersion"
        return $true
    }
    catch {
        Write-Debug "Failed to set Sentry context: $_"
        return $false
    }
}

<#
.SYNOPSIS
Wrapper for Out-Sentry that fails silently if Sentry is unavailable.

.DESCRIPTION
Sends an error, exception, or message to Sentry. Automatically ensures Sentry
is ready before sending. Fails silently if Sentry is not available.

.PARAMETER InputObject
The object to send to Sentry. Can be an ErrorRecord, Exception, or string message.

.PARAMETER Tag
Optional hashtable of tags to attach to the event.

.PARAMETER Level
Optional severity level (Debug, Info, Warning, Error, Fatal).

.EXAMPLE
try {
    Get-Item "nonexistent.txt"
}
catch {
    $_ | TryOut-Sentry
}

.EXAMPLE
"Something important happened" | TryOut-Sentry -Level Info

.EXAMPLE
$error[0] | TryOut-Sentry -Tag @{operation = "device_connect"; platform = "Xbox"}

.OUTPUTS
[Guid] Event ID if sent successfully, $null otherwise.
#>
function TryOut-Sentry {
    [CmdletBinding()]
    [OutputType([System.Nullable[Guid]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [hashtable]$Tag = @{},

        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Fatal')]
        [string]$Level
    )

    process {
        if (-not (Ensure-SentryReady)) {
            return $null
        }

        try {
            # Build Out-Sentry parameters
            $outSentryParams = @{}

            if ($Tag.Count -gt 0) {
                $outSentryParams['EditScope'] = {
                    foreach ($key in $Tag.Keys) {
                        $_.SetTag($key, $Tag[$key])
                    }
                }.GetNewClosure()
            }

            # Send to Sentry based on input type
            if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
                $eventId = $InputObject | Out-Sentry @outSentryParams
            }
            elseif ($InputObject -is [System.Exception]) {
                $eventId = Out-Sentry -Exception $InputObject @outSentryParams
            }
            else {
                # Treat as message
                $eventId = Out-Sentry -Message $InputObject.ToString() @outSentryParams
            }

            if ($eventId) {
                Write-Debug "Event sent to Sentry: $eventId"
            }

            return $eventId
        }
        catch {
            Write-Debug "Failed to send event to Sentry: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
Wrapper for Add-SentryBreadcrumb that fails silently if Sentry is unavailable.

.DESCRIPTION
Adds a breadcrumb to the current Sentry scope. Breadcrumbs provide context
for subsequent events. Automatically ensures Sentry is ready before adding.

.PARAMETER Message
The breadcrumb message.

.PARAMETER Category
Optional category for the breadcrumb (e.g., "device", "network", "app").

.PARAMETER Data
Optional hashtable of additional data to attach to the breadcrumb.

.PARAMETER Level
Optional breadcrumb level (Debug, Info, Warning, Error, Critical).

.EXAMPLE
TryAdd-SentryBreadcrumb -Message "Acquiring device lock" -Category "device"

.EXAMPLE
TryAdd-SentryBreadcrumb -Message "HTTP request completed" -Category "network" -Data @{
    status_code = 200
    duration_ms = 150
}

.EXAMPLE
"Starting application installation" | TryAdd-SentryBreadcrumb -Category "app"
#>
function TryAdd-SentryBreadcrumb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [hashtable]$Data = @{},

        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Critical')]
        [string]$Level
    )

    process {
        if (-not (Ensure-SentryReady)) {
            return
        }

        try {
            $breadcrumbParams = @{
                Message = $Message
            }

            if ($Category) {
                $breadcrumbParams['Category'] = $Category
            }

            if ($Data.Count -gt 0) {
                $breadcrumbParams['Data'] = $Data
            }

            if ($Level) {
                $breadcrumbParams['Level'] = $Level
            }

            Add-SentryBreadcrumb @breadcrumbParams
            Write-Debug "Breadcrumb added: $Message"
        }
        catch {
            Write-Debug "Failed to add Sentry breadcrumb: $_"
        }
    }
}

<#
.SYNOPSIS
Wrapper for Edit-SentryScope that fails silently if Sentry is unavailable.

.DESCRIPTION
Modifies the current Sentry scope to add tags, extra data, or change context.
Automatically ensures Sentry is ready before editing.

.PARAMETER ScopeSetup
Scriptblock that receives the scope object and modifies it.

.EXAMPLE
TryEdit-SentryScope {
    $_.SetTag('operation', 'device_connect')
    $_.SetExtra('target', '192.168.1.100')
}

.EXAMPLE
TryEdit-SentryScope {
    $_.User = @{
        id = $env:USERNAME
        username = $env:USERNAME
    }
}
#>
function TryEdit-SentryScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScopeSetup
    )

    if (-not (Ensure-SentryReady)) {
        return
    }

    try {
        Edit-SentryScope -ScopeSetup $ScopeSetup
        Write-Debug "Sentry scope edited"
    }
    catch {
        Write-Debug "Failed to edit Sentry scope: $_"
    }
}

<#
.SYNOPSIS
Wrapper for Start-SentryTransaction that fails silently if Sentry is unavailable.

.DESCRIPTION
Starts a performance monitoring transaction to track operation duration and create spans.
Returns a transaction object that can be used to create child spans and finish the transaction.
Automatically ensures Sentry is ready before starting.

.PARAMETER Name
The name of the transaction (e.g., "Connect-Device", "Deploy-App").

.PARAMETER Operation
The operation type (e.g., "device.connect", "app.deploy", "http.request").

.PARAMETER CustomSamplingContext
Optional hashtable with additional context for sampling decisions.

.EXAMPLE
$transaction = TryStart-SentryTransaction -Name "Connect-Device" -Operation "device.connect"
try {
    # Create a span for a sub-operation
    $span = $transaction?.StartChild("device.lock.acquire")
    # ... perform lock acquisition ...
    $span?.Finish()

    # Create another span
    $span = $transaction?.StartChild("device.connection.establish")
    # ... establish connection ...
    $span?.Finish()
}
finally {
    # Always finish the transaction
    $transaction?.Finish()
}

.EXAMPLE
$transaction = TryStart-SentryTransaction -Name "Build-App" -Operation "build" -CustomSamplingContext @{
    target = "Xbox"
    preset = "Debug"
}
try {
    # ... build operations ...
}
finally {
    $transaction?.Finish()
}

.OUTPUTS
[Sentry.ITransaction] Transaction object if successful, $null otherwise.
#>
function TryStart-SentryTransaction {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $false)]
        [hashtable]$CustomSamplingContext = @{}
    )

    if (-not (Ensure-SentryReady)) {
        return $null
    }

    try {
        $transactionParams = @{
            Name      = $Name
            Operation = $Operation
        }

        if ($CustomSamplingContext.Count -gt 0) {
            $transactionParams['CustomSamplingContext'] = $CustomSamplingContext
        }

        $transaction = Start-SentryTransaction @transactionParams
        Write-Debug "Sentry transaction started: $Name ($Operation)"
        return $transaction
    }
    catch {
        Write-Debug "Failed to start Sentry transaction: $_"
        return $null
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'TryStart-Sentry',
    'TryOut-Sentry',
    'TryAdd-SentryBreadcrumb',
    'TryEdit-SentryScope',
    'TryStart-SentryTransaction'
)
