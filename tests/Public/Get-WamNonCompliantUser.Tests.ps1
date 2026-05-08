# =============================================================================
# tests/Public/Get-WamNonCompliantUser.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# Unit tests for Get-WamNonCompliantUser, the Public cmdlet that queries the
# WAM SQL source and projects DataRows to [pscustomobject] with SamAccountName.
#
# The function is the primary entry point for the non-compliant user discovery
# stage. It orchestrates configuration resolution (via Resolve-WamConfiguration),
# SQL execution (via Invoke-WamSqlStoredProcedure), and row projection with
# DOMAIN\ prefix stripping (defect-12 fix: returns ALL rows, not just the first).
#
# This test suite pins:
#
#   1. Row projection: DataTable rows are enumerated; one [pscustomobject] per
#      row; DOMAIN\ prefix is stripped; order is preserved.
#   2. Config resolution: parameter overrides flow through; shipped defaults are
#      used when parameters are omitted; empty-string defect is avoided.
#   3. Edge cases: $null DataTable, empty DataTable, [DBNull] username values.
#
# =============================================================================

#Requires -Version 5.1

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    # Resolve the repo root from this script's location. The test file lives
    # at tests/Public/Get-WamNonCompliantUser.Tests.ps1, so two levels up (..)
    # gets us to the repo root. We use Resolve-Path to handle symbolic links
    # and relative-to-absolute conversion.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module so we can test Get-WamNonCompliantUser in InModuleScope
    # (needed to mock the Private helper Invoke-WamSqlStoredProcedure).
    Import-Module -Name $script:ModulePath -Force

    # -------------------------------------------------------------------------
    # Helper: factory for constructing fake DataTables.
    # -------------------------------------------------------------------------
    # Builds a System.Data.DataTable with a single column and zero or more
    # rows. We declare the helper at GLOBAL scope so it is visible from
    # inside Pester Mock -MockWith bodies, which run in a Pester-internal
    # scope when Mocks target a module via InModuleScope. Test-file
    # script: scope does not survive that boundary on pwsh 7.
    # The leading comma in the return statement prevents PowerShell from
    # unrolling the DataTable (whose rows are enumerable) into individual
    # DataRow objects.
    # -------------------------------------------------------------------------
    function global:New-WamFakeNonCompliantTable {
        [CmdletBinding()]
        param(
            [Parameter()]
            [string] $UsernameColumn = 'nt_username',

            [Parameter()]
            [string[]] $Rows
        )

        $table = New-Object -TypeName System.Data.DataTable
        $null = $table.Columns.Add($UsernameColumn, [string])

        foreach ($r in $Rows) {
            $null = $table.Rows.Add($r)
        }

        return ,$table
    }
}

AfterAll {
    # Clean up the module import to avoid polluting other test runs in the
    # same session.
    if (Get-Module -Name 'WamTrainingDisable' -ErrorAction SilentlyContinue) {
        Remove-Module -Name 'WamTrainingDisable' -Force
    }

    # And the global helper function so a subsequent test file does not
    # see it leaking across boundaries.
    if (Test-Path -Path 'function:global:New-WamFakeNonCompliantTable') {
        Remove-Item -Path 'function:global:New-WamFakeNonCompliantTable' -Force
    }
}

Describe 'Get-WamNonCompliantUser' {

    # =========================================================================
    # CONTEXT: row projection
    # =========================================================================
    # Validates that DataTable rows are correctly enumerated, projected to
    # [pscustomobject], and DOMAIN\ prefixes are stripped. The defect-12 fix
    # is verified: all rows are returned, not just the first.
    # =========================================================================
    Context 'row projection' {

        It 'returns one [pscustomobject] per DataTable row (defect-12 fix; v1 truncated to first row)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # v1 had Select-Object -Index 0, which truncated to the first row
                # only. v2 enumerates all rows. This test confirms all three rows
                # are returned.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @('DOMAIN\alice', 'DOMAIN\bob', 'DOMAIN\carol')
                }

                $results = @(Get-WamNonCompliantUser)

                $results.Count | Should -Be 3
            }
        }

        It 'strips DOMAIN\ prefix from rows that carry one' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The backslash prefix (domain name before the first backslash)
                # is stripped. Different domain prefixes are handled correctly.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @('CORP\alice.normal', 'OTHERDOMAIN\bob.lonely')
                }

                $results = @(Get-WamNonCompliantUser)

                $results[0].SamAccountName | Should -Be 'alice.normal'
                $results[1].SamAccountName | Should -Be 'bob.lonely'
            }
        }

        It 'rows without a backslash pass through unchanged' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # If a row has no backslash (already bare SamAccountName or the
                # stored procedure schema changed), it is surfaced unchanged.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @('charlie.bare')
                }

                $results = @(Get-WamNonCompliantUser)

                $results[0].SamAccountName | Should -Be 'charlie.bare'
            }
        }

        It 'each emitted record exposes SamAccountName as a property' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Every returned object is a [pscustomobject] with at minimum
                # a SamAccountName property. This test confirms the property
                # is present.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @('CORP\user1')
                }

                $results = @(Get-WamNonCompliantUser)

                $results[0].PSObject.Properties.Name | Should -Contain 'SamAccountName'
            }
        }

        It 'preserves row order' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Rows are enumerated in the order they appear in the DataTable.
                # This test confirms a specific sequence is preserved.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @('CORP\first', 'CORP\second', 'CORP\third')
                }

                $results = @(Get-WamNonCompliantUser)

                @($results[0..2].SamAccountName) | Should -Be @('first', 'second', 'third')
            }
        }
    }

    # =========================================================================
    # CONTEXT: config resolution
    # =========================================================================
    # Validates that configuration resolution flows correctly, parameter
    # overrides win over defaults, and the shipped defaults are applied when
    # parameters are omitted. The empty-string defect (where bound-but-empty
    # parameters would override defaults) is verified as avoided.
    # =========================================================================
    Context 'config resolution' {

        It 'uses the shipped default StoredProcedure when none is supplied' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The shipped default StoredProcedure is 'orc.get_Pers_Training_Disable_Accounts'
                # (from WamTrainingDisable.config.psd1). When the caller does not supply
                # -StoredProcedure, the resolved config uses this default.
                Mock -CommandName Invoke-WamSqlStoredProcedure -ParameterFilter {
                    $StoredProcedure -eq 'orc.get_Pers_Training_Disable_Accounts'
                } -MockWith {
                    New-WamFakeNonCompliantTable -Rows @()
                }

                Get-WamNonCompliantUser

                Should -Invoke Invoke-WamSqlStoredProcedure -ParameterFilter {
                    $StoredProcedure -eq 'orc.get_Pers_Training_Disable_Accounts'
                } -Times 1
            }
        }

        It 'ConnectionString parameter overrides the resolved config' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The -ConnectionString parameter, when supplied, overrides the
                # resolved config value. Invoke-WamSqlStoredProcedure receives
                # the override value.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @()
                }

                Get-WamNonCompliantUser -ConnectionString 'Server=alt;Database=alt;'

                Should -Invoke Invoke-WamSqlStoredProcedure -ParameterFilter {
                    $ConnectionString -eq 'Server=alt;Database=alt;'
                } -Times 1
            }
        }

        It 'StoredProcedure parameter overrides the resolved config' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The -StoredProcedure parameter, when supplied, overrides the
                # resolved config value.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @()
                }

                Get-WamNonCompliantUser -StoredProcedure 'sp_alt'

                Should -Invoke Invoke-WamSqlStoredProcedure -ParameterFilter {
                    $StoredProcedure -eq 'sp_alt'
                } -Times 1
            }
        }

        It 'UsernameColumn parameter overrides the resolved config (column read)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The -UsernameColumn parameter specifies which column to read
                # from the DataTable. When supplied, it overrides the config value
                # (default 'nt_username'). The function reads from the supplied
                # column name.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -UsernameColumn 'custom_user' -Rows @('CORP\dave')
                }

                $results = @(Get-WamNonCompliantUser -UsernameColumn 'custom_user')

                $results[0].SamAccountName | Should -Be 'dave'
            }
        }

        It 'CommandTimeoutSeconds is forwarded from the resolved config (default 60)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The shipped default CommandTimeoutSeconds is 60
                # (from WamTrainingDisable.config.psd1). When the caller does not
                # supply -CommandTimeoutSeconds, this default is resolved and
                # forwarded to Invoke-WamSqlStoredProcedure.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @()
                }

                Get-WamNonCompliantUser

                Should -Invoke Invoke-WamSqlStoredProcedure -ParameterFilter {
                    $CommandTimeoutSeconds -eq 60
                } -Times 1
            }
        }

        It 'unspecified parameters are NOT forwarded (the empty-string defect)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The function builds the sqlOverrides hashtable by checking
                # PSBoundParameters. Only parameters the caller actually supplied
                # are included; bound-but-empty parameters do NOT pollute the
                # overrides. This test confirms that when no parameters are supplied,
                # Invoke-WamSqlStoredProcedure receives a valid (non-empty, non-null)
                # ConnectionString from the resolved config, not an empty string.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @()
                }

                Get-WamNonCompliantUser

                Should -Invoke Invoke-WamSqlStoredProcedure -ParameterFilter {
                    $null -ne $ConnectionString -and $ConnectionString -ne ''
                } -Times 1
            }
        }
    }

    # =========================================================================
    # CONTEXT: edge cases
    # =========================================================================
    # Validates behavior when SQL returns $null or empty results, and when
    # a column value is [DBNull].
    # =========================================================================
    Context 'edge cases' {

        It 'returns nothing when Invoke-WamSqlStoredProcedure returns $null' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # If the SQL seam returns $null (no data, connection error, etc.),
                # the function returns nothing (empty collection). The caller sees
                # no objects.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    return $null
                }

                $results = @(Get-WamNonCompliantUser)

                $results.Count | Should -Be 0
            }
        }

        It 'returns nothing when DataTable has zero rows' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # An empty DataTable (zero rows) results in no output.
                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    New-WamFakeNonCompliantTable -Rows @()
                }

                $results = @(Get-WamNonCompliantUser)

                $results.Count | Should -Be 0
            }
        }

        It 'a DBNull username surfaces as the empty string' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # If a column value is [System.DBNull]::Value (a NULL in SQL),
                # casting it to [string] produces the empty string. The function
                # does NOT strip a backslash from an empty string.
                $table = New-Object -TypeName System.Data.DataTable
                $null = $table.Columns.Add('nt_username', [string])
                $null = $table.Rows.Add([System.DBNull]::Value)

                Mock -CommandName Invoke-WamSqlStoredProcedure -MockWith {
                    return ,$table
                }

                $results = @(Get-WamNonCompliantUser)

                $results[0].SamAccountName | Should -Be ''
            }
        }
    }
}
