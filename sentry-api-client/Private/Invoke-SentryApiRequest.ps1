function Invoke-SentryApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body
    )

    $RequestParams = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = $Script:SentryApiConfig.Headers
        ContentType = 'application/json'
    }

    if ($Body) {
        $RequestParams.Body = $Body | ConvertTo-Json -Depth 10
    }

    try {
        Write-Debug "Making $Method request to: $Uri"

        # Use Invoke-WebRequest instead of Invoke-RestMethod to get explicit control over JSON parsing
        # Invoke-RestMethod silently returns strings when JSON parsing fails (e.g., with empty string keys)
        $WebResponse = Invoke-WebRequest @RequestParams

        # Explicitly parse JSON with error handling
        # Use -AsHashtable to gracefully handle JSON with empty string keys (common in Sentry API responses)
        $Response = $WebResponse.Content | ConvertFrom-Json -AsHashtable

        return $Response
    } catch {
        $ErrorMessage = "Sentry API request ($Method $Uri) failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $StatusCode = $_.Exception.Response.StatusCode
            $ErrorMessage += " (Status: $StatusCode)"
        }
        throw $ErrorMessage
    }
}
