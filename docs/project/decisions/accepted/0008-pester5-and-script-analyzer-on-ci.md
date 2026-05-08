---
id: 0008
title: Use Pester 5 for tests and PSScriptAnalyzer for lint, both on CI
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [testing, lint, ci]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0001-modular-rewrite.md
  - docs/project/decisions/accepted/0005-verbose-code-no-aliases.md
---

## Context

v1 has no automated testing or lint. The rebuild needs both, partly because
the maintainer wants the safety net for refactoring, and partly because
"this is what professional PowerShell looks like" is part of the learning
artifact value.

The PowerShell ecosystem has effectively standardized on two tools: Pester
for tests (5.x is the current major version) and PSScriptAnalyzer for
lint. Both are MIT-licensed, both are maintained by the PowerShell team,
both run on Windows PowerShell 5.1 and PowerShell 7+.

## Decision

- **Pester 5** for all tests. Minimum version 5.5 because that is where
  `Describe -ForEach` became stable; we lean on it heavily for the
  exemption-matrix table.
- **PSScriptAnalyzer** for lint. Configured via
  `PSScriptAnalyzerSettings.psd1` at the repo root.
- Both run in `.github/workflows/ci.yml` on every push and pull request.
- Test matrix: `(windows-latest x powershell)`, `(windows-latest x pwsh)`,
  `(ubuntu-latest x pwsh)`. The first cell is the prod-parity cell that
  must be green for an ops sign-off. The other two cells widen the
  compatibility net.

The free GitHub plan gives unlimited Actions minutes on public repositories
including Windows runners. We use that allowance instead of constraining
ourselves to Linux-only CI.

## Consequences

- Every push gets immediate feedback on lint and tests across three
  runtimes. Drift between Windows PowerShell 5.1 and pwsh 7 is caught at
  PR time, not on Monday morning when ops re-runs the script.
- The minimum versions are pinned in the workflow's `Install-Module
  -MinimumVersion` calls, so a Pester or PSScriptAnalyzer breaking change
  cannot silently land on us.
- The config files (`PSScriptAnalyzerSettings.psd1`,
  `tests/PesterConfiguration.psd1`) are also picked up by editor tooling
  (VS Code's PowerShell extension), so local feedback matches CI.
- We chose not to add a separate code-coverage gate at PR-1 time because
  there is no code yet. The Pester configuration sets a coverage
  threshold of 80% on `src/WamTrainingDisable/**/*.ps1` and that gate
  becomes meaningful starting at PR 4 (when the first real cmdlet
  arrives).

## Alternatives considered

- **Pester 4.x.** Older but stabler API; some community blog posts still
  reference it. Rejected because Pester 5 is the actively-developed
  version and the `-ForEach` table-driven syntax we plan to lean on does
  not exist in 4.
- **A custom lint script using `Get-Verb` and pattern matching.**
  Rejected -- PSScriptAnalyzer already does what we need plus a hundred
  other things, and writing our own is a maintenance burden for no win.
- **Skip Windows CI to save runner minutes.** Rejected because the prod
  runtime is Windows PowerShell 5.1. Linux-only CI would test a runtime
  the script never sees in production.
- **Add a separate "smoke" job that imports the module on a real Windows
  domain controller.** Out of scope for free CI -- no domain controller
  available on a GitHub runner. See gap 0002.

## References

- `.github/workflows/ci.yml`
- `PSScriptAnalyzerSettings.psd1`
- `tests/PesterConfiguration.psd1` (created in PR 2)
- Pester 5 docs: <https://pester.dev/>
- PSScriptAnalyzer:
  <https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview>
