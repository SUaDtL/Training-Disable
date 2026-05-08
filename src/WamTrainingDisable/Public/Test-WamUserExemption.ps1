# =============================================================================
# Public/Test-WamUserExemption.ps1
# =============================================================================
# The exemption matrix as a PURE function. Given a user record and a
# policy, returns a decision object: is the user exempt, why, and which
# log channels should receive a line for this decision.
#
# v2 vs. v1 behavior matrix
# -------------------------
# v1 had the exemption ladder inlined in WAM-ADSearch's foreach loop,
# mixed with the log-write side effects, with three boolean toggles
# ($VIP, $REL, $SCO) controlling individual OU exemptions. v2 collapses
# the toggles into a single Policy.ExemptOus array and separates the
# decision (this function) from the action (Write-WamLog, called by
# the orchestrator on the channels this function returns).
#
# The decision precedence order is preserved verbatim from v1:
#
#   1. Account is already disabled         -> exempt, Main only
#   2. Account is within grace period      -> exempt, Main + Exempt
#   3. Account's DN matches an ExemptOu    -> exempt, Main + Exempt
#   4. Account is in an ExemptGroup        -> exempt, Main + Exempt
#   5. Otherwise                           -> not exempt, Main
#
# VIP-channel routing is INDEPENDENT of the decision: if the user's DN
# matches the configured VipDistinguishedNamePattern, 'Vip' is added to
# the Channels list regardless of which precedence branch fired. This
# fixes the v1 inconsistency where the disable path used the suffix
# match '*VIP' and the exemption path used the substring match
# '*OU=VIP*' -- the same user could route differently between runs
# depending on which branch fired. v2 settles on one matcher and
# applies it once.
#
# Reason-string compatibility
# ---------------------------
# The Reason strings emitted here are a drop-in contract: the snapshot
# fixtures captured in PR 2 pin them verbatim. Changing any of them
# requires updating the fixture in the same PR with a note explaining
# why.
# =============================================================================

function Test-WamUserExemption {
    <#
    .SYNOPSIS
        Decide whether a user is exempt from WAM training disablement
        and which log channels should record the decision.

    .DESCRIPTION
        Pure function: no AD, no SQL, no I/O of any kind. Inputs are the
        user record (a [pscustomobject] shaped like the AD return of
        Get-ADUser with -Properties Department, OfficePhone, whenCreated,
        MemberOf, DistinguishedName) and the policy (a [hashtable] with
        the keys from WamTrainingDisable.config.psd1's Policy section).

        The output is a [pscustomobject] with three members:

          - IsExempt    [bool]      True if the user should NOT be
                                    disabled.
          - Reason      [string]    Human-readable explanation, used
                                    verbatim in the log messages.
          - Channels    [string[]]  Which log channels should receive a
                                    line for this decision. Subset of
                                    'Main', 'Vip', 'Exempt'. The
                                    orchestrator iterates the list.

        The decision precedence (highest first) is:

          1. Already disabled            -> IsExempt = $true (no need to
                                            disable an already-disabled
                                            account); Channels = Main.
          2. Within grace period         -> IsExempt = $true;
                                            Channels = Main + Exempt.
          3. In an exempt OU             -> IsExempt = $true;
                                            Channels = Main + Exempt
                                            (+ Vip if the user is also
                                            in the VIP DN-pattern).
          4. In an exempt group          -> IsExempt = $true;
                                            Channels = Main + Exempt
                                            (+ Vip if the user is also
                                            in the VIP DN-pattern).
          5. Otherwise                   -> IsExempt = $false;
                                            Channels = Main
                                            (+ Vip if VIP-tagged).

        Note: the VIP channel is ALWAYS routed via the same
        DN-pattern check, regardless of the exemption decision. This
        fixes a v1 inconsistency where the disable path used '*VIP'
        (suffix match) and the exemption path used '*OU=VIP*' (substring
        match), causing the same user to be routed differently between
        runs depending on which branch fired.

    .PARAMETER UserRecord
        The user record to evaluate. Required keys: Enabled,
        whenCreated, DistinguishedName, MemberOf (array of group display
        names, NOT DNs -- the orchestrator pre-resolves group names via
        Get-ADGroup).

    .PARAMETER Policy
        The policy hashtable. Required keys: GracePeriodDays, ExemptOus,
        ExemptGroups, OuMatchPattern.

    .PARAMETER VipDistinguishedNamePattern
        The DN pattern used to tag a user as VIP for the VIP log
        channel. Independent of the exempt-OU decision; a user can be
        both VIP-tagged AND non-exempt (the VIP support team gets a
        line, the user gets disabled).

    .PARAMETER WorkingDate
        Reference date for the grace-period check. Defaults to the
        current date; override only for deterministic testing.

    .EXAMPLE
        Test-WamUserExemption -UserRecord $u -Policy $cfg.Policy `
            -VipDistinguishedNamePattern $cfg.Logging.Channels.VipDistinguishedNamePattern

        Evaluate one user against the resolved policy.

    .EXAMPLE
        $users | ForEach-Object {
            Test-WamUserExemption -UserRecord $_ -Policy $policy `
                -VipDistinguishedNamePattern '*OU=VIP*'
        }

        Evaluate every user in a list. Pure function so this is safe to
        parallelize via ForEach-Object -Parallel on PowerShell 7+.

    .EXAMPLE
        $decision = Test-WamUserExemption @args
        if (-not $decision.IsExempt) {
            Disable-WamUserAccount -Identity $u.SamAccountName -WhatIf:$WhatIfPreference
        }

        Drive a disable decision off the matrix output.

    .OUTPUTS
        [pscustomobject] with members IsExempt [bool], Reason [string],
        Channels [string[]].

    .NOTES
        Pure: no AD, no SQL, no I/O. The unit tests for this function
        are the Pester table that pins each branch of the matrix.

    .LINK
        Invoke-WamTrainingDisable

    .LINK
        about_WamTrainingDisable
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $UserRecord,

        [Parameter(Mandatory)]
        [hashtable] $Policy,

        [Parameter(Mandatory)]
        [string] $VipDistinguishedNamePattern,

        [Parameter()]
        [datetime] $WorkingDate = [datetime]::Now
    )

    # -------------------------------------------------------------------------
    # VIP routing is computed up-front and applied to every decision
    # branch. This is the unification fix for v1's defect 6.
    # -------------------------------------------------------------------------
    $isVipTagged = $UserRecord.DistinguishedName -like $VipDistinguishedNamePattern

    # -------------------------------------------------------------------------
    # Branch 1: account is already disabled.
    # -------------------------------------------------------------------------
    # v1 logs only to Main here ("Account is already disabled."). It does
    # NOT log to the Exempt channel because the user is not really
    # "exempt" -- they were just already done. We preserve that behavior.
    # -------------------------------------------------------------------------
    if (-not $UserRecord.Enabled) {
        $channels = @('Main')
        if ($isVipTagged) {
            $channels += 'Vip'
        }
        return [pscustomobject] @{
            IsExempt = $true
            Reason = 'Account is already disabled.'
            Channels = $channels
        }
    }

    # -------------------------------------------------------------------------
    # Branch 2: within grace period.
    # -------------------------------------------------------------------------
    # v1: "if ($ADAccount.whenCreated.AddDays($GracePeriod) -lt (get-date))"
    # The condition is "true means past grace, proceed to disable check."
    # The else (which is what we want here) means "still within grace."
    # We invert: $whenCreated.AddDays(GracePeriod) -ge $WorkingDate is
    # "still within grace."
    #
    # The {0} in the message is the GracePeriodDays value, formatted via
    # PowerShell's -f operator. v1's message inlined "$GracePeriod"
    # (which was 30 by default); v2 mirrors that by interpolating the
    # configured value, so a custom GracePeriodDays surfaces in the log.
    # -------------------------------------------------------------------------
    $graceThreshold = $UserRecord.whenCreated.AddDays($Policy.GracePeriodDays)
    if ($graceThreshold -ge $WorkingDate) {
        $channels = @('Main', 'Exempt')
        if ($isVipTagged) {
            $channels += 'Vip'
        }
        return [pscustomobject] @{
            IsExempt = $true
            Reason = "Account is less than $($Policy.GracePeriodDays) days old."
            Channels = $channels
        }
    }

    # -------------------------------------------------------------------------
    # Branch 3: in an exempt OU.
    # -------------------------------------------------------------------------
    # We iterate ExemptOus in array order; the FIRST match wins. The
    # OuMatchPattern uses a -f-style placeholder ({0}) which we fill in
    # per OU. Default pattern is '*OU={0}*' (the substring matcher v2
    # standardizes on). The matched OU name is interpolated into the
    # log message so the VIP/REL/SCO/etc. distinction surfaces.
    # -------------------------------------------------------------------------
    foreach ($exemptOu in $Policy.ExemptOus) {
        $pattern = $Policy.OuMatchPattern -f $exemptOu
        if ($UserRecord.DistinguishedName -like $pattern) {
            $channels = @('Main', 'Exempt')
            if ($isVipTagged) {
                $channels += 'Vip'
            }
            return [pscustomobject] @{
                IsExempt = $true
                Reason = "$exemptOu Users are currently exempt from WAM Training."
                Channels = $channels
            }
        }
    }

    # -------------------------------------------------------------------------
    # Branch 4: in an exempt group.
    # -------------------------------------------------------------------------
    # v1 used "-match" (regex partial) which had surprising behavior on
    # group names that happened to contain regex metacharacters. v2 uses
    # equality with case-insensitive comparison, which is the unsurprising
    # behavior. The user's MemberOf is expected to be display names
    # (already resolved by Get-WamUserDetail), not DNs.
    # -------------------------------------------------------------------------
    foreach ($groupName in $UserRecord.MemberOf) {
        foreach ($exemptGroup in $Policy.ExemptGroups) {
            if ($groupName -ieq $exemptGroup) {
                $channels = @('Main', 'Exempt')
                if ($isVipTagged) {
                    $channels += 'Vip'
                }
                return [pscustomobject] @{
                    IsExempt = $true
                    Reason = 'User is a member of an exemption group in AD.'
                    Channels = $channels
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Branch 5: not exempt -- disable the account.
    # -------------------------------------------------------------------------
    # The Reason here ("Account Disabled.") is what v1 wrote to the log
    # in the WAM-Disable success branch. The orchestrator emits this on
    # the Main channel (and the Vip channel if the user is VIP-tagged).
    # -------------------------------------------------------------------------
    $channels = @('Main')
    if ($isVipTagged) {
        $channels += 'Vip'
    }
    return [pscustomobject] @{
        IsExempt = $false
        Reason = 'Account Disabled.'
        Channels = $channels
    }
}
