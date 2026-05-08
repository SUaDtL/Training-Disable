# =============================================================================
# WamTrainingDisable.psm1 -- Root module for WamTrainingDisable
# =============================================================================
#
# Responsibilities of this file (and ONLY of this file):
#
#   1. Declare strict mode and the error preference for the whole module.
#      Strict mode 3.0 catches typoed property names (which silently return
#      $null in lax mode and bite during a 3am incident); ErrorActionPreference
#      = 'Stop' makes any non-handled cmdlet error terminate, which is what
#      we want in a scheduled-task context.
#
#   2. Dot-source every Public\*.ps1 and Private\*.ps1 file. Each file
#      contains exactly one function definition, named after the file. The
#      Public/Private split mirrors the FunctionsToExport list in the
#      manifest -- Public functions are the documented API surface; Private
#      helpers are implementation details.
#
#   3. Export ONLY the Public functions. The manifest's FunctionsToExport
#      key is the authoritative list, but we also call Export-ModuleMember
#      explicitly so re-importing the module in the same session does not
#      accidentally leak Private helpers.
#
# What this file deliberately does NOT do:
#
#   - It does not contain business logic. Every if/foreach/AD call lives in
#     a Public/Private file. Keeping the .psm1 thin makes it easy to reason
#     about module-load behavior; it also keeps the PSScriptAnalyzer scan
#     fast (the .psm1 is plumbing, not surface).
#
#   - It does not auto-load configuration. Configuration resolution is the
#     responsibility of Resolve-WamConfiguration (Private), invoked by each
#     Public cmdlet at call time. Loading config at module-import would
#     mean every consumer pays the cost of reading config files even if
#     they only call one helper that does not need them.
#
#   - It does not call Add-Type, Import-Module, or any other side effect
#     that the consumer might be sensitive to. Module import should be
#     idempotent and observable-effect-free.
# =============================================================================

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Discover Public/* and Private/* files.
# -----------------------------------------------------------------------------
# Dot-source instead of Import-Module per-file because:
#   - Each file is a function definition, not a module.
#   - Dot-sourcing puts the function in this .psm1's scope, which means
#     Private helpers can call other Private helpers without re-importing.
#   - Import-Module of a single .ps1 actually wraps it in a script module
#     anyway -- dot-sourcing is the canonical lower-overhead pattern.
#
# We use ErrorAction Stop on the discovery so a missing directory (or a
# typo in the path) fails loudly at import time, not silently at first
# call.
# -----------------------------------------------------------------------------
$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

$publicFiles = @(
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -File -ErrorAction Stop
)
$privateFiles = @(
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -File -ErrorAction Stop
)

# -----------------------------------------------------------------------------
# Dot-source every discovered file.
# -----------------------------------------------------------------------------
# We deliberately let an exception during dot-source propagate. If a
# Public/Private file has a syntax error or fails to load, the module is
# unusable anyway -- a half-loaded module is worse than a clean failure.
# -----------------------------------------------------------------------------
foreach ($file in @($publicFiles + $privateFiles)) {
    . $file.FullName
}

# -----------------------------------------------------------------------------
# Export ONLY the Public functions.
# -----------------------------------------------------------------------------
# By convention each Public/*.ps1 file is named for the function it defines,
# so the function name is the file's BaseName. The manifest's
# FunctionsToExport key is the authoritative list at the consumer end,
# but Export-ModuleMember here belt-and-suspenders the policy.
# -----------------------------------------------------------------------------
Export-ModuleMember -Function $publicFiles.BaseName
