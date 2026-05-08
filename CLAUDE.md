# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Single-file PowerShell automation (`src/TrainingDisable.ps1`) that disables Active Directory user accounts for users delinquent on "What About Me" (WAM) training. The script is environment-specific: it was written for the author's organization and is published as a reference implementation, not as a generic tool. Per `README.md`, requested changes for other environments are out of scope — fork and modify locally.

## Running the Script

PowerShell only (uses `System.Data.SqlClient` and the `ActiveDirectory` module). There is no build, lint, or test infrastructure.

```powershell
# Execute end-to-end (logs only, default — see $ReportOnly)
pwsh -File src/TrainingDisable.ps1
```

`Start-Main` runs at the bottom of the file, so dot-sourcing the script will also execute it. To inspect functions interactively without firing the workflow, comment out the trailing `Start-Main` call.

## Configuration

All runtime knobs live in the `CONFIGURATION VARIABLES` block near the top of `src/TrainingDisable.ps1` (~lines 41–71). Edit these directly — there is no external config file:

- `$ReportOnly` — when `$TRUE` (default), generates logs as if accounts were disabled but performs no AD writes. Flip to `$FALSE` only after a verified report run.
- `$GracePeriod` — days since `whenCreated` during which an AD account is exempt from disablement.
- `$VIP` / `$REL` / `$SCO` — boolean OU-level exemptions matched against `DistinguishedName` substrings (`*OU=VIP*`, etc.).
- `$Exempt` — array of AD group names whose members are exempt.
- `$LogFileBasePath` — root for the four daily output files; the date suffix `$Date` is `yyyyMMdd` from script start.
- The SQL connection string in `WAM-SQLLookup` is hard-coded (`Server=XXXXX\XXXXX;Database=WebTraining`) and must be set per environment. The stored procedure consumed is `orc.get_Pers_Training_Disable_Accounts`, expected to return a table whose first column `nt_username` contains `DOMAIN\Username` strings.

## Architecture

The script is organized as a flat set of functions invoked in sequence by `Start-Main`:

1. **`WAM-SQLLookup`** — Opens an integrated-auth SQL connection, calls the stored procedure, strips the `DOMAIN\` prefix from each `nt_username`, and writes the resulting username list to `$LockOutListFile`. The file on disk is the contract between this stage and the next.
2. **`WAM-ADSearch`** — Reads `$LockOutListFile` and, for each username, performs a layered exemption check before deciding to disable. The order matters because the conditions are wired as `if/elseif` (only the first matching exemption is logged):
   1. AD lookup must succeed (`Get-ADUser` in try/catch).
   2. Account must currently be `Enabled`.
   3. `whenCreated + $GracePeriod` must be in the past.
   4. OU exemptions in priority order: REL → VIP → SCO.
   5. AD group membership against `$Exempt`.
   6. Otherwise call `WAM-Disable`.
3. **`WAM-Disable`** — Calls `Disable-ADAccount` and appends a dated note to the user's `Description`. When `$ReportOnly` is `$TRUE`, the function takes the `Else` branch and only writes log lines — useful for dry-run verification.
4. **`Write-Log` / `Write-LogVIP` / `Write-LogEXEMPT`** — Three parallel loggers that each lazily create `$LogFileBasePath` if missing. VIP users matching `DistinguishedName -like "*VIP"` are written to both the main log and the VIP log; exempt users are written to the main log and the EXEMPT log.

### Things to know when modifying

- `WAM-Disable` reuses the caller's `$User` and `$ADAccount` variables from `WAM-ADSearch`'s `foreach` scope rather than receiving them as parameters. Refactoring the disable function in isolation will silently break logging.
- `WAM-Disable` shadows the automatic `$Error` variable to track try/catch state. Renaming this is safer if you touch the function.
- Log directory creation is duplicated across the three `Write-Log*` functions; keep them in sync if you change the path-creation logic.
- The OU exemption checks rely on substring matches against `DistinguishedName` (`*OU=VIP*`, `*OU=REL*`, `*OU=SCO*`). These strings are environment-specific.
- The script appends to log files (`Out-File -Append`); rerunning on the same day adds to the existing day's logs rather than overwriting.

## Git Workflow

Active development branch for this session: `claude/init-project-setup-s2ajg`. Commit changes here and push with `git push -u origin claude/init-project-setup-s2ajg`. Do not open a pull request unless explicitly asked.
