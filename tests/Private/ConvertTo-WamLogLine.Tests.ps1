# =============================================================================
# tests/Private/ConvertTo-WamLogLine.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# This file is the unit test suite for ConvertTo-WamLogLine, the pure
# log-line formatting function that emits timestamp + hostname + message
# in either v2-ISO or v1-legacy shape. The function is the testable seam
# that lets us validate timestamp rendering without I/O, making it easy
# to assert exact output across different cultural contexts.
#
# PR 4 introduces ConvertTo-WamLogLine alongside this test suite. PR 5's
# Write-WamLog will call this function to format each line, and this test
# suite pins the expected output for every combination:
#
#   - v2 default (ISO 8601 under InvariantCulture)
#   - v2 with custom format strings
#   - v1 legacy (culture-dependent short date + long time)
#   - edge cases: empty hostname, multi-line message, brackets in message
#
# The LegacyTimestamp opt-in is critical because v1's scheduled task
# runs every day, and downstream consumers (if any) may parse the log
# format; we must be able to reproduce v1's byte-for-byte output when
# an operator sets LegacyTimestamp = $true. This test captures all the
# variants so v2's implementation can be refactored later without
# regressing the legacy shape.
#
# =============================================================================

#Requires -Version 5.1

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Pester 5 requires BeforeDiscovery to exist if we reference $PSScriptRoot
    # in computed test names; we keep it as an anchor even though this file
    # has no parameterized test discovery.
}

BeforeAll {
    # Resolve the repo root from this script's location. The test file lives
    # at tests/Private/ConvertTo-WamLogLine.Tests.ps1, so two levels up (..)
    # gets us to the repo root. We use Resolve-Path to handle symbolic links
    # and relative-to-absolute conversion.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module. We import before each Describe so private functions
    # are available via InModuleScope; AfterAll removes it.
    Import-Module -Name $script:ModulePath -Force
}

AfterAll {
    # Clean up the module import to avoid polluting other test runs in the
    # same session.
    if (Get-Module -Name 'WamTrainingDisable' -ErrorAction SilentlyContinue) {
        Remove-Module -Name 'WamTrainingDisable' -Force
    }
}

Describe 'ConvertTo-WamLogLine' {

    Context 'default v2 ISO output' {

        It 'empty LoggingConfig produces ISO timestamp' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $line = ConvertTo-WamLogLine `
                    -Message 'hello' `
                    -LoggingConfig @{} `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -ComputerName 'TESTHOST'
                $line | Should -Be '[2026-05-08 10:30:00] [TESTHOST] hello'
            }
        }

        It 'custom TimestampFormat is honored' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $line = ConvertTo-WamLogLine `
                    -Message 'msg' `
                    -LoggingConfig @{ TimestampFormat = 'yyyy-MM-ddTHH:mm:ssZ' } `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -ComputerName 'H'
                $line | Should -Be '[2026-05-08T10:30:00Z] [H] msg'
            }
        }

        It 'InvariantCulture pin survives a non-en-US CurrentCulture' {
            # This test validates that the implementation formats the ISO
            # timestamp under [System.Globalization.CultureInfo]::InvariantCulture
            # rather than the ambient CurrentCulture. v1 did not pin the culture,
            # which caused a bug: a de-DE operator would see '08.05.2026' (dots
            # as date separators) instead of '2026-05-08' (dashes as separators).
            # v2's default behavior pins InvariantCulture so the timestamp is
            # stable regardless of where the code runs.
            #
            # We test this by temporarily switching the thread's CurrentCulture
            # to German and validating that the output still uses dashes. If
            # the implementation failed to pin InvariantCulture, a German culture
            # would render '08.05.2026' and the test would catch the regression.
            $previousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('de-DE')
                InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                    $line = ConvertTo-WamLogLine `
                        -Message 'hello' `
                        -LoggingConfig @{} `
                        -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                        -ComputerName 'TESTHOST'
                    $line | Should -Be '[2026-05-08 10:30:00] [TESTHOST] hello'
                }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previousCulture
            }
        }

        It 'empty ComputerName emits empty brackets without error' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $line = ConvertTo-WamLogLine `
                    -Message 'm' `
                    -LoggingConfig @{} `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -ComputerName ''
                $line | Should -Be '[2026-05-08 10:30:00] [] m'
            }
        }

        It 'multi-line Message round-trips verbatim' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $line = ConvertTo-WamLogLine `
                    -Message "line1`nline2" `
                    -LoggingConfig @{} `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -ComputerName 'H'
                $line | Should -Be "[2026-05-08 10:30:00] [H] line1`nline2"
            }
        }
    }

    Context 'LegacyTimestamp = $true' {

        It 'reproduces v1s en-US shape under en-US culture' {
            # When LegacyTimestamp is $true, the implementation calls
            # ToShortDateString() and ToLongTimeString() under the ambient
            # CurrentCulture. v1 had no culture pinning, which means the output
            # is culture-dependent. The prod scheduled task runs on Windows
            # servers that are configured for en-US, so the expected output
            # is '5/8/2026 10:30:00 AM' (American date + time format). This test
            # confirms that v2 reproduces that shape faithfully when running
            # under en-US culture.
            $previousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('en-US')
                InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                    $line = ConvertTo-WamLogLine `
                        -Message 'hello' `
                        -LoggingConfig @{ LegacyTimestamp = $true } `
                        -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                        -ComputerName 'TESTHOST'
                    $line | Should -Be '[5/8/2026 10:30:00 AM] [TESTHOST] hello'
                }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previousCulture
            }
        }

        It 'LegacyTimestamp ignores TimestampFormat' {
            # When LegacyTimestamp is $true, the implementation ignores any
            # TimestampFormat key in the LoggingConfig hashtable. It calls
            # ToShortDateString() and ToLongTimeString() directly, bypassing
            # the format-string path. This test confirms that including
            # TimestampFormat in the config does not affect the output.
            $previousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('en-US')
                InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                    $line = ConvertTo-WamLogLine `
                        -Message 'x' `
                        -LoggingConfig @{
                        LegacyTimestamp = $true
                        TimestampFormat = 'this-must-be-ignored'
                    } `
                        -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                        -ComputerName 'TESTHOST'
                    $line | Should -Be '[5/8/2026 10:30:00 AM] [TESTHOST] x'
                }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previousCulture
            }
        }

        It 'truthy non-bool LegacyTimestamp value coerces to legacy mode' {
            # The implementation casts the LegacyTimestamp value to [bool],
            # which means any truthy value (1, "yes", $true, etc.) triggers
            # legacy mode. This test confirms that passing 1 instead of $true
            # still activates the legacy timestamp shape. This flexibility
            # allows config sources (JSON, CSV, etc.) to provide boolean values
            # without strict type checking.
            $previousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('en-US')
                InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                    $line = ConvertTo-WamLogLine `
                        -Message 'x' `
                        -LoggingConfig @{ LegacyTimestamp = 1 } `
                        -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                        -ComputerName 'H'
                    $line | Should -Be '[5/8/2026 10:30:00 AM] [H] x'
                }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previousCulture
            }
        }
    }

    Context 'message content edge cases' {

        It 'message containing literal brackets is preserved' {
            # The function builds its output by concatenating strings with
            # hardcoded '[' and ']' delimiters. A message that contains
            # brackets (e.g., '[user.name]') is part of the message segment,
            # not parsed as structural delimiters. This test confirms the
            # function does not strip or escape message content. The PR 2
            # snapshot test later strips the prefix '[timestamp] [host]' to
            # compare normalized content; this test confirms the prefix
            # pattern stays well-defined: only the LEADING two bracketed
            # groups are structural, the rest is message.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $line = ConvertTo-WamLogLine `
                    -Message '[bracketed-content]' `
                    -LoggingConfig @{} `
                    -WorkingDate ([datetime]'2026-05-08T10:30:00') `
                    -ComputerName 'H'
                $line | Should -Be '[2026-05-08 10:30:00] [H] [bracketed-content]'
            }
        }
    }
}
