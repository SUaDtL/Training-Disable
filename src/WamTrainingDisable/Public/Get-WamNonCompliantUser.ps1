# =============================================================================
# Public/Get-WamNonCompliantUser.ps1
# =============================================================================
# Reads the list of non-compliant users from the WAM SQL source, returns
# objects (not files; the v1 Out-File-as-IPC handoff is retired). The
# orchestrator may optionally write a v1-shaped LockoutList_<date>.txt
# audit artifact for downstream consumers that grep it directly.
#
# At PR 3 this is a stub. PR 5 fills in the body.
# =============================================================================

function Get-WamNonCompliantUser {
    <#
    .SYNOPSIS
        Query the WAM training DB for users currently flagged as
        training-non-compliant.

    .DESCRIPTION
        Opens an ADO.NET connection to the configured SQL server, calls
        the configured stored procedure (default
        orc.get_Pers_Training_Disable_Accounts), strips the leading
        DOMAIN\ prefix from each returned username, and emits one
        [pscustomobject] per row.

        The connection lifecycle is wrapped in a try/finally so a
        thrown exception cannot leak the connection until garbage
        collection. v1 had no try/finally and reportedly leaked
        connections during a SQL outage.

        Replaces v1's WAM-SQLLookup function. Two key changes from v1:

          1. Returns objects, not a file. v1 wrote
             $LockOutListFile and the AD stage read it back; v2 keeps
             the data in memory by default. The orchestrator can
             optionally still write the file (configured by
             Logging.WriteLockoutListFile, default $true) for
             downstream consumers.

          2. Returns ALL rows. v1 had a defect where
             "Select-Object -InputObject ... -Index 0" truncated the
             result set to the first row; v2 enumerates the DataTable
             properly.

    .PARAMETER ConnectionString
        Override the SQL connection string. When omitted, resolved
        from the configuration stack.

    .PARAMETER StoredProcedure
        Override the stored procedure name. When omitted, resolved
        from the configuration stack.

    .PARAMETER UsernameColumn
        Override the column name that holds the username. When
        omitted, resolved from the configuration stack (default
        'nt_username').

    .PARAMETER ConfigPath
        Path to a project-level configuration file used as the source
        of unspecified parameters.

    .EXAMPLE
        Get-WamNonCompliantUser

        Returns the current non-compliant user list using the configured
        connection string and stored procedure.

    .EXAMPLE
        Get-WamNonCompliantUser -ConnectionString 'Server=...;Database=...'

        Override the connection string for an ad-hoc query against a
        non-prod database.

    .EXAMPLE
        Get-WamNonCompliantUser | Select-Object -ExpandProperty SamAccountName

        Project to a flat string list for downstream consumption.

    .OUTPUTS
        [pscustomobject] -- one per non-compliant user, with at minimum
        a SamAccountName property.

    .NOTES
        Read-only. Does not write to AD or to any log file. The
        orchestrator handles the audit-artifact write.

    .LINK
        Invoke-WamTrainingDisable

    .LINK
        about_WamTrainingDisable
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string] $ConnectionString,

        [Parameter()]
        [string] $StoredProcedure,

        [Parameter()]
        [string] $UsernameColumn,

        [Parameter()]
        [string] $ConfigPath
    )

    throw [System.NotImplementedException]::new(
        'Get-WamNonCompliantUser will be implemented in PR 5 (I/O wrappers).'
    )
}
