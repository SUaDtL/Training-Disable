---
id: 0001
title: Establish tooling and project artifact archive skeleton
status: applied
category: change
created: 2026-05-08
updated: 2026-05-08
tags: [tooling, ci, lint, archive]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0001-modular-rewrite.md
  - docs/project/decisions/accepted/0003-no-vendor-references-in-repo.md
  - docs/project/decisions/accepted/0005-verbose-code-no-aliases.md
  - docs/project/decisions/accepted/0008-pester5-and-script-analyzer-on-ci.md
---

## Summary

Initial scaffolding for the v2 modernization. Adds repo-level tooling
(.gitignore, .editorconfig, PSScriptAnalyzer settings), the GitHub
Actions CI workflow with a three-cell test matrix and a vendor-reference
gate, the project artifact archive layout under `docs/project/`, and a
set of seeded Architectural Decision Records and known-gap entries
that document the choices already made on this branch.

No production-code behavior changes. The v1 script `src/TrainingDisable.ps1`
is unmodified.

## Files touched

- New: `.gitignore`, `.editorconfig`, `PSScriptAnalyzerSettings.psd1`
- New: `AGENTS.md` (replaces the prior vendor-named instruction file)
- Removed: the prior vendor-named instruction file (renamed to
  `AGENTS.md`)
- New: `.github/workflows/ci.yml`
- New: `.github/dependabot.yml`
- New: `.github/pull_request_template.md`
- New: `.github/ISSUE_TEMPLATE/bug_report.md`
- New: `.github/ISSUE_TEMPLATE/feature_request.md`
- New: full `docs/project/` tree:
  - `docs/project/README.md`
  - `docs/project/decisions/_template.md` and 10 seeded ADRs in
    `accepted/`
  - `docs/project/gaps/_template.md` and 3 seeded gap records in
    `open/`
  - `docs/project/discrepancies/_template.md`
  - `docs/project/security/_template.md`
  - `docs/project/changes/_template.md` and this record
  - empty status subfolders preserved with `.gitkeep`
- New: empty `tests/` directory with `.gitkeep`

## Why this is a change record

This change does not ship product behavior, but it ships a substantial
amount of *policy*: how the project will be linted, what status flow
artifacts move through, what CI gates exist, the no-vendor-reference
rule. A future maintainer should be able to see at a glance "when did
the lint config arrive?" without having to git-blame every file.

## Verification

Local checks performed:

- All decision and gap files have well-formed YAML frontmatter and the
  conventional section headings.
- The workflow file's vendor-reference gate excludes itself and
  fixtures from the scan, so the workflow can mention the prohibited
  patterns in fragments without failing.
- `git ls-files | xargs -d '\n' grep -PIn '(?i)cl..ude|anth..pic'`
  returns hits ONLY in `.github/workflows/ci.yml` (regex fragments) --
  which is the expected exclusion.

Remote checks (deferred until pushed):

- The CI workflow's `analyze`, `test`, and `manifest` jobs are all
  no-ops at this PR because no PowerShell sources exist under the
  scanned paths yet. They should pass with "no files / no tests"
  messages.

## References

- ADR 0001 (modular rewrite) -- the strategic context
- ADR 0003 (no vendor references) -- the policy this change enforces
- ADR 0005 (verbose code, no aliases) -- the lint config encodes this
- ADR 0008 (Pester 5 + PSScriptAnalyzer on CI) -- this PR sets up both
