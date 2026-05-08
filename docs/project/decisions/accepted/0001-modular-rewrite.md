---
id: 0001
title: Rewrite the single-file script as a PowerShell module
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [architecture, module, public-private-split]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0008-pester5-and-script-analyzer-on-ci.md
  - docs/project/decisions/accepted/0009-shim-preserves-v1-entrypoint.md
---

## Context

`src/TrainingDisable.ps1` is a 373-line monolithic script. Every concern --
SQL access, Active Directory queries, exemption logic, logging, the
production-vs-report-only switch -- is mixed into one file with `Start-Main`
at the bottom that runs at parse time. There is no test harness, no lint, no
way to exercise the exemption logic in isolation.

The maintainer wants to use the rewrite as a personal learning artifact for
idiomatic modern PowerShell. The single-file structure is fine for a quick
operational tool but actively counterproductive as a teaching artifact: a
reader cannot easily see "this is the unit of testable logic" because the
whole script is one unit.

## Decision

Convert the codebase into a proper PowerShell module rooted at
`src/WamTrainingDisable/`, using the same Public/Private folder layout used
by Pester, PSScriptAnalyzer, and PSReadLine. The structure is:

- `WamTrainingDisable.psd1` -- module manifest, lists exported functions
  explicitly.
- `WamTrainingDisable.psm1` -- root module, dot-sources `Public/*.ps1` and
  `Private/*.ps1` and re-exports the public set.
- `Public/*.ps1` -- one file per exported cmdlet.
- `Private/*.ps1` -- one file per internal helper.
- `WamTrainingDisable.config.psd1` -- shipped default configuration.
- `en-US/about_WamTrainingDisable.help.txt` -- conceptual help topic.

Each .ps1 file is dedicated to a single cmdlet/function and includes
comment-based help on Public functions.

## Consequences

- Each function becomes individually testable. Mocking AD/SQL at a single
  thin Private wrapper enables the whole exemption matrix to run on Linux
  pwsh in CI without a real domain.
- The module is loadable in isolation: `Import-Module ./src/WamTrainingDisable`
  brings the cmdlets into scope. The drop-in shim (decision 0009) is what
  preserves the original `pwsh -File ...` entrypoint.
- `Test-ModuleManifest` becomes a useful smoke check.
- Added complexity: more files to navigate, a manifest to maintain. The
  trade-off is that "single file" stops being a constraint we have to work
  around for testing.

## Alternatives considered

- **Keep the single-file structure, add tests at a higher level.** Rejected
  because the pure-vs-impure separation needed for unit tests is exactly
  the separation a module structure forces. Doing it without the module
  layout is doing the same work without the discoverability win.
- **Split into multiple .ps1 scripts that each stand alone.** Rejected
  because PowerShell's idiomatic packaging unit is the module, not a
  collection of scripts. Tooling (Get-Help, Test-ModuleManifest, the
  Modules folder convention) all assumes the module form.

## References

- `src/WamTrainingDisable/WamTrainingDisable.psd1` (created in PR 3)
- `src/TrainingDisable.ps1` (the v1 monolith we are replacing)
- PowerShell-team module layout reference:
  <https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-script-module>
