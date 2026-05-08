# =============================================================================
# WamTrainingDisable.psd1 -- Module manifest for the v2 module
# =============================================================================
#
# This file is the contract between the module and the rest of PowerShell.
# Test-ModuleManifest validates the data shape; Import-Module reads it to
# decide what to load and what to export.
#
# We hand-author this file rather than running New-ModuleManifest because:
#
#   1. New-ModuleManifest's output ships with every key (including the ones
#      we leave empty), all uncommented. That output is hard to review --
#      the relevant decisions are buried among the boilerplate. A
#      hand-authored manifest with a comment per non-default decision is
#      easier to read AND smaller in the diff.
#
#   2. The 'Prerelease' field (when v2 enters a beta cycle) and the
#      'PSData' subkeys both live inside PrivateData, which the generator
#      formats inconsistently across PowerShell versions. Hand-formatting
#      keeps the file stable.
#
# Approved-key reference:
# https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest
# =============================================================================

@{
    # -------------------------------------------------------------------------
    # Identity.
    # -------------------------------------------------------------------------

    # The .psm1 entry point. Test-ModuleManifest verifies this file exists.
    RootModule = 'WamTrainingDisable.psm1'

    # Semantic version. v2.0.0 is the first proper module release; everything
    # before this lived as src/TrainingDisable.ps1 (a bare .ps1 that never
    # had a version of its own). Bump the second component on backward-
    # compatible feature additions, the third on bug fixes.
    ModuleVersion = '2.0.0'

    # GUID is a one-time identity; never regenerate. Generated 2026-05-08
    # via [guid]::NewGuid().ToString() on pwsh 7.6.1. If the module is ever
    # forked AND published under a different name, the fork should mint a
    # new GUID; renaming alone is not enough to disambiguate in PSGallery.
    GUID = '1449f16d-a0fc-43ee-b9a0-f928d17e6215'

    Author = 'SUaDtL'
    CompanyName = 'Unknown'
    Copyright = '(c) 2024-2026 SUaDtL. All rights reserved.'

    Description = @'
Disables Active Directory user accounts for users delinquent on the
"What About Me" (WAM) training, with a configurable exemption matrix
covering OUs and group memberships, a 30-day grace period for new
hires, and three log channels (main, VIP, exempt) consumed by separate
downstream teams. Drop-in compatible with the v1 src/TrainingDisable.ps1
scheduled task; environment-specific to the maintainer's organization.
'@

    # -------------------------------------------------------------------------
    # Compatibility.
    # -------------------------------------------------------------------------
    # The production scheduled task runs Windows PowerShell 5.1 (the desktop
    # edition that ships in-box on Windows Server 2016+). pwsh 7.4 LTS is
    # the cross-platform target the CI matrix exercises in addition. Both
    # editions must work; the analyzer's PSUseCompatibleSyntax/Cmdlets rules
    # enforce this at lint time.

    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # -------------------------------------------------------------------------
    # Dependencies.
    # -------------------------------------------------------------------------
    # The module does NOT declare ActiveDirectory as a RequiredModules entry.
    # ActiveDirectory is platform-specific (Desktop edition on Windows) and
    # listing it here would block the module from loading on a Linux pwsh
    # used for testing. Instead, the module loads ActiveDirectory lazily,
    # only when the disable path is actually exercised, and tests inject
    # function-scope stubs the way V1Sandbox.ps1 does today.

    RequiredModules = @()

    # -------------------------------------------------------------------------
    # Exports.
    # -------------------------------------------------------------------------
    # Listing the exports explicitly (instead of using '*') keeps Private/
    # functions invisible to consumers and makes Get-Command predictable.
    # PSGallery's manifest scanner also rejects '*' on the exports for the
    # same reasons.

    FunctionsToExport = @(
        'Invoke-WamTrainingDisable'
        'Get-WamNonCompliantUser'
        'Test-WamUserExemption'
        'Disable-WamUserAccount'
        'Get-WamConfiguration'
    )

    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    # -------------------------------------------------------------------------
    # File manifest.
    # -------------------------------------------------------------------------
    # We do NOT enumerate every .ps1 in FileList; the generator's habit of
    # exhaustively listing each file produces a manifest that breaks every
    # time a Public/Private file is added or renamed. The .psm1 dot-sources
    # what it finds at runtime, which is the canonical pattern.

    FileList = @()

    # -------------------------------------------------------------------------
    # Private data: PSGallery metadata + project metadata.
    # -------------------------------------------------------------------------

    PrivateData = @{
        PSData = @{
            # Tags surface the module in PSGallery search results (when we
            # ever publish; ADR 0010 says we deliberately do not, but the
            # tags belong here in case that decision is revisited).
            Tags = @(
                'ActiveDirectory'
                'Compliance'
                'Training'
                'Automation'
                'Audit'
            )

            # No license URL key -- the LICENSE file in the repo is the
            # authoritative copy. PSGallery will pick it up from the repo
            # when (if) we publish.
            ProjectUri = 'https://github.com/SUaDtL/Training-Disable'

            # ReleaseNotes is intentionally short; the long-form record
            # lives in CHANGELOG.md (added in PR 8).
            ReleaseNotes = @'
v2.0.0 -- initial module release. See CHANGELOG.md for the full
v1 -> v2 migration notes including the LegacyTimestamp opt-in.
'@
        }
    }

    # -------------------------------------------------------------------------
    # Help info URI (Updatable Help; not used today, reserved).
    # -------------------------------------------------------------------------
    # Updatable Help (Save-Help / Update-Help) needs a public CAB endpoint;
    # we have none and probably never will, since this module is
    # deliberately env-specific (ADR 0010). The about_WamTrainingDisable.help.txt
    # topic plus the comment-based help on each Public cmdlet is the help
    # surface.

    HelpInfoURI = ''
}
