---
id: 0002
title: Use [adsisearcher] for bulk AD reads, keep the AD module for writes
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [performance, active-directory, type-accelerator]
supersedes: []
superseded-by: []
related:
  - docs/project/decisions/accepted/0005-verbose-code-no-aliases.md
---

## Context

v1 calls `Get-ADUser` per user inside the main loop, sometimes twice per
user (once for the user record, once again to fetch group membership for the
exemption check). For a daily run that processes several thousand users that
is several thousand round trips through Active Directory Web Services
(ADWS). Each call also goes through the `ActiveDirectory` module's pipeline,
which adds non-trivial PowerShell overhead per invocation.

The maintainer specifically called out that "if using a type accelerator
would increase performance make the swap (`adsisearcher` over `Get-ADUser`
for example)."

## Decision

For the **read** path, replace `Get-ADUser` with `[adsisearcher]` -- the
PowerShell type accelerator for `System.DirectoryServices.DirectorySearcher`.
The module's `Private/Get-WamUserDetail.ps1` builds an LDAP filter from the
list of usernames returned by SQL, queries in chunks (sized below the AD
`MaxValRange` ceiling, typically 1500), and returns one record per user
along with a pre-resolved set of exempt-group DNs.

For the **write** path (`Disable-ADAccount`, `Set-ADUser`), keep the
`ActiveDirectory` module cmdlets. The number of writes per run is small
(handful to a few dozen), the perf cost of ADWS is negligible at that
volume, and the strongly-typed cmdlet error surface is much friendlier
than chasing `COMException` HRESULTs out of `[adsi]`.

## Consequences

- Read latency drops from O(N) round trips to O(N/MaxValRange) round trips,
  which on the worst-case daily run is a meaningful difference (minutes to
  seconds).
- The wrapper function has to know about `[adsisearcher]` quirks:
  - Returned objects are `SearchResult`, not `ADUser`.
  - Properties are `ResultPropertyValueCollection`. Indexing one with a
    single value returns the value; indexing one with NO values returns
    `$null`. Code must guard explicitly.
  - `MemberOf` is DN strings, not group objects. The caller has to
    pre-resolve exempt-group DNs (a single `[adsisearcher]` query at
    startup).
  - LDAP filter syntax is its own grammar (`(&(...)(...))`) and has to be
    constructed carefully to avoid injection if a username ever contains
    special characters. We use `[regex]::Escape` then LDAP-escape per
    RFC 4515.
- The wrapper hides all of this behind a typed pscustomobject return so the
  rest of the module is unaware. The trade-off is concentrated.
- Tests mock the wrapper, not the type accelerator directly, so unit tests
  do not depend on `System.DirectoryServices` being available on the test
  runner.

## Alternatives considered

- **Stay on `Get-ADUser` but batch via `-Filter`.** `Get-ADUser` does
  support OR'd filters (`Filter "(samAccountName -eq 'a' -or
  samAccountName -eq 'b' -or ...)"`), and at moderate batch sizes the perf
  difference shrinks. Rejected because (a) the `-Filter` syntax has its
  own quirks (`-or` translates to LDAP differently than expected on some
  builds), (b) we still pay ADWS overhead, and (c) the maintainer
  explicitly asked for the type-accelerator swap as a learning exercise.
- **Use raw `[adsi]` instead of `[adsisearcher]`.** `[adsi]` is the older
  ADO interface and offers no real perf win over `[adsisearcher]` for our
  access pattern (we are searching, not binding to a known DN).
- **Use `System.DirectoryServices.AccountManagement` instead.** Higher
  level, but slower for bulk queries because each call binds a
  `PrincipalContext` separately and resolves attributes lazily.
  Inappropriate for this workload.

## References

- `src/WamTrainingDisable/Private/Get-WamUserDetail.ps1` (created in PR 5)
- Microsoft Learn -- DirectorySearcher:
  <https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.directorysearcher>
- RFC 4515 -- LDAP search filter syntax:
  <https://datatracker.ietf.org/doc/html/rfc4515>
