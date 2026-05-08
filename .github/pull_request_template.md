<!--
  Pull request template -- WAM Training Disable.

  Filling this in matters because the project's `docs/project/changes/`
  archive often pulls language directly from the PR description. Please
  write the description for the future maintainer skimming git log six
  months from now, not for the current reviewer.
-->

## Summary

<!-- One or two sentences. What changed and why. -->

## Scope

- [ ] Affects production behavior of `src/TrainingDisable.ps1`
- [ ] Affects v2 module behavior (`src/WamTrainingDisable/`)
- [ ] Tests / lint / CI only
- [ ] Documentation only
- [ ] Project artifact archive (`docs/project/`) only

## Test plan

<!--
  Bulleted list of how this was verified. "Tests pass" is not enough --
  state which tests, on which runtime. If a verification step is impossible
  in CI (requires a real domain controller, real SQL DB, prod data) say so
  explicitly and explain what was done instead.
-->

- [ ]
- [ ]
- [ ]

## Project artifacts

<!--
  Did this PR change any decisions, gaps, discrepancies, security notes, or
  granular change records under docs/project/? List them here. Linking the
  artifact in the PR is the canonical way the archive stays current.
-->

- [ ] No artifact changes
- [ ] Added artifact(s):
- [ ] Moved artifact(s) between statuses:

## Vendor-reference checklist

<!--
  The CI workflow runs a "vendor-reference gate" that fails the build if any
  prohibited assistant-vendor string appears in tracked files. The exact
  pattern is defined in `.github/workflows/ci.yml`. If you have intentionally
  introduced an allow-listed occurrence, document it here so the reviewer
  knows to expect it.
-->

- [ ] No new vendor references introduced
- [ ] Allow-listed occurrence(s) -- documented:

## Drop-in compatibility

<!-- Required for any PR that touches src/. If the production scheduled
     task contract is affected, say so explicitly. -->

- [ ] `pwsh -File src/TrainingDisable.ps1 -WhatIf` still produces the same
      log files at the same paths with the same line shape (the
      `tests/Integration/DropInCompat.Tests.ps1` suite still passes)
- [ ] N/A -- no behavior change to the entrypoint
