---
id: 0005
title: Verbose code, no aliases, type accelerators where they win on perf
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [coding-style, lint, learning-artifact]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0002-adsisearcher-over-get-aduser.md
  - docs/project/decisions/accepted/0008-pester5-and-script-analyzer-on-ci.md
---

## Context

The maintainer has explicitly framed this rebuild as a personal learning
artifact. They have looked at the v1 source and observed that the syntax is
not self-documenting in any meaningful sense -- the production code in
their environment was written under deadline, by a then-junior engineer,
without code review. Reading it now is harder than it should be.

For the rebuild, they want code that a future reader (likely themselves,
months from now, rusty in PowerShell) can pick up and understand without
running the script. That goal sits orthogonal to "minimal, terse code"
which is the more common style guide goal.

## Decision

Three binding rules apply to every committed source file:

1. **Verbose, conversational comments.** Every non-trivial code block has
   a multi-line comment that explains *why*. The comment anticipates the
   reader's question, calls out trade-offs, and names failure modes the
   code is guarding against. Comments are first-class code, not
   afterthoughts. Public cmdlets additionally have full PowerShell
   comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.EXAMPLE`
   x >=3/`.NOTES`/`.LINK`).
2. **No aliases.** `gci`, `?`, `%`, `where`, `select`, `ft`, `gm`, `iex`,
   `cd`, `ls`, `cat`, etc. are banned. Use `Get-ChildItem`, `Where-Object`,
   `ForEach-Object`, `Format-Table`, etc. The PSScriptAnalyzer rule
   `PSAvoidUsingCmdletAliases` enforces this at CI time at Error severity.
3. **Named parameters only, no positional.** `Get-Content -Path $foo`,
   never `Get-Content $foo`. Lint enforces it via
   `PSAvoidUsingPositionalParameters` at Error severity.

A complementary rule: where a type accelerator gives a measurable
performance win over the equivalent cmdlet, use the accelerator and
**explain inline why** in a multi-line comment that calls out the
trade-off. Examples:

- `[adsisearcher]` over `Get-ADUser` for bulk reads (decision 0002)
- `[System.IO.File]::AppendAllText` over `Out-File -Append` for log writes
- `[System.IO.Path]::Combine` over `Join-Path` inside hot loops
- `[datetime]::UtcNow` over `Get-Date` when ordering or formatting
  invariantly

The accelerator swap is justified per-call site, not per-style-guide-rule.
A reader should never have to wonder why we suddenly broke into .NET
syntax in the middle of a PowerShell script.

## Consequences

- Source files are larger than they would be with idiomatic PowerShell
  shorthand. The maintainer accepts this trade explicitly.
- New contributors face a steeper "first PR" cost because they have to
  learn the convention. CI catches violations mechanically so the cost
  is bounded.
- Code review can focus on logic instead of style nitpicks because lint
  has already caught style issues before review.
- Some PSScriptAnalyzer rules issue diagnostics that look noisy to
  developers used to terser PowerShell (e.g. flagging `?`-as-Where-Object
  in a one-liner). We accept the noise as the price of consistency.

## Alternatives considered

- **Use the PowerShell-team in-box style guide as written.** The in-box
  style is fine but does not specifically mandate verbose comments. We
  needed the verbose-comment requirement to be a binding rule, not a
  suggestion, so we layered our own rules on top of the in-box style.
- **Allow aliases in REPL-like one-liners (e.g. `examples/` scripts) but
  not in module code.** Rejected as too much surface for a small
  repository. One rule applies everywhere; less mental overhead.
- **Optimize for terseness; rely on documentation in `docs/` to teach.**
  Rejected because the maintainer specifically said the syntax is not
  self-documenting and they do not want to maintain a parallel doc tree
  that drifts from the code.

## References

- `PSScriptAnalyzerSettings.psd1` -- the lint rules
- `AGENTS.md` -- the contributor-facing version of these rules
