# =============================================================================
# Public/Test-WamUserExemption.ps1
# =============================================================================
# The exemption matrix as a PURE function. Given a user record and a
# policy, returns a decision object: is the user exempt, why, and which
# log channels should receive a line for this decision.
#
# The "pure function" framing is the key v2 lesson over v1. v1 had the
# exemption ladder inlined in WAM-ADSearch's foreach loop, mixed with the
# log-write side effects. There was no way to test the matrix without
# spinning up AD and the logger. v2 separates the decision from the
# action so the matrix becomes a Pester table.
#
# At PR 3 this is a stub. PR 4 fills in the body and the table-driven
# tests.
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

    throw [System.NotImplementedException]::new(
        'Test-WamUserExemption will be implemented in PR 4 (pure logic extraction).'
    )
}
