---
id: 0007
title: Use .psd1 as the on-disk configuration format
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [config, security, format-choice]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0001-modular-rewrite.md
---

## Context

v1 has no external configuration. All runtime knobs (SQL connection
string, grace period, exempt OUs, log file base path, the report-only
switch) live in a `CONFIGURATION VARIABLES` block at the top of the
script. To change a value the maintainer edits the script in place.

This is fine for a script that lives on one server forever, but it
fails the v2 goal of being a properly packaged module: a module's source
files should not be edited by users at runtime, and a config that lives
inside the source tree gets accidentally overwritten on `git pull`.

We need an on-disk format for default configuration shipped with the
module, plus a precedence chain (cmdlet parameter > environment variable
> user config > project config > shipped default).

## Decision

Use PowerShell data files (`.psd1`) for configuration. The shipped
default lives at
`src/WamTrainingDisable/WamTrainingDisable.config.psd1` next to the
manifest. The user-overridable file lives at
`$env:LOCALAPPDATA\WamTrainingDisable\config.psd1` on Windows. The
resolver function `Private/Resolve-WamConfiguration.ps1` walks the
precedence chain and merges hashtables.

The config file is loaded with `Import-PowerShellDataFile` -- the safe
loader that **does not invoke** code in the file, so a tampered config
cannot execute arbitrary PowerShell.

## Consequences

- Comments and trailing commas are supported (unlike strict JSON).
- The format is signable like any .ps1 (Authenticode), so a deployment
  pipeline can sign config alongside code.
- `Test-ModuleManifest` already speaks .psd1; tooling reuses naturally.
- Consumers from other languages (a future dashboard, an external audit
  tool) cannot read .psd1 directly. We accept that the operational
  config is internal to PowerShell; if cross-language consumption ever
  comes up we can emit a generated JSON view.
- The precedence chain order (parameter > env var > user file > project
  file > default) is the conventional order used by most CLI tools and
  matches what a developer would assume.

## Alternatives considered

- **JSON.** Common and tooling-friendly but loses comments. The maintainer
  specifically wants the config file to be self-documenting; comments
  are a hard requirement.
- **YAML.** Supports comments, widely used in CI configs. Rejected
  because it adds a non-shipping module dependency (`powershell-yaml`)
  and the YAML-spec gotchas (Norway problem, octal numbers, etc.) are a
  poor fit for credential-adjacent config.
- **TOML.** Comments, simple syntax, no PowerShell-native parser. Same
  rejection reason as YAML: extra dependency for marginal gain.
- **Environment variables only.** Works for the SQL connection string
  but does not work for nested structures (per-channel filename
  templates, the OuMatchPattern). Env vars remain a layer in the
  precedence chain, not the canonical format.
- **`.ini`.** No nesting, no list support, parser is hand-rolled. Out.

## References

- Microsoft Learn -- Import-PowerShellDataFile:
  <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-powershelldatafile>
- `src/WamTrainingDisable/WamTrainingDisable.config.psd1` (PR 5)
- `src/WamTrainingDisable/Private/Resolve-WamConfiguration.ps1` (PR 4)
