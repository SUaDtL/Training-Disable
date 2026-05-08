---
id: 0003
title: It is not yet confirmed whether v1 logs feed a downstream parser
status: open
category: gap
created: 2026-05-08
updated: 2026-05-08
tags: [logging, drop-in, behavior-change]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0004-snapshot-driven-modernization.md
  - docs/project/decisions/accepted/0006-vip-log-is-downstream-contract.md
---

## Context

v1's log lines start with a timestamp produced by
`(Get-Date).ToShortDateString() + ' ' + (Get-Date).ToLongTimeString()`,
which is **culture-dependent**. On `en-US` it renders as
`5/8/2026 2:30:00 PM`. On `de-DE` it renders as
`08.05.2026 14:30:00`. On `ja-JP` it renders differently again.

In v1's environment the host's culture is presumably `en-US` and the
output is stable. v2's default uses an ISO-8601 timestamp
(`2026-05-08 14:30:00`) which is culture-invariant and sortable, and
which we believe is a strict improvement.

However: the maintainer suspects (but has not confirmed) that v1's
output may feed an email-summary tool downstream that parses these
lines with a regex tuned to the `en-US` shape. If that is true, flipping
to ISO-8601 would silently break the parser.

## Impact

If a downstream parser exists and we do not preserve v1's shape:
medium. The parser would stop matching, the email summary would go
empty, and an ops person would notice within a day or two. Not
destructive but embarrassing.

If no such parser exists: zero impact.

## Plan (or lack thereof)

v2 ships an opt-in escape hatch: `Logging.LegacyTimestamp = $true` in
the config file reproduces v1's culture-dependent timestamp shape
exactly (under the same culture as v1 was running, which we capture in
the snapshot test fixture as `en-US`). The default is the ISO format.

Action item for the maintainer: before flipping the production
scheduled task to v2, **verify** whether any downstream tool parses the
log files. If yes, set `LegacyTimestamp = $true` for now and file a
follow-up gap to migrate the downstream tool to ISO-8601 on a planned
schedule. If no, leave the default and close this gap.

## Workaround

Set `Logging.LegacyTimestamp = $true` in the user config file. The
shipped default ships `LegacyTimestamp = $false` so a fresh deployment
gets ISO timestamps, but a prod-cutover deployment can opt back into
the v1 shape with a one-line change.

## References

- `src/WamTrainingDisable/Private/ConvertTo-WamLogLine.ps1` (PR 4)
- `src/WamTrainingDisable/WamTrainingDisable.config.psd1` (PR 5)
- `tests/Integration/DropInCompat.Tests.ps1` (PR 2 -- exercises both
  paths)
