---
id: 0010
title: Do not publish the module to the PowerShell Gallery (yet)
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [release, scope, psgallery]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0001-modular-rewrite.md
---

## Context

A natural question for a packaged PowerShell module is "should we publish
it to the PowerShell Gallery?" Publishing would let any consumer run
`Install-Module WamTrainingDisable` and pull the latest version.

For a generic-utility module the answer is usually yes. For this module
the answer is less obvious: it is **environment-specific** by design.
The hard-coded SQL stored procedure name (`orc.get_Pers_Training_Disable_Accounts`),
the OU naming convention (`OU=VIP`, `OU=REL`, `OU=SCO`), the AD group
names in the `Exempt` array, and the log file path layout are all
specific to the maintainer's organization. A consumer who installed the
module from PSGallery would have to override every one of those before
the module did anything useful in their environment.

## Decision

Do not publish to PSGallery in the v2.0 release. The module is
distributed as a git clone or download from this repository. If a
consumer wants to use it, they fork and modify -- which is exactly what
the README has always told them.

`CONTRIBUTING.md` retains a "Future work: PSGallery publish" recipe so
that, if someone ever generalizes the module to be environment-agnostic
(see gap below), the publish workflow is documented and ready to
activate.

## Consequences

- The CI workflow has no `publish` job. We do not need to set up a
  PSGallery API key, a NuGet apikey rotation, or a GitHub release-tag
  trigger.
- The module's consumer experience is "git clone, edit
  WamTrainingDisable.config.psd1, run". This is the same experience as
  v1; we are not regressing.
- A future contributor who wants to make the module
  environment-agnostic would need to:
  1. Add abstract config for the SQL stored procedure name (already
     done in v2).
  2. Generalize the OU exemption substring matching (already done -- it
     reads `Policy.ExemptOus` from config).
  3. Add a sample config that demonstrates a different organization's
     naming.
  4. Update README to describe the customization story.
  5. Activate the publish workflow per the recipe in CONTRIBUTING.md.
  We accept that this work is out of scope for v2.

## Alternatives considered

- **Publish to PSGallery as `WamTrainingDisable.<org>.<region>` with a
  vendor-specific name.** Rejected -- vendor naming pollutes the
  PSGallery namespace and the module is not generically useful.
- **Publish to PSGallery with strong "this is environment-specific"
  caveats.** Rejected -- caveats in package metadata are routinely
  ignored. The right place for "this is environment-specific" is the
  README of the source repo.
- **Publish to a private feed at the maintainer's organization.** Out
  of scope for the public repo. The maintainer can add a private feed
  workflow on a fork if they want one.

## References

- `README.md` (rewritten in PR 8)
- `CONTRIBUTING.md` (created in PR 8)
- Gap candidate: "Module is not generically usable across organizations"
  -- not yet filed as we are accepting that as the design, not a gap.
