# =============================================================================
# Private/ConvertTo-WamLogLine.ps1
# =============================================================================
# Pure log-line formatting. Two output shapes:
#
#   - Default (v2):
#       "[2026-05-08 10:30:00] [TESTHOST] alice.normal, ..., Account Disabled."
#     ISO 8601 timestamp formatted under InvariantCulture so the output is
#     stable regardless of the runner's CurrentCulture. The configurable
#     timestamp format string still allows operators to dial it (e.g. swap
#     in fractional seconds, milliseconds for forensics).
#
#   - Legacy (LegacyTimestamp = $true):
#       "[5/8/2026 10:30:00 AM] [TESTHOST] alice.normal, ..."
#     v1's exact culture-dependent shape. ToShortDateString() and
#     ToLongTimeString() each format under CurrentCulture; the en-US
#     output above is what the prod scheduled task emits today and what
#     downstream consumers (if any) parse.
#
# The split-from-Write-WamLog matters because it makes the format
# testable in isolation: every culture / format-string combination can
# be a Pester table row, and PR 5's Write-WamLog can mock this function
# rather than re-implementing the format.
#
# Why the v1 shape uses $WorkingDate twice
# ----------------------------------------
# v1 calls (Get-Date) twice per log line -- once for ToShortDateString,
# once for ToLongTimeString. The two calls can land in different
# milliseconds. We replicate this faithfully by calling the methods on
# our $WorkingDate parameter twice. In practice the gap between the two
# calls is microseconds, so the date and the time always correspond to
# the same instant -- but if a future test pins exact output we need
# the v1 behavior reproduced as-written.
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
        [AllowEmptyString()]
        [string] $ComputerName = $env:COMPUTERNAME
    )

    # We default ComputerName from $env:COMPUTERNAME at param-default time.
    # Linux pwsh leaves that empty, which would emit "[]" for the host
    # bracket. That is acceptable -- consumers that care about the host
    # name are running on Windows where the variable is populated. The
    # snapshot test pins the value via the harness explicitly.

    # The legacy switch comes from the LoggingConfig hashtable. We treat
    # a missing key the same as a $false value -- absent means "v2
    # default behavior."
    $useLegacy = $false
    if ($LoggingConfig.ContainsKey('LegacyTimestamp')) {
        $useLegacy = [bool] $LoggingConfig['LegacyTimestamp']
    }

    if ($useLegacy) {
        # Faithful v1 reproduction. ToShortDateString and
        # ToLongTimeString each format under CurrentCulture; an en-US
        # runner produces "5/8/2026 10:30:00 AM", a de-DE runner would
        # produce "08.05.2026 10:30:00". v1 had no culture pinning, so
        # neither do we; downstream consumers that depend on the v1
        # shape are presumed to run under the same culture they always
        # have.
        $timestamp = $WorkingDate.ToShortDateString() + ' ' + $WorkingDate.ToLongTimeString()
    }
    else {
        # ISO 8601 default. Format string comes from config so an
        # operator can opt into milliseconds without a code change. We
        # format under InvariantCulture explicitly so the output is
        # culture-stable -- a German operator running interactively
        # gets the same string a CI runner produces.
        $format = if ($LoggingConfig.ContainsKey('TimestampFormat')) {
            [string] $LoggingConfig['TimestampFormat']
        }
        else {
            'yyyy-MM-dd HH:mm:ss'
        }

        $timestamp = $WorkingDate.ToString($format, [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return ('[' + $timestamp + '] [' + $ComputerName + '] ' + $Message)
}
