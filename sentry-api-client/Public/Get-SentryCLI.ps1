function Get-SentryCLI
{
    <#
    .SYNOPSIS
    Downloads the Sentry CLI executable for the current platform.

    .DESCRIPTION
    Downloads the specified version of the Sentry CLI executable from the official
    Sentry release registry. Automatically detects the platform and architecture,
    verifies the SHA256 checksum, and sets appropriate permissions.

    .PARAMETER Version
    The version of Sentry CLI to download. Default is 'latest'.
    Can be a specific semantic version like '2.50.1'.

    .PARAMETER DownloadDirectory
    The directory to save the executable. Default is the current directory.

    .EXAMPLE
    Get-SentryCLI
    # Downloads the latest version to the current directory

    .EXAMPLE
    Get-SentryCLI -Version '2.50.1' -DownloadDirectory './bin'
    # Downloads version 2.50.1 to the ./bin directory

    .EXAMPLE
    $cliPath = Get-SentryCLI -Version 'latest' -DownloadDirectory "$HOME/.local/bin"
    & $cliPath --version
    # Downloads to a specific location and verifies installation

    .OUTPUTS
    System.String
    Returns the full path to the downloaded executable.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Version = 'latest',

        [Parameter()]
        [string]$DownloadDirectory = $PWD.Path
    )
    
    # Determine platform and architecture
    $platform = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'Windows' }
    elseif ($IsMacOS) { 'Darwin' }
    elseif ($IsLinux) { 'Linux' }
    else { throw 'Unsupported platform' }
    
    # Get architecture
    $arch = switch -Regex ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)
    {
        'X64' { 'x86_64' }
        'X86' { 'i686' }
        'Arm64' { 'aarch64' }
        'Arm' { 'armv7' }
        default { throw "Unsupported architecture: $_" }
    }
    
    # Special handling for macOS universal binary
    if ($platform -eq 'Darwin')
    {
        $arch = 'universal'
    }
    
    # Construct download URL
    $baseUrl = "https://release-registry.services.sentry.io/apps/sentry-cli/$Version"
    $queryParams = @{
        response = 'download'
        arch = $arch
        platform = $platform
        package = 'sentry-cli'
    }
    
    # Build query string
    $queryString = ($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&'
    $downloadUrl = "$baseUrl`?$queryString"
    
    # Determine output filename
    $fileName = if ($platform -eq 'Windows') { 'sentry-cli.exe' } else { 'sentry-cli' }
    $outputPath = Join-Path -Path $DownloadDirectory -ChildPath $fileName
    
    Write-Verbose "Downloading Sentry CLI from: $downloadUrl"
    Write-Verbose "Output path: $outputPath"
    
    # Download the file
    try
    {
        $headers = @{}
        $response = Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath -PassThru -Headers $headers
        
        # Extract SHA256 digest from headers if available
        $digestHeader = $response.Headers['x-amz-meta-digest-sha256-base64']
        if ($digestHeader)
        {
            Write-Verbose "Found SHA256 digest in response headers"
            
            # Verify checksum
            $fileHash = Get-FileHash -Path $outputPath -Algorithm SHA256
            $expectedHash = [System.Convert]::FromBase64String($digestHeader)
            $expectedHashHex = [System.BitConverter]::ToString($expectedHash) -replace '-', ''
            
            if ($fileHash.Hash -ne $expectedHashHex)
            {
                Remove-Item -Path $outputPath -Force
                throw "SHA256 checksum verification failed. Expected: $expectedHashHex, Got: $($fileHash.Hash)"
            }
            
            Write-Verbose "SHA256 checksum verified successfully"
        }
        else
        {
            Write-Warning "No SHA256 digest found in response headers. Skipping checksum verification."
        }
    }
    catch
    {
        if (Test-Path $outputPath)
        {
            Remove-Item -Path $outputPath -Force
        }
        throw "Failed to download Sentry CLI: $_"
    }
    
    # Set executable permissions on non-Windows platforms
    if ($platform -ne 'Windows')
    {
        try
        {
            chmod +x $outputPath
            Write-Verbose "Set executable permissions on $outputPath"
        }
        catch
        {
            Write-Warning "Failed to set executable permissions. You may need to run: chmod +x $outputPath"
        }
    }
    
    # Verify the executable works
    try
    {
        $versionOutput = & $outputPath --version 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            throw "Failed to execute sentry-cli: $versionOutput"
        }
        
        Write-Host "Successfully downloaded and verified: $versionOutput"
        Write-Host "Location: $outputPath"
        
        # Return the path to the downloaded executable
        return $outputPath
    }
    catch
    {
        throw "Downloaded file does not appear to be a valid executable: $_"
    }
}