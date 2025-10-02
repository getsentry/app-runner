function ConvertTo-SentryApiUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    $BaseUrl = $Script:SentryApiConfig.BaseUrl
    if (-not $BaseUrl.EndsWith('/')) {
        $BaseUrl += '/'
    }

    if ($Endpoint.StartsWith('/')) {
        $Endpoint = $Endpoint.Substring(1)
    }

    return "$BaseUrl$Endpoint"
}

function Get-SentryProjectUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [Parameter(Mandatory = $false)]
        [string]$QueryString
    )

    if (-not $Script:SentryApiConfig.Organization)
    {
        throw 'Organization not configured. Use Connect-SentryApi to set organization.'
    }

    if (-not $Script:SentryApiConfig.Project)
    {
        throw 'Project not configured. Use Connect-SentryApi to set project.'
    }

    $Endpoint = "projects/$($Script:SentryApiConfig.Organization)/$($Script:SentryApiConfig.Project)/$Resource"
    if ($QueryString) {
        $Endpoint += "?$QueryString"
    }

    return ConvertTo-SentryApiUrl -Endpoint $Endpoint
}

function Get-SentryOrganizationUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [Parameter(Mandatory = $false)]
        [string]$QueryString
    )

    if (-not $Script:SentryApiConfig.Organization)
    {
        throw 'Organization not configured. Use Connect-SentryApi to set organization.'
    }

    $Endpoint = "organizations/$($Script:SentryApiConfig.Organization)/$Resource"
    if ($QueryString) {
        $Endpoint += "?$QueryString"
    }

    return ConvertTo-SentryApiUrl -Endpoint $Endpoint
}


function Build-QueryString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $QueryParams = @()
    foreach ($Key in $Parameters.Keys) {
        $Value = $Parameters[$Key]
        if ($null -ne $Value -and $Value -ne '') {
            if ($Key -eq 'query') {
                $QueryParams += "$Key=$([System.Web.HttpUtility]::UrlEncode($Value))"
            } else {
                $QueryParams += "$Key=$Value"
            }
        }
    }

    return $QueryParams -join "&"
}
