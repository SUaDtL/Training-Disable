# =============================================================================
# Public/Invoke-WamTrainingDisable.ps1
# =============================================================================
# This is the orchestrator: the cmdlet the prod scheduled task ultimately
# invokes. It pulls the non-compliant user list, walks each through the
# exemption matrix, and either disables or skips, emitting log lines on
# the configured channels along the way.
#
# At PR 3 this is a stub. PR 6 fills in the body.
# =============================================================================

function Invoke-WamTrainingDisable {
    <#
    .SYNOPSIS
        Disable AD accounts for users delinquent on WAM training, with
        configurable exemptions and three log-channel output.

    .DESCRIPTION
        Reads the non-compliant user list from the WAM SQL source
        (orc.get_Pers_Training_Disable_Accounts by default), looks each
        user up in Active Directory, applies the configured exemption
        matrix (grace period, OU exemptions, group exemptions), disables
        the AD account where appropriate, and emits a line on each
        relevant log channel (main, VIP, exempt).

        Replaces the v1 src/TrainingDisable.ps1's Start-Main entrypoint.
        The drop-in shim (PR 7) will call this cmdlet under the hood so
        the prod scheduled task does not need to change.

        With -WhatIf the cmdlet performs every step EXCEPT
        Disable-ADAccount and Set-ADUser; log files are still written so
        the operator gets a complete picture of what would have happened.
        This replaces v1's $ReportOnly = $true flag with the standard
        PowerShell convention.

    .PARAMETER ConfigPath
        Path to a project-level configuration file. If supplied, this
        config layer takes precedence over user config and the shipped
        defaults. Cmdlet parameters and environment variables still
        override anything resolved from the file.

    .PARAMETER WorkingDate
        The date used to compute log file paths and the grace-period
        threshold. Defaults to the current date. Override only for
        deterministic testing or for re-running a missed scheduled day.

    .PARAMETER ConnectionString
        Override the SQL connection string. When supplied, takes
        precedence over every config layer.

    .PARAMETER GracePeriodDays
        Override the grace period in days.

    .PARAMETER LegacyTimestamp
        When set, log lines use the v1 culture-dependent timestamp
        shape ("(Get-Date).ToShortDateString() + ' ' + ToLongTimeString()")
        instead of the v2 ISO 8601 default. Documented in open gap 0003;
        use only if a downstream parser is known to depend on the v1
        shape.

    .EXAMPLE
        Invoke-WamTrainingDisable -WhatIf

        Runs the full pipeline in report-only mode. Equivalent to v1's
        $ReportOnly = $true.

    .EXAMPLE
        Invoke-WamTrainingDisable

        Runs the full pipeline in enforcement mode. Disables AD accounts
        that hit the disable branch.

    .EXAMPLE
        Invoke-WamTrainingDisable -ConfigPath ./config.test.psd1 -WhatIf

        Runs against a non-prod config (different SQL server, different
        log directory) without disabling anything. Useful in
        pre-production validation.

    .NOTES
        State-changing cmdlet. SupportsShouldProcess is enabled with
        ConfirmImpact = 'High' because disabling a user account is a
        consequential operation; non-interactive scheduled-task runs
        should pass -Confirm:$false explicitly to suppress the
        confirmation prompt.

    .LINK
        Get-WamNonCompliantUser

    .LINK
        Test-WamUserExemption

    .LINK
        Disable-WamUserAccount

    .LINK
        about_WamTrainingDisable
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string] $ConfigPath,

        [Parameter()]
        [datetime] $WorkingDate = [datetime]::Now,

        [Parameter()]
        [string] $ConnectionString,

        [Parameter()]
        [int] $GracePeriodDays,

        [Parameter()]
        [switch] $LegacyTimestamp
    )

    # The ShouldProcess call here is a stub-time placeholder. PR 6 will
    # move it into the per-user disable loop. We invoke it before the
    # NotImplementedException so PSScriptAnalyzer's PSShouldProcess rule
    # is satisfied at lint time -- the rule fires when SSP is declared
    # but ShouldProcess is never called.
    if ($PSCmdlet.ShouldProcess('the WAM non-compliance pipeline', 'run')) {
        throw [System.NotImplementedException]::new(
            'Invoke-WamTrainingDisable will be implemented in PR 6 (orchestrator wiring).'
        )
    }
}
