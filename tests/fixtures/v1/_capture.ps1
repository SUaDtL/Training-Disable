# =============================================================================
# tests/fixtures/v1/_capture.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# Bootstrap script that runs the v1 sandbox harness against the canned
# fixtures in this directory and writes the produced log files back to
# tests/fixtures/v1/expected/. Run this when:
#
#   - The fixture inputs change (a new user added, a group added, etc.) and
#     the expected output needs to be regenerated.
#
#   - A genuine v1 behavior change is being intentionally accepted (rare;
#     v1 is supposed to be frozen). Regenerate, eyeball the diff, commit.
#
# Run it from the repo root:
#
#     pwsh -NoProfile -File tests/fixtures/v1/_capture.ps1
#
# The script does NOT run in CI. CI runs Pester against the committed
# expected/ files; that is the regression check. This script is purely a
# developer convenience for regenerating those files when the inputs
# legitimately change.
#
# Why not just commit a "first run" of the test?
# ----------------------------------------------
# The Pester test runs in $TestDrive and tears its working directory down
# at the end. If we relied on the test to write the fixtures, we would have
# a chicken-and-egg problem: the first run would always fail (no fixtures
# to compare against), and there is no clean signal-from-Pester to "please
# write the fixtures this time instead of comparing." Capturing here keeps
# the test pure-comparison.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter()]
    [switch] $WhatIf
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Resolve repo paths from this script's location -- the script can be run
# from any working directory.
$ScriptDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -Path (Join-Path -Path $ScriptDir -ChildPath '../../..')).Path
$V1Path = Join-Path -Path $RepoRoot -ChildPath 'src/TrainingDisable.ps1'
$HelperPath = Join-Path -Path $RepoRoot -ChildPath 'tests/Integration/_helpers/V1Sandbox.ps1'
$ExpectedDir = Join-Path -Path $ScriptDir -ChildPath 'expected'

# Working directory under the OS temp dir. We do NOT use $ScriptDir as the
# working directory because the harness creates 'logs/' inside it and we
# do not want stray sandbox runs polluting the fixture tree.
$WorkDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wam-v1-capture-" + [Guid]::NewGuid().ToString('N'))

. $HelperPath

# -----------------------------------------------------------------------------
# Fixture inputs.
# -----------------------------------------------------------------------------
# These mirror what the Pester test feeds to the harness; keeping them in
# sync is what makes the captured output match the test's expectations.
# When you add a user to one place, add them to the other.
#
# User picks cover the v1 if/elseif/else branches in WAM-ADSearch:
#
#   alice.normal    enabled, past grace, no exemptions          -> disable path
#                                                                  (logged-only
#                                                                   in ReportOnly
#                                                                   default)
#   bob.disabled    Enabled = $false                             -> already-disabled
#   carol.grace     enabled, within 30-day grace                 -> grace-period
#   dan.rel         enabled, past grace, OU=REL                  -> REL exempt
#   eve.sco         enabled, past grace, OU=SCO                  -> SCO exempt
#   frank.group     enabled, past grace, in 'VIP No Tng Req'     -> group-exempt
# -----------------------------------------------------------------------------
$UsernameList = @(
    'alice.normal'
    'bob.disabled'
    'carol.grace'
    'dan.rel'
    'eve.sco'
    'frank.group'
)

# The pinned date is 2026-05-08; whenCreated values are computed relative
# to that so the grace-period check is deterministic. We must not let the
# fixture computation drift with the wall clock.
$PinnedNow = [datetime]'2026-05-08T10:30:00'

$AdRecords = @{
    'alice.normal' = @{
        Name = 'Alice Normal'
        Enabled = $true
        whenCreated = $PinnedNow.AddDays(-90)
        Department = 'Engineering'
        OfficePhone = '555-0001'
        Description = 'Software Engineer II'
        DistinguishedName = 'CN=alice.normal,OU=Users,DC=example,DC=com'
        MemberOf = @()
    }
    'bob.disabled' = @{
        Name = 'Bob Disabled'
        Enabled = $false
        whenCreated = $PinnedNow.AddDays(-90)
        Department = 'Engineering'
        OfficePhone = '555-0002'
        Description = 'Software Engineer II'
        DistinguishedName = 'CN=bob.disabled,OU=Users,DC=example,DC=com'
        MemberOf = @()
    }
    'carol.grace' = @{
        Name = 'Carol Grace'
        Enabled = $true
        whenCreated = $PinnedNow.AddDays(-10)
        Department = 'Engineering'
        OfficePhone = '555-0003'
        Description = 'Software Engineer I'
        DistinguishedName = 'CN=carol.grace,OU=Users,DC=example,DC=com'
        MemberOf = @()
    }
    'dan.rel' = @{
        Name = 'Dan REL'
        Enabled = $true
        whenCreated = $PinnedNow.AddDays(-90)
        Department = 'Engineering'
        OfficePhone = '555-0004'
        Description = 'Software Engineer II'
        DistinguishedName = 'CN=dan.rel,OU=REL,OU=Users,DC=example,DC=com'
        MemberOf = @()
    }
    'eve.sco' = @{
        Name = 'Eve SCO'
        Enabled = $true
        whenCreated = $PinnedNow.AddDays(-90)
        Department = 'Engineering'
        OfficePhone = '555-0005'
        Description = 'Software Engineer II'
        DistinguishedName = 'CN=eve.sco,OU=SCO,OU=Users,DC=example,DC=com'
        MemberOf = @()
    }
    'frank.group' = @{
        Name = 'Frank Group'
        Enabled = $true
        whenCreated = $PinnedNow.AddDays(-90)
        Department = 'Engineering'
        OfficePhone = '555-0006'
        Description = 'Software Engineer II'
        DistinguishedName = 'CN=frank.group,OU=Users,DC=example,DC=com'
        MemberOf = @('CN=VIP No Tng Req,OU=Groups,DC=example,DC=com')
    }
}

$GroupRecords = @{
    'CN=VIP No Tng Req,OU=Groups,DC=example,DC=com' = 'VIP No Tng Req'
}

# -----------------------------------------------------------------------------
# Run the sandbox: default config (ReportOnly = $true).
# -----------------------------------------------------------------------------
# This is the read-only run. It produces the lockout list, main log, VIP
# log, and exempt log fixtures the snapshot comparison locks. AD calls are
# expected to be empty because ReportOnly short-circuits the disable path.
# -----------------------------------------------------------------------------
$result = Invoke-V1InSandbox `
    -V1ScriptPath $V1Path `
    -WorkingDirectory (Join-Path $WorkDir 'default') `
    -UsernameList $UsernameList `
    -AdRecords $AdRecords `
    -GroupRecords $GroupRecords `
    -DateString '20260508' `
    -ComputerName 'TESTHOST'

# -----------------------------------------------------------------------------
# Run the sandbox: enforcement config (ReportOnly = $false).
# -----------------------------------------------------------------------------
# This run uses the same fixture user set; the only difference from the
# default run is that v1's WAM-Disable actually invokes the (stubbed)
# Disable-ADAccount and Set-ADUser cmdlets for alice.normal -- the only
# user who reaches the disable branch. The four log files produced are
# byte-identical to the default run because the log lines emitted by
# WAM-Disable are the same in both modes; we therefore only capture the
# AD-calls JSON from this run, not the logs.
# -----------------------------------------------------------------------------
$enforcementResult = Invoke-V1InSandbox `
    -V1ScriptPath $V1Path `
    -WorkingDirectory (Join-Path $WorkDir 'enforcement') `
    -UsernameList $UsernameList `
    -AdRecords $AdRecords `
    -GroupRecords $GroupRecords `
    -ConfigOverrides @{ ReportOnly = $false } `
    -DateString '20260508' `
    -ComputerName 'TESTHOST'

# -----------------------------------------------------------------------------
# Read the produced files, normalize the timestamp/host prefix, write the
# golden fixtures back to expected/.
# -----------------------------------------------------------------------------
if (-not (Test-Path -Path $ExpectedDir)) {
    New-Item -ItemType Directory -Path $ExpectedDir -Force | Out-Null
}

# Map of (output-name -> source-path) drives the capture loop.
$captures = @(
    @{ Name = 'lockout-list.txt'; Source = $result.LockoutListFile; Normalize = $false }
    @{ Name = 'main.normalized.log'; Source = $result.LogFileALL; Normalize = $true }
    @{ Name = 'vip.normalized.log'; Source = $result.LogFileVIP; Normalize = $true }
    @{ Name = 'exempt.normalized.log'; Source = $result.LogFileExempt; Normalize = $true }
)

foreach ($capture in $captures) {
    $destination = Join-Path -Path $ExpectedDir -ChildPath $capture.Name
    $sourcePath = $capture.Source

    if (-not (Test-Path -Path $sourcePath)) {
        Write-Warning "Source file missing: $sourcePath -- skipping $($capture.Name)."
        continue
    }

    $sourceLines = Get-Content -Path $sourcePath -Encoding utf8

    $output = if ($capture.Normalize) {
        $sourceLines | ConvertTo-NormalizedV1LogLine
    }
    else {
        $sourceLines
    }

    if ($WhatIf) {
        Write-Output "==> Would write $($capture.Name)"
        $output | Write-Output
        Write-Output ''
        continue
    }

    # We write the normalized files with LF line endings explicitly so the
    # snapshot comparison is line-ending-stable across runners. The test
    # normalizes incoming line endings the same way before comparing.
    Set-Content -Path $destination -Value $output -Encoding ascii -NoNewline:$false
    Write-Output "Wrote $destination"
}

# -----------------------------------------------------------------------------
# Pin the AD call captures from each run.
#
# The default-mode AD calls should be empty -- ReportOnly = $true means v1
# never invokes Disable-ADAccount or Set-ADUser. We pin that emptiness
# explicitly so a regression that accidentally introduces an AD write in
# the read-only path is caught immediately.
#
# The enforcement-mode AD calls are the (Identity, Description) pairs v1
# would have sent to the directory. The Description string includes a
# culture-dependent date and a pre-existing v1 typo (a stray opening
# parenthesis with no matching close). Both quirks are pinned in the
# fixture so we know if v2's behavior diverges.
# -----------------------------------------------------------------------------
$adCaptureMap = @(
    @{ Path = 'ad-calls.default.json'; Source = $result }
    @{ Path = 'ad-calls.enforcement.json'; Source = $enforcementResult }
)

foreach ($capture in $adCaptureMap) {
    $destination = Join-Path -Path $ExpectedDir -ChildPath $capture.Path
    $payload = [pscustomobject] @{
        DisableCalls = $capture.Source.DisableCalls
        SetUserCalls = $capture.Source.SetUserCalls
    }
    $serialized = $payload | ConvertTo-Json -Depth 4

    if ($WhatIf) {
        Write-Output "==> Would write $($capture.Path)"
        $serialized | Write-Output
        continue
    }

    Set-Content -Path $destination -Value $serialized -Encoding ascii
    Write-Output "Wrote $destination"
}

# Sandbox cleanup. The Pester test uses $TestDrive; this script makes its
# own temp dir which we tidy up here.
Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
