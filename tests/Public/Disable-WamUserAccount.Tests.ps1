# =============================================================================
# tests/Public/Disable-WamUserAccount.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# Unit tests for Disable-WamUserAccount, the single-user AD disable cmdlet.
# The function disables an account and appends a training-non-compliance note
# to the description. Three key v1 defects are fixed in v2:
#
#   1. Identity is now a parameter (v1 used dynamic scope).
#   2. Success tracking uses a local boolean, not $Error shadowing.
#   3. Caller passes ExistingDescription (v1 re-fetched the user).
#
# Structure
# ---------
# One Describe block contains four Context blocks: 'happy path',
# 'description format', 'WhatIf gating', and 'error path'. Inside each
# Context, It blocks exercise specific scenarios and pin expected behavior.
#
# Mocking
# -------
# Disable-ADAccount and Set-ADUser are mocked inside InModuleScope so we can
# drive the AD write path independently of AD connectivity. Tests that need
# to simulate AD failures override the mocks with exception-throwing versions.
#
# Culture pinning
# ---------------
# The LegacyTimestamp tests pin CurrentCulture to en-US inside a try/finally
# block, following the pattern in ConvertTo-WamLogLine.Tests.ps1. This ensures
# the v1-exact shape (culture-dependent date format) is validated regardless
# of the test runner's locale.
#
# =============================================================================

#Requires -Version 5.1

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    # Resolve the repo root from this script's location. The test file lives
    # at tests/Public/Disable-WamUserAccount.Tests.ps1, so two levels up (..)
    # gets us to the repo root. We use Resolve-Path to handle symbolic links
    # and relative-to-absolute conversion.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module. We use InModuleScope below to mock Disable-ADAccount
    # and Set-ADUser, which are internal calls within Disable-WamUserAccount.
    Import-Module -Name $script:ModulePath -Force

    # Install no-op stubs for AD cmdlets directly inside the module's session
    # state. Pester's Mock requires the target command to exist before
    # intercepting it; on a Linux runner the ActiveDirectory module is not
    # installed, so we install stubs explicitly. See
    # tests/_helpers/ModuleStubs.ps1 for the long-form rationale.
    . (Join-Path -Path $PSScriptRoot -ChildPath '../_helpers/ModuleStubs.ps1')
    Install-WamModuleStubs

    # -------------------------------------------------------------------------
    # Pinned reference date for all tests.
    # -------------------------------------------------------------------------
    # This date is used throughout the test suite to ensure deterministic
    # output regardless of when the tests run. All description-suffix
    # assertions use this date.
    # -------------------------------------------------------------------------
    $script:WorkingDate = [datetime]'2026-05-08T10:30:00'
}

AfterAll {
    # Clean up the module import to avoid polluting other test runs in the
    # same session.
    if (Get-Module -Name 'WamTrainingDisable' -ErrorAction SilentlyContinue) {
        Remove-Module -Name 'WamTrainingDisable' -Force
    }
}

Describe 'Disable-WamUserAccount' {

    # =========================================================================
    # Context: happy path
    # =========================================================================
    # Happy-path tests verify that the function successfully disables an
    # account and updates its description. Mocks for Disable-ADAccount and
    # Set-ADUser are set to do nothing (success path), and we verify that
    # both are called with the correct parameters. Tests in this context
    # pass -Confirm:$false to suppress the High-impact prompt.
    # =========================================================================
    Context 'happy path' {

        BeforeEach {
            # Set up successful mocks that do nothing.
            Mock -CommandName Disable-ADAccount -ModuleName 'WamTrainingDisable' -MockWith { }
            Mock -CommandName Set-ADUser -ModuleName 'WamTrainingDisable' -MockWith { }
        }

        It 'calls Disable-ADAccount with -Identity' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Disable-ADAccount -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $Identity -eq 'alice.normal'
            } -Times 1 -Scope It
        }

        It 'calls Set-ADUser with -Identity matching Disable-ADAccount' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $Identity -eq 'alice.normal'
            } -Times 1 -Scope It
        }

        It 'returns $true on success' {
            $result = Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            $result | Should -Be $true
        }

        It 'passes -ErrorAction Stop to Disable-ADAccount' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Disable-ADAccount -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $ErrorAction -eq 'Stop'
            } -Times 1 -Scope It
        }

        It 'passes -ErrorAction Stop to Set-ADUser' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $ErrorAction -eq 'Stop'
            } -Times 1 -Scope It
        }

        It 'does not re-fetch the user via Get-ADUser (defect-4: caller passes ExistingDescription)' {
            # v1 called Get-ADUser inside Disable-WamUserAccount, making two
            # round-trips to AD per user (one in the orchestrator, one here).
            # v2 requires the caller to pass ExistingDescription, avoiding the
            # redundant fetch. We mock Get-ADUser to throw if called; if the
            # implementation calls it anyway, the test fails.
            Mock -CommandName Get-ADUser -ModuleName 'WamTrainingDisable' -MockWith { throw 'should not be called' }

            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Get-ADUser -ModuleName 'WamTrainingDisable' -Times 0 -Scope It
        }
    }

    # =========================================================================
    # Context: description format
    # =========================================================================
    # These tests verify the exact shape of the description suffix. Two
    # shapes are tested: the v2 default (ISO 8601, culture-invariant, with
    # closing paren) and the v1 legacy shape (culture-dependent short date,
    # trailing period, missing closing paren). The legacy tests pin
    # CurrentCulture to en-US to ensure the v1 shape is reproduced byte-for-byte.
    # =========================================================================
    Context 'description format' {

        BeforeEach {
            Mock -CommandName Disable-ADAccount -ModuleName 'WamTrainingDisable' -MockWith { }
            Mock -CommandName Set-ADUser -ModuleName 'WamTrainingDisable' -MockWith { }
        }

        It 'default suffix uses ISO 8601 date with closing paren' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'Software Engineer II' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $Description -eq 'Software Engineer II, (Account disabled for training non-compliance on 2026-05-08)'
            } -Times 1 -Scope It
        }

        It 'default suffix is culture-stable (ISO under de-DE culture remains dashes)' {
            # The implementation formats the default suffix under InvariantCulture,
            # which means the date is always 'YYYY-MM-DD' regardless of the
            # thread's CurrentCulture. We test this by switching CurrentCulture
            # to de-DE (which would render '08.05.2026' for ToShortDateString)
            # and verifying the output still has dashes.
            $previousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('de-DE')

                Disable-WamUserAccount `
                    -Identity 'alice.normal' `
                    -ExistingDescription 'Software Engineer II' `
                    -WorkingDate $script:WorkingDate `
                    -Confirm:$false

                Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                    $Description -eq 'Software Engineer II, (Account disabled for training non-compliance on 2026-05-08)'
                } -Times 1 -Scope It
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previousCulture
            }
        }

        It 'LegacyTimestamp under en-US reproduces v1 exact shape (trailing period, missing close paren)' {
            # v1 used ToShortDateString() without culture pinning. On an en-US
            # system, this renders '5/8/2026'. v1 also had a typo: trailing
            # period and no closing parenthesis. We reproduce this shape exactly
            # when -LegacyTimestamp is passed, for compatibility with downstream
            # consumers that scrape the description field. The fixture
            # 'ad-calls.enforcement.json' pins this shape.
            $previousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('en-US')

                Disable-WamUserAccount `
                    -Identity 'alice.normal' `
                    -ExistingDescription 'Software Engineer II' `
                    -WorkingDate $script:WorkingDate `
                    -LegacyTimestamp `
                    -Confirm:$false

                Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                    $Description -eq 'Software Engineer II, (Account disabled for training non-compliance on 5/8/2026.'
                } -Times 1 -Scope It
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previousCulture
            }
        }

        It 'empty ExistingDescription still composes a valid suffix' {
            # ExistingDescription is mandatory but [AllowEmptyString()], so the
            # caller can pass ''. In that case, the suffix is appended to an
            # empty string, resulting in a description that starts with ', '.
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription '' `
                -WorkingDate $script:WorkingDate `
                -Confirm:$false

            Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $Description -eq ', (Account disabled for training non-compliance on 2026-05-08)'
            } -Times 1 -Scope It
        }

        It 'WorkingDate parameter is honored (default and explicit overrides differ)' {
            # The default value of WorkingDate is [datetime]::Now, but tests
            # pass an explicit date. This test verifies that a different
            # WorkingDate produces a different suffix. We use a date string in
            # the -Like comparison to validate the format without hardcoding
            # the entire suffix.
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'Test User' `
                -WorkingDate ([datetime]'2027-12-31T23:59:59') `
                -Confirm:$false

            Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -ParameterFilter {
                $Description -like '*2027-12-31)'
            } -Times 1 -Scope It
        }
    }

    # =========================================================================
    # Context: WhatIf gating
    # =========================================================================
    # SupportsShouldProcess + ConfirmImpact='High' gates the AD writes. When
    # -WhatIf is passed, the function returns early without calling
    # Disable-ADAccount or Set-ADUser. These tests verify that behavior.
    # =========================================================================
    Context 'WhatIf gating' {

        BeforeEach {
            Mock -CommandName Disable-ADAccount -ModuleName 'WamTrainingDisable' -MockWith { }
            Mock -CommandName Set-ADUser -ModuleName 'WamTrainingDisable' -MockWith { }
        }

        It 'WhatIf does NOT call Disable-ADAccount' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -WhatIf

            Should -Invoke Disable-ADAccount -ModuleName 'WamTrainingDisable' -Times 0 -Scope It
        }

        It 'WhatIf does NOT call Set-ADUser' {
            Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -WhatIf

            Should -Invoke Set-ADUser -ModuleName 'WamTrainingDisable' -Times 0 -Scope It
        }

        It 'WhatIf returns nothing' {
            $result = Disable-WamUserAccount `
                -Identity 'alice.normal' `
                -ExistingDescription 'SE II' `
                -WorkingDate $script:WorkingDate `
                -WhatIf

            $null -eq $result | Should -Be $true
        }
    }

    # =========================================================================
    # Context: error path
    # =========================================================================
    # These tests verify error handling when Disable-ADAccount or Set-ADUser
    # throw an exception. The function catches the exception, writes it as a
    # non-terminating error, and returns $false. Tests use -ErrorAction
    # SilentlyContinue to suppress the Write-Error output. Defect 2 (v1's
    # $Error shadowing) is fixed by using a local boolean.
    # =========================================================================
    Context 'error path' {

        It 'Disable-ADAccount throwing causes the function to return $false (no $Error shadowing; defect-2 fix)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Disable-ADAccount -MockWith { throw 'AD failure' }
                Mock -CommandName Set-ADUser -ModuleName 'WamTrainingDisable' -MockWith { }

                $result = Disable-WamUserAccount `
                    -Identity 'a' `
                    -ExistingDescription 'd' `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue

                $result | Should -Be $false
            }
        }

        It 'Disable-ADAccount throwing prevents Set-ADUser from running' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Disable-ADAccount -MockWith { throw 'AD failure' }
                Mock -CommandName Set-ADUser -ModuleName 'WamTrainingDisable' -MockWith { }

                Disable-WamUserAccount `
                    -Identity 'a' `
                    -ExistingDescription 'd' `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue

                Should -Invoke Set-ADUser -Times 0 -Scope It
            }
        }

        It 'Set-ADUser throwing causes the function to return $false (Disable-ADAccount succeeded but the description update failed)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Disable-ADAccount -ModuleName 'WamTrainingDisable' -MockWith { }
                Mock -CommandName Set-ADUser -MockWith { throw 'AD failure on description' }

                $result = Disable-WamUserAccount `
                    -Identity 'a' `
                    -ExistingDescription 'd' `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue

                $result | Should -Be $false
            }
        }

        It 'Set-ADUser throwing does NOT undo the Disable-ADAccount call' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Disable-ADAccount -ModuleName 'WamTrainingDisable' -MockWith { }
                Mock -CommandName Set-ADUser -MockWith { throw 'AD failure on description' }

                Disable-WamUserAccount `
                    -Identity 'a' `
                    -ExistingDescription 'd' `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue

                # The disable has already run; we do not attempt to roll back.
                Should -Invoke Disable-ADAccount -Times 1 -Scope It
            }
        }
    }
}
