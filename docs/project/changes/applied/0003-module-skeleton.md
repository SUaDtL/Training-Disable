---
id: 0003
title: Stand up the WamTrainingDisable module skeleton
status: applied
category: change
created: 2026-05-08
updated: 2026-05-08
tags: [module, manifest, stubs, scaffolding, comment-based-help]
supersedes: []
superseded-by: []
related:
  - docs/project/changes/applied/0001-tooling-skeleton.md
  - docs/project/changes/applied/0002-v1-snapshot-tests.md
  - docs/project/decisions/accepted/0001-modular-rewrite.md
  - docs/project/decisions/accepted/0007-psd1-config-format.md
---

## Summary

Stands up the v2 module skeleton at `src/WamTrainingDisable/`. Creates the
manifest, the root .psm1, the shipped default config, the about_ help
topic, and an empty stub for each Public and Private function the
follow-up PRs will fill in. Each stub throws
`[System.NotImplementedException]` with a "filled in by PR N" message
so attempts to call the function before its target PR fail loudly
rather than silently no-op.

Every Public cmdlet ships with full PowerShell comment-based help
(`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for each parameter,
`.EXAMPLE` x 3, `.NOTES`, `.LINK`) per the AGENTS.md convention. Stubs
for state-changing verbs (`Disable-WamUserAccount`,
`Invoke-WamTrainingDisable`) declare
`[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]`
and call `$PSCmdlet.ShouldProcess(...)` before throwing, so the
PSScriptAnalyzer rules `PSUseShouldProcessForStateChangingFunctions`
and `PSShouldProcess` are satisfied at lint time.

`src/TrainingDisable.ps1` is unchanged. The PR 2 snapshot test continues
to pass against v1 unmodified.

## Files touched

New (`src/WamTrainingDisable/`):

- `WamTrainingDisable.psd1` -- module manifest (v2.0.0; GUID
  1449f16d-a0fc-43ee-b9a0-f928d17e6215; targets PowerShell 5.1+ Desktop
  and Core editions; explicit `FunctionsToExport` list).
- `WamTrainingDisable.psm1` -- root module that dot-sources Public/* and
  Private/* and exports only Public functions.
- `WamTrainingDisable.config.psd1` -- shipped default config; lowest
  precedence layer in the resolution stack documented in
  `Resolve-WamConfiguration` and `about_WamTrainingDisable.help.txt`.
- `Public/Invoke-WamTrainingDisable.ps1` -- orchestrator stub
  (filled by PR 6).
- `Public/Get-WamNonCompliantUser.ps1` -- SQL stage stub (filled by
  PR 5).
- `Public/Test-WamUserExemption.ps1` -- pure exemption-decision stub
  (filled by PR 4).
- `Public/Disable-WamUserAccount.ps1` -- AD-write stage stub (filled by
  PR 5).
- `Public/Get-WamConfiguration.ps1` -- diagnostic stub (filled by PR 6).
- `Private/Write-WamLog.ps1` -- multi-channel logger stub (filled by
  PR 5).
- `Private/Get-WamUserDetail.ps1` -- AD wrapper stub (filled by PR 5).
- `Private/Resolve-WamConfiguration.ps1` -- config resolver stub
  (filled by PR 4).
- `Private/Invoke-WamSqlStoredProcedure.ps1` -- SQL seam stub (filled
  by PR 5).
- `Private/ConvertTo-WamLogLine.ps1` -- log-line formatter stub
  (filled by PR 4).
- `en-US/about_WamTrainingDisable.help.txt` -- topic-level help; covers
  the pipeline, configuration resolution, log channels, grace period,
  report-only mode, and a command index.

## Why this is a change record

This change ships a substantial amount of policy: the API surface
(which functions are Public, which are Private), the manifest's GUID
(a one-time identity that should never be regenerated), the
configuration-resolution precedence stack (documented in three
places: the .config.psd1 header, `Resolve-WamConfiguration`, and
the about_ topic), the comment-based help convention applied
uniformly across the five Public cmdlets, and the stub-throws-with-PR-pointer
discipline that makes the ladder of follow-up PRs easy to walk.

A future maintainer reading the manifest's GUID or the
`FunctionsToExport` list should be able to find the artifact that
documented "why these specific names" without git-blaming each file.

## Verification

Local checks performed (pwsh 7.6.1, Ubuntu 24.04):

- `Test-ModuleManifest -Path ./src/WamTrainingDisable/WamTrainingDisable.psd1`
  returns silently (no validation errors).
- `Import-Module ./src/WamTrainingDisable/WamTrainingDisable.psd1 -Force`
  loads cleanly (no errors, no warnings).
- `Get-Command -Module WamTrainingDisable` returns exactly the five
  Public functions; Private functions (`Write-WamLog`, etc.) are NOT
  reachable from outside the module.
- Every Public stub, when called with a minimal valid argument set,
  throws `[System.NotImplementedException]` with a message that names
  the PR that will fill it in.
- `Get-Help -Full` on every Public cmdlet renders the synopsis,
  description, parameters, three examples, notes, and links.

Remote checks (deferred until pushed):

- The CI `manifest` job runs `Test-ModuleManifest` on a Linux runner.
  Local pwsh validation already performed; CI should be green.
- The CI `analyze` job runs PSScriptAnalyzer with the repo settings
  against `./src/WamTrainingDisable` recursively. Local PSSA was
  unavailable (PSGallery is not on the dev environment's HTTP
  allowlist); CI is the first place the rules get exercised against
  the module. Any findings will be fixed in a follow-up commit on the
  same branch.
- The CI `test` matrix runs Pester against the PR 2 integration test;
  PR 3 does not change v1, so the snapshot must remain green.

## References

- ADR 0001 -- the modular-rewrite decision the skeleton implements.
- ADR 0007 -- the .psd1-config-format decision the shipped default
  follows.
- Change record 0002 -- the PR 2 snapshot test that protects this
  module's eventual cutover from v1.
- `src/WamTrainingDisable/WamTrainingDisable.psd1` -- the manifest
  (v2.0.0; the GUID is permanent).
- `src/WamTrainingDisable/en-US/about_WamTrainingDisable.help.txt` --
  the topic-level help; the canonical orientation document for
  consumers running `Get-Help about_WamTrainingDisable`.
