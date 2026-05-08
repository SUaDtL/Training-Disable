# =============================================================================
# Private/Add-WamLogContent.ps1
# =============================================================================
# Thin wrapper around [System.IO.File]::AppendAllText. Exists for two
# reasons:
#
#   1. AGENTS.md guidance prefers AppendAllText over Out-File for log
#      writes (avoids the per-line pipeline overhead of Out-File). This
#      wrapper centralizes the static-method call so a future swap (e.g.
#      to a buffered writer for higher-throughput logs) lives in one
#      place.
#
#   2. PowerShell test frameworks cannot mock .NET static methods
#      directly. Wrapping the static call in a function gives Pester a
#      Command name to intercept, which the unit tests for Write-WamLog
#      use to assert per-channel calls without writing to the real
#      filesystem.
#
# The wrapper is intentionally a one-liner with no error handling: any
# I/O exception propagates up to the caller (Write-WamLog), which lets
# the orchestrator decide how to react (typically: log a "failed to
# write to log" line on a different channel).
# =============================================================================

function Add-WamLogContent {
    <#
    .SYNOPSIS
        Append text to a file using the supplied encoding.

    .DESCRIPTION
        Internal helper. Wraps [System.IO.File]::AppendAllText so that
        Pester's Mock can intercept the call. The string is appended
        as-is (no automatic newline). Callers that want a trailing
        newline must add it explicitly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Content,

        [Parameter(Mandatory)]
        [System.Text.Encoding] $Encoding
    )

    [System.IO.File]::AppendAllText($Path, $Content, $Encoding)
}
