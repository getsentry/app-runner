# Logging Functions
# This file contains internal logging utilities

function Write-GitHub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    # Only write output if running in GitHub Actions
    if ($env:GITHUB_ACTIONS -eq 'true') {
        Write-Host $Message
    }
}
