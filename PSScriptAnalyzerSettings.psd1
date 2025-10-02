@{
    # Inherit default rules from PSGallery
    IncludeDefaultRules = $true

    # General settings
    Severity            = @('Error', 'Warning', 'Information')

    # Rules to exclude
    ExcludeRules        = @()

    # Rules to include (if empty, all rules are included except those in ExcludeRules)
    IncludeRules        = @()

    # Custom rule settings
    Rules               = @{
        # Enforce consistent indentation
        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        # Enforce consistent whitespace
        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckPipe       = $true
            CheckSeparator  = $true
            CheckParameter  = $false
        }

        # Enforce placement of open braces
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        # Enforce placement of close braces
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        # Enforce alignment of hashtables
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        # Use correct casing for cmdlets
        PSUseCorrectCasing         = @{
            Enable = $true
        }
    }
}
