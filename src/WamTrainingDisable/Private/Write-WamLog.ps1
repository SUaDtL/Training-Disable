# =============================================================================
# Private/Write-WamLog.ps1
# =============================================================================
# Single multi-channel logger. v1 had three near-identical functions
# (Write-Log, Write-LogVIP, Write-LogEXEMPT) with their own copies of
# the timestamp logic, the mkdir-if-missing guard, and the file-append
# call. v2 collapses to one function that takes -Channel as an array;
# the orchestrator passes the channel list returned by
# Test-WamUserExemption.
#
# Why this consolidation matters:
#
#   - One copy of the timestamp formatting -- swap to ISO 8601 in one
#     place instead of three.
#   - One copy of the mkdir guard -- v1's three copies each leaked the
#     New-Item DirectoryInfo to the success stream because none of them
#     piped to Out-Null. The fix lives here, once.
#   - One Channels-to-paths mapping -- adding a fourth channel (e.g.
#     a "ChangedDescription" audit channel for SOX) becomes a single
#     keyword change.
#
# At PR 3 this is a stub. PR 5 fills in the body.
# =============================================================================

function Write-WamLog {
    <#
    .SYNOPSIS
        Append a line to one or more WAM log channels.

    .DESCRIPTION
        Internal helper. Formats a log line via ConvertTo-WamLogLine,
        ensures the destination directory exists (without leaking the
        New-Item output -- v1's bug), and appends the line to each of
        the named channels' files.

        Channel-to-path mapping comes from the resolved
        Logging.FileNameFormat hashtable. Unknown channel names raise
        a terminating error so a typo in the orchestrator surfaces
        immediately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [ValidateSet('Main', 'Vip', 'Exempt')]
        [string[]] $Channel,

        [Parameter(Mandatory)]
        [hashtable] $LoggingConfig,

        [Parameter()]
        [datetime] $WorkingDate = [datetime]::Now
    )

    throw [System.NotImplementedException]::new(
        'Write-WamLog will be implemented in PR 5 (I/O wrappers).'
    )
}
