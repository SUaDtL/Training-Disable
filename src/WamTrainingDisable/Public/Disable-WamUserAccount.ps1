# =============================================================================
# Public/Disable-WamUserAccount.ps1
# =============================================================================
# Disables exactly one AD user account and appends a non-compliance note
# to the description. The orchestrator calls this in a loop; the function
# itself is single-user so unit tests can drive each error branch
# independently.
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

    # -------------------------------------------------------------------------
    # Compose the new description.
    # -------------------------------------------------------------------------
    # Two shapes:
    #
    #   - Legacy (v1, byte-for-byte): "<old>, (Account disabled for
    #     training non-compliance on <ToShortDateString>." The trailing
    #     period and the missing closing parenthesis are v1 typos that
    #     we deliberately reproduce when LegacyTimestamp is set --
    #     downstream consumers that scrape AD descriptions may rely on
    #     the exact v1 string. The PR 2 snapshot fixture pins this
    #     shape.
    #
    #   - Default (v2): "<old>, (Account disabled for training
    #     non-compliance on <yyyy-MM-dd>)" -- ISO date,
    #     properly-balanced parens. Culture-stable, format-stable.
    #
    # We compose the suffix BEFORE the ShouldProcess check so a -WhatIf
    # invocation can include the proposed description in its
    # confirmation message (which uses the $Identity argument; the
    # description does not surface there but the composition is cheap
    # and keeps the two branches symmetric).
    # -------------------------------------------------------------------------
    if ($LegacyTimestamp.IsPresent) {
        # ToShortDateString formats under the ambient CurrentCulture --
        # an en-US runner emits "5/8/2026", a de-DE runner would emit
        # "08.05.2026". v1 had no culture pinning and we honor that
        # here for byte-for-byte compatibility. The trailing period
        # and the missing closing paren are v1 typos preserved verbatim.
        $suffix = ", (Account disabled for training non-compliance on $($WorkingDate.ToShortDateString())."
    }
    else {
        # ISO 8601 date, culture-invariant. The closing paren matches
        # the opening paren; v2 fixes v1's typo. The 'd' format
        # specifier under InvariantCulture would render '05/08/2026'
        # (slashes); we want '2026-05-08' (dashes) so we use the
        # explicit format string.
        $isoDate = $WorkingDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $suffix = ", (Account disabled for training non-compliance on $isoDate)"
    }
    $newDescription = $ExistingDescription + $suffix

    # -------------------------------------------------------------------------
    # ShouldProcess gate.
    # -------------------------------------------------------------------------
    # SupportsShouldProcess + ConfirmImpact='High' means the cmdlet
    # will prompt unless the caller passes -Confirm:$false or has
    # $ConfirmPreference set above 'High'. -WhatIf skips the body of
    # this block entirely. The orchestrator (PR 6) is responsible for
    # threading -WhatIf through; we just respect it here.
    # -------------------------------------------------------------------------
    if (-not $PSCmdlet.ShouldProcess($Identity, 'Disable AD account')) {
        return
    }

    # -------------------------------------------------------------------------
    # Perform the AD writes inside a try/catch.
    # -------------------------------------------------------------------------
    # v1 used a try/catch/finally and shadowed the $Error automatic
    # variable to track success across the boundary (defect 2). v2
    # uses a local boolean ($disableSucceeded) and surfaces any failure
    # as a non-terminating error via Write-Error so the orchestrator's
    # foreach loop can log it and continue.
    #
    # The catch in v1 wrote a "Failed to Disable Account" log line
    # AND swallowed the original exception. That made debugging
    # impossible -- the operator only saw the log line, not the
    # underlying ADException. v2 emits the original exception
    # unchanged via Write-Error so the orchestrator (or an interactive
    # operator) can see exactly what AD complained about.
    # -------------------------------------------------------------------------
    $disableSucceeded = $false

    try {
        Disable-ADAccount -Identity $Identity -ErrorAction Stop
        Set-ADUser -Identity $Identity -Description $newDescription -ErrorAction Stop
        $disableSucceeded = $true
    }
    catch {
        # PSItem here is the ErrorRecord PowerShell binds for the
        # catch block. We re-emit it via Write-Error so it surfaces
        # as a non-terminating error in the calling pipeline; the
        # orchestrator's outer try/catch can decide whether to log
        # and continue. -ErrorAction Stop on Write-Error itself
        # would re-throw -- we explicitly do NOT want that here, so
        # we leave the default (Continue).
        Write-Error -ErrorRecord $_
    }

    # -------------------------------------------------------------------------
    # Return success state to the caller.
    # -------------------------------------------------------------------------
    # The orchestrator inspects this to decide which log line shape to
    # emit ("Account Disabled." vs. "Failed to Disable Account.").
    # Returning a [bool] keeps the contract narrow; if we ever need
    # richer telemetry (rows-affected, latency, etc.) we'll add a
    # [pscustomobject] in a future minor version.
    # -------------------------------------------------------------------------
    return $disableSucceeded
}
