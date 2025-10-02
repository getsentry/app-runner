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
        Uri = $Uri
        Method = $Method
        Headers = $Script:SentryApiConfig.Headers
        ContentType = 'application/json'
    }

    if ($Body) {
        $RequestParams.Body = $Body | ConvertTo-Json -Depth 10
    }

    try {
        Write-Debug "Making $Method request to: $Uri"
        $Response = Invoke-RestMethod @RequestParams
        return $Response
    }
    catch {
        $ErrorMessage = "Sentry API request ($Method $Uri) failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $StatusCode = $_.Exception.Response.StatusCode
            $ErrorMessage += " (Status: $StatusCode)"
        }
        throw $ErrorMessage
    }
}
