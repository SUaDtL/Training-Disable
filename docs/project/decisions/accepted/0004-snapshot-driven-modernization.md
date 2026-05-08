---
id: 0004
title: Lock v1 output with a snapshot test before any v2 refactor
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [testing, drop-in, refactoring-strategy]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0006-vip-log-is-downstream-contract.md
  - docs/project/decisions/accepted/0009-shim-preserves-v1-entrypoint.md
---

## Context

The v1 script has many non-best-practice patterns: variable shadowing of
automatic variables, scope leaks across function boundaries, duplicate AD
calls, unapproved verbs, no parameter binding on internal helpers,
unconditional dot-sourcing-runs-the-program, and so on. The maintainer
acknowledged that the volume is high enough that asking "is this weird
thing intentional or just bad code?" on each occurrence would create
unsustainable friction.

We need a decision rule that lets us modernize aggressively without
breaking the production scheduled task that depends on v1's exact output.

## Decision

Before any refactor work begins, capture v1's *output* behavior as a
snapshot test (`tests/Integration/DropInCompat.Tests.ps1`). The test runs
v1 end-to-end with mocked AD and SQL, captures every file v1 writes, and
locks those files (paths, line shape, character-by-character content) as a
fixture under `tests/fixtures/`. The test then asserts byte-equality
through every subsequent refactor.

This converts the question "is this weird internal pattern intentional?"
into a much narrower question: "does removing this pattern change any
file v1 writes?" If the snapshot still passes, the change is safe. If the
snapshot fails, the diff itself is the conversation surface for asking
the maintainer whether the output change is acceptable.

The decision rule is:

- **Internal weirdness** (variable shadowing, scope leaks, duplicate
  `Get-ADUser` calls, unapproved verbs, `Out-File`-as-IPC, ...) -- modernize
  silently as long as the snapshot still passes.
- **Output-observable weirdness** (timestamp format, file paths, log line
  shape, description suffix on the AD record, channel routing of which
  user goes to which log file) -- the snapshot diff is the surface; ask
  the maintainer whether the diff is acceptable before merging the change.

## Consequences

- The snapshot test must be the FIRST PR after the tooling skeleton (PR 2).
  Subsequent PRs cannot start landing real v2 code until the safety net
  exists.
- Any deliberate output change requires updating the fixture in the same
  PR as the change, with a short note in the PR description explaining
  why. Reviewers are trained to look for fixture changes specifically.
- The fixture is captured with mocked AD and SQL, so it is reproducible on
  CI runners (Linux pwsh works fine because the AD/SQL mocks are
  PowerShell stubs, not real services). It is not a test against a real
  domain.
- Some v1 output is culture-dependent (timestamp format uses
  `(Get-Date).ToShortDateString()` which renders differently in different
  locales). The fixture is captured under a fixed culture
  (`en-US`) and the snapshot test sets `[CultureInfo]::CurrentCulture =
  'en-US'` on entry to keep the assertion stable.
- v2 fixes the culture-dependent behavior in its default code path but
  ships an opt-in `Logging.LegacyTimestamp` switch that reproduces v1's
  shape exactly. The snapshot test exercises both paths: default v1 (with
  mocked culture) AND v2 with `LegacyTimestamp = $true`. Both must match
  the fixture for the same input.

## Alternatives considered

- **Refactor without a safety net, rely on code review and manual
  testing.** Rejected because the maintainer is the only reviewer and is
  honest about being rusty in PowerShell. Manual testing against a real
  AD/SQL is not available.
- **Write unit tests for v1 first, then refactor.** Rejected because v1
  has no testable seams -- the whole script is one untestable unit. The
  smallest test we can write against v1 *is* a snapshot test.
- **Big-bang rewrite, keep v1 in a separate branch as the source of
  truth.** Rejected because the moment v2 lands and the schedule task
  starts running it, v1 is no longer the source of truth. We need a
  forcing function that holds during the cutover, not before it.

## References

- `tests/Integration/DropInCompat.Tests.ps1` (created in PR 2)
- `tests/fixtures/` (the captured v1 output)
- `src/TrainingDisable.ps1` (current v1; replaced by the shim in PR 7)
