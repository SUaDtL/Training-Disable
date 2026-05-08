# AGENTS.md

This file provides guidance to AI coding assistants and human contributors
working in this repository. It documents the codebase layout, the conventions
the maintainer cares about, and the project-artifact archive system.

> **A note for assistants:** the conventions below are not suggestions. They
> are the working agreement for any change that lands on this branch. If a
> rule conflicts with your default behavior, follow the rule.

## Repository overview

Single-file PowerShell automation (`src/TrainingDisable.ps1`) that disables
Active Directory user accounts for users delinquent on "What About Me" (WAM)
training. The script is environment-specific: it was written for the author's
organization and is published as a reference implementation, not as a generic
tool. Per `README.md`, requested changes for other environments are out of
scope -- fork and modify locally.

The repository is in the middle of a v2 modernization. The single .ps1 file
is being converted into a proper PowerShell module (`src/WamTrainingDisable/`)
with tests, lint, and CI. The original entrypoint
(`pwsh -File src/TrainingDisable.ps1`) is preserved as a thin compatibility
shim so the production scheduled task is not affected.

## Running the script

PowerShell only (uses `System.Data.SqlClient` and the `ActiveDirectory`
module). The drop-in entrypoint:

```powershell
# Execute end-to-end (logs only when -WhatIf is supplied)
pwsh -File src/TrainingDisable.ps1
```

Once v2 lands, the same workflow is also available as a cmdlet:

```powershell
Import-Module ./src/WamTrainingDisable/WamTrainingDisable.psd1
Invoke-WamTrainingDisable -WhatIf
```

## Coding conventions (binding)

These apply to every file that goes into a commit on this repo.

### Verbose, conversational comments

Comments are first-class. Default is "explain WHY in a multi-line block." A
contributor reading the code six months from now (or the maintainer, who is
honest about being rusty in PowerShell) is the audience.

- State *why* the code does what it does, not what (the cmdlet name says
  what).
- Anticipate the reader's question. ("If you're wondering why we're not using
  `Get-ADUser` here, see the comment two functions up.")
- Call out trade-offs explicitly. ("This is faster but loses the strongly-typed
  return objects; we cast manually below.")
- Name the failure mode the code is guarding against. ("This try/finally exists
  because a thrown exception would otherwise leak the connection until GC kicks
  in, which on a long-running scheduled task is hours.")
- Read like a senior engineer pairing with a junior. Sentences, not
  stenography.

Every Public cmdlet ALSO has full PowerShell comment-based help (`.SYNOPSIS`,
`.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` x >=3, `.NOTES`, `.LINK`). The two
layers are not duplicates: comment-based help is the API surface for users
running `Get-Help`; inline comments are the code-review surface for the
maintainer.

### No aliases

Banned: `gci`, `gi`, `gc`, `sc`, `sls`, `?`, `%`, `where`, `select`, `ft`,
`fl`, `gm`, `iex`, `iwr`, `curl`, `wget`, `cd`, `pwd`, `ls`, `cat`, `echo`,
`cls`, `dir`, `mv`, `cp`, `rm`, `del`, `type`, and the rest of the alias
table. Use the full cmdlet name everywhere. The lint rule
`PSAvoidUsingCmdletAliases` enforces this at CI time.

### Named parameters only

`Get-Content -Path $foo`, never `Get-Content $foo`. Lint
(`PSAvoidUsingPositionalParameters`) enforces it.

### Approved verb-noun naming

`Get-Verb` lists the allowed set. No `WAM-*` style. Module prefix `Wam` on
every noun (`Get-WamNonCompliantUser`, `Test-WamUserExemption`, etc.).

### Strict mode

Every `.psm1` declares `Set-StrictMode -Version 3.0` and
`$ErrorActionPreference = 'Stop'`. Null comparisons go reference-first:
`$null -eq $value`, never `$value -eq $null`.

### Type accelerators where they win on perf

Use them, but justify each swap inline in the code. Specific guidance:

- `[adsisearcher]` for bulk AD reads (one chunked LDAP query vs N round-trips
  through ADWS via `Get-ADUser`). The wrapper function's comment explains
  the LDAP filter we build, the `PropertiesToLoad` set, and the
  `ResultPropertyValueCollection` casting foot-gun (indexing a one-element
  collection returns the element; indexing a zero-element collection returns
  `$null` -- guard explicitly).
- `[System.IO.File]::AppendAllText($path, $line, [System.Text.Encoding]::ASCII)`
  for log writes -- avoids `Out-File`'s pipeline overhead per line. Comment
  explains the encoding choice.
- `[System.IO.Path]::Combine` over `Join-Path` inside hot loops; `Join-Path`
  everywhere else for readability.
- `[datetime]::UtcNow` over `Get-Date` when ordering or formatting invariantly;
  local time only at the user-facing logging boundary.
- `[regex]::Escape` over manual escaping when building patterns from data.

The AD module's cmdlets (`Disable-ADAccount`, `Set-ADUser`) stay in place for
the write path -- N is small, clarity beats perf there, and the
strongly-typed error surface is much friendlier than chasing
`COMException` hresults out of `[adsi]`.

### `-ErrorAction` is explicit on every cmdlet that can throw

Either `Stop` (we want it to bubble) or `SilentlyContinue` paired with
`-ErrorVariable` (we want to inspect). Never relying on the ambient
`$ErrorActionPreference` for behavior.

### No automatic-variable shadowing

`$Error`, `$Input`, `$Args`, `$Matches`, `$PSItem`, `$_`, `$Host`, `$Home`,
`$PID`, etc. are off-limits as parameter or local names. v1 shadowed `$Error`
in the disable function; v2 does not.

## Project artifact archive (`docs/project/`)

Long-lived archive for the *thinking* behind the project, separate from
`CHANGELOG.md` and PR descriptions. Five categories, each with its own status
subfolder layout:

- `decisions/` -- Architectural Decision Records (ADRs).
  Statuses: `proposed/`, `accepted/`, `deferred/`, `superseded/`, `rejected/`.
- `gaps/` -- known gaps between current state and ideal.
  Statuses: `open/`, `deferred/`, `closed/`, `wont-fix/`.
- `discrepancies/` -- where the implementation diverges from documented intent.
  Statuses: `open/`, `closed/`.
- `security/` -- observations from security review and antagonistic-tester
  sessions.
  Statuses: `open/`, `mitigated/`, `accepted/` (risk knowingly accepted),
  `closed/`.
- `changes/` -- granular per-change records (finer-grained than CHANGELOG.md
  release entries).
  Statuses: `proposed/`, `applied/`, `reverted/`.

See `docs/project/README.md` for the schema, numbering convention, and the
"how to move an artifact between statuses" workflow.

## No vendor references in committed artifacts

The maintainer's customer would have an allergic reaction to assistant-vendor
branding in the public repo. Therefore:

- Commit messages do NOT include `Co-Authored-By: <assistant>` trailers,
  `https://*/code/...` session links, or "Generated with..." marketing lines.
- Code, comments, tests, fixtures, and docs do NOT mention specific assistant
  vendors by name.
- This file (`AGENTS.md`) is the cross-tool convention used by Cursor, Aider,
  OpenAI Codex CLI, and any agent that reads it. It replaces an earlier
  vendor-named instruction file.
- CI gates against the prohibited string set on every push (see
  `.github/workflows/ci.yml`).

## Git workflow

Active development branch for this rebuild: `claude/init-project-setup-s2ajg`
(harness-mandated). Final merge to `main` is a **squash merge** so the
branch name does not appear in `main`'s commit graph. Delete the branch on
merge.

Commit on the branch with descriptive messages (subject + body, no AI
trailers). Push with:

```sh
git push -u origin claude/init-project-setup-s2ajg
```

Do not open a pull request unless explicitly asked.
