# =============================================================================
# tests/Private/Resolve-WamConfiguration.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# Unit tests for the Resolve-WamConfiguration private function. This function
# walks the five-layer configuration stack, deep-merges them, and returns a
# unified hashtable. The layers are:
#
#   1. Shipped defaults (WamTrainingDisable.config.psd1)
#   2. Project config (-ConfigPath)
#   3. User config ($env:LOCALAPPDATA / $env:HOME/.config)
#   4. Environment variables (WAM_* prefix)
#   5. Parameter overrides (highest precedence)
#
# Each test verifies one layer's behavior or the interaction between layers.
# =============================================================================

#Requires -Version 5.1

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # In Pester 5, BeforeDiscovery runs during the discovery phase and is
    # where we compute paths used in test names. We have no data-driven
    # test names here, so this block is empty but present as a discoverable
    # anchor (Pester complains if BeforeAll references $PSScriptRoot without
    # this block).
}

BeforeAll {
    # Resolve repo paths from this script's location. The test lives at
    # tests/Private/, so two levels up is the repo root.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module. We use InModuleScope to invoke the private function.
    Import-Module -Name $script:ModulePath -Force
}

Describe 'Resolve-WamConfiguration' {

    # =========================================================================
    # Layer 1: Shipped defaults
    # =========================================================================

    Context 'Layer 1: shipped defaults' {

        It 'defaults load and contain expected keys' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $cfg.Policy.GracePeriodDays | Should -Be 30
                $cfg.Sql.UsernameColumn | Should -Be 'nt_username'
                $cfg.Logging.LegacyTimestamp | Should -Be $false
                $cfg.Logging.TimestampFormat | Should -Be 'yyyy-MM-dd HH:mm:ss'
            }
        }

        It 'ExemptOus default is the v1-equivalent set' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $result = $cfg.Policy.ExemptOus -join ','
                $result | Should -Be 'REL,SCO'
            }
        }

        It 'defaults are independent across calls' {
            # This test guards against a cross-call pollution hazard: if
            # Resolve-WamConfiguration returned a shared singleton hashtable
            # (common but dangerous), then mutating the result of one call
            # would affect the next call. To prevent this, the function
            # re-reads the defaults file on every invocation, allocating a
            # fresh hashtable each time. This test mutates a returned config
            # and asserts that a subsequent call still sees the original
            # values. The guarantee is subtle but critical: if a Public
            # cmdlet (or unit test) writes to the result hashtable, it must
            # not affect the next invocation.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg1 = Resolve-WamConfiguration
                $cfg1.Policy.GracePeriodDays = 999

                $cfg2 = Resolve-WamConfiguration
                $cfg2.Policy.GracePeriodDays | Should -Be 30
            }
        }
    }

    # =========================================================================
    # Layer 2: Project config (-ConfigPath)
    # =========================================================================

    Context 'Layer 2: -ConfigPath' {

        It 'project config overrides defaults' {
            $projectConfigPath = Join-Path -Path $TestDrive -ChildPath 'proj.psd1'
            Set-Content -Path $projectConfigPath -Value '@{ Policy = @{ GracePeriodDays = 7 } }' -Encoding utf8

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock -Parameters @{
                ProjectConfigPath = $projectConfigPath
            } {
                param($ProjectConfigPath)
                $cfg = Resolve-WamConfiguration -ConfigPath $ProjectConfigPath
                $cfg.Policy.GracePeriodDays | Should -Be 7
                # Deep merge: unspecified keys are preserved from defaults
                ($cfg.Policy.ExemptOus -join ',') | Should -Be 'REL,SCO'
            }
        }

        It 'missing -ConfigPath throws' {
            $missingPath = Join-Path -Path $TestDrive -ChildPath "does-not-exist-$([guid]::NewGuid()).psd1"

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock -Parameters @{
                MissingPath = $missingPath
            } {
                param($MissingPath)
                { Resolve-WamConfiguration -ConfigPath $MissingPath } | Should -Throw -ExpectedMessage '*does not exist*'
            }
        }
    }

    # =========================================================================
    # Layer 4: Environment variables
    # =========================================================================

    Context 'Layer 4: environment variables' {

        BeforeAll {
            # Snapshot the original environment so we can restore it per test.
            # This prevents env var leaks between tests in the same session.
            $script:OriginalEnv = @{}
            @(
                'WAM_SQL_CONNECTION'
                'WAM_SQL_STORED_PROCEDURE'
                'WAM_SQL_USERNAME_COLUMN'
                'WAM_SQL_TIMEOUT_SECONDS'
                'WAM_GRACE_PERIOD_DAYS'
                'WAM_LOG_DIR'
                'WAM_LOG_ENCODING'
                'WAM_LEGACY_TIMESTAMP'
                'WAM_TIMESTAMP_FORMAT'
                'WAM_VIP_DN_PATTERN'
            ) | ForEach-Object {
                $script:OriginalEnv[$_] = [System.Environment]::GetEnvironmentVariable($_)
            }
        }

        AfterEach {
            # Restore all WAM_* env vars to their original state. This is
            # critical: Pester runs multiple tests in a single PowerShell
            # process, so an env var set in one test leaks to all subsequent
            # tests in the same session unless we restore it explicitly.
            $script:OriginalEnv.GetEnumerator() | ForEach-Object {
                [System.Environment]::SetEnvironmentVariable($_.Key, $_.Value)
            }
        }

        It 'WAM_GRACE_PERIOD_DAYS coerces to [int]' {
            [System.Environment]::SetEnvironmentVariable('WAM_GRACE_PERIOD_DAYS', '14')

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $cfg.Policy.GracePeriodDays | Should -Be 14
                $cfg.Policy.GracePeriodDays | Should -BeOfType [int]
            }
        }

        It 'WAM_LEGACY_TIMESTAMP truthy values' -ForEach @(
            @{ Value = 'true' }
            @{ Value = '1' }
            @{ Value = 'yes' }
            @{ Value = 'on' }
            @{ Value = 'TRUE' }
        ) {
            # The boolean coercion for WAM_LEGACY_TIMESTAMP follows the Docker
            # / Kubernetes convention: '1', 'true', 'yes', 'on' (case-insensitive)
            # are $true; everything else is $false. This matches the deployment
            # ecosystem most PowerShell users interact with.
            [System.Environment]::SetEnvironmentVariable('WAM_LEGACY_TIMESTAMP', $Value)

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $cfg.Logging.LegacyTimestamp | Should -Be $true
            }
        }

        It 'WAM_LEGACY_TIMESTAMP falsy values' -ForEach @(
            @{ Value = 'false' }
            @{ Value = '0' }
            @{ Value = 'no' }
            @{ Value = 'off' }
            @{ Value = 'gibberish' }
        ) {
            # Any value that does not match the truthy set becomes $false.
            [System.Environment]::SetEnvironmentVariable('WAM_LEGACY_TIMESTAMP', $Value)

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $cfg.Logging.LegacyTimestamp | Should -Be $false
            }
        }

        It 'WAM_VIP_DN_PATTERN reaches deep-nested key' {
            [System.Environment]::SetEnvironmentVariable('WAM_VIP_DN_PATTERN', '*OU=Executive*')

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $cfg.Logging.Channels.VipDistinguishedNamePattern | Should -Be '*OU=Executive*'
            }
        }

        It 'empty env var is treated as unset' {
            # Setting an env var to an empty string should be equivalent to
            # not setting it at all. The default value is preserved.
            [System.Environment]::SetEnvironmentVariable('WAM_GRACE_PERIOD_DAYS', '')

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration
                $cfg.Policy.GracePeriodDays | Should -Be 30
            }
        }
    }

    # =========================================================================
    # Layer 5: Parameter overrides
    # =========================================================================

    Context 'Layer 5: ParameterOverrides' {

        BeforeAll {
            # Snapshot and restore env vars again. Even though this Context
            # tests parameter overrides (layer 5), test #6 sets env vars
            # (layer 4) to verify that overrides win; we must restore.
            $script:OriginalEnv = @{}
            @('WAM_GRACE_PERIOD_DAYS') | ForEach-Object {
                $script:OriginalEnv[$_] = [System.Environment]::GetEnvironmentVariable($_)
            }
        }

        AfterEach {
            $script:OriginalEnv.GetEnumerator() | ForEach-Object {
                [System.Environment]::SetEnvironmentVariable($_.Key, $_.Value)
            }
        }

        It 'ParameterOverrides win over env vars' {
            # Layer 5 (parameter overrides) has higher precedence than layer 4
            # (env vars). Set an env var to one value, pass an override with
            # a different value, and assert the override wins.
            [System.Environment]::SetEnvironmentVariable('WAM_GRACE_PERIOD_DAYS', '14')

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration -ParameterOverrides @{ Policy = @{ GracePeriodDays = 99 } }
                $cfg.Policy.GracePeriodDays | Should -Be 99
            }
        }

        It 'deep-merge: nested keys merge, sibling keys preserved' {
            # Deep merging means that only the keys specified in the override
            # are replaced; unspecified keys at the same nesting level are
            # preserved from the lower layer. This test overrides one key in
            # the Logging hashtable and asserts that an unrelated key
            # (LegacyTimestamp) is still the default.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration -ParameterOverrides @{
                    Logging = @{ TimestampFormat = 'X' }
                }
                $cfg.Logging.TimestampFormat | Should -Be 'X'
                $cfg.Logging.LegacyTimestamp | Should -Be $false
            }
        }

        It 'arrays are REPLACED, not concatenated' {
            # Arrays are replaced wholesale, not merged. If the default
            # ExemptOus is @('REL', 'SCO') and the override specifies
            # @('VIP'), the result must be @('VIP') exactly, not
            # @('REL', 'SCO', 'VIP'). This is a critical distinction for
            # correctness: a user who overrides the exempt-OU list expects
            # to REPLACE it, not append to it.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $cfg = Resolve-WamConfiguration -ParameterOverrides @{
                    Policy = @{ ExemptOus = @('VIP') }
                }
                $result = $cfg.Policy.ExemptOus -join ','
                $result | Should -Be 'VIP'
            }
        }
    }

    # =========================================================================
    # Layer interaction
    # =========================================================================

    Context 'Layer interaction' {

        BeforeAll {
            # Snapshot env vars for cleanup.
            $script:OriginalEnv = @{}
            @('WAM_GRACE_PERIOD_DAYS') | ForEach-Object {
                $script:OriginalEnv[$_] = [System.Environment]::GetEnvironmentVariable($_)
            }
        }

        AfterAll {
            $script:OriginalEnv.GetEnumerator() | ForEach-Object {
                [System.Environment]::SetEnvironmentVariable($_.Key, $_.Value)
            }
        }

        It 'all layers cooperate' {
            # This test exercises all five layers in a single call:
            # - Defaults: ExemptOus (not overridden, falls through)
            # - Env var: WAM_GRACE_PERIOD_DAYS
            # - Project config: Sql.ConnectionString
            # - Parameter overrides: Logging.LegacyTimestamp
            # The result should reflect all layers in precedence order.
            [System.Environment]::SetEnvironmentVariable('WAM_GRACE_PERIOD_DAYS', '14')

            $projectConfigPath = Join-Path -Path $TestDrive -ChildPath 'proj-multi.psd1'
            Set-Content -Path $projectConfigPath -Value '@{ Sql = @{ ConnectionString = "project-conn" } }' -Encoding utf8

            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock -Parameters @{
                ProjectConfigPath = $projectConfigPath
            } {
                param($ProjectConfigPath)
                $cfg = Resolve-WamConfiguration `
                    -ConfigPath $ProjectConfigPath `
                    -ParameterOverrides @{ Logging = @{ LegacyTimestamp = $true } }

                # Env var (layer 4)
                $cfg.Policy.GracePeriodDays | Should -Be 14
                # Project config (layer 2)
                $cfg.Sql.ConnectionString | Should -Be 'project-conn'
                # Parameter override (layer 5)
                $cfg.Logging.LegacyTimestamp | Should -Be $true
                # Default (layer 1)
                ($cfg.Policy.ExemptOus -join ',') | Should -Be 'REL,SCO'
            }

            # Clean up the env var.
            [System.Environment]::SetEnvironmentVariable('WAM_GRACE_PERIOD_DAYS', $null)
        }
    }
}
