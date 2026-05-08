---
id: 0006
title: Treat the VIP log file as a downstream contract, not duplication
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [logging, contracts, vip]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0004-snapshot-driven-modernization.md
---

## Context

v1 produces three log files per run: a main log, an EXEMPT log of users
spared from disablement, and a VIP log of users in the VIP organizational
unit. A casual reading of v1 suggests the VIP log is a duplicate of part
of the main log -- a refactor candidate.

It is not. The VIP team at the maintainer's organization has its own
support team, its own SLAs, and its own reporting structure. They consume
`LockoutUsers_VIP_*.log` as a feed, parse it with whatever tooling they
have today, and act on it independently of the rest of the operations
team.

Two things were nevertheless wrong with v1's VIP handling:

1. v1 used the substring matcher `*VIP` (suffix) in one code path and
   `*OU=VIP*` (substring) in another. A user in `OU=VIP,OU=Exec,...`
   would match the second pattern but not the first, so routing to the
   VIP log was inconsistent depending on which code path triggered it.
2. The exempt-vs-VIP routing logic was scattered across the three log
   functions, each of which independently decided whether to write a
   given line.

## Decision

The VIP log is a first-class output channel, preserved exactly. v2 keeps
the file at the same path with the same line shape (the snapshot test
in PR 2 pins this).

The two real bugs are fixed:

1. **One DN match pattern, configured.** The exemption matrix uses
   `*OU=VIP*` everywhere. The pattern is exposed in the config schema as
   `Logging.Channels.VipDistinguishedNamePattern` so the maintainer can
   tune it without code changes if the OU layout shifts.
2. **Centralized channel routing.** The pure function
   `Test-WamUserExemption` returns a decision object that includes a
   `Channel[]` array naming which log files the user belongs in. The
   single multi-channel logger `Write-WamLog` consumes the array. There
   is now exactly one place that decides "VIP user goes to Main + VIP +
   Exempt" -- not three.

## Consequences

- The VIP team's tooling continues to work without any heads-up. We do
  not need to coordinate a release with them.
- The fix for the inconsistent matcher is a behavior change: a user in
  `OU=VIP,OU=Exec,...` now routes to VIP consistently. If that user was
  previously sometimes-routed-sometimes-not, the VIP team will see them
  more often. We flag this in the v2 changelog under "Behavior
  changes" so the VIP team can adjust their dashboards if needed.
- The pure-function design makes the routing testable. The exemption
  matrix is a Pester table with one row per branch in v1's if/elseif
  ladder; the snapshot test additionally guarantees the line shape.

## Alternatives considered

- **Treat the VIP log as a refactor candidate; collapse it into a
  filtered view of the main log.** Rejected -- this would break the VIP
  team's downstream tooling, which is not negotiable.
- **Keep v1's two-pattern matching as documented behavior.** Rejected --
  the maintainer characterized the pattern split as a defect, not an
  intentional design. Fixing it is the goal of v2.

## References

- `src/WamTrainingDisable/Public/Test-WamUserExemption.ps1` (PR 4)
- `src/WamTrainingDisable/Private/Write-WamLog.ps1` (PR 5)
- `tests/Integration/DropInCompat.Tests.ps1` (PR 2)
