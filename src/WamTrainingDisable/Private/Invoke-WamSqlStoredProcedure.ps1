# =============================================================================
# Private/Invoke-WamSqlStoredProcedure.ps1
# =============================================================================
# The single SQL seam. Wraps the ADO.NET connection-open / command-build /
# adapter-fill / dataset-extract / connection-close lifecycle in a
# try/finally so a thrown exception cannot leak the connection.
#
# v1's WAM-SQLLookup had no try/finally and would leak the connection on
# a SQL outage. The Private/* split exists specifically so unit tests can
# mock this single seam instead of mocking the System.Data.SqlClient API
# surface piece by piece.
#
# At PR 3 this is a stub. PR 5 fills in the body.
# =============================================================================

function Invoke-WamSqlStoredProcedure {
    <#
    .SYNOPSIS
        Open a SQL connection, execute a stored procedure, return the
        first DataTable.

    .DESCRIPTION
        Internal helper. The connection lifecycle is wrapped in
        try/finally; a thrown exception during command execution still
        closes the connection. Returns the first DataTable from the
        DataSet; downstream code projects to objects.
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectionString,

        [Parameter(Mandatory)]
        [string] $StoredProcedure,

        [Parameter()]
        [int] $CommandTimeoutSeconds = 60
    )

    throw [System.NotImplementedException]::new(
        'Invoke-WamSqlStoredProcedure will be implemented in PR 5 (I/O wrappers).'
    )
}
