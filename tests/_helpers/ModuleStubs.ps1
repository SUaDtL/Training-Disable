# =============================================================================
# tests/_helpers/ModuleStubs.ps1 -- WAM Training Disable
# =============================================================================
#
# Pester 5's `Mock -CommandName X` requires that X already exist as a
# registered command in the session state where the mock is being installed.
# When the module under test calls cmdlets that are not available on the
# test runner (specifically: the ActiveDirectory module on a Linux pwsh
# runner where it is not installed), Pester's Mock fails with
# "Could not find Command Get-ADUser" before any It block runs.
#
# This helper installs no-op stubs for those cmdlets directly into the
# WamTrainingDisable module's session state. The stubs are defined as
# functions, which take precedence over cmdlets in command resolution. They
# do nothing useful on their own; they exist purely so that Mock has
# something to intercept.
#
# Usage from a Tests.ps1 file:
#
#     BeforeAll {
#         Import-Module $script:ModulePath -Force
#         . (Join-Path $PSScriptRoot '../_helpers/ModuleStubs.ps1')
#         Install-WamModuleStubs
#     }
#
# Why a function rather than dot-source side effects:
#
#   - The function takes the module name so a future test suite for a
#     different module can reuse the stubs by passing a different name.
#   - The function call is explicit in the BeforeAll body; a future
#     contributor reading the test file sees the stubs being installed
#     rather than wondering why Get-ADUser exists in the module scope.
# =============================================================================

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Install-WamModuleStubs {
    <#
    .SYNOPSIS
        Install no-op stubs for the AD module cmdlets the WamTrainingDisable
        module calls, into the module's own session state.

    .DESCRIPTION
        Pester 5's Mock requires the target command to exist before mocking.
        On a Linux runner without the ActiveDirectory module, those cmdlets
        do not exist, so Mock would fail. This function defines empty
        function stubs in the module's scope so Mock can intercept them.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ModuleName = 'WamTrainingDisable'
    )

    $module = Get-Module -Name $ModuleName -ErrorAction Stop

    # We use & $module { ... } rather than InModuleScope because the latter
    # is a Pester construct that requires Pester loaded; this helper is
    # callable from raw pwsh harnesses too. & $module { ... } executes the
    # scriptblock inside the module's session state -- which is exactly
    # what we need for `function script:X` to take effect there.
    & $module {
        # Disable-ADAccount: the WAM-Disable success branch.
        function script:Disable-ADAccount {
            [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
            param(
                [Parameter(Mandatory)] $Identity
            )
        }

        # Set-ADUser: the description-suffix update.
        function script:Set-ADUser {
            [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
            param(
                [Parameter(Mandatory)] $Identity,
                [Parameter()] [string] $Description
            )
        }

        # Get-ADUser: the user-record fetch.
        function script:Get-ADUser {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory, Position = 0)] $Identity,
                [Parameter()] [string[]] $Properties
            )
        }

        # Get-ADGroup: the group display-name resolution.
        function script:Get-ADGroup {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)] $Identity
            )
        }
    }
}
