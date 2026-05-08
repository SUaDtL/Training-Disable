# =============================================================================
# tests/PesterConfiguration.psd1 -- WAM Training Disable
# =============================================================================
#
# Pester 5 configuration. Loaded by the CI workflow and -- because it is
# parameter-compatible with Pester's New-PesterConfiguration -- by any
# developer who runs:
#
#     Invoke-Pester -Configuration (New-PesterConfiguration -Hashtable `
#         (Import-PowerShellDataFile -Path ./tests/PesterConfiguration.psd1))
#
# Hoisting the configuration into a .psd1 keeps CI and local runs in sync,
# the same way PSScriptAnalyzerSettings.psd1 does for the linter.
#
# Why .psd1 and not .json or .yaml?
# ---------------------------------
# Pester's New-PesterConfiguration expects a hashtable. Import-PowerShellDataFile
# returns a hashtable from a .psd1 with no Invoke-Expression risk on a
# tampered file (.psd1 is data-only by spec). JSON would also work but
# loses comments. YAML would require a separate dependency. .psd1 is the
# PowerShell-native, sign-able, comment-supporting choice.
#
# Coverage threshold
# ------------------
# At PR 2 there is no v2 module yet, so CodeCoverage is disabled. Once
# src/WamTrainingDisable/ exists (PR 3+) the CodeCoverage section will be
# turned on with paths pointing at Public/ and Private/ and a 80% threshold.
# Leaving the section commented-out documents the intent without breaking
# the early CI runs.
# =============================================================================

@{
    # -------------------------------------------------------------------------
    # Run section: which tests to discover and how to fail.
    # -------------------------------------------------------------------------
    Run = @{
        # Pester searches recursively from this path. We point at ./tests so
        # both the unit suites (added in PR 4+) and the integration suite
        # (added in this PR) are picked up.
        Path = './tests'

        # Throw on test failure so the CI step exits non-zero. Without this,
        # Pester exits with code 0 even if assertions failed.
        Throw = $true

        # Exit on test errors (vs. discovery errors). We want both to fail CI.
        Exit = $true
    }

    # -------------------------------------------------------------------------
    # Filter section: which tests run.
    # -------------------------------------------------------------------------
    Filter = @{
        # Tags can be used by future suites to mark slow / network-dependent
        # tests. None at PR 2.
        ExcludeTag = @()
    }

    # -------------------------------------------------------------------------
    # Output section: how Pester prints results.
    # -------------------------------------------------------------------------
    Output = @{
        # 'Detailed' prints each It block's name + status. 'Diagnostic' is
        # noisier (good for debugging Pester itself); 'Normal' hides It-level
        # detail. 'Detailed' is the right balance for a CI log.
        Verbosity = 'Detailed'

        # Color the output even on a non-tty CI runner. GitHub Actions
        # render ANSI escape codes correctly.
        CIFormat = 'Auto'
    }

    # -------------------------------------------------------------------------
    # TestResult section: NUnit-format XML for CI artifact upload.
    # -------------------------------------------------------------------------
    TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
        OutputPath = 'TestResults.xml'
    }

    # -------------------------------------------------------------------------
    # CodeCoverage section -- INTENTIONALLY DISABLED at PR 2.
    # -------------------------------------------------------------------------
    # Will be enabled in PR 4 when the v2 module starts to exist. The shape
    # of the configuration we expect is documented here so the wiring is
    # visible at review time:
    #
    #     CodeCoverage = @{
    #         Enabled               = $true
    #         Path                  = @(
    #             './src/WamTrainingDisable/Public'
    #             './src/WamTrainingDisable/Private'
    #         )
    #         OutputFormat          = 'JaCoCo'
    #         OutputPath            = 'CoverageReport.xml'
    #         CoveragePercentTarget = 80
    #     }
    #
    # We do not commit this enabled at PR 2 because PSScriptAnalyzer and the
    # CI workflow have nothing to scan yet -- enabling coverage now would
    # produce zero-coverage warnings that obscure real failures.
    # -------------------------------------------------------------------------
    CodeCoverage = @{
        Enabled = $false
    }
}
