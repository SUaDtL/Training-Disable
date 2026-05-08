# Project artifact archive

This directory holds the long-lived record of the *thinking* behind this
project: the decisions, gaps, discrepancies, security observations, and
granular change notes. It is deliberately separate from `CHANGELOG.md` (which
is a release-oriented summary) and from PR descriptions (which are ephemeral
and rot).

The maintainer wants to be able to walk into this directory two years from
now, with no other context, and reconstruct *why* every non-obvious choice
was made. That is the bar.

## Categories

| Category          | What goes here                                               |
| ----------------- | ------------------------------------------------------------ |
| `decisions/`      | Architectural Decision Records (ADRs). Any choice big enough that someone six months from now would ask "why did we do this?" gets one. |
| `gaps/`           | Known gaps between current state and ideal. Things we *know* are missing or imperfect but chose not to fix this round. |
| `discrepancies/`  | Where the implementation diverges from documented intent (or vice versa). The forensic surface for "I thought this did X but it actually does Y." |
| `security/`       | Security observations, especially from antagonistic-tester sessions ("I tried to make it disable a user it shouldn't have"). |
| `changes/`        | Granular per-change records, finer-grained than CHANGELOG.md release entries. Each non-trivial PR gets one. |

## Statuses

Each category has its own valid status set, encoded as a subfolder. An
artifact's path tells you its status without opening the file. The status is
*also* duplicated in YAML frontmatter so a tool that does not understand the
folder hierarchy (e.g. `grep -l "status: open"`) still finds it.

| Category          | Statuses (subfolders)                                              |
| ----------------- | ------------------------------------------------------------------ |
| `decisions/`      | `proposed/`, `accepted/`, `deferred/`, `superseded/`, `rejected/`  |
| `gaps/`           | `open/`, `deferred/`, `closed/`, `wont-fix/`                       |
| `discrepancies/`  | `open/`, `closed/`                                                 |
| `security/`       | `open/`, `mitigated/`, `accepted/`, `closed/`                      |
| `changes/`        | `proposed/`, `applied/`, `reverted/`                               |

Status definitions (use these consistently):

- **proposed** -- under consideration, not yet committed to.
- **accepted** -- decision made; in effect.
- **deferred** -- recognized but explicitly punted to a future round.
- **superseded** -- replaced by a later decision; see the `superseded-by`
  frontmatter field for the pointer.
- **rejected** -- considered and explicitly turned down; kept for history so
  we don't relitigate.
- **open** -- gap or discrepancy is real and unresolved.
- **closed** -- resolved (gap filled, discrepancy fixed, security finding
  remediated).
- **wont-fix** -- gap is real but we have decided not to address it. Different
  from `deferred` in that there is no future round expected.
- **mitigated** -- security risk reduced to a level the maintainer is
  comfortable with, but the underlying surface still exists.
- **accepted** (security) -- risk knowingly accepted as-is. The asymmetry
  between this and `mitigated` is deliberate.
- **applied** -- change record describes a change that has shipped.
- **reverted** -- change was applied and then rolled back; the record
  remains for forensics.

## Numbering

Zero-padded four-digit numbers, monotonic per category, never reused.

```
docs/project/decisions/accepted/0007-psd1-config-format.md
docs/project/gaps/open/0001-prod-sql-connection-string-untested-locally.md
```

When you add a new artifact, find the highest existing number in that
*category* (across all status subfolders) and increment by one. Do not
restart the count per status -- the number is the artifact's identity.

## Frontmatter schema

Every artifact starts with YAML frontmatter:

```yaml
---
id: 0007                                        # zero-padded, matches the filename
title: Use .psd1 as the on-disk config format   # imperative voice
status: accepted                                # must match the subfolder name
category: decision                              # decision | gap | discrepancy | security | change
created: 2026-05-08
updated: 2026-05-08
tags: [config, security, psd1]                  # free-form, lowercase
supersedes: []                                  # paths to artifacts THIS one replaces
superseded-by: []                               # paths to artifacts that replace THIS one
related: []                                     # paths to non-superseding related artifacts
---
```

Fields below the `---` are free-form Markdown. The conventional headings are
documented in each category's `_template.md`.

## How to add an artifact

1. Pick the category and the initial status. Decisions are usually born
   `proposed/`; gaps are usually born `open/`; change records for shipped PRs
   are born `applied/`.
2. Find the next number for that category. Across *all* status subfolders.
3. Create the file at `docs/project/<category>/<status>/NNNN-<slug>.md`.
4. Fill out the frontmatter and the body. Use the matching `_template.md` as
   the starting point.
5. Reference the artifact from the PR description that introduced it. The
   PR body is where the link lives during review; the archive is where the
   record persists after merge.

## How to move an artifact between statuses

Use `git mv` to preserve history:

```sh
git mv docs/project/decisions/proposed/0011-foo.md \
       docs/project/decisions/accepted/0011-foo.md
```

Then update two frontmatter fields:

- `status:` -- must match the new subfolder.
- `updated:` -- today's ISO date.

If the move is `superseded/`, also fill in `superseded-by:` with the path to
the replacing artifact. If the move is `closed/`, append a new section to the
body titled "Resolution" describing how the gap or discrepancy was closed.

## Why we use folder-as-status

Two reasons:

1. The maintainer wanted it that way. (Listed first because it is the actual
   reason. The next two bullet points are post-hoc justifications.)
2. `ls docs/project/gaps/open/` is a one-keystroke "what's left to do?"
   query, no metadata index required.
3. A file's path is the most stable summary anyone reading the repo will see
   first -- in PR diffs, in `git log --stat`, in GitHub's tree view. Encoding
   status there means the status travels with every casual mention of the
   file.
