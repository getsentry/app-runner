function Add-ArgumentIfMissing {
    param(
        [array]$Arguments,
        [string]$ArgumentName,
        [string]$ArgumentValue
    )

    # Check if the argument is already present
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -eq $ArgumentName) {
            return $Arguments
        }
    }

    # Add the argument and its value
    return $Arguments + @($ArgumentName, $ArgumentValue)
}

function Invoke-SentryCLI
{
    <#
    .SYNOPSIS
    Executes Sentry CLI commands with automatic configuration.

    .DESCRIPTION
    Wrapper for executing Sentry CLI commands with automatic organization and project
    configuration. Supports using system-installed sentry-cli or downloading specific
    versions. Downloaded versions are cached for reuse.

    .PARAMETER Version
    Version of sentry-cli to use. Default is 'system'.
    - 'system': Use sentry-cli from PATH
    - 'latest': Download/use latest version
    - Semantic version (e.g., '2.50.1'): Download/use specific version

    .PARAMETER Arguments
    Command line arguments to pass to sentry-cli. Automatically adds --org and --project
    when running 'debug-files upload' commands.

    .EXAMPLE
    Invoke-SentryCLI debug-files upload ./symbols
    # Uses system-installed sentry-cli with auto-configured org/project

    .EXAMPLE
    Invoke-SentryCLI -Version latest releases list
    # Downloads/uses latest version (cached as sentry-cli-latest)

    .EXAMPLE
    Invoke-SentryCLI -Version 2.50.1 projects list
    # Downloads/uses version 2.50.1 (cached as sentry-cli-2.50.1)

    .EXAMPLE
    Invoke-SentryCLI -Version 2.50.1 --version
    # Uses cached version (if already downloaded)
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateScript({
            $_ -eq 'system' -or $_ -eq 'latest' -or $_ -match '^[0-9]+\.[0-9]+\.[0-9]+$'
        }, ErrorMessage = "Version must be 'system', 'latest', or a semantic version like '2.50.1'")]
        [string]$Version = 'system',

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    $sentryCli = $null

    if ($Version -eq 'system')
    {
        # Use system-installed sentry-cli
        $sentryCli = Get-Command 'sentry-cli' -ErrorAction SilentlyContinue
        if (-not $sentryCli)
        {
            $sentryCli = Get-Command 'sentry' -ErrorAction SilentlyContinue
        }
        if (-not $sentryCli)
        {
            throw 'sentry-cli command not found. Please ensure it is installed and available in PATH.'
        }
    }
    else
    {
        # Use specific version or latest
        $extension = if ($IsWindows -or $env:OS -eq 'Windows_NT') { '.exe' } else { '' }
        $versionedFileName = "sentry-cli-$Version$extension"
        $versionedPath = Join-Path -Path $PWD.Path -ChildPath $versionedFileName

        # Check if we already have this version
        if (Test-Path $versionedPath)
        {
            Write-Verbose "Using cached sentry-cli version $Version from $versionedPath"
            $sentryCli = Get-Command $versionedPath
        }
        else
        {
            Write-Host "Downloading sentry-cli version $Version..."

            try
            {
                # Download the CLI
                $downloadedPath = Get-SentryCLI -Version $Version -DownloadDirectory $PWD.Path

                # Rename to versioned filename
                Move-Item -Path $downloadedPath -Destination $versionedPath -Force

                Write-Host "Downloaded and cached sentry-cli $Version as $versionedFileName"
                $sentryCli = Get-Command $versionedPath
            }
            catch
            {
                throw "Failed to download sentry-cli version $Version`: $_"
            }
        }
    }

    # Prepare final arguments
    $finalArgs = @($Arguments)

    # If the first two args are "debug-files upload", automatically add org and project
    if ($Arguments.Count -ge 2 -and $Arguments[0] -eq 'debug-files' -and $Arguments[1] -eq 'upload')
    {
        if ($Script:SentryApiConfig.Organization)
        {
            $finalArgs = Add-ArgumentIfMissing -Arguments $finalArgs -ArgumentName '--org' -ArgumentValue $Script:SentryApiConfig.Organization
        }
        else
        {
            Write-Warning "Organization not configured. Use Connect-SentryApi first to set up configuration."
        }

        if ($Script:SentryApiConfig.Project)
        {
            $finalArgs = Add-ArgumentIfMissing -Arguments $finalArgs -ArgumentName '--project' -ArgumentValue $Script:SentryApiConfig.Project
        }
        else
        {
            Write-Warning "Project not configured. Use Connect-SentryApi first to set up configuration."
        }
    }

    # Get the actual executable path
    $cliPath = if ($sentryCli.Source) { $sentryCli.Source } else { $sentryCli.Name }
    
    Write-Host "Invoking $(& $cliPath --version) with arguments: $($finalArgs -join ' ')"

    $prevAction = $ErrorActionPreference
    $prevPref = $PSNativeCommandUseErrorActionPreference
    try
    {
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $true
        & $cliPath @finalArgs
    }
    finally
    {
        $ErrorActionPreference = $prevAction
        $PSNativeCommandUseErrorActionPreference = $prevPref
    }
}
