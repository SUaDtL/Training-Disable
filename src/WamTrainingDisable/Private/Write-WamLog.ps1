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

    # -------------------------------------------------------------------------
    # Resolve the directory.
    # -------------------------------------------------------------------------
    # The Directory key is a -f-format string with {0} expecting a
    # [datetime] (see WamTrainingDisable.config.psd1 for the shipped
    # default 'C:\PS\Script_Output\WAM\{0:yyyyMMdd}'). We feed
    # $WorkingDate so the date in the path matches the date in the log
    # lines we write -- a run that crosses midnight still writes a
    # consistent set of files.
    # -------------------------------------------------------------------------
    if (-not $LoggingConfig.ContainsKey('Directory')) {
        throw 'Write-WamLog: LoggingConfig is missing the required Directory key.'
    }
    $directory = $LoggingConfig['Directory'] -f $WorkingDate

    # -------------------------------------------------------------------------
    # mkdir -p, defect-11 fix.
    # -------------------------------------------------------------------------
    # v1's three loggers each had their own "if (-not test-path) New-Item"
    # block that did NOT pipe to Out-Null. The DirectoryInfo returned by
    # New-Item bubbled up and contaminated the caller's return stream --
    # specifically, the V1Sandbox harness had to pre-create the directory
    # to dodge that exact leak (see the long comment in V1Sandbox.ps1
    # step 8). v2 routes the New-Item output to Out-Null so the leak is
    # impossible by construction.
    #
    # We use -Force so a concurrent process that creates the directory
    # between our Test-Path and our New-Item does not race us into an
    # error. The cost of -Force on an existing directory is a no-op; the
    # benefit is one fewer narrow race.
    # -------------------------------------------------------------------------
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # -------------------------------------------------------------------------
    # Format the line through ConvertTo-WamLogLine.
    # -------------------------------------------------------------------------
    # We do this once per Write-WamLog call (NOT once per channel) so a
    # message broadcast to Main+Vip+Exempt has byte-identical timestamps
    # across the three files. v1's three loggers each called Get-Date
    # independently, so the same logical event could land at three
    # different timestamps if the second hand rolled over between calls.
    # That is a v1 quirk; we improve on it.
    # -------------------------------------------------------------------------
    $line = ConvertTo-WamLogLine `
        -Message $Message `
        -LoggingConfig $LoggingConfig `
        -WorkingDate $WorkingDate

    # -------------------------------------------------------------------------
    # File-name template lookup.
    # -------------------------------------------------------------------------
    # The Channel parameter is ValidateSet'd to {Main, Vip, Exempt}, but
    # the FileNameFormat hashtable might be missing a key if a user-
    # supplied config dropped one (deep merge replaces leaf values, not
    # the parent table). Guard explicitly with a clear error so a
    # missing key is caught at the first call rather than silently
    # writing to a typo'd file.
    # -------------------------------------------------------------------------
    if (-not $LoggingConfig.ContainsKey('FileNameFormat')) {
        throw 'Write-WamLog: LoggingConfig is missing the required FileNameFormat key.'
    }
    $fileNameFormat = $LoggingConfig['FileNameFormat']

    # -------------------------------------------------------------------------
    # Encoding selection.
    # -------------------------------------------------------------------------
    # v1 uses 'ascii' for every Out-File call; we honor that as the
    # default but allow override via Logging.Encoding. The string is
    # mapped to a real [System.Text.Encoding] instance so the
    # AppendAllText call below has a typed encoding object. Mapping is
    # case-insensitive and accepts the common string aliases that v1's
    # Out-File -Encoding accepted.
    # -------------------------------------------------------------------------
    $encodingName = if ($LoggingConfig.ContainsKey('Encoding')) {
        [string] $LoggingConfig['Encoding']
    }
    else {
        'ascii'
    }
    $encoding = switch -Regex ($encodingName) {
        '^(?i)ascii$' {
            [System.Text.Encoding]::ASCII
            break
        }
        '^(?i)utf8$' {
            [System.Text.UTF8Encoding]::new($false)
            break
        }
        '^(?i)utf8(no)?bom$' {
            [System.Text.UTF8Encoding]::new($false)
            break
        }
        '^(?i)utf8bom$' {
            [System.Text.UTF8Encoding]::new($true)
            break
        }
        '^(?i)unicode$' {
            [System.Text.Encoding]::Unicode
            break
        }
        '^(?i)utf32$' {
            [System.Text.Encoding]::UTF32
            break
        }
        default {
            throw "Write-WamLog: Unsupported encoding '$encodingName'. Use one of: ascii, utf8, utf8bom, unicode, utf32."
        }
    }

    # -------------------------------------------------------------------------
    # Append to every requested channel via Add-WamLogContent.
    # -------------------------------------------------------------------------
    # We iterate $Channel in the order the caller passed them. The
    # ValidateSet attribute already screened for unknown names, but we
    # double-check the FileNameFormat lookup for robustness against a
    # hand-edited config that dropped a key.
    #
    # Why the helper: Add-WamLogContent wraps
    # [System.IO.File]::AppendAllText. Per AGENTS.md guidance for log
    # writes, AppendAllText avoids the pipeline overhead Out-File incurs
    # per line. Wrapping in a function also gives Pester a Command name
    # to mock so the unit tests can assert per-channel calls without
    # writing to the real filesystem.
    #
    # AppendAllText writes the supplied string as-is. v1's Out-File
    # writes the line followed by the platform line ending. We append
    # [Environment]::NewLine explicitly so v1's behavior is preserved on
    # both Windows (CRLF) and Linux (LF).
    # -------------------------------------------------------------------------
    foreach ($channelName in $Channel) {
        if (-not $fileNameFormat.ContainsKey($channelName)) {
            throw "Write-WamLog: FileNameFormat has no entry for channel '$channelName'."
        }
        $fileName = $fileNameFormat[$channelName] -f $WorkingDate
        $filePath = Join-Path -Path $directory -ChildPath $fileName
        Add-WamLogContent -Path $filePath -Content ($line + [Environment]::NewLine) -Encoding $encoding
    }
}
