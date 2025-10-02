# Sentry API Client PowerShell Module

A PowerShell module that provides a client interface for interacting with Sentry's REST APIs.

## Installation

```powershell
# Import the module
Import-Module ./SentryApiClient.psd1
```

## Quick Start

```powershell
# Connect to Sentry API
Connect-SentryApi -ApiToken "your-api-token" -Organization "your-org" -Project "your-project"

# Get specific event
Get-SentryEvent -EventId "123456"

# Find events by tag
Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'

# Find issues and events by tag
Find-SentryEventByTag -TagName 'release' -TagValue 'v1.0.0'

# Download Sentry CLI
Get-SentryCLI -Version 'latest' -DownloadDirectory './bin'

# Use Sentry CLI with auto-configured org/project
Invoke-SentryCLI debug-files upload ./symbols

# Disconnect
Disconnect-SentryApi
```

## Functions

### Connect-SentryApi

Establishes connection to Sentry API with authentication and organization/project configuration.

```powershell
# Connect with organization and project
Connect-SentryApi -ApiToken "your-api-token" -Organization "your-org" -Project "your-project"

# Connect using DSN (automatically extracts org/project)
Connect-SentryApi -ApiToken "your-api-token" -DSN "https://PUBLIC_KEY@o123456.ingest.sentry.io/789"

# Uses $env:SENTRY_AUTH_TOKEN if ApiToken not specified
Connect-SentryApi -Organization "your-org" -Project "your-project"
```

### Disconnect-SentryApi

Clears the current Sentry API connection and configuration.

### Get-SentryEvent

Retrieves a specific event from Sentry by its ID.

### Get-SentryEventsByTag

Retrieves events filtered by a specific tag name and value.

```powershell
# Basic usage
Get-SentryEventsByTag -TagName 'environment' -TagValue 'production'

# With full event details
Get-SentryEventsByTag -TagName 'user.email' -TagValue 'user@example.com' -Full

# With pagination
Get-SentryEventsByTag -TagName 'release' -TagValue '1.0.0' -Limit 50 -Cursor 'next123'
```

### Find-SentryEventByTag

Finds issues and their associated events filtered by a tag. Returns structured data with both issues and events.

```powershell
# Basic usage
Find-SentryEventByTag -TagName 'environment' -TagValue 'production'

# With custom sorting
Find-SentryEventByTag -TagName 'browser' -TagValue 'Chrome' -Sort 'date' -Limit 50
```

Returns an object with:

- `Issues`: Array of issue objects with tag information
- `Events`: Array of the latest events for each issue  
- `NextCursor`: Cursor for pagination

### Get-SentryCLI

Downloads the Sentry CLI executable for the current platform.

```powershell
# Download latest version to current directory
Get-SentryCLI

# Download specific version to custom directory
Get-SentryCLI -Version '2.50.1' -DownloadDirectory './bin'

# Download and verify
$cliPath = Get-SentryCLI -Version 'latest' -DownloadDirectory "$HOME/.local/bin"
& $cliPath --version
```

Parameters:

- `Version`: Version to download (default: 'latest')
- `DownloadDirectory`: Directory to save the executable (default: current directory)

Returns the full path to the downloaded executable.

### Invoke-SentryCLI

Wrapper for executing Sentry CLI commands with automatic organization and project configuration.

```powershell
# Use system-installed sentry-cli (default)
Invoke-SentryCLI debug-files upload ./symbols

# Use latest version (downloads if needed, caches as sentry-cli-latest)
Invoke-SentryCLI -Version latest releases list

# Use specific version (downloads if needed, caches as sentry-cli-2.50.1)
Invoke-SentryCLI -Version 2.50.1 projects list

# Cached versions are reused automatically
Invoke-SentryCLI -Version 2.50.1 --version  # Uses cached sentry-cli-2.50.1
```

Parameters:

- `Version`: Version of sentry-cli to use (default: 'system')
  - `'system'`: Use sentry-cli from PATH
  - `'latest'`: Download/use latest version
  - Semantic version (e.g., '2.50.1'): Download/use specific version
- `Arguments`: Command line arguments to pass to sentry-cli

The function automatically adds `--org` and `--project` parameters when running `debug-files upload` command.

## Testing

```powershell
# Run tests
Invoke-Pester ./Tests/

# Clean up after testing
Remove-Module SentryApiClient
```

## API Reference

Based on [Sentry API Documentation](https://docs.sentry.io/api/)
