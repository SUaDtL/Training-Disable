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

    # -------------------------------------------------------------------------
    # Allocate the connection BEFORE the try, so a New-Object failure
    # (e.g. the System.Data.SqlClient assembly is not loaded -- which
    # happens on Linux pwsh without the Microsoft.Data.SqlClient package
    # installed) surfaces as the original exception rather than a
    # NullReferenceException inside the finally.
    # -------------------------------------------------------------------------
    # Why not [Microsoft.Data.SqlClient.SqlConnection]: the prod environment
    # runs Windows PowerShell 5.1 + .NET Framework, which ships
    # System.Data.SqlClient in the GAC. Microsoft.Data.SqlClient is the
    # "modern" .NET successor but is a separate NuGet that is NOT in the
    # prod box. v1 uses System.Data.SqlClient; we keep it for drop-in
    # compatibility. A future PR can swap the namespace once the prod
    # environment is upgraded.
    # -------------------------------------------------------------------------
    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $ConnectionString

    try {
        # ---------------------------------------------------------------------
        # Open the connection. ErrorAction Stop is implicit on the .NET
        # method call (a thrown exception is always terminating) but we
        # write it out for documentation: a SQL outage here jumps directly
        # to finally, which closes the (still-not-open) connection
        # gracefully.
        # ---------------------------------------------------------------------
        $connection.Open()

        # ---------------------------------------------------------------------
        # Build the command.
        # ---------------------------------------------------------------------
        # v1's command uses CommandType.StoredProcedure, no parameters,
        # default timeout. We honor all three but expose CommandTimeoutSeconds
        # because the procedure has been observed to take 35-40s during
        # peak times (config default is 60s).
        # ---------------------------------------------------------------------
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $command.CommandType = [System.Data.CommandType]::StoredProcedure
        $command.CommandText = $StoredProcedure
        $command.CommandTimeout = $CommandTimeoutSeconds
        $command.Connection = $connection

        # ---------------------------------------------------------------------
        # Fill a DataSet via SqlDataAdapter.
        # ---------------------------------------------------------------------
        # Adapter+DataSet is the same shape v1 used. We could use
        # ExecuteReader for slightly less memory footprint, but the
        # result set is small (the non-compliant-user list is in the
        # hundreds at most) and the adapter pattern is what every prior
        # contributor will recognize.
        # ---------------------------------------------------------------------
        $adapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
        $adapter.SelectCommand = $command

        $dataSet = New-Object -TypeName System.Data.DataSet
        $null = $adapter.Fill($dataSet)

        # ---------------------------------------------------------------------
        # Surface the first table.
        # ---------------------------------------------------------------------
        # If the procedure returns no result sets at all, $dataSet.Tables
        # is empty -- we return $null and the caller decides whether
        # that is a malformed schema or just an empty result. Most of
        # the time the procedure returns exactly one table, which is
        # the case v1 was written for.
        # ---------------------------------------------------------------------
        if ($dataSet.Tables.Count -eq 0) {
            return $null
        }
        return $dataSet.Tables[0]
    }
    finally {
        # ---------------------------------------------------------------------
        # Close the connection unconditionally (defect-8 fix).
        # ---------------------------------------------------------------------
        # v1's WAM-SQLLookup called $SQLConnection.Close() inline at the
        # end of the success path with no try/finally, so a thrown
        # exception during Open/Fill bypassed the close call and the
        # connection leaked until garbage collection -- on a long-lived
        # scheduled-task runspace, that is hours.
        #
        # We Dispose() rather than just Close() to release the underlying
        # native handle eagerly. SqlConnection.Dispose calls Close
        # internally, then frees the handle; Close alone leaves the
        # managed wrapper around for finalizer cleanup.
        # ---------------------------------------------------------------------
        if ($null -ne $connection) {
            $connection.Dispose()
        }
    }
}
