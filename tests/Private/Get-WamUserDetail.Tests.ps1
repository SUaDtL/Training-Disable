# =============================================================================
# tests/Private/Get-WamUserDetail.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# This file is the unit test suite for Get-WamUserDetail, the single-call
# Get-ADUser wrapper that fetches a user's WAM-relevant attributes and
# resolves their group memberships to display names. The function returns a
# [pscustomobject] with SamAccountName, Name, Enabled, whenCreated, Department,
# OfficePhone, Description, DistinguishedName, and MemberOf (display names,
# not DNs).
#
# Defect-4 fix
# -------
# v1's WAM-ADSearch made TWO Get-ADUser calls per user:
#   1. Get-ADUser -Identity $User -Properties Department, OfficePhone,
#      whenCreated, MemberOf
#   2. Get-ADUser $ADAccount -Properties memberof
#
# The second call was redundant: MemberOf was already requested in the first.
# v2 fixes this by making a single Get-ADUser call with the union of all
# properties, then resolving group names inline via Get-ADGroup per DN in
# the MemberOf array. This halves the AD load per user.
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
    # at tests/Private/Get-WamUserDetail.Tests.ps1, so two levels up (..)
    # gets us to the repo root. We use Resolve-Path to handle symbolic links
    # and relative-to-absolute conversion.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module. We import before each Describe so private functions
    # are available via InModuleScope; AfterAll removes it.
    Import-Module -Name $script:ModulePath -Force

    # Install no-op stubs for AD cmdlets directly inside the module's session
    # state. Pester's Mock requires the target command to exist before
    # intercepting it; on a Linux runner the ActiveDirectory module is not
    # installed, so we install stubs explicitly. See
    # tests/_helpers/ModuleStubs.ps1 for the long-form rationale.
    . (Join-Path -Path $PSScriptRoot -ChildPath '../_helpers/ModuleStubs.ps1')
    Install-WamModuleStubs
}

AfterAll {
    # Clean up the module import to avoid polluting other test runs in the
    # same session.
    if (Get-Module -Name 'WamTrainingDisable' -ErrorAction SilentlyContinue) {
        Remove-Module -Name 'WamTrainingDisable' -Force
    }
}

Describe 'Get-WamUserDetail' {

    Context 'happy path' {

        BeforeEach {
            # Default Get-ADUser mock returns a record with all the attributes
            # Get-WamUserDetail requests. This is the golden path: the user
            # exists, is enabled, and has two group memberships.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Get-ADUser -MockWith {
                    [pscustomobject] @{
                        SamAccountName = $Identity
                        Name = 'Alice Normal'
                        Enabled = $true
                        whenCreated = [datetime]'2024-01-01'
                        Department = 'Engineering'
                        OfficePhone = '555-1212'
                        Description = 'Software Engineer II'
                        DistinguishedName = 'CN=alice.normal,OU=Users,DC=corp'
                        MemberOf = @(
                            'CN=Engineers,OU=Groups,DC=corp'
                            'CN=VIP No Tng Req,OU=Groups,DC=corp'
                        )
                    }
                }

                # Default Get-ADGroup mock parses the CN from the DN and returns it
                # as the display name. This is the standard behavior when the group
                # record exists and is resolvable.
                Mock -CommandName Get-ADGroup -MockWith {
                    if ($Identity -match '^CN=([^,]+)') {
                        [pscustomobject] @{ Name = $matches[1] }
                    }
                    else {
                        [pscustomobject] @{ Name = [string] $Identity }
                    }
                }
            }
        }

        It 'calls Get-ADUser exactly once (defect-4 fix; v1 made two calls per user)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $null = Get-WamUserDetail -Identity 'alice.normal'
                Should -Invoke Get-ADUser -Times 1
            }
        }

        It 'returns SamAccountName from the AD record' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.SamAccountName | Should -Be 'alice.normal'
            }
        }

        It 'returns Name from the AD record' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.Name | Should -Be 'Alice Normal'
            }
        }

        It 'returns Enabled as bool' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.Enabled | Should -BeOfType [bool]
                $detail.Enabled | Should -Be $true
            }
        }

        It 'returns whenCreated as datetime' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.whenCreated | Should -Be ([datetime]'2024-01-01')
            }
        }

        It 'returns Department as supplied' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.Department | Should -Be 'Engineering'
            }
        }

        It 'returns OfficePhone as supplied' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.OfficePhone | Should -Be '555-1212'
            }
        }

        It 'returns Description as supplied' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.Description | Should -Be 'Software Engineer II'
            }
        }

        It 'returns DistinguishedName as supplied' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.DistinguishedName | Should -Be 'CN=alice.normal,OU=Users,DC=corp'
            }
        }

        It 'requests the union of v1 + v2 properties from Get-ADUser' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $null = Get-WamUserDetail -Identity 'alice.normal'
                Should -Invoke Get-ADUser -ParameterFilter {
                    $Properties -contains 'Department' -and
                    $Properties -contains 'OfficePhone' -and
                    $Properties -contains 'whenCreated' -and
                    $Properties -contains 'MemberOf' -and
                    $Properties -contains 'Description' -and
                    $Properties -contains 'DistinguishedName' -and
                    $Properties -contains 'Enabled'
                }
            }
        }

        It 'passes -ErrorAction Stop to Get-ADUser' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $null = Get-WamUserDetail -Identity 'alice.normal'
                Should -Invoke Get-ADUser -ParameterFilter { $ErrorAction -eq 'Stop' }
            }
        }
    }

    Context 'group resolution' {

        BeforeEach {
            # Set up the default mocks for group resolution tests. The default
            # Get-ADUser returns two groups; tests can override as needed.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Get-ADUser -MockWith {
                    [pscustomobject] @{
                        SamAccountName = $Identity
                        Name = 'Alice Normal'
                        Enabled = $true
                        whenCreated = [datetime]'2024-01-01'
                        Department = 'Engineering'
                        OfficePhone = '555-1212'
                        Description = 'Software Engineer II'
                        DistinguishedName = 'CN=alice.normal,OU=Users,DC=corp'
                        MemberOf = @(
                            'CN=Engineers,OU=Groups,DC=corp'
                            'CN=VIP No Tng Req,OU=Groups,DC=corp'
                        )
                    }
                }

                Mock -CommandName Get-ADGroup -MockWith {
                    if ($Identity -match '^CN=([^,]+)') {
                        [pscustomobject] @{ Name = $matches[1] }
                    }
                    else {
                        [pscustomobject] @{ Name = [string] $Identity }
                    }
                }
            }
        }

        It 'MemberOf is the resolved display-name array, not DNs' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.MemberOf | Should -Be @('Engineers', 'VIP No Tng Req')
            }
        }

        It 'calls Get-ADGroup once per DN in MemberOf' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $null = Get-WamUserDetail -Identity 'alice.normal'
                Should -Invoke Get-ADGroup -Times 2
            }
        }

        It 'empty MemberOf yields an empty MemberOf array' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Override Get-ADUser to return MemberOf = @()
                Mock -CommandName Get-ADUser -MockWith {
                    [pscustomobject] @{
                        SamAccountName = $Identity
                        Name = 'Alice Normal'
                        Enabled = $true
                        whenCreated = [datetime]'2024-01-01'
                        Department = 'Engineering'
                        OfficePhone = '555-1212'
                        Description = 'Software Engineer II'
                        DistinguishedName = 'CN=alice.normal,OU=Users,DC=corp'
                        MemberOf = @()
                    }
                }

                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.MemberOf.Count | Should -Be 0
                Should -Invoke Get-ADGroup -Times 0
            }
        }

        It 'Get-ADGroup returning $null for a DN -> entry skipped, others kept' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Discriminate by the supplied $Identity rather than a counter.
                # PowerShell scope rules mean a `$callCount++` inside the mock
                # scriptblock would NOT persist across invocations (read-from-
                # parent / write-to-local), so we use the DN's CN as the key.
                # The Engineers group's lookup returns $null (simulating a
                # deleted-group race); the VIP group resolves normally.
                Mock -CommandName Get-ADGroup -MockWith {
                    if ($Identity -like 'CN=Engineers,*') {
                        return $null
                    }
                    if ($Identity -match '^CN=([^,]+)') {
                        [pscustomobject] @{ Name = $matches[1] }
                    }
                    else {
                        [pscustomobject] @{ Name = [string] $Identity }
                    }
                }

                $detail = Get-WamUserDetail -Identity 'alice.normal'
                $detail.MemberOf.Count | Should -Be 1
                $detail.MemberOf[0] | Should -Be 'VIP No Tng Req'
            }
        }

        It 'Get-ADGroup is called with -ErrorAction SilentlyContinue (so a deleted-group race does not abort the user)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $null = Get-WamUserDetail -Identity 'alice.normal'
                Should -Invoke Get-ADGroup -ParameterFilter { $ErrorAction -eq 'SilentlyContinue' }
            }
        }
    }

    Context 'error propagation' {

        BeforeEach {
            # Set up default mocks before each error propagation test.
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                Mock -CommandName Get-ADUser -MockWith {
                    [pscustomobject] @{
                        SamAccountName = $Identity
                        Name = 'Alice Normal'
                        Enabled = $true
                        whenCreated = [datetime]'2024-01-01'
                        Department = 'Engineering'
                        OfficePhone = '555-1212'
                        Description = 'Software Engineer II'
                        DistinguishedName = 'CN=alice.normal,OU=Users,DC=corp'
                        MemberOf = @(
                            'CN=Engineers,OU=Groups,DC=corp'
                            'CN=VIP No Tng Req,OU=Groups,DC=corp'
                        )
                    }
                }

                Mock -CommandName Get-ADGroup -MockWith {
                    if ($Identity -match '^CN=([^,]+)') {
                        [pscustomobject] @{ Name = $matches[1] }
                    }
                    else {
                        [pscustomobject] @{ Name = [string] $Identity }
                    }
                }
            }
        }

        It 'Get-ADUser throwing propagates as a terminating error' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Override Get-ADUser to throw an error message that mimics
                # the ActiveDirectory module's behavior when an identity is
                # not found.
                Mock -CommandName Get-ADUser -MockWith {
                    throw 'AD: identity not found'
                }

                { Get-WamUserDetail -Identity 'ghost.user' } |
                    Should -Throw -ExpectedMessage '*identity not found*'
            }
        }

        It 'output object has the expected member set' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $detail = Get-WamUserDetail -Identity 'alice.normal'

                # Verify the output object has exactly the expected properties.
                # Sort both arrays before comparison to ensure order does not
                # affect the assertion.
                $detail.PSObject.Properties.Name | Sort-Object | Should -Be (
                    @(
                        'Department',
                        'Description',
                        'DistinguishedName',
                        'Enabled',
                        'MemberOf',
                        'Name',
                        'OfficePhone',
                        'SamAccountName',
                        'whenCreated'
                    ) | Sort-Object
                )
            }
        }
    }
}
