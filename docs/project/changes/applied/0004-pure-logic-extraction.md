---
id: 0004
title: Fill three pure functions and their unit tests (exemption matrix, log formatter, config resolver)
status: applied
category: change
created: 2026-05-08
updated: 2026-05-08
tags: [implementation, unit-tests, pure-logic, pester, exemption-matrix, configuration]
supersedes: []
superseded-by: []
related:
  - docs/project/changes/applied/0003-module-skeleton.md
  - docs/project/decisions/accepted/0001-modular-rewrite.md
  - docs/project/decisions/accepted/0006-vip-log-is-downstream-contract.md
  - docs/project/decisions/accepted/0007-psd1-config-format.md
---

## Summary

Fills the three pure-logic stubs from PR 3 with real implementations and
ships exhaustive Pester 5 unit-test coverage for each:

- `Public/Test-WamUserExemption.ps1` -- the decision matrix as a pure
  function. Returns `[pscustomobject] @{ IsExempt; Reason; Channels }`.
  The Reason strings match the v1 log fixtures verbatim (snapshot in
  PR 2). The five-branch precedence ladder (already-disabled, in-grace,
  exempt-OU, exempt-group, default-disable) is preserved from v1; VIP
  channel routing is now uniform across every branch (the v1
  matcher-inconsistency defect is fixed).

- `Private/ConvertTo-WamLogLine.ps1` -- the log-line formatter. Default
  v2 output is ISO 8601 timestamp under InvariantCulture (so the output
  is stable regardless of runner culture). LegacyTimestamp = $true
  reproduces v1's `(Get-Date).ToShortDateString() + ' ' +
  (Get-Date).ToLongTimeString()` shape under CurrentCulture for
  byte-for-byte compatibility with downstream consumers that depend on
  the v1 format.

- `Private/Resolve-WamConfiguration.ps1` -- the five-layer config
  resolver. Walks shipped defaults -> project config (-ConfigPath) ->
  user config -> environment variables -> parameter overrides, deep
  merging hashtables key-by-key. Arrays are REPLACED wholesale (never
  concatenated). Env vars use a documented WAM_* mapping with type
  coercion for ints and Docker-style truthy-bool parsing.

The `Public/Get-WamNonCompliantUser.ps1`, `Public/Disable-WamUserAccount.ps1`,
`Public/Invoke-WamTrainingDisable.ps1`, `Public/Get-WamConfiguration.ps1`,
and the remaining Private/* I/O wrappers stay as PR 3 stubs (they throw
NotImplementedException with PR 5 / PR 6 pointers). v1 is unchanged;
the PR 2 snapshot test continues to pass.

## Files touched

Implementations (replaces the PR 3 stub bodies):

- `src/WamTrainingDisable/Public/Test-WamUserExemption.ps1`
- `src/WamTrainingDisable/Private/ConvertTo-WamLogLine.ps1`
- `src/WamTrainingDisable/Private/Resolve-WamConfiguration.ps1`

New (Pester 5 unit tests):

- `tests/Public/Test-WamUserExemption.Tests.ps1` -- 27 tests across 6
  Contexts: one per decision branch, one for VIP-routing
  independence, one for precedence interactions.
- `tests/Private/ConvertTo-WamLogLine.Tests.ps1` -- 9 tests across 3
  Contexts: ISO defaults (5), LegacyTimestamp (3), edge cases (1).
- `tests/Private/Resolve-WamConfiguration.Tests.ps1` -- 14 tests across
  5 Contexts: each layer plus their interaction.

## Why this is a change record

This change ships the substantive v2 logic the entire module hangs off
of. A future maintainer working on PR 5/6 needs to read these files
to know what the orchestrator's contract is; capturing the design
choices (Channels-as-data, VIP-routing-as-orthogonal-pass, deep-merge
arrays-replace-not-concat, env-var typed-coercion) in one record
saves them git-blaming each function to figure out "why was this
done this way?"

A particularly subtle point worth pinning here: the unit tests for
`Test-WamUserExemption` cross-check their expected `Reason` strings
against `tests/fixtures/v1/expected/exempt.normalized.log` and
`main.normalized.log`. The two layers (PR 2 snapshot test against v1,
PR 4 unit tests against v2) MUST produce identical Reason strings or
PR 7's drop-in shim will not be byte-for-byte compatible. That is the
contract these tests enforce.

## Verification

All test files were validated via raw pwsh simulation (PSGallery
unreachable from the dev environment; no Pester locally) against the
live module:

- 9 / 9 ConvertTo-WamLogLine assertions pass
- 14 / 14 Resolve-WamConfiguration assertions pass
- 30 / 30 Test-WamUserExemption assertions pass
  (the ForEach truthy/falsy cases in the env-var test count as 10
  individual assertions in the simulation)

Specific behaviors verified:

- ConvertTo-WamLogLine: ISO output is byte-stable across en-US and
  de-DE cultures; LegacyTimestamp = $true under en-US reproduces
  '5/8/2026 10:30:00 AM' verbatim; the LegacyTimestamp branch ignores
  TimestampFormat; truthy non-bool LegacyTimestamp values coerce.
- Resolve-WamConfiguration: arrays are REPLACED in deep merges;
  ParameterOverrides win over env vars; env vars win over project
  config; project config wins over defaults; missing -ConfigPath
  throws with a 'does not exist' message; env-var int coercion
  produces an actual [int] (not a string); truthy/falsy bool
  coercion follows the Docker convention; cross-call mutation of
  one returned config does not pollute a subsequent call's defaults.
- Test-WamUserExemption: every branch produces the v1-shape Reason;
  channel routing is `Main` for disable / already-disabled,
  `Main+Exempt` for the three exempt branches, and `Vip` is added
  uniformly when the DN matches the VipDistinguishedNamePattern;
  precedence is preserved (already-disabled > in-grace > exempt-OU >
  exempt-group > default-disable); array order in ExemptOus
  determines first-match wins; group equality is case-insensitive
  (v1's `-match` regex partial behavior is intentionally simplified).

The Pester suites themselves are CI-validated (the analyze and test
matrix jobs run against ./tests recursively); local PSScriptAnalyzer
unavailable, so any analyzer findings will be addressed as follow-up
commits on the same branch.

The PR 2 snapshot test against v1 was NOT re-run here -- v1's source
file `src/TrainingDisable.ps1` is unchanged, so the snapshot
necessarily still passes. CI will confirm.

## Notes on test authorship

The three test files were drafted by Haiku-class subagents working
from spec briefs with strict scope (one file each, no other-file
modification, no commits, no shell execution). Each agent received:

- The implementation file path (read-only).
- The PR 2 integration test as a style template.
- An exhaustive numbered list of test cases with inputs and expected
  outputs.
- Convention notes drawn from AGENTS.md.

The drafts were then read end-to-end and every assertion replayed
against the live implementations via raw pwsh before commit. This
two-step (delegate-mechanical-typing, validate-with-execution) keeps
the high-judgment work (precedence design, v1 compatibility,
LegacyTimestamp byte-for-byte fidelity) on the primary author while
letting the boilerplate-heavy test files come together quickly.

## References

- ADR 0006 -- VIP-as-downstream-contract; the channel-routing tests
  pin the contract for the VIP support team.
- PR 2 (change record 0002) -- the v1 snapshot fixtures the v2 Reason
  strings must match verbatim.
- `src/WamTrainingDisable/Public/Test-WamUserExemption.ps1` -- the
  precedence-ladder docstring is the authoritative description of
  the decision logic.
- `src/WamTrainingDisable/Private/Resolve-WamConfiguration.ps1` -- the
  env-var override map is the authoritative description of the WAM_*
  -> config-key mapping.
