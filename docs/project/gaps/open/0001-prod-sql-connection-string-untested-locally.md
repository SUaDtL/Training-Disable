---
id: 0001
title: Production SQL connection cannot be exercised outside the prod environment
status: open
category: gap
created: 2026-05-08
updated: 2026-05-08
tags: [sql, testing, environment]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0007-psd1-config-format.md
  - docs/project/gaps/open/0002-no-end-to-end-test-against-real-ad.md
---

## Context

The script's SQL stage calls a stored procedure
(`orc.get_Pers_Training_Disable_Accounts`) on a database
(`WebTraining`) that exists only inside the maintainer's organization. We
have no test harness, sample database, or schema fixture that lets us
exercise the real SQL path outside that environment.

CI mocks the SQL boundary at `Private/Invoke-WamSqlStoredProcedure.ps1`
so unit tests can run on Linux pwsh without a database. The mock is
reliable for the contract we expect (return a `DataTable` whose first
column `nt_username` contains `DOMAIN\Username` strings), but if the
real stored procedure ever returns an unexpected schema -- additional
columns, a different column name, no rows on a non-empty source table --
we will not notice until a prod run logs zero candidates.

## Impact

Low to medium. The production stored procedure has been stable for
years; schema drift is unlikely in the short term. If it does drift,
the failure mode is "no users get disabled today" -- not a destructive
failure. The morning operations team would notice within a day or two
when the daily summary email shows zero activity.

## Plan (or lack thereof)

Plan: defer until we have a synthetic SQL Server we can run in CI (e.g.
a Linux container of SQL Server Express). Specifically:

1. Author a `tests/fixtures/sql/setup.sql` that creates the
   `WebTraining` schema and the stored procedure as a no-op that returns
   a small fixed dataset.
2. Add a CI job that spins up a SQL Server Express container, runs the
   setup script, and runs an integration test against it.
3. Drop the SQL mock for that test path; keep mocks for unit tests that
   should not need a database.

Estimated effort: half a day plus CI minute budget. Not in v2 scope.

## Workaround

Two layers of mitigation in v2 itself:

1. The integration test (`tests/Integration/DropInCompat.Tests.ps1`)
   exercises the SQL boundary contract: it calls
   `Invoke-WamSqlStoredProcedure` with a stub that returns the schema
   we expect. If the contract changes, that test breaks before any
   real run does.
2. The orchestrator logs the count of users returned by SQL at
   `Verbose` level; an ops person rerunning with `-Verbose` can tell at
   a glance whether the stored procedure returned anything.

## References

- `src/WamTrainingDisable/Private/Invoke-WamSqlStoredProcedure.ps1`
  (PR 5)
- `tests/Public/Get-WamNonCompliantUser.Tests.ps1` (PR 5)
