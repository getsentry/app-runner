# Conversion Functions

<#
.SYNOPSIS
Converts an array of arguments to a PowerShell Invoke-Expression-safe string.

.DESCRIPTION
Converts an array of string arguments to a properly formatted string for PowerShell's
Invoke-Expression context. Uses a different escaping strategy that works with PowerShell's
parsing of command strings.

.PARAMETER Arguments
Array of string arguments to convert

.EXAMPLE
ConvertTo-ArgumentString @('--debug', '--config', 'my config.txt')
Returns: "--debug --config 'my config.txt'"

.EXAMPLE
ConvertTo-ArgumentString @('-Command', "Write-Host 'test'")
Returns: "-Command 'Write-Host ''test'''"
#>
function ConvertTo-ArgumentString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Arguments
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        return ""
    }

    $formattedArgs = @()

    foreach ($arg in $Arguments) {
        # If argument is already quoted with matching quotes, preserve it as-is
        if ($arg.Length -ge 2 -and (($arg[0] -eq '"' -and $arg[-1] -eq '"') -or ($arg[0] -eq "'" -and $arg[-1] -eq "'"))) {
            # Preserve original formatting for already-quoted arguments because
            # the argument was intentionally quoted by the caller for a specific reason
            $formattedArgs += $arg
        } elseif ($arg -match '[\s"''&|<>^;]') {
            # For PowerShell Invoke-Expression context, use PowerShell-style single quote escaping
            # In PowerShell, single quotes are escaped by doubling them
            $escapedArg = $arg -replace "'", "''"
            $formattedArgs += "'" + $escapedArg + "'"
        } else {
            $formattedArgs += $arg
        }
    }

    return $formattedArgs -join ' '
}
