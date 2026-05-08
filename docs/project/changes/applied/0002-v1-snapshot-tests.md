---
id: 0002
title: Lock v1 output behavior with a snapshot test and a deterministic harness
status: applied
category: change
created: 2026-05-08
updated: 2026-05-08
tags: [testing, drop-in, snapshot, fixtures, harness]
supersedes: []
superseded-by: []
related:
  - docs/project/changes/applied/0001-tooling-skeleton.md
  - docs/project/decisions/accepted/0004-snapshot-driven-modernization.md
  - docs/project/decisions/accepted/0006-vip-log-is-downstream-contract.md
  - docs/project/decisions/accepted/0008-pester5-and-script-analyzer-on-ci.md
  - docs/project/decisions/accepted/0009-shim-preserves-v1-entrypoint.md
---

## Summary

Stands up the snapshot-driven safety net mandated by ADR 0004. Adds the
v1 sandbox harness, the canned AD/SQL fixtures it runs against, the
golden expected/ files captured from the harness, the Pester 5
configuration shared by CI and local runs, and the integration test that
asserts v1's observable behavior is unchanged by future refactors.

The v1 script `src/TrainingDisable.ps1` is unmodified. The harness
sandboxes it: stubs for `Get-ADUser`, `Get-ADGroup`, `Disable-ADAccount`,
`Set-ADUser`, and `Write-Host` are defined in the harness's function
scope (so they shadow the AD module's cmdlets and work on Linux pwsh
where the AD module is not even installed); v1 is dot-sourced after
stripping its parse-time `Start-Main` invocation; path variables are
redirected to a sandbox working directory; v1's SQL stage is replaced
with a stub that writes a caller-supplied username list. v1's
`Start-Main` then runs end-to-end against fixtures that exercise each
branch in `WAM-ADSearch` (normal disable, already-disabled,
in-grace-period, REL exempt, SCO exempt, group exempt).

Two configurations are pinned: ReportOnly = $true (the file-shape
contract -- four log files with v1's timestamps and hostnames stripped)
and ReportOnly = $false (the AD-write contract -- the exact (Identity,
Description) pairs v1 would have sent to `Disable-ADAccount` and
`Set-ADUser`, including the v1 missing-paren typo and the
culture-dependent date format).

## Files touched

New:

- `tests/PesterConfiguration.psd1` -- Pester 5 configuration shared by
  CI and local runs.
- `tests/Integration/DropInCompat.Tests.ps1` -- the snapshot test, two
  Contexts (default + enforcement), 13 It blocks.
- `tests/Integration/_helpers/V1Sandbox.ps1` -- the sandbox harness.
  Exports `Invoke-V1InSandbox` and `ConvertTo-NormalizedV1LogLine`.
- `tests/fixtures/v1/_capture.ps1` -- developer-only bootstrap script
  that regenerates the expected/ fixtures when the inputs change.
  Documented in its own header comment; not run by CI.
- `tests/fixtures/v1/expected/lockout-list.txt`
- `tests/fixtures/v1/expected/main.normalized.log`
- `tests/fixtures/v1/expected/vip.normalized.log`
- `tests/fixtures/v1/expected/exempt.normalized.log`
- `tests/fixtures/v1/expected/ad-calls.default.json`
- `tests/fixtures/v1/expected/ad-calls.enforcement.json`

Removed:

- `tests/.gitkeep` -- replaced by the test-and-fixture tree above.

Deliberately NOT touched:

- `src/TrainingDisable.ps1` -- v1 is the contract; we work around its
  quirks rather than fixing them in place. v2 fixes them in
  `src/WamTrainingDisable/`.

## Why this is a change record

This change ships the regression net every subsequent v2 refactor will
lean on. A future maintainer doing repo archaeology after a snapshot
failure ("why is this exact log line pinned?") will want the artifact
that spells out:

- Which v1 quirks are intentionally locked (the missing-paren typo, the
  culture-dependent date format, the four-file output shape with the
  empty-body VIP log on a no-VIP-user run).
- Which v1 quirks are NOT covered by this snapshot and are pinned
  elsewhere (the SQL `Select-Object -Index 0` truncation defect lives in
  PR 5's `Get-WamNonCompliantUser` unit tests; the `$ADAccount`
  carry-over bug between iterations lives in PR 4's exemption-matrix
  tests).
- How to regenerate the fixtures intentionally when v2 deliberately
  changes an output (the `_capture.ps1` workflow, with eyeballing the
  diff before commit).

## Verification

Local checks performed (all on pwsh 7.6.1 on Ubuntu 24.04):

- `pwsh -NoProfile -File tests/fixtures/v1/_capture.ps1` writes the six
  expected/ files. Diffing two consecutive runs shows zero changes;
  the harness is deterministic.
- A simulation script (not committed; lived in the dev shell) runs
  `Invoke-V1InSandbox` for both ReportOnly modes against the same
  fixture, then performs the same line-normalization and JSON-equality
  comparisons the Pester test does, against the committed expected/
  files. All six comparisons pass:
    - lockout-list, main.log, vip.log, exempt.log
    - ad-calls.default, ad-calls.enforcement
- `Invoke-V1InSandbox` was driven with a single-user fixture in
  enforcement mode. The captured `Disable-ADAccount` call carries
  `Identity = 'alice.normal'`. The captured `Set-ADUser` call carries
  the description `"Software Engineer II, (Account disabled for
  training non-compliance on 5/8/2026."` -- the v1 missing-paren typo
  and the culture-dependent date format are both preserved.

Remote checks (deferred until pushed):

- The CI `analyze` job runs PSScriptAnalyzer with the repo settings
  against `./tests` recursively. Local PSScriptAnalyzer was
  unavailable (PSGallery is not on the dev environment's HTTP
  allowlist); CI on a GitHub-hosted runner is the first place the
  analyzer rules get exercised against this code. Any findings will be
  fixed in a follow-up commit on the same branch.
- The CI `test` matrix (Windows PS 5.1, Windows pwsh, Ubuntu pwsh) runs
  Pester against `tests/PesterConfiguration.psd1`. Local Pester was
  similarly unavailable.

## References

- ADR 0004 -- the snapshot-driven decision rule this change implements.
- ADR 0006 -- the VIP-as-downstream-contract rationale; the empty
  `vip.normalized.log` body is a deliberate part of the contract for the
  no-VIP-user fixture.
- ADR 0008 -- Pester 5 + PSScriptAnalyzer on CI; this change adds the
  first real Pester suite the matrix runs against.
- ADR 0009 -- the drop-in entrypoint preservation rationale; the test
  enforces this contract end-to-end.
- The harness header comment in
  `tests/Integration/_helpers/V1Sandbox.ps1` is the single most
  detailed write-up of the dynamic-scope, function-shadowing, and
  parse-time-side-effect-stripping techniques used here.
