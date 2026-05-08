# =============================================================================
# Public/Disable-WamUserAccount.ps1
# =============================================================================
# Disables exactly one AD user account and appends a non-compliance note
# to the description. The orchestrator calls this in a loop; the function
# itself is single-user so unit tests can drive each error branch
# independently.
#
# At PR 3 this is a stub. PR 5 fills in the body.
# =============================================================================

function Disable-WamUserAccount {
    <#
    .SYNOPSIS
        Disable an AD user account and append a training-non-compliance
        note to the description.

    .DESCRIPTION
        Calls Disable-ADAccount and Set-ADUser against the supplied
        identity. The Set-ADUser call appends ", (Account disabled for
        training non-compliance on <yyyy-MM-dd>)" to the existing
        description -- v2 fixes the v1 missing-paren typo and uses
        ISO 8601 date by default, with the legacy v1 shape available
        via -LegacyTimestamp for downstream-consumer compatibility.

        Replaces v1's WAM-Disable function. Three key changes:

          1. Identity is a parameter, not a caller-scope variable.
             v1's WAM-Disable read $User and $ADAccount via dynamic
             scope; v2 takes them as parameters so unit tests can
             drive each branch directly.

          2. Strict-mode-clean. v1 shadowed the $Error automatic
             variable to track success/failure across try/finally;
             v2 uses a local boolean.

          3. SupportsShouldProcess. v1 had a $ReportOnly flag; v2
             uses the standard PowerShell convention. Pass -WhatIf
             to skip the AD writes; the cmdlet still emits no log
             output (the orchestrator handles logging).

    .PARAMETER Identity
        The SamAccountName to disable.

    .PARAMETER ExistingDescription
        The user's current description. Caller is responsible for
        reading it via Get-ADUser before invoking this cmdlet so we
        don't make a second AD round-trip per user (v1's WAM-Disable
        re-fetched the user inside the disable path, doubling the AD
        load).

    .PARAMETER WorkingDate
        Reference date for the description suffix. Defaults to the
        current date.

    .PARAMETER LegacyTimestamp
        When set, the description suffix uses v1's
        culture-dependent date format
        ((Get-Date).ToShortDateString()) instead of v2's ISO 8601
        default. Use only if a downstream consumer of the AD
        description field is known to depend on the v1 shape.

    .EXAMPLE
        Disable-WamUserAccount -Identity 'alice.normal' `
            -ExistingDescription 'Software Engineer II' `
            -WhatIf

        Reports what would happen without writing to AD.

    .EXAMPLE
        $u = Get-ADUser -Identity 'alice.normal' -Properties Description
        Disable-WamUserAccount -Identity $u.SamAccountName `
            -ExistingDescription $u.Description

        Standard usage: caller passes the existing description so we
        avoid a redundant Get-ADUser round-trip.

    .EXAMPLE
        Disable-WamUserAccount -Identity 'alice.normal' `
            -ExistingDescription 'SE II' -LegacyTimestamp

        Use the v1 culture-dependent date format. Only enable when
        compatibility with a known v1-shaped downstream consumer is
        required.

    .NOTES
        State-changing. SupportsShouldProcess is enabled with
        ConfirmImpact = 'High'. Errors during Disable-ADAccount or
        Set-ADUser are surfaced as non-terminating errors so the
        orchestrator can log them and continue with the next user.

    .LINK
        Invoke-WamTrainingDisable

    .LINK
        Test-WamUserExemption

    .LINK
        about_WamTrainingDisable
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string] $Identity,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ExistingDescription,

        [Parameter()]
        [datetime] $WorkingDate = [datetime]::Now,

        [Parameter()]
        [switch] $LegacyTimestamp
    )

    if ($PSCmdlet.ShouldProcess($Identity, 'Disable AD account')) {
        throw [System.NotImplementedException]::new(
            'Disable-WamUserAccount will be implemented in PR 5 (I/O wrappers).'
        )
    }
}
