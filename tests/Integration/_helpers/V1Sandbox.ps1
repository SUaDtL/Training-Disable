# =============================================================================
# tests/Integration/_helpers/V1Sandbox.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# This file exposes ONE function -- Invoke-V1InSandbox -- which runs the
# original src/TrainingDisable.ps1 (v1) end-to-end against in-memory fixtures
# and returns the paths of the four output files it produced plus the AD
# write calls it would have made.
#
# It is the linchpin of the v2 modernization. PR 2 stands up this harness
# AND the golden fixtures it produces; every subsequent PR that touches
# v1's behavior must keep the integration test green. When v1 is finally
# replaced by the drop-in shim in PR 7, this same harness will run the
# shim instead of v1 and the test will assert that the shim's output is
# byte-for-byte (after timestamp normalization) identical to the v1
# baseline locked in PR 2.
#
# Why a hand-rolled sandbox instead of Pester's Mock?
# ---------------------------------------------------
# Two reasons:
#
#   1. v1 is not testable as written. It calls Start-Main at parse time, has
#      no parameters, hard-codes the SQL connection string, depends on the
#      ActiveDirectory module (which is not available on Linux pwsh runners),
#      and binds log paths via shared script-scope variables. Pester's Mock
#      cannot reach inside a script that auto-runs at parse time.
#
#   2. The harness needs to work standalone -- not just inside Pester. We use
#      it directly in a fixture-capture script the first time we want to
#      regenerate the golden output, and that script is plain pwsh, not
#      Pester. Building on Pester primitives would couple the harness to a
#      test framework that is not even on the developer's PATH if PSGallery
#      is unreachable.
#
# How the sandbox works
# ---------------------
# Each call to Invoke-V1InSandbox follows this recipe:
#
#   1. Set up isolated state inside the function's local scope. PowerShell
#      function scopes evaporate on return, so each call is hermetic.
#
#   2. Define stub functions for Get-ADUser, Get-ADGroup, Disable-ADAccount,
#      Set-ADUser, and Write-Host. These are FUNCTIONS, which take precedence
#      over CMDLETS in PowerShell command resolution -- so when v1's
#      WAM-ADSearch calls Get-ADUser, the stub answers, not the AD module.
#      This works on a Linux runner where the AD module is not installed.
#
#   3. Read v1's source file, strip the trailing 'Start-Main' invocation
#      (otherwise dot-sourcing v1 would auto-run it before we have a chance
#      to override the SQL stage), and write the patched copy to a temp
#      file. We dot-source the temp copy.
#
#   4. After dot-source, override the path variables ($LogFileBasePath etc.)
#      to point at the harness's working directory. v1's loggers and SQL
#      stage all read these via dynamic scope, so this redirection is the
#      only thing that keeps them out of the prod path C:\PS\Script_Output.
#
#   5. Replace v1's WAM-SQLLookup function with a stub that writes the
#      caller-supplied username list to $LockoutListFile. This bypasses the
#      hard-coded SQL connection string.
#
#   6. Call Start-Main. v1 executes top-to-bottom against the fixtures.
#
#   7. Return a result object with the file paths it produced and the AD
#      write calls it attempted. The caller reads those files and compares
#      against the golden fixtures.
#
# What the harness intentionally does NOT do
# ------------------------------------------
# - It does not modify src/TrainingDisable.ps1. v1 is the contract; we work
#   around its quirks rather than fixing them in place. v2 fixes them in
#   src/WamTrainingDisable/.
#
# - It does not silence v1's pre-existing PSScriptAnalyzer violations. The
#   CI workflow excludes src/TrainingDisable.ps1 from analysis precisely
#   because v1 has dozens of known violations that are intentionally out of
#   scope until the rewrite cuts over.
#
# - It does not reproduce v1's SQL stage faithfully. The SQL stage's
#   exact behavior (including its known defect of selecting only the first
#   row via Select-Object -Index 0) is locked separately by unit tests on
#   v2's Get-WamNonCompliantUser. The drop-in compatibility contract this
#   harness pins is "given a list of usernames, the AD/log pipeline
#   produces these files."
#
# Variable shadowing / dynamic scope
# ----------------------------------
# v1 binds $LogFileBasePath, $LogFileALL, $LogFileVIP, $LogFileExempt,
# $LockoutListFile, $Date, $GracePeriod, $ReportOnly, $VIP, $REL, $SCO, and
# $Exempt at top-level. Dot-sourcing v1 inside Invoke-V1InSandbox puts those
# variables in this function's scope. v1's nested functions (Write-Log,
# WAM-Disable, etc.) resolve them via PowerShell's dynamic-scope fallback
# at call time -- which means we can simply re-assign them in this function
# AFTER the dot-source and v1's code will see the new values.
#
# This is normally a code smell (relying on dynamic scope is brittle), but
# v1 was written to depend on it, so we lean on it deliberately to keep v1
# unmodified.
#
# Determinism
# -----------
# Two sources of non-determinism need to be pinned for the snapshot to be
# stable across runners:
#
#   1. $env:COMPUTERNAME -- on Windows it is the machine name; on Linux pwsh
#      it is empty unless explicitly set. Both runners need the same value.
#      We pin it via the -ComputerName parameter and write directly to
#      $env:COMPUTERNAME inside the sandbox.
#
#   2. CurrentCulture -- v1's timestamps come from .ToShortDateString() and
#      .ToLongTimeString(), which format according to the current culture.
#      An en-US runner emits "5/8/2026 10:30:00 AM"; a de-DE runner would
#      emit "08.05.2026 10:30:00". We pin to en-US for the test. The
#      culture-independence fix lives in v2's ConvertTo-WamLogLine.
#
# The third source -- the timestamp itself -- is intentionally NOT pinned.
# The snapshot fixtures store messages with a placeholder where the
# timestamp prefix would go, and the test's normalizer strips the actual
# prefix before comparison. We do not freeze the clock because doing so
# would also alter the inputs to the grace-period check, and we want the
# grace-period check to use real time arithmetic.
# =============================================================================

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-V1InSandbox {
    <#
    .SYNOPSIS
        Runs an unmodified copy of src/TrainingDisable.ps1 against in-memory
        fixtures and returns the produced log files plus the AD writes it
        attempted.

    .DESCRIPTION
        The function dot-sources v1 into its own function scope after stripping
        v1's auto-run line, redirects the path variables, replaces the SQL
        stage with a stub that writes the caller's username list, and then
        calls Start-Main. The Get-ADUser, Get-ADGroup, Disable-ADAccount,
        Set-ADUser, and Write-Host calls v1 makes are intercepted by stub
        functions defined inside this scope.

        Each invocation is hermetic: function scope ends on return, so the
        stubs and the dot-sourced v1 functions do not leak to the caller.

    .PARAMETER V1ScriptPath
        Absolute path to src/TrainingDisable.ps1. Required so the harness
        works whether it is invoked from $PSScriptRoot, the repo root, or a
        Pester runner.

    .PARAMETER WorkingDirectory
        Directory under which the harness writes the patched-v1 script copy
        and the log file tree. Will be created if missing. Use $TestDrive
        from inside Pester for automatic cleanup.

    .PARAMETER UsernameList
        Array of bare usernames (post-DOMAIN\ trim) the SQL stub will write
        to $LockoutListFile. The order matters because v1 iterates the file
        in order and emits log lines in order.

    .PARAMETER AdRecords
        Hashtable keyed by SamAccountName. Each value is itself a hashtable
        with keys: Name, Enabled, whenCreated (datetime), Department,
        OfficePhone, Description, DistinguishedName, MemberOf (array of
        group DNs). A username that is in $UsernameList but missing from
        $AdRecords causes the stub Get-ADUser to throw a terminating
        identity error -- which mirrors the ActiveDirectory module's
        real-world behavior on non-existent identities.

    .PARAMETER GroupRecords
        Hashtable keyed by group DN. Each value is the group display name.
        v1 calls Get-ADGroup with each DN in MemberOf to project to display
        names; this table is the lookup. Missing DNs fall back to the CN=
        portion of the DN.

    .PARAMETER ConfigOverrides
        Hashtable of v1 config variable names to override (e.g.
        @{ ReportOnly = $false }). Keys must match v1's variable names
        verbatim. Missing keys keep v1's defaults.

    .PARAMETER DateString
        Pinned yyyyMMdd date used for the log file path suffix. Defaults to
        '20260508'. We pin this rather than reading the current date because
        $LogFileBasePath bakes the date into the directory name and the
        snapshot fixtures need a deterministic path to compare against.

    .PARAMETER ComputerName
        Pinned hostname for the [$ComputerName] log prefix. Defaults to
        'TESTHOST'. Linux pwsh leaves $env:COMPUTERNAME empty by default;
        pinning here gives parity with Windows runners.

    .OUTPUTS
        [pscustomobject] with the following members:
            LogFileBasePath  - the directory containing the four output files
            LockoutListFile  - path to the v1 LockoutList_<date>.txt
            LogFileALL       - path to the v1 LockoutUsers_All_<date>.log
            LogFileVIP       - path to the v1 LockoutUsers_VIP_<date>.log
            LogFileExempt    - path to the v1 LockoutUsers_EXEMPT_<date>.log
            DisableCalls     - array of @{ Identity = ... } hashtables, one
                               per Disable-ADAccount call v1 attempted
            SetUserCalls     - array of @{ Identity, Description } hashtables,
                               one per Set-ADUser call v1 attempted
            HostMessages     - array of strings, one per Write-Host call

    .EXAMPLE
        $result = Invoke-V1InSandbox `
            -V1ScriptPath './src/TrainingDisable.ps1' `
            -WorkingDirectory $TestDrive `
            -UsernameList @('alice.normal') `
            -AdRecords @{ 'alice.normal' = @{ Name = 'Alice'; Enabled = $true; ... } } `
            -GroupRecords @{}

        Get-Content -Path $result.LogFileALL

        Runs v1 against a single-user fixture and inspects the main log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $V1ScriptPath,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]] $UsernameList,

        [Parameter(Mandatory)]
        [hashtable] $AdRecords,

        [Parameter()]
        [hashtable] $GroupRecords = @{},

        [Parameter()]
        [hashtable] $ConfigOverrides = @{},

        [Parameter()]
        [string] $DateString = '20260508',

        [Parameter()]
        [string] $ComputerName = 'TESTHOST'
    )

    # -------------------------------------------------------------------------
    # Step 1: Initialize the call recorders.
    # -------------------------------------------------------------------------
    # The stubs (defined below) write to these lists by walking up the
    # dynamic-scope chain. We must initialize them BEFORE defining the stubs
    # so the lookup succeeds at stub-call time.
    # -------------------------------------------------------------------------
    $disableCalls = [System.Collections.Generic.List[object]]::new()
    $setUserCalls = [System.Collections.Generic.List[object]]::new()
    $hostMessages = [System.Collections.Generic.List[object]]::new()

    # -------------------------------------------------------------------------
    # Step 2: Define stub functions in this scope.
    # -------------------------------------------------------------------------
    # Functions defined here are visible to v1's nested functions (which run
    # in a child dynamic scope) and shadow the cmdlets of the same name in
    # the ActiveDirectory module. PowerShell command resolution order is
    # Aliases > Functions > Cmdlets, so a function named Get-ADUser in our
    # scope wins over the AD module's cmdlet of the same name -- even when
    # that module has been auto-loaded.
    # -------------------------------------------------------------------------

    function Get-ADUser {
        # PURPOSE: stand in for ActiveDirectory's Get-ADUser cmdlet.
        #
        # v1 calls this in two shapes:
        #   1. Get-ADUser -Identity $User -Properties ...   # $User is a string
        #   2. Get-ADUser $ADAccount -Properties memberof   # $ADAccount is the
        #                                                   # object returned
        #                                                   # by call (1)
        #
        # Both forms boil down to "give me the record for this SamAccountName."
        # We accept both shapes by sniffing the type of -Identity.
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, Mandatory)]
            $Identity,

            [Parameter()]
            [string[]] $Properties
        )

        # The -Properties list is irrelevant in the sandbox -- we always
        # return all the attributes v1 ever reads. Reference it explicitly
        # to keep PSUseDeclaredVarsMoreThanAssignments quiet.
        $null = $Properties

        $key = if ($Identity -is [string]) {
            $Identity
        }
        else {
            $Identity.SamAccountName
        }

        if (-not $AdRecords.ContainsKey($key)) {
            # Mirror the AD module's behavior: a missing identity raises a
            # terminating error. v1's WAM-ADSearch wraps the call in
            # try/catch; the catch branch prints a Write-Host and falls
            # through to the (broken) "is $ADAccount $null" guard.
            throw "Cannot find an object with identity: '$key' under: 'sandbox'."
        }

        $record = $AdRecords[$key]
        return [pscustomobject] @{
            SamAccountName = $key
            Name = $record.Name
            Enabled = [bool] $record.Enabled
            whenCreated = [datetime] $record.whenCreated
            Department = $record.Department
            OfficePhone = $record.OfficePhone
            Description = $record.Description
            DistinguishedName = $record.DistinguishedName
            MemberOf = @($record.MemberOf)
        }
    }

    function Get-ADGroup {
        # PURPOSE: project a group DN to a display name.
        #
        # v1 calls Get-ADGroup once per DN in $ADAccount.MemberOf, then reads
        # the .Name property on each result. Our stub returns a record with
        # just .Name; v1 does not read anything else from it.
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, Mandatory, ValueFromPipeline = $true)]
            $Identity
        )

        process {
            if ($GroupRecords.ContainsKey($Identity)) {
                return [pscustomobject] @{ Name = $GroupRecords[$Identity] }
            }

            # Fall back to parsing the leading CN= of the DN. That matches
            # what v1 would observe in production for any group whose name
            # is encoded in its CN -- which is essentially all of them.
            if ($Identity -match '^CN=([^,]+)') {
                return [pscustomobject] @{ Name = $matches[1] }
            }

            return [pscustomobject] @{ Name = [string] $Identity }
        }
    }

    function Disable-ADAccount {
        # PURPOSE: record the disable attempt without touching real AD.
        #
        # v1 calls this from WAM-Disable's try block. On success, v1
        # proceeds to read the user's old description and append the
        # disabled-for-training-non-compliance suffix via Set-ADUser. To
        # exercise that whole code path the stub must succeed silently.
        #
        # Why suppress PSUseShouldProcessForStateChangingFunctions: this is a
        # test stub that shadows the AD module's real cmdlet of the same
        # name. The PSScriptAnalyzer rule fires on any user function whose
        # verb is in the state-changing list (Disable, Set, Remove, etc.)
        # and that does not declare SupportsShouldProcess. Adding
        # ShouldProcess to a no-op stub would be cosmetic noise; the stub
        # never performs the operation it is named after.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Test stub; the function name shadows a real cmdlet but performs no state change.')]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            $Identity
        )

        # [ordered] preserves key insertion order so the JSON-serialized
        # capture is deterministic across runs. Plain @{} is a Hashtable,
        # whose key enumeration order is implementation-defined.
        $disableCalls.Add([ordered] @{ Identity = $Identity })
    }

    function Set-ADUser {
        # PURPOSE: record the description-update attempt without touching AD.
        #
        # v1 invokes Set-ADUser ONLY in the success branch of WAM-Disable's
        # try block. Capturing the (Identity, Description) pair here lets
        # the test assert exactly what v1 would have written to AD.
        #
        # See the suppression note on Disable-ADAccount above. Same reasoning
        # applies: this is a test stub, not a real state-changing cmdlet.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Test stub; the function name shadows a real cmdlet but performs no state change.')]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            $Identity,

            [Parameter()]
            [string] $Description
        )

        # See the [ordered] note in Disable-ADAccount above. Identity comes
        # first in the captured JSON; Description second.
        $setUserCalls.Add([ordered] @{
                Identity = $Identity
                Description = $Description
            })
    }

    function Write-Host {
        # PURPOSE: capture v1's Write-Host calls to a list instead of the
        # console.
        #
        # v1 uses Write-Host for "Searching for $User in AD" and "$User not
        # found" debug output. The harness silences the console (otherwise
        # CI logs are full of fixture chatter) but keeps the messages
        # available for assertion-by-the-tests.
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline = $true)]
            $Object,

            [Parameter()]
            [string] $ForegroundColor
        )

        # Reference -ForegroundColor so the analyzer does not flag it as an
        # unused parameter; v1 passes it for the not-found message.
        $null = $ForegroundColor

        $hostMessages.Add([string] $Object)
    }

    # -------------------------------------------------------------------------
    # Step 3: Pin the determinism levers.
    # -------------------------------------------------------------------------
    $env:COMPUTERNAME = $ComputerName
    [System.Threading.Thread]::CurrentThread.CurrentCulture =
    [System.Globalization.CultureInfo]::new('en-US')

    # -------------------------------------------------------------------------
    # Step 4: Patch v1 to disable its parse-time auto-run.
    # -------------------------------------------------------------------------
    # v1's last non-comment line is a bare 'Start-Main' invocation. If we
    # simply dot-source v1, that line runs against v1's defaults BEFORE we
    # have a chance to redirect the log paths or replace the SQL stage. We
    # strip the line and dot-source the patched copy.
    #
    # We use a line-equality filter rather than a regex so we cannot
    # accidentally strip a function definition that happens to mention
    # 'Start-Main' in a comment.
    # -------------------------------------------------------------------------
    if (-not (Test-Path -Path $WorkingDirectory)) {
        New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    }

    $sourceLines = Get-Content -Path $V1ScriptPath -Encoding utf8
    $patchedLines = $sourceLines | Where-Object { $_.Trim() -ne 'Start-Main' }
    $tempScript = Join-Path -Path $WorkingDirectory -ChildPath 'v1.harness.ps1'
    Set-Content -Path $tempScript -Value $patchedLines -Encoding utf8

    # -------------------------------------------------------------------------
    # Step 5: Dot-source the patched v1.
    # -------------------------------------------------------------------------
    # This loads v1's functions and v1's default config variables into THIS
    # function's scope. v1's nested functions resolve $LogFileBasePath etc.
    # via dynamic scope at call time, so re-binding those variables AFTER
    # this dot-source (Step 6) does the right thing.
    # -------------------------------------------------------------------------
    . $tempScript

    # -------------------------------------------------------------------------
    # Step 6: Redirect path variables to the sandbox working directory.
    # -------------------------------------------------------------------------
    # v1 binds $LogFileBasePath = "C:\PS\Script_Output\WAM\$Date". We replace
    # that with a path under $WorkingDirectory so the snapshot lives under
    # $TestDrive (or any caller-supplied temp location) instead of touching
    # the production output tree.
    # -------------------------------------------------------------------------
    $Date = $DateString
    $LogFileBasePath = Join-Path -Path $WorkingDirectory -ChildPath 'logs'
    $LockoutListFile = Join-Path -Path $LogFileBasePath -ChildPath "LockoutList_$Date.txt"
    $LogFileALL = Join-Path -Path $LogFileBasePath -ChildPath "LockoutUsers_All_$Date.log"
    $LogFileVIP = Join-Path -Path $LogFileBasePath -ChildPath "LockoutUsers_VIP_$Date.log"
    $LogFileExempt = Join-Path -Path $LogFileBasePath -ChildPath "LockoutUsers_EXEMPT_$Date.log"

    # The dot-sourced v1 also sets $GracePeriod, $ReportOnly, $VIP, $REL,
    # $SCO, $Exempt at its defaults. Apply caller-supplied overrides on top.
    foreach ($key in $ConfigOverrides.Keys) {
        Set-Variable -Name $key -Value $ConfigOverrides[$key]
    }

    # -------------------------------------------------------------------------
    # Step 7: Replace v1's SQL stage with a fixture-writing stub.
    # -------------------------------------------------------------------------
    # v1's WAM-SQLLookup hard-codes a connection string to the production
    # WebTraining DB. It also has a separate defect (Select-Object -Index 0
    # truncates the result set to a single user) that we sidestep by
    # replacing the function entirely. The replacement writes the caller's
    # username list to $LockOutListFile in v1's expected format. v1's
    # Out-File-as-IPC handoff to WAM-ADSearch is preserved so the rest of
    # the pipeline runs end-to-end.
    #
    # We re-define the function AFTER the dot-source so the new definition
    # shadows v1's. PowerShell allows re-definition of functions in the
    # same scope -- the latest assignment wins.
    # -------------------------------------------------------------------------
    function WAM-SQLLookup {
        # Why suppress PSUseApprovedVerbs: this stub intentionally reproduces
        # v1's unapproved-verb function name. The integration sandbox dot-
        # sources v1's script, then re-defines this function to capture the
        # call without contacting the real production database. Renaming the
        # stub would break the shadow-and-replace pattern.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseApprovedVerbs',
            '',
            Justification = 'Intentional shadow of v1 function name; stub captures the call without renaming the surface seen by the dot-sourced v1 script.')]
        [CmdletBinding()]
        param()

        if (-not (Test-Path -Path $LogFileBasePath)) {
            New-Item -ItemType Directory -Path $LogFileBasePath -Force | Out-Null
        }
        $UsernameList | Out-File -FilePath $LockoutListFile -Encoding ascii
    }

    # -------------------------------------------------------------------------
    # Step 8: Pre-create the log directory.
    # -------------------------------------------------------------------------
    # v1's three loggers (Write-Log, Write-LogVIP, Write-LogEXEMPT) each have
    # a "if directory missing, New-Item it" guard. The New-Item call is NOT
    # piped to Out-Null, so the DirectoryInfo it returns bubbles up the
    # call stack and merges with this function's own return value -- so the
    # caller's $result.LogFileALL becomes "object 1 of 2 in an array."
    #
    # We sidestep the leak by creating the directory ourselves before
    # calling Start-Main. v1's guards then evaluate false and the New-Item
    # branch never runs. v2 will fix this properly by piping the New-Item
    # result to Out-Null inside the unified Write-WamLog.
    # -------------------------------------------------------------------------
    if (-not (Test-Path -Path $LogFileBasePath)) {
        New-Item -ItemType Directory -Path $LogFileBasePath -Force | Out-Null
    }

    # -------------------------------------------------------------------------
    # Step 9: Run v1 end-to-end.
    # -------------------------------------------------------------------------
    # We pipe to Out-Null defensively. v1 should not emit anything to the
    # success stream now that the directory pre-exists, but if a future
    # change introduces another stray emission we'd rather quietly drop it
    # than corrupt the harness's own return value. The HostMessages list
    # captures Write-Host output for separate inspection.
    # -------------------------------------------------------------------------
    Start-Main | Out-Null

    # -------------------------------------------------------------------------
    # Step 10: Surface results to the caller.
    # -------------------------------------------------------------------------
    return [pscustomobject] @{
        LogFileBasePath = $LogFileBasePath
        LockoutListFile = $LockoutListFile
        LogFileALL = $LogFileALL
        LogFileVIP = $LogFileVIP
        LogFileExempt = $LogFileExempt
        DisableCalls = $disableCalls.ToArray()
        SetUserCalls = $setUserCalls.ToArray()
        HostMessages = $hostMessages.ToArray()
    }
}

function ConvertTo-NormalizedV1LogLine {
    <#
    .SYNOPSIS
        Strip the variable-prefix portion of a v1 log line so the snapshot
        comparison can ignore timestamps and hostnames.

    .DESCRIPTION
        v1's log lines have the shape "[<timestamp>] [<host>] <message>".
        The timestamp varies on every run; the hostname is stable in our
        sandbox but varies in production. The snapshot fixtures only pin
        the message portion so the test passes on Windows PS 5.1, pwsh on
        Windows, and pwsh on Linux without baking in machine-specific
        details.

        Lines that do not match the expected prefix shape are returned
        unchanged -- this catches the BEGIN/END banner lines (which DO
        carry a prefix in v1) and any unexpected output (which should
        fail the snapshot loudly rather than be silently mangled).

    .PARAMETER Line
        A single log line, with or without the prefix.

    .OUTPUTS
        [string] -- the message portion, or the original line if no prefix
        was found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string] $Line
    )

    process {
        # Anchor to start-of-line to avoid stripping a bracketed token that
        # appears inside a message. The prefix is two bracketed groups
        # separated by a single space, followed by a single space before the
        # message body.
        $stripped = $Line -replace '^\[[^\]]*\] \[[^\]]*\] ', ''
        return $stripped
    }
}
