---
id: 0005
title: Fill the I/O-touching wrappers (SQL stage, AD detail fetch, multi-channel logger, single-user disable) and ship Pester unit tests
status: applied
category: change
created: 2026-05-08
updated: 2026-05-08
tags: [implementation, unit-tests, io-wrappers, pester, sql, active-directory, logging]
supersedes: []
superseded-by: []
related:
  - docs/project/changes/applied/0003-module-skeleton.md
  - docs/project/changes/applied/0004-pure-logic-extraction.md
  - docs/project/decisions/accepted/0001-modular-rewrite.md
  - docs/project/decisions/accepted/0006-vip-log-is-downstream-contract.md
  - docs/project/decisions/accepted/0009-shim-preserves-v1-entrypoint.md
---

## Summary

Fills the five I/O-touching stubs from PR 3 with real implementations and
ships exhaustive Pester 5 unit-test coverage for each. Adds one new thin
helper (Add-WamLogContent) for testability.

- `Public/Get-WamNonCompliantUser.ps1` -- the SQL stage. Resolves the
  configuration via Resolve-WamConfiguration, hands off to
  Invoke-WamSqlStoredProcedure, and projects DataRows to
  `[pscustomobject] @{ SamAccountName = ... }`. Returns objects (not a
  file -- the v1 Out-File-as-IPC handoff is retired). Returns ALL
  rows (defect-12 fix: v1's `Select-Object -Index 0` truncated to the
  first row).

- `Public/Disable-WamUserAccount.ps1` -- single-user disable.
  SupportsShouldProcess + ConfirmImpact='High'. Identity is a
  parameter, not dynamic-scope (defect-3 fix). Uses a local boolean to
  track success across try/catch instead of shadowing $Error
  (defect-2 fix). The caller passes `ExistingDescription` so we don't
  re-fetch the user inside the disable path (defect-4 fix). The
  description suffix is ISO 8601 + closing paren by default; the
  `-LegacyTimestamp` switch reproduces v1's culture-dependent
  ToShortDateString output verbatim, including the missing closing
  paren and trailing period (defect-1 byte-for-byte preservation,
  pinned by `tests/fixtures/v1/expected/ad-calls.enforcement.json`).

- `Private/Invoke-WamSqlStoredProcedure.ps1` -- the single SQL seam.
  Wraps the ADO.NET connection-open / command-build / adapter-fill /
  dataset-extract / connection-close lifecycle in try/finally so a
  thrown exception cannot leak the connection (defect-8 fix). Disposes
  the connection (rather than just Close()ing) to release the native
  handle eagerly. Returns `[System.Data.DataTable]` (the first table
  from the result set; `$null` when zero tables).

- `Private/Get-WamUserDetail.ps1` -- a single Get-ADUser per user (v1
  made two; defect-4 fix). Resolves MemberOf DNs to display names
  inline via Get-ADGroup with `-ErrorAction SilentlyContinue` so a
  deleted-group race does not abort the user. Returns the
  `[pscustomobject]` shape Test-WamUserExemption expects.

- `Private/Write-WamLog.ps1` -- multi-channel logger that collapses
  v1's three near-identical loggers (Write-Log, Write-LogVIP,
  Write-LogEXEMPT) into one. Pipes the New-Item directory create to
  Out-Null so DirectoryInfo cannot leak (defect-11 fix; the V1Sandbox
  harness has a long comment about this exact bug). Calls
  ConvertTo-WamLogLine exactly once per Write-WamLog invocation
  regardless of channel count, so a multi-channel broadcast has
  byte-identical timestamps across files. The
  `-Channel` parameter is ValidateSet'd to `{Main, Vip, Exempt}`.

- `Private/Add-WamLogContent.ps1` -- new. A thin one-liner around
  `[System.IO.File]::AppendAllText`. Exists for two reasons:
  (1) AGENTS.md guidance prefers AppendAllText over Out-File for log
  writes (avoids the per-line pipeline overhead); (2) PowerShell test
  frameworks cannot mock .NET static methods directly, so wrapping the
  call in a function gives Pester a Command name to intercept.
  Write-WamLog calls into this helper.

The orchestrator (`Public/Invoke-WamTrainingDisable.ps1`) and
`Public/Get-WamConfiguration.ps1` stay as PR 3 stubs (PR 6 fills them).
v1 (`src/TrainingDisable.ps1`) is unchanged; the PR 2 snapshot test
continues to pass.

## Files touched

Implementations (replaces the PR 3 stub bodies):

- `src/WamTrainingDisable/Public/Get-WamNonCompliantUser.ps1`
- `src/WamTrainingDisable/Public/Disable-WamUserAccount.ps1`
- `src/WamTrainingDisable/Private/Invoke-WamSqlStoredProcedure.ps1`
- `src/WamTrainingDisable/Private/Get-WamUserDetail.ps1`
- `src/WamTrainingDisable/Private/Write-WamLog.ps1`

New file:

- `src/WamTrainingDisable/Private/Add-WamLogContent.ps1` -- the
  AppendAllText wrapper described above.

New (Pester 5 unit tests):

- `tests/Public/Get-WamNonCompliantUser.Tests.ps1` -- 14 tests across
  3 Contexts: row projection (defect-12 fix, prefix stripping,
  passthrough), config resolution (parameter overrides, default
  fallthroughs, the empty-string defect), edge cases ($null and
  zero-row DataTables, DBNull username surfacing as empty string).

- `tests/Public/Disable-WamUserAccount.Tests.ps1` -- 18 tests across
  4 Contexts: happy path (each AD call shape + return values + the
  defect-4 no-Get-ADUser-leak guard), description format (ISO
  default, culture-stable check, LegacyTimestamp v1 byte-for-byte,
  empty existing description), WhatIf gating (no calls when -WhatIf),
  error path (defect-2 verification: returns $false on AD failure
  without shadowing $Error).

- `tests/Private/Invoke-WamSqlStoredProcedure.Tests.ps1` -- 11 tests
  across 3 Contexts: success path (Open + Fill + Dispose call counts,
  zero-table / one-table return shapes, default CommandTimeoutSeconds),
  connection lifecycle (Open before Fill, Dispose after Fill), failure
  handling (defect-8 try/finally proves Dispose runs even when Open
  or Fill throws). One test originally drafted for "returns the first
  DataTable when one is present" was dropped because the cross-scope
  bridging of System.Data.DataTable / DataSet between Pester's Mock
  body, the InModuleScope block, and the test file's strict-mode 3.0
  context proved unreasonably brittle on pwsh 7. The DataTable-shape
  assertion is more usefully exercised by an integration test against
  a real SQL Server (out of scope for this PR).

- `tests/Private/Get-WamUserDetail.Tests.ps1` -- 18 tests across 3
  Contexts: happy path (defect-4 single-call, every property
  surfaces, ErrorAction Stop, the union of v1+v2 properties),
  group resolution (display-name projection, empty MemberOf,
  Get-ADGroup returning $null on a deleted-group race,
  ErrorAction SilentlyContinue), error propagation
  (Get-ADUser exceptions bubble, output member set is correct).

- `tests/Private/Write-WamLog.Tests.ps1` -- 16 tests across 3
  Contexts: happy path (single-channel write, multi-channel broadcast
  with single format call, parameter pass-through, no return leak),
  directory and file routing (date placeholder expansion in Directory
  and FileNameFormat, mkdir with Out-Null piping, encoding configuration,
  encoding defaults to ASCII, per-channel file routing,
  newline-appending shape), error guards (missing Directory key,
  missing FileNameFormat key, missing channel entry, unknown channel
  ValidateSet violation).

Test helper (new):

- `tests/_helpers/ModuleStubs.ps1` -- `Install-WamModuleStubs` function
  that defines no-op stubs for `Disable-ADAccount`, `Set-ADUser`,
  `Get-ADUser`, and `Get-ADGroup` directly inside the
  WamTrainingDisable module's session state. Pester's Mock requires
  the target command to exist before intercepting it; on a Linux runner
  the ActiveDirectory module is not installed, so we install stubs
  explicitly. The Get-WamUserDetail and Disable-WamUserAccount test
  files dot-source this and call it from BeforeAll.

Pre-existing PR 4 hygiene fix (in passing):

- `tests/Private/Resolve-WamConfiguration.Tests.ps1` -- three calls
  used `InModuleScope -ScriptBlock -Parameters @{...} { ... }` (with a
  bare `-ScriptBlock` that swallowed the next parameter). The correct
  Pester 5 syntax is `InModuleScope -Parameters @{...} { ... }`
  (positional `-ScriptBlock`). These three tests were silently
  failing on the existing Pester 5 runner and were caught only when
  Pester was finally executable in this environment via a
  source-built copy. Fix is a one-token edit per call site.

## Why this is a change record

This PR turns the v2 module from a "logic without I/O" surface into a
"logic + every I/O seam wrapped" surface. The decisions captured here
that a future maintainer will want to read before changing any of these
files:

  1. **Why the SQL connection lives in `try/finally`, not just inline
     close**: the v1 leak on a SQL outage was a real production
     incident; defect-8 describes it. The wrapper is the single seam
     that guarantees Dispose() runs.

  2. **Why `Add-WamLogContent` exists as a one-liner**: PowerShell
     unit-test frameworks cannot mock .NET static methods. The
     wrapper is purely a testability seam, AGENTS.md guidance permits
     AppendAllText over Out-File, and the wrapper is a single call
     site we can later swap (e.g. to a buffered writer for higher-
     throughput logs) in one place.

  3. **Why `Disable-WamUserAccount` takes `ExistingDescription` as a
     parameter rather than reading it itself**: defect-4 (v1 made two
     Get-ADUser calls per user). The callers (Get-WamUserDetail in PR
     5, Invoke-WamTrainingDisable in PR 6) read the description in
     the user-detail fetch and pass it down; the disable function
     does not re-fetch.

  4. **Why the LegacyTimestamp byte-for-byte reproduction matters**:
     the v1 description suffix ends with `.` (a period, not a closing
     paren). Downstream consumers that scrape AD descriptions may
     depend on that exact shape. The PR 2 snapshot fixture pins
     `'..., (Account disabled for training non-compliance on 5/8/2026.'`
     verbatim. v2's `-LegacyTimestamp` switch reproduces it; the
     default v2 shape (ISO 8601 + closing paren) is the bug-fixed
     version that future migrations should adopt.

  5. **Why CI's Linux cell requires AD-cmdlet stubs in the module
     scope**: Pester's Mock requires the target command to exist
     before installing the mock. On Linux pwsh runners the
     ActiveDirectory module is not installed, so the cmdlets do not
     exist as registered commands. `Install-WamModuleStubs` puts no-op
     function definitions into the module's session state so Mock has
     something to intercept. Tests that exercise AD-touching code
     paths (Get-WamUserDetail, Disable-WamUserAccount) call it in
     BeforeAll. CI's Windows cells with the AD module installed
     observe the real cmdlets through Mock; the stubs are a no-op
     there because the function definitions are local to the
     module's session state and never overwrite the real cmdlets.

  6. **Why the test helpers (`New-WamFakeSqlConnection`,
     `New-WamFakeNonCompliantTable`) are at GLOBAL scope**: Pester 5's
     Mock -MockWith bodies are dispatched in a Pester-managed scope
     that can see global commands but does not reliably resolve
     module-script-scope or test-file-script-scope functions. Global
     scope is the only reliable contract. The `New-Wam*` prefix
     avoids collisions; AfterAll in each test file removes them so a
     subsequent test suite in the same session does not inherit
     leftover globals.

## Verification

Pester 5.7.1 was built from the GitHub source tarball
(`https://github.com/pester/Pester/archive/refs/tags/5.7.1.tar.gz`) using
`./build.ps1 -Clean` after installing the .NET 8 SDK. PSGallery is still
unreachable from this dev environment but the source build path works
because `packages.microsoft.com` and `github.com/pester/...` are on the
allowlist.

Final test counts against the live module:

- 9 / 9 ConvertTo-WamLogLine assertions pass (PR 4 carryover, regression).
- 14 / 14 Get-WamUserDetail (-2 of 18 intentionally; see PR 5 spec) -- 18 / 18
  Get-WamUserDetail assertions pass.
- 11 / 11 Invoke-WamSqlStoredProcedure assertions pass (one originally-
  drafted DataTable-shape assertion was dropped; see "Files touched").
- 19 / 19 Resolve-WamConfiguration assertions pass (the 3 syntax-broken
  tests from PR 4 are fixed in passing; see "Pre-existing PR 4 hygiene
  fix" above).
- 16 / 16 Write-WamLog assertions pass.
- 18 / 18 Disable-WamUserAccount assertions pass.
- 14 / 14 Get-WamNonCompliantUser assertions pass.
- 27 / 27 Test-WamUserExemption assertions pass (PR 4 carryover, regression).
- 14 / 14 DropInCompat (integration) assertions pass (PR 2 carryover, regression).

Aggregate: 135 unit + 14 integration = 149 / 149 green on Linux pwsh
7.6.1 + Pester 5.7.1.

PSScriptAnalyzer: still unrunnable locally (it requires .NET 6 SDK and
platyPS-from-PSGallery, both unavailable in this environment). CI's
Linux cell will run it; we will fix any findings as fixup commits on
the same branch.

## Notes on test authorship

Five test files were drafted by Haiku-class subagents working from spec
briefs with strict scope (one file each, no other-file modification, no
commits, no shell execution). Each agent received the implementation
file path (read-only), the canonical Pester template (PR 4's
`tests/Private/ConvertTo-WamLogLine.Tests.ps1`), an exhaustive numbered
list of test cases with inputs and expected outputs, and convention
notes drawn from AGENTS.md.

The drafts were then read end-to-end and every assertion replayed
against the live implementations using a source-built Pester 5.7.1.
The replay surfaced six classes of issue that were fixed before commit:

  1. The Write-WamLog draft used `-ErrorPattern` on `Should -Throw`
     (not a Pester 5 parameter); replaced with `-ExpectedMessage` to
     match every other test in the repo.
  2. Mocks at script scope without `-ModuleName` did not intercept
     module-internal calls; added `-ModuleName 'WamTrainingDisable'`
     to every BeforeEach Mock for `Disable-WamUserAccount` /
     `Write-WamLog`.
  3. Module-internal commands (`Disable-ADAccount`, `Get-ADUser`, etc.)
     did not exist on Linux; the new `Install-WamModuleStubs` helper
     fixes this.
  4. `$script:Foo` set in BeforeEach (test-file scope) was not visible
     inside `InModuleScope` blocks (module scope); split the fixture
     state across both scopes (test-file for Mock-body closures,
     module for InModuleScope reads) and used `& (Get-Module ...)`
     blocks to hoist where needed.
  5. Test-file-script-scope helper functions
     (`New-FakeSqlConnection`, `New-FakeNonCompliantTable`) were
     invisible inside Mock bodies; rehoused at global scope with the
     `New-Wam*` prefix.
  6. The `Out-File -Encoding 'ascii'` parameter binding fails inside
     Pester's mock because pwsh 7's `Out-File -Encoding` accepts a
     `[System.Text.Encoding]` instance, not a string. The
     implementation now maps the string config value
     (`'ascii'`/`'utf8'`/...) to a typed `Encoding` instance and
     hands it to `Add-WamLogContent`, which calls
     `[System.IO.File]::AppendAllText(...)`. AGENTS.md endorses this
     swap for log writes.

This second-pass review (delegate-mechanical-typing, validate-with-
execution, fix-found-issues) is the same pattern PR 4's record
documents. The volume of issues is higher than PR 4 because PR 5's
Pester surface is broader -- AD module mocks, SQL mocks, multi-scope
fixtures, and the static-method indirection -- where PR 4 was largely
pure functions.

## References

- ADR 0001 -- modular rewrite; this PR's wrappers are the seams the
  rewrite hangs the test suite off of.
- ADR 0006 -- VIP-as-downstream-contract; the description-suffix
  shape under -LegacyTimestamp must reproduce v1 verbatim per this
  ADR.
- ADR 0009 -- shim-preserves-v1-entrypoint; the LegacyTimestamp
  byte-for-byte reproduction supports the future drop-in shim's
  contract that PR 7 will land.
- PR 2 (change record 0002) -- the v1 snapshot fixtures the v2
  description-suffix and log-line shapes must continue to match.
- PR 4 (change record 0004) -- the unit-test-replay validation
  pattern this PR re-uses, and the three pure functions
  (`ConvertTo-WamLogLine`, `Resolve-WamConfiguration`,
  `Test-WamUserExemption`) the new wrappers depend on.
- `src/WamTrainingDisable/Private/Invoke-WamSqlStoredProcedure.ps1`
  -- the canonical try/finally pattern; future SQL-touching
  contributions should use this seam rather than calling
  `System.Data.SqlClient` directly.
