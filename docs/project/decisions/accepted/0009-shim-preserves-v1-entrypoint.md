---
id: 0009
title: Keep src/TrainingDisable.ps1 as a thin compatibility shim
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [drop-in, compatibility, deployment]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0001-modular-rewrite.md
  - docs/project/decisions/accepted/0004-snapshot-driven-modernization.md
---

## Context

The production scheduled task at the maintainer's organization is
configured as:

```
pwsh -File C:\Path\To\src\TrainingDisable.ps1
```

That command line is hard-coded in the scheduled task definition. We
cannot change it without coordinating a deployment with the ops team --
which is exactly the kind of friction that kills modernization
projects.

Decision 0001 moves the real code into a module under
`src/WamTrainingDisable/`. The original path needs to keep working.

## Decision

`src/TrainingDisable.ps1` becomes a ~30-line compatibility shim. It:

1. Imports the v2 module from a path relative to itself.
2. Preserves the v1 top-of-file configuration variables (`$ReportOnly`,
   `$GracePeriod`, `$VIP`, `$REL`, `$SCO`, `$Exempt`, `$LogFileBasePath`)
   so any in-place edits the maintainer applied to v1 port forward
   without needing a config file change.
3. Translates the v1 knobs into the v2 cmdlet's parameters via
   parameter splatting.
4. Translates `$ReportOnly = $TRUE` into `-WhatIf`, the native PowerShell
   idiom.
5. Calls `Invoke-WamTrainingDisable @splat`.

The shim is the **only** file in `src/` outside the module directory.

## Consequences

- Production deployment is a `git pull`. No scheduled-task changes, no
  ops ticket, no coordination call.
- The shim's existence is documented inline in the file with a long
  comment explaining why we keep it and what its contract is.
- The shim is exercised by the snapshot test (decision 0004), so a
  refactor that breaks the shim trips PR 2's safety net before merge.
- A consumer who wants the new cmdlet directly can ignore the shim and
  `Import-Module src/WamTrainingDisable/...; Invoke-WamTrainingDisable`.
- We accept the small ongoing maintenance cost of two entrypoints
  (the shim and the cmdlet) because the alternative -- breaking the prod
  task -- is unacceptable.

## Alternatives considered

- **Replace `src/TrainingDisable.ps1` with a hard-error message
  pointing at the new path.** Would break the prod scheduled task
  immediately. Out.
- **Auto-redirect the scheduled task to the new path during deployment
  via an installer script.** Adds an installer to a project that
  doesn't have one. Disproportionate.
- **Ship the v2 module as a sibling and leave v1 untouched until
  ops can cut over manually.** Doubles the maintenance surface (two
  copies of the logic). Rejected -- the snapshot test gives us
  confidence to retire v1 immediately.

## References

- `src/TrainingDisable.ps1` (rewritten in PR 7)
- `src/WamTrainingDisable/Public/Invoke-WamTrainingDisable.ps1` (PR 6)
- `tests/Integration/DropInCompat.Tests.ps1` (PR 2)
