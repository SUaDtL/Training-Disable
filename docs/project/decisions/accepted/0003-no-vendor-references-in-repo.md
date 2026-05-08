---
id: 0003
title: No assistant-vendor references in committed repository artifacts
status: accepted
category: decision
created: 2026-05-08
updated: 2026-05-08
tags: [policy, ci, vendor-neutrality]
supersedes: []
superseded-by: []
related: []
---

## Context

The maintainer's customer (the organization whose production environment
runs this script) would have an allergic reaction to specific
assistant-vendor branding appearing anywhere in the public repository. Even
incidental occurrences -- co-author trailers, marketing links auto-appended
to commit messages, file names that mention a specific tool -- are
unacceptable.

The maintainer cannot vouch for what every contributor's tooling does by
default, and assistant tools in particular tend to add vendor signatures to
commit messages without prompting. A policy without enforcement is just
hope.

## Decision

The repository enforces a "no vendor references" policy with two layers:

1. **Convention.** Contributors do not introduce specific assistant-vendor
   names into committed artifacts: code, comments, tests, fixtures,
   filenames, commit messages, PR descriptions, branch names where they can
   choose. The cross-tool agent-instruction file is `AGENTS.md` (the
   convention used by Cursor, Aider, OpenAI Codex CLI, and any tool that
   reads it). If a tool requires a vendor-specific filename to read
   instructions, the developer can keep one locally as a `.gitignore`-d
   symlink to `AGENTS.md`.
2. **Mechanical enforcement.** A CI step in `.github/workflows/ci.yml`
   greps tracked files for the prohibited strings (the canonical list lives
   in that workflow). The build fails on any hit. Two narrow exclusions:
   - The workflow file itself, because the regex literal must contain
     fragments of the strings to match them.
   - `tests/fixtures/`, because v1 may have captured organization-specific
     output that we want byte-identical for the snapshot test (see
     decision 0004).

A small allow-list line-pattern (the harness-mandated working branch name)
is also exempted; that branch name is part of the harness contract that
the maintainer cannot change locally.

## Consequences

- Future contributors using assistant tooling must configure their tooling
  to suppress co-author trailers and marketing links. Failure to do so
  fails CI before merge.
- The branch name `<harness>/init-project-setup-s2ajg` is on the working
  branch and would otherwise leak into `main`'s commit history. We
  mitigate by **squash-merging** the eventual PR (see decision 0009 and
  the AGENTS.md "Git workflow" section). Squash-merge collapses the
  branch's commits into one new commit on `main` whose message we author;
  the original branch's name and individual commit messages do not appear
  in `main`'s linear history.
- The policy is not retroactive against the existing branch's git log
  beyond the squash-merge boundary. The branch retains its earlier history
  privately; only `main` is sanitized.

## Alternatives considered

- **Trust contributors to follow convention without enforcement.** Rejected
  because the whole class of risk is "tools doing this automatically
  without the contributor noticing."
- **Ban only on `main`, allow on feature branches.** Rejected because
  feature branches on a public repo are visible to anyone with clone
  access. The customer's reaction is to seeing the public repo, not to
  reading `main` specifically.
- **Use `.gitattributes` filters to scrub on commit.** Rejected because
  filters are easy to bypass with `--no-verify` and because a filter that
  rewrites content silently is hostile to contributors who wonder why
  their commit looks different from what they typed.

## References

- `.github/workflows/ci.yml` -- the gate implementation
- `AGENTS.md` -- the cross-tool convention file
- `.github/pull_request_template.md` -- the contributor checklist
