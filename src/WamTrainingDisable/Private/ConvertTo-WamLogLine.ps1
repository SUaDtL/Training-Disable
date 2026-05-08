# =============================================================================
# Private/ConvertTo-WamLogLine.ps1
# =============================================================================
# Pure log-line formatting. Given a message and a logging config, returns
# the bytes-on-disk a Write-WamLog call would produce. The split exists
# so the format is testable in isolation -- and so the LegacyTimestamp
# opt-in lives in one place.
#
# Two formats:
#
#   - Default: "[<ISO 8601 timestamp>] [<host>] <message>"
#       e.g. "[2026-05-08 10:30:00] [TESTHOST] alice.normal, ..., Account Disabled."
#
#   - Legacy (Logging.LegacyTimestamp = $true): v1's
#     "(Get-Date).ToShortDateString() + ' ' + (Get-Date).ToLongTimeString()"
#     output, culture-dependent, intentionally bug-for-bug compatible
#     with v1 for downstream parsers that depend on the v1 shape.
#
# At PR 3 this is a stub. PR 4 fills in the body and the table-driven
# tests (one row per format / culture combination).
# =============================================================================

function ConvertTo-WamLogLine {
    <#
    .SYNOPSIS
        Format a WAM log line for a given message and logging
        configuration.

    .DESCRIPTION
        Pure function: no I/O. Returns the string a logger would
        write. Used by Write-WamLog for the actual log files and by
        Pester tests to assert exact output without a filesystem
        round-trip.

        Honors Logging.LegacyTimestamp to reproduce v1's exact
        culture-dependent timestamp shape.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [hashtable] $LoggingConfig,

        [Parameter()]
        [datetime] $WorkingDate = [datetime]::Now,

        [Parameter()]
        [string] $ComputerName = $env:COMPUTERNAME
    )

    throw [System.NotImplementedException]::new(
        'ConvertTo-WamLogLine will be implemented in PR 4 (pure logic extraction).'
    )
}
