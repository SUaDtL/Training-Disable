# =============================================================================
# PSScriptAnalyzerSettings.psd1 -- WAM Training Disable
# =============================================================================
#
# What this file does:
#   PSScriptAnalyzer is the official PowerShell linter -- think pylint or
#   eslint, but for .ps1/.psm1/.psd1. By default it ships with ~60 rules at a
#   mix of severities. This file pins which rules we run, which severity each
#   reports at, and which compatibility targets we check against.
#
# How it is loaded:
#   - CI: .github/workflows/ci.yml passes -Settings on the Invoke-ScriptAnalyzer
#     call.
#   - VS Code: the PowerShell extension automatically discovers this file in
#     the workspace root and applies it for live linting.
#   - Local: developers can run
#         Invoke-ScriptAnalyzer -Path . -Recurse `
#             -Settings ./PSScriptAnalyzerSettings.psd1
#     and get the same results CI gets.
#
# Why we care more than usual about lint:
#   This codebase is being rebuilt as a teaching artifact. The user has
#   explicitly mandated:
#     - no aliases anywhere (gci, %, ?, where, select, etc.)
#     - no positional parameters (always Get-Content -Path $foo)
#     - approved verb-noun naming
#     - explicit ShouldProcess on state-changing cmdlets
#   Lint enforces these mechanically so a rusty hand or a future contributor
#   cannot accidentally re-introduce v1's habits.
# =============================================================================

@{
    # -------------------------------------------------------------------------
    # IncludeRules
    # -------------------------------------------------------------------------
    # We enumerate the rules we care about explicitly rather than relying on
    # "default" because:
    #   1. Different PSSA versions ship slightly different default sets, and we
    #      want CI behavior to be deterministic across runs.
    #   2. Listing rules forces a deliberate decision when adding or muting one
    #      -- "why is this in the file?" is easier to answer than "why is this
    #      missing from the file?".
    # -------------------------------------------------------------------------
    IncludeRules = @(
        # -- The hard bans the user asked for ---------------------------------
        # Aliases like gci, %, ?, where, select, ft, gm leak through fingers
        # when typing fast. v1 uses several of them. Lint catches all of them.
        'PSAvoidUsingCmdletAliases'

        # Positional parameters obscure intent. `Get-Content $path` works but
        # `Get-Content -Path $path` reads better and survives the Cmdlet adding
        # a new positional later (rare but real).
        'PSAvoidUsingPositionalParameters'

        # -- Cmdlet hygiene ---------------------------------------------------
        # Verb-noun naming with verbs from Get-Verb. WAM-SQLLookup fails this;
        # Get-WamNonCompliantUser passes.
        'PSUseApprovedVerbs'

        # State-changing operations (anything that disables an account, writes
        # to a file the user wouldn't expect, etc.) MUST take -WhatIf and
        # -Confirm. v1 has none of this; v2 wires it on every Public cmdlet.
        'PSUseShouldProcessForStateChangingFunctions'

        # Catches `if ($foo -eq $null)`. The recommended idiom is
        # `if ($null -eq $foo)` because $foo might be an array, and on the
        # left side of -eq the comparison would surprisingly become "does
        # this array contain $null?" rather than "is this scalar null?".
        'PSPossibleIncorrectComparisonWithNull'

        # -- Style and structure ----------------------------------------------
        # Catches dead variables (assigned but never read). Useful for spotting
        # a typo'd variable name on the read side.
        'PSUseDeclaredVarsMoreThanAssignments'

        # Globals leak across module boundaries and break tests; ban them.
        'PSAvoidGlobalVars'

        # `Write-Host` bypasses the pipeline and breaks Pester output capture.
        # Use Write-Verbose / Write-Information / Write-Output instead.
        'PSAvoidUsingWriteHost'

        # If you take -Credential, accept [PSCredential], not a username string.
        'PSUsePSCredentialType'

        # Detects assignments like `if ($x = 5)` which are almost always typos
        # for `-eq`.
        'PSPossibleIncorrectUsageOfAssignmentOperator'

        # Reserved characters in cmdlet/function names break things in subtle
        # ways. Errors on # ` { } ( ) etc.
        'PSReservedCmdletChar'

        # Reserved parameter names (e.g. -Verbose, -Debug) cannot be reused.
        'PSReservedParams'

        # -- Whitespace & layout ----------------------------------------------
        # The PowerShell-team default style. Catches inconsistent indentation,
        # missing space after comma, missing space around operators.
        'PSUseConsistentIndentation'
        'PSUseConsistentWhitespace'
        'PSPlaceOpenBrace'
        'PSPlaceCloseBrace'

        # -- Compatibility checks ---------------------------------------------
        # These two rules are the killer feature of PSScriptAnalyzer for a
        # cross-edition module. They tell us at lint time if we used a syntax
        # or cmdlet that would break on one of our target runtimes. We target:
        #   - Windows PowerShell 5.1 (the desktop edition, ships in-box on
        #     Windows Server 2016+; this is what the prod scheduled task uses)
        #   - PowerShell 7.4 LTS (the cross-platform pwsh)
        # Settings for these rules live in the Rules block below.
        'PSUseCompatibleSyntax'
        'PSUseCompatibleCmdlets'
    )

    # -------------------------------------------------------------------------
    # Severity gate
    # -------------------------------------------------------------------------
    # By default PSSA reports Error / Warning / Information. CI fails on any
    # Error or Warning. We do NOT include Information here because PSSA emits
    # a Information-level diagnostic for several formatting choices that we do
    # not want to auto-fail on (e.g. line length suggestions). Information is
    # still reported in the analyzer output for awareness.
    # -------------------------------------------------------------------------
    Severity = @('Error', 'Warning')

    # -------------------------------------------------------------------------
    # ExcludeRules
    # -------------------------------------------------------------------------
    # We deliberately do NOT exclude any rules globally. Per-file suppression
    # via [Diagnostics.CodeAnalysis.SuppressMessageAttribute] is allowed where
    # the suppression has a comment explaining why. If you find yourself
    # adding a rule to ExcludeRules, that is a signal to instead suppress at
    # the call site with a justification.
    # -------------------------------------------------------------------------
    ExcludeRules = @()

    # -------------------------------------------------------------------------
    # Rules
    # -------------------------------------------------------------------------
    # Per-rule configuration. Each rule that takes options is configured here.
    # -------------------------------------------------------------------------
    Rules = @{

        # ---------------------------------------------------------------------
        # PSUseCompatibleSyntax: target multiple PowerShell language versions.
        # ---------------------------------------------------------------------
        # If a future contributor uses (for example) the PowerShell 7+
        # null-conditional operator `?.`, this rule fails CI -- preventing a
        # working-on-pwsh-7 / broken-on-WindowsPowerShell-5.1 surprise.
        # ---------------------------------------------------------------------
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @(
                '5.1'    # Windows PowerShell 5.1 -- the prod runtime
                '7.4'    # PowerShell 7.4 LTS -- cross-platform pwsh
            )
        }

        # ---------------------------------------------------------------------
        # PSUseCompatibleCmdlets: target multiple PowerShell platform/edition
        # combinations.
        # ---------------------------------------------------------------------
        # The "compatibility" profiles are JSON files shipped with PSSA. They
        # enumerate which cmdlets exist on each platform/edition. Reference:
        #   https://github.com/PowerShell/PSScriptAnalyzer/tree/master/PSCompatibilityCollector/profiles
        # ---------------------------------------------------------------------
        PSUseCompatibleCmdlets = @{
            Compatibility = @(
                'desktop-5.1.14393.206-windows'  # Windows PowerShell 5.1
                'core-7.2.0-windows'              # pwsh on Windows
                'core-7.2.0-linux'                # pwsh on Linux (CI matrix)
            )
        }

        # ---------------------------------------------------------------------
        # PSUseConsistentIndentation: 4 spaces, no tabs.
        # ---------------------------------------------------------------------
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }

        # ---------------------------------------------------------------------
        # PSUseConsistentWhitespace: enable all the sub-checks the rule offers.
        # ---------------------------------------------------------------------
        PSUseConsistentWhitespace = @{
            Enable                          = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckSeparator                  = $true
            CheckParameter                  = $true
            CheckInnerBrace                 = $true
            CheckPipeForRedundantWhitespace = $true
        }

        # ---------------------------------------------------------------------
        # PSPlaceOpenBrace: opening brace on the same line as the statement.
        # ---------------------------------------------------------------------
        # `function Foo {` not `function Foo` newline `{`. PowerShell-team
        # convention; matches what `Get-Help`'s formatter and most code
        # samples use.
        # ---------------------------------------------------------------------
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        # ---------------------------------------------------------------------
        # PSPlaceCloseBrace: closing brace on its own line.
        # ---------------------------------------------------------------------
        PSPlaceCloseBrace = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
    }
}
