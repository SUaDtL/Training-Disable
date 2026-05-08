---
id: 0002
title: No end-to-end test against a real Active Directory
status: open
category: gap
created: 2026-05-08
updated: 2026-05-08
tags: [active-directory, testing, environment]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0002-adsisearcher-over-get-aduser.md
  - docs/project/gaps/open/0001-prod-sql-connection-string-untested-locally.md
---

## Context

The module's AD interactions go through two seams:

- `Private/Get-WamUserDetail.ps1` -- bulk reads via `[adsisearcher]`.
- `Public/Disable-WamUserAccount.ps1` -- writes via `Disable-ADAccount`
  and `Set-ADUser`.

Both are fully mocked in CI: tests inject stub functions before module
import and assert on the call shape. This catches regressions in our
own code, but it does not catch the class of bugs where:

- A real domain returns `MemberOf` in a different DN canonicalization
  than the mock expects.
- A real `Disable-ADAccount` succeeds locally but fails to replicate to
  another DC for several minutes.
- The `[adsisearcher]` `MaxValRange` chunking ceiling differs from the
  default 1500 in some forest configurations.
- The `whenCreated` attribute returns as a date type that surprises
  `[datetime]::Parse` on a non-default culture.

Free GitHub runners do not provide a real domain controller, so we
have no automated way to exercise these paths.

## Impact

Medium. The mocks have been written to match documented AD behavior,
but documented and observed are not always the same thing. The most
likely failure mode is: a refactor lands, CI is green, the prod
scheduled task runs, and a user that should have been exempted gets
disabled because of a DN canonicalization mismatch we did not
anticipate.

## Plan (or lack thereof)

Plan: when the maintainer next has access to a non-prod test domain at
their organization, capture a small fixture (`tests/fixtures/ad/`) of
real `[adsisearcher]` output and replay it through a custom mock that
returns the captured records. This narrows the gap without requiring a
domain in CI.

Longer term, evaluate Microsoft's `Selenium for AD` style approach
(running a containerized AD LDS in a Docker container and pointing the
test at it). Out of scope for v2.

## Workaround

The maintainer should run `pwsh -File src/TrainingDisable.ps1 -WhatIf`
manually against the non-prod test domain at least once after every
non-trivial PR before flipping the production task. The
`tests/Integration/DropInCompat.Tests.ps1` snapshot, while it does not
exercise real AD, does at least guarantee that the v2 code path
produces v1-equivalent output for the inputs the snapshot covers --
which is a useful hedge against silent behavior drift.

## References

- `src/WamTrainingDisable/Private/Get-WamUserDetail.ps1` (PR 5)
- `src/WamTrainingDisable/Public/Disable-WamUserAccount.ps1` (PR 5)
