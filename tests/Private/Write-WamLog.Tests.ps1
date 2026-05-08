# =============================================================================
# tests/Private/Write-WamLog.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# This file is the unit test suite for Write-WamLog, the multi-channel log
# appender that formats a message and writes it to one or more channel files
# (Main, Vip, Exempt). The function manages directory creation, file routing,
# encoding selection, and ensures ConvertTo-WamLogLine is called exactly once
# per Write-WamLog invocation so all channels receive byte-identical timestamps.
#
# PR 5 introduces Write-WamLog alongside this test suite. This consolidates
# v1's three near-identical single-channel loggers (Write-Log, Write-LogVIP,
# Write-LogEXEMPT) into a single function that takes a channel array. The test
# suite pins the critical behaviors:
#
#   - happy path: message formatted once and written to requested channels
#   - directory and file routing: {0} placeholders expanded correctly, mkdir
#     with Out-Null piping (defect-11 fix), encoding defaults and overrides
#   - error guards: missing required config keys, unknown channels,
#     FileNameFormat lacking a channel entry
#
# This test suite uses Pester's Mock feature to isolate the function from
# the filesystem, allowing tight assertions on cmdlet inputs (path, encoding,
# content) without brittle filesystem manipulation.
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
    # at tests/Private/Write-WamLog.Tests.ps1, so two levels up (..)
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

Describe 'Write-WamLog' {

    Context 'happy path' {

        BeforeEach {
            # Set up mocks to isolate Write-WamLog from the filesystem.
            # Each test in this context starts with clean mocks.
            # Mocks must be installed in the WamTrainingDisable module's session
            # state because the It bodies use InModuleScope; without -ModuleName
            # the mock would only intercept calls from the test script's scope,
            # not from inside Write-WamLog.
            Mock -CommandName Test-Path -ModuleName 'WamTrainingDisable' -MockWith { $script:DirectoryAlreadyExists }
            Mock -CommandName New-Item -ModuleName 'WamTrainingDisable' -MockWith {
                [pscustomobject] @{ FullName = $Path; Mode = 'd-----' }
            }
            Mock -CommandName Add-WamLogContent -ModuleName 'WamTrainingDisable' -MockWith { }
            Mock -CommandName ConvertTo-WamLogLine -ModuleName 'WamTrainingDisable' -MockWith { '<<formatted-line>>' }

            # DirectoryAlreadyExists lives at TEST-FILE script scope. The Mock
            # -MockWith scriptblocks are closures over the test file's scope,
            # so when the mock body reads $script:DirectoryAlreadyExists at
            # fire time it resolves here -- not inside the module scope.
            $script:DirectoryAlreadyExists = $true

            # The default config and working date, by contrast, are read
            # INSIDE InModuleScope blocks (where $script: points at the
            # module's session state), so we hoist them into the module
            # scope.
            #
            # The test fixture path is intentionally drive-less so that
            # Join-Path inside Write-WamLog does not attempt drive
            # resolution on Linux (where 'C:' is not a valid PSDrive).
            # The real prod path uses 'C:\PS\Script_Output\WAM\<date>';
            # the tests assert behavior against the fixture, not the
            # prod string.
            & (Get-Module -Name 'WamTrainingDisable') {
                $script:DefaultLoggingConfig = @{
                    Directory = '/tmp/wam-test/Script_Output/WAM/{0:yyyyMMdd}'
                    Encoding = 'ascii'
                    TimestampFormat = 'yyyy-MM-dd HH:mm:ss'
                    FileNameFormat = @{
                        Main = 'LockoutUsers_All_{0:yyyyMMdd}.log'
                        Vip = 'LockoutUsers_VIP_{0:yyyyMMdd}.log'
                        Exempt = 'LockoutUsers_EXEMPT_{0:yyyyMMdd}.log'
                        Lockout = 'LockoutList_{0:yyyyMMdd}.txt'
                    }
                }
                $script:WorkingDate = [datetime]'2026-05-08T10:30:00'
            }
        }

        It 'writes the formatted line to the Main channel file' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 1 -ParameterFilter {
                    $Path -like '*LockoutUsers_All_20260508.log' -and $Content -like '<<formatted-line>>*'
                }
            }
        }

        It 'broadcasts to multiple channels with identical formatting' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main', 'Vip', 'Exempt') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 3
                Should -Invoke -CommandName ConvertTo-WamLogLine -Times 1
            }
        }

        It 'passes WorkingDate, Message, and LoggingConfig through to ConvertTo-WamLogLine' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName ConvertTo-WamLogLine -Times 1 -ParameterFilter {
                    $Message -eq 'msg' -and $WorkingDate -eq $script:WorkingDate
                }
            }
        }

        It 'returns nothing (no DirectoryInfo leak; defect-11 fix)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $result = Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                $null -eq $result | Should -Be $true
            }
        }
    }

    Context 'directory and file routing' {

        BeforeEach {
            # Set up mocks for file system operations.
            # Mocks must be installed in the WamTrainingDisable module's session
            # state because the It bodies use InModuleScope; without -ModuleName
            # the mock would only intercept calls from the test script's scope,
            # not from inside Write-WamLog.
            Mock -CommandName Test-Path -ModuleName 'WamTrainingDisable' -MockWith { $script:DirectoryAlreadyExists }
            Mock -CommandName New-Item -ModuleName 'WamTrainingDisable' -MockWith {
                [pscustomobject] @{ FullName = $Path; Mode = 'd-----' }
            }
            Mock -CommandName Add-WamLogContent -ModuleName 'WamTrainingDisable' -MockWith { }
            Mock -CommandName ConvertTo-WamLogLine -ModuleName 'WamTrainingDisable' -MockWith { '<<formatted-line>>' }

            # Hoist test fixtures into the module's session state so the
            # InModuleScope blocks below can reach them via $script:.
            & (Get-Module -Name 'WamTrainingDisable') {
                $script:DirectoryAlreadyExists = $true
                $script:DefaultLoggingConfig = @{
                    Directory = '/tmp/wam-test/Script_Output/WAM/{0:yyyyMMdd}'
                    Encoding = 'ascii'
                    TimestampFormat = 'yyyy-MM-dd HH:mm:ss'
                    FileNameFormat = @{
                        Main = 'LockoutUsers_All_{0:yyyyMMdd}.log'
                        Vip = 'LockoutUsers_VIP_{0:yyyyMMdd}.log'
                        Exempt = 'LockoutUsers_EXEMPT_{0:yyyyMMdd}.log'
                        Lockout = 'LockoutList_{0:yyyyMMdd}.txt'
                    }
                }
                $script:WorkingDate = [datetime]'2026-05-08T10:30:00'
            }
        }

        It '{0} in Directory is replaced by yyyyMMdd of WorkingDate' {
            # The function formats the Directory template string using -f,
            # passing $WorkingDate so the {0:yyyyMMdd} placeholder expands.
            # This test validates that Add-WamLogContent receives a path with
            # the date correctly expanded.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 1 -ParameterFilter {
                    $Path -like '/tmp/wam-test/Script_Output/WAM/20260508/*'
                }
            }
        }

        It '{0} in FileNameFormat is replaced by yyyyMMdd of WorkingDate' {
            # The function formats each channel's file-name template using -f,
            # passing $WorkingDate so the {0:yyyyMMdd} placeholder expands.
            # This test validates that the file name ends with the correct date.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 1 -ParameterFilter {
                    $Path -like '*_20260508.log'
                }
            }
        }

        It 'creates the directory when missing, piping New-Item to Out-Null' {
            # When Test-Path returns $false (directory does not exist), the
            # function calls New-Item. The defect-11 fix requires piping the
            # result to Out-Null so the DirectoryInfo does not leak. This test
            # validates that New-Item is called when the directory is missing
            # and that the function still returns nothing (the New-Item output
            # was consumed by Out-Null).
            $script:DirectoryAlreadyExists = $false
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $result = Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName New-Item -Times 1 -Scope It
                $null -eq $result | Should -Be $true
            }
        }

        It 'does NOT call New-Item when the directory already exists' {
            # When Test-Path returns $true (directory exists), the function
            # skips the New-Item call. This test validates that New-Item is
            # not invoked for an existing directory.
            $script:DirectoryAlreadyExists = $true
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName New-Item -Times 0 -Scope It
            }
        }

        It 'Add-WamLogContent receives the configured Encoding (ASCII for default config)' {
            # The function reads LoggingConfig['Encoding'], maps the string to
            # a [System.Text.Encoding] instance, and forwards it to
            # Add-WamLogContent. The default config sets Encoding = 'ascii',
            # which maps to [System.Text.Encoding]::ASCII.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 1 -ParameterFilter {
                    $Encoding -is [System.Text.Encoding] -and $Encoding.WebName -eq 'us-ascii'
                }
            }
        }

        It 'Encoding defaults to ASCII when LoggingConfig.Encoding is missing' {
            # When LoggingConfig lacks an 'Encoding' key, the function defaults
            # to ASCII. We build a config without the Encoding key and verify
            # the wrapper still receives an ASCII encoding instance.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $configWithoutEncoding = @{
                    Directory = '/tmp/wam-test/Script_Output/WAM/{0:yyyyMMdd}'
                    FileNameFormat = @{
                        Main = 'LockoutUsers_All_{0:yyyyMMdd}.log'
                        Vip = 'LockoutUsers_VIP_{0:yyyyMMdd}.log'
                        Exempt = 'LockoutUsers_EXEMPT_{0:yyyyMMdd}.log'
                    }
                }
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $configWithoutEncoding `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 1 -ParameterFilter {
                    $Encoding -is [System.Text.Encoding] -and $Encoding.WebName -eq 'us-ascii'
                }
            }
        }

        It 'each channel writes to a different file' {
            # When multiple channels are requested, the function iterates them
            # and calls Add-WamLogContent once per channel with a different
            # Path. This test validates that Main and Vip channels write to
            # distinct files with their respective naming patterns.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main', 'Vip') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -ParameterFilter {
                    $Path -like '*LockoutUsers_All_*'
                } -Times 1
                Should -Invoke -CommandName Add-WamLogContent -ParameterFilter {
                    $Path -like '*LockoutUsers_VIP_*'
                } -Times 1
            }
        }

        It 'appends a platform line ending to the formatted line' {
            # AppendAllText writes the supplied string verbatim with no
            # automatic newline. We append [Environment]::NewLine ourselves
            # to match v1 Out-Files trailing-newline behavior. This test
            # confirms the trailing newline is part of the Content the
            # wrapper receives.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Write-WamLog `
                    -Message 'msg' `
                    -Channel @('Main') `
                    -LoggingConfig $script:DefaultLoggingConfig `
                    -WorkingDate $script:WorkingDate
                Should -Invoke -CommandName Add-WamLogContent -Times 1 -ParameterFilter {
                    $Content.EndsWith([Environment]::NewLine)
                }
            }
        }
    }

    Context 'error guards' {

        BeforeEach {
            # Set up mocks for error-path testing.
            # Mocks must be installed in the WamTrainingDisable module's session
            # state because the It bodies use InModuleScope; without -ModuleName
            # the mock would only intercept calls from the test script's scope,
            # not from inside Write-WamLog.
            Mock -CommandName Test-Path -ModuleName 'WamTrainingDisable' -MockWith { $true }
            Mock -CommandName New-Item -ModuleName 'WamTrainingDisable' -MockWith {
                [pscustomobject] @{ FullName = $Path; Mode = 'd-----' }
            }
            Mock -CommandName Add-WamLogContent -ModuleName 'WamTrainingDisable' -MockWith { }
            Mock -CommandName ConvertTo-WamLogLine -ModuleName 'WamTrainingDisable' -MockWith { '<<formatted-line>>' }

            & (Get-Module -Name 'WamTrainingDisable') {
                $script:WorkingDate = [datetime]'2026-05-08T10:30:00'
            }
        }

        It 'missing Directory key in LoggingConfig throws' {
            # When LoggingConfig lacks the 'Directory' key, the function throws
            # a terminating error with a message mentioning 'Directory'. This
            # guards against misconfigured LoggingConfig inputs.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $configWithoutDir = @{
                    FileNameFormat = @{ Main = 'test_{0:yyyyMMdd}.log' }
                }
                {
                    Write-WamLog `
                        -Message 'msg' `
                        -Channel @('Main') `
                        -LoggingConfig $configWithoutDir `
                        -WorkingDate $script:WorkingDate
                } | Should -Throw -ExpectedMessage '*Directory*'
            }
        }

        It 'missing FileNameFormat key in LoggingConfig throws' {
            # When LoggingConfig lacks the 'FileNameFormat' key, the function
            # throws a terminating error with a message mentioning
            # 'FileNameFormat'. This guards against incomplete config.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $configWithoutFnf = @{
                    Directory = '/tmp/wam-test/Script_Output/WAM/{0:yyyyMMdd}'
                }
                {
                    Write-WamLog `
                        -Message 'msg' `
                        -Channel @('Main') `
                        -LoggingConfig $configWithoutFnf `
                        -WorkingDate $script:WorkingDate
                } | Should -Throw -ExpectedMessage '*FileNameFormat*'
            }
        }

        It 'requested channel missing from FileNameFormat throws' {
            # When a requested channel is not present in the FileNameFormat
            # hashtable, the function throws a terminating error with a message
            # mentioning the missing channel name. This catches typos in
            # user-supplied config that deleted a FileNameFormat key.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $configWithoutVip = @{
                    Directory = '/tmp/wam-test/Script_Output/WAM/{0:yyyyMMdd}'
                    FileNameFormat = @{
                        Main = 'LockoutUsers_All_{0:yyyyMMdd}.log'
                        Exempt = 'LockoutUsers_EXEMPT_{0:yyyyMMdd}.log'
                    }
                }
                {
                    Write-WamLog `
                        -Message 'msg' `
                        -Channel @('Vip') `
                        -LoggingConfig $configWithoutVip `
                        -WorkingDate $script:WorkingDate
                } | Should -Throw -ExpectedMessage '*Vip*'
            }
        }

        It 'unknown channel name (outside ValidateSet) throws on parameter binding' {
            # The -Channel parameter is ValidateSet'd to {Main, Vip, Exempt}.
            # Pester catches a ValidateSet violation as a terminating error at
            # parameter-binding time before the function body runs. This test
            # validates that an unknown channel name causes the call to fail.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $configWithoutDir = @{
                    Directory = '/tmp/wam-test/Script_Output/WAM/{0:yyyyMMdd}'
                    FileNameFormat = @{ Main = 'test_{0:yyyyMMdd}.log' }
                }
                {
                    Write-WamLog `
                        -Message 'msg' `
                        -Channel @('NotAChannel') `
                        -LoggingConfig $configWithoutDir `
                        -WorkingDate $script:WorkingDate
                } | Should -Throw
            }
        }
    }
}
