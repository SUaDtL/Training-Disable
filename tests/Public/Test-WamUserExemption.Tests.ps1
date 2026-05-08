# =============================================================================
# tests/Public/Test-WamUserExemption.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# Unit tests for Test-WamUserExemption, the pure decision-matrix function
# that determines whether a user is exempt from WAM training disablement and
# which log channels should receive a decision record.
#
# This function is the heart of v2's exemption logic. The test suite pins
# each branch of the precedence ladder, boundary conditions (grace-period
# cutoffs), VIP routing orthogonality, and precedence interactions. By
# design, the Reason strings match the v1 log messages verbatim (captured
# in the snapshot fixtures); changing any of them requires a corresponding
# fixture update.
#
# Structure
# ---------
# One Describe block contains multiple Context blocks: one per decision
# branch, one for VIP routing, and one for precedence interactions.
# Inside each Context, It blocks exercise specific scenarios and pin
# expected outputs.
#
# Helpers
# -------
# New-FakeUser: rapid construction of test user records with the minimal
# shape: Enabled, whenCreated, DistinguishedName, MemberOf. The real
# Get-ADUser returns many more fields; this pares it down to what
# Test-WamUserExemption actually consumes.
# =============================================================================

#Requires -Version 5.1

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    # Resolve repo paths from this script's location. Using $PSScriptRoot
    # is the Pester-recommended pattern; it works whether the test is
    # invoked from the repo root, from inside ./tests, or from a CI step
    # that uses an arbitrary working directory.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module. We use the Public function directly; no InModuleScope
    # is required because Test-WamUserExemption is a public cmdlet.
    Import-Module -Name $script:ModulePath -Force

    # -------------------------------------------------------------------------
    # Helper: construct a user record for testing.
    # -------------------------------------------------------------------------
    # The real Get-ADUser returns Enabled, whenCreated, DistinguishedName,
    # MemberOf, Department, OfficePhone, and many others. For this pure
    # function, we only care about the exemption-relevant fields. Enabled
    # gates branch 1; whenCreated gates branch 2; DistinguishedName gates
    # branches 3 and VIP routing; MemberOf gates branch 4.
    # -------------------------------------------------------------------------
    function script:New-FakeUser {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [bool] $Enabled,

            [Parameter(Mandatory)]
            [datetime] $WhenCreated,

            [Parameter(Mandatory)]
            [string] $DistinguishedName,

            [Parameter()]
            [string[]] $MemberOf = @()
        )
        return [pscustomobject] @{
            Enabled = $Enabled
            whenCreated = $WhenCreated
            DistinguishedName = $DistinguishedName
            MemberOf = $MemberOf
        }
    }

    # -------------------------------------------------------------------------
    # Pinned reference date for grace-period arithmetic.
    # -------------------------------------------------------------------------
    # All grace-period calculations are relative to this point in time.
    # By pinning it, we ensure boundary tests (exactly 30 days, 31 days)
    # produce deterministic results without depending on the actual date
    # when the test runs.
    # -------------------------------------------------------------------------
    $script:PinnedNow = [datetime]'2026-05-08T10:30:00'

    # -------------------------------------------------------------------------
    # Default policy matching the v1 shipped config.
    # -------------------------------------------------------------------------
    # GracePeriodDays=30, ExemptOus=@('REL','SCO'), ExemptGroups matching
    # the Exempt array from v1. The OuMatchPattern uses -f substitution
    # where {0} is the OU name.
    # -------------------------------------------------------------------------
    $script:Policy = @{
        GracePeriodDays = 30
        ExemptOus = @('REL', 'SCO')
        ExemptGroups = @('VIP No Tng Req', 'Temp No Tng Req')
        OuMatchPattern = '*OU={0}*'
    }

    # -------------------------------------------------------------------------
    # VIP pattern matching the v1 shipped logging config.
    # -------------------------------------------------------------------------
    # The unification fix in v2: one pattern, applied uniformly across all
    # decision branches. v1 had inconsistent patterns in different code
    # paths; we settle on the substring match here.
    # -------------------------------------------------------------------------
    $script:VipPattern = '*OU=VIP*'
}

Describe 'Test-WamUserExemption' {

    # =========================================================================
    # Branch 1: account is already disabled
    # =========================================================================
    # An account with Enabled=$false bypasses all other checks and is
    # considered "exempt" (not that it needs exempting -- it's just already
    # done). v1 logs this to Main only, NOT to the Exempt channel, because
    # the user was not really "exempt" in the policy sense -- they were just
    # already disabled. The Reason is the v1 log message verbatim.
    # =========================================================================
    Context 'Branch 1: already disabled' {

        It 'disabled account is exempt with v1 Reason and Main-only channels' {
            $user = New-FakeUser `
                -Enabled $false `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'Account is already disabled.'
            ($result.Channels -join ',') | Should -Be 'Main'
        }

        It 'disabled account routes to Main+Vip when VIP-tagged' {
            $user = New-FakeUser `
                -Enabled $false `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'Account is already disabled.'
            ($result.Channels -join ',') | Should -Be 'Main,Vip'
        }
    }

    # =========================================================================
    # Branch 2: within grace period
    # =========================================================================
    # An account created less than GracePeriodDays days ago is exempt, even
    # if not in any exempt OU or group. The grace period is new-account
    # onboarding slack: give admins time to configure compliance tooling
    # before enforcement begins. v1 uses the condition "whenCreated +
    # GracePeriod >= today", which is "still within grace" (the inverse of
    # the "past grace, ready to disable" check). These tests pin the cutoff
    # behavior at 30 days (exactly 30 is still in grace; 31 is past grace).
    # =========================================================================
    Context 'Branch 2: within grace period' {

        It 'in-grace user is exempt with v1 Reason and Main+Exempt channels' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-10) `
                -DistinguishedName 'CN=u,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'Account is less than 30 days old.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt'
        }

        It 'grace-period boundary: exactly 30 days old is still in-grace' {
            # v1's condition is "whenCreated.AddDays(30) >= now", which means
            # a user created exactly 30 days ago (whenCreated.AddDays(30) == now)
            # is still within the grace window. This is the upper boundary of
            # the grace period: the inclusive end point.
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-30) `
                -DistinguishedName 'CN=u,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Match 'less than 30 days old'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt'
        }

        It 'grace-period boundary: 31 days old is past grace' {
            # A user created 31 days ago falls out of the grace window:
            # whenCreated.AddDays(30) < now. They are no longer in-grace and
            # proceed to the next exemption checks. Since this user is not in
            # any exempt OU or group, they land in the disable branch (branch 5).
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-31) `
                -DistinguishedName 'CN=u,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $false
            $result.Reason | Should -Be 'Account Disabled.'
        }

        It 'custom GracePeriodDays in Policy is honored' {
            # The grace period is configurable. Here we use a 7-day grace
            # instead of the default 30. A user created 10 days ago falls
            # past the 7-day window and is not exempt.
            $customPolicy = $script:Policy.Clone()
            $customPolicy.GracePeriodDays = 7

            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-10) `
                -DistinguishedName 'CN=u,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $customPolicy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $false
            $result.Reason | Should -Be 'Account Disabled.'
        }

        It 'in-grace + VIP-tagged routes to all three channels' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-10) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            ($result.Channels -join ',') | Should -Be 'Main,Exempt,Vip'
        }
    }

    # =========================================================================
    # Branch 3: exempt OU
    # =========================================================================
    # A user whose DN matches one of the ExemptOus is exempt. The match uses
    # the OuMatchPattern, a -f-style template where {0} is the OU name.
    # Array order matters: the FIRST matching OU wins if a user is in
    # multiple exempt OUs. The Reason includes the OU name for audit clarity.
    # =========================================================================
    Context 'Branch 3: exempt OU' {

        It 'REL OU exempt produces v1 Reason' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=REL,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'REL Users are currently exempt from WAM Training.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt'
        }

        It 'SCO OU exempt produces v1 Reason' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=SCO,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'SCO Users are currently exempt from WAM Training.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt'
        }

        It 'OuMatchPattern is interpolated correctly' {
            # The -f substitution is core to the OU matching logic. Here we
            # use a different pattern shape to verify the interpolation works
            # for custom patterns. The pattern '*,OU={0},*' matches an OU name
            # sandwiched between commas, which is a valid alternative to the
            # default '*OU={0}*' substring match.
            $customPolicy = $script:Policy.Clone()
            $customPolicy.OuMatchPattern = '*,OU={0},*'

            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=REL,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $customPolicy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'REL Users are currently exempt from WAM Training.'
        }

        It 'array order: first matching OU wins' {
            # When a user is in multiple exempt OUs, the first match in the
            # ExemptOus array wins. Here we add 'VIP' to the front of the
            # array, and a user in both OU=VIP and OU=REL will match VIP
            # first and report a VIP-specific Reason.
            $customPolicy = $script:Policy.Clone()
            $customPolicy.ExemptOus = @('VIP', 'REL', 'SCO')

            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=REL,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $customPolicy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            # Should match VIP (first in array), not REL.
            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'VIP Users are currently exempt from WAM Training.'
        }

        It 'OU exempt + VIP-tagged adds Vip channel' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x'

            # For this test, we need VIP in the exempt OUs so it matches
            # the OU exemption branch (not the disable branch).
            $customPolicy = $script:Policy.Clone()
            $customPolicy.ExemptOus = @('VIP', 'REL', 'SCO')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $customPolicy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'VIP Users are currently exempt from WAM Training.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt,Vip'
        }
    }

    # =========================================================================
    # Branch 4: exempt group
    # =========================================================================
    # A user whose MemberOf array contains one of the ExemptGroups is exempt.
    # The match is case-insensitive equality (-ieq). v1 used regex partial
    # match (-match), which had surprising behavior for group names containing
    # regex metacharacters; v2 uses exact equality for clarity.
    # =========================================================================
    Context 'Branch 4: exempt group' {

        It 'group-membership exempt produces v1 Reason' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=Users,DC=x' `
                -MemberOf @('VIP No Tng Req')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'User is a member of an exemption group in AD.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt'
        }

        It 'group match is case-insensitive' {
            # The exemption group 'VIP No Tng Req' is defined in the policy.
            # If the user's MemberOf array contains 'vip no tng req' (lowercase),
            # it should still match via case-insensitive equality.
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=Users,DC=x' `
                -MemberOf @('vip no tng req')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'User is a member of an exemption group in AD.'
        }

        It 'multiple groups: any match suffices' {
            # If the user is a member of multiple groups and any of them
            # is an exempt group, the user is exempt. Here the user is a
            # member of 'Some Random Group' (not exempt) and
            # 'Temp No Tng Req' (exempt); they should be exempt overall.
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=Users,DC=x' `
                -MemberOf @('Some Random Group', 'Temp No Tng Req')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'User is a member of an exemption group in AD.'
        }

        It 'no group match: not exempt' {
            # A user in only non-exempt groups is not exempt via the group
            # route. They proceed to the next checks (OU exemption, grace
            # period, etc.). If they don't match any of those either, they
            # land in the disable branch.
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=Users,DC=x' `
                -MemberOf @('Some Random Group')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $false
            $result.Reason | Should -Be 'Account Disabled.'
        }

        It 'group exempt + VIP-tagged routes to Main+Exempt+Vip' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x' `
                -MemberOf @('VIP No Tng Req')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'User is a member of an exemption group in AD.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt,Vip'
        }
    }

    # =========================================================================
    # Branch 5: not exempt (disable path)
    # =========================================================================
    # The user falls through all exemption checks and lands in the disable
    # branch. The Reason is the v1 log message for the disable action.
    # =========================================================================
    Context 'Branch 5: not exempt (disable path)' {

        It 'standard disable path: Main only' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=Users,DC=x' `
                -MemberOf @()

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $false
            $result.Reason | Should -Be 'Account Disabled.'
            ($result.Channels -join ',') | Should -Be 'Main'
        }

        It 'VIP-tagged disable: Main+Vip' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x' `
                -MemberOf @()

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $false
            $result.Reason | Should -Be 'Account Disabled.'
            ($result.Channels -join ',') | Should -Be 'Main,Vip'
        }
    }

    # =========================================================================
    # Precedence interactions
    # =========================================================================
    # The decision branches form an if/elseif/else ladder. A user matching
    # a higher-precedence branch never reaches lower branches. These tests
    # verify that precedence is preserved.
    #
    # v1's precedence (now v2's precedence):
    #   1. Disabled (highest)
    #   2. Grace period
    #   3. Exempt OU
    #   4. Exempt group
    #   5. Disable (lowest)
    #
    # The VIP routing is ORTHOGONAL to this ladder: it applies to every
    # result, independent of which branch fired. This was a v1 defect
    # (inconsistent VIP routing between branches); v2 fixes it here.
    # =========================================================================
    Context 'precedence interactions' {

        It 'disabled beats grace' {
            # An account created 10 days ago is in-grace (branch 2). But if
            # the account is disabled (branch 1), branch 1 wins and fires
            # first. The user is not "within grace"; they are just already
            # disabled.
            $user = New-FakeUser `
                -Enabled $false `
                -WhenCreated $script:PinnedNow.AddDays(-10) `
                -DistinguishedName 'CN=u,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.Reason | Should -Be 'Account is already disabled.'
        }

        It 'grace beats OU exemption' {
            # A user created 10 days ago is in-grace (branch 2) even if their
            # DN is in an exempt OU (branch 3). Branch 2 fires first, and the
            # user is exempt with the in-grace Reason.
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-10) `
                -DistinguishedName 'CN=u,OU=REL,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.Reason | Should -Be 'Account is less than 30 days old.'
        }

        It 'OU exemption beats group membership' {
            # A user in an exempt OU (branch 3) is exempt even if also a member
            # of an exempt group (branch 4). Branch 3 fires first, and the user
            # is exempt with the OU-specific Reason.
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=REL,OU=Users,DC=x' `
                -MemberOf @('VIP No Tng Req')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.Reason | Should -Be 'REL Users are currently exempt from WAM Training.'
        }

        It 'VIP routing is independent: disabled + VIP yields Main+Vip' {
            $user = New-FakeUser `
                -Enabled $false `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.Reason | Should -Be 'Account is already disabled.'
            ($result.Channels -join ',') | Should -Be 'Main,Vip'
        }

        It 'VIP routing is independent: disable path + VIP yields Main+Vip' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x' `
                -MemberOf @()

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $false
            $result.Reason | Should -Be 'Account Disabled.'
            ($result.Channels -join ',') | Should -Be 'Main,Vip'
        }

        It 'VIP routing is independent: in-grace + VIP yields Main+Exempt+Vip' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-10) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x'

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            ($result.Channels -join ',') | Should -Be 'Main,Exempt,Vip'
        }

        It 'VIP routing is independent: OU exempt + VIP yields Main+Exempt+Vip' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=REL,OU=VIP,OU=Users,DC=x' `
                -MemberOf @()

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'REL Users are currently exempt from WAM Training.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt,Vip'
        }

        It 'VIP routing is independent: group exempt + VIP yields Main+Exempt+Vip' {
            $user = New-FakeUser `
                -Enabled $true `
                -WhenCreated $script:PinnedNow.AddDays(-90) `
                -DistinguishedName 'CN=u,OU=VIP,OU=Users,DC=x' `
                -MemberOf @('VIP No Tng Req')

            $result = Test-WamUserExemption `
                -UserRecord $user `
                -Policy $script:Policy `
                -VipDistinguishedNamePattern $script:VipPattern `
                -WorkingDate $script:PinnedNow

            $result.IsExempt | Should -Be $true
            $result.Reason | Should -Be 'User is a member of an exemption group in AD.'
            ($result.Channels -join ',') | Should -Be 'Main,Exempt,Vip'
        }
    }
}
