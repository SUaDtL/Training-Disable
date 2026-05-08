# =============================================================================
# Private/Get-WamUserDetail.ps1
# =============================================================================
# One Get-ADUser per user, with the full property set the rest of the
# pipeline needs. v1 made TWO Get-ADUser calls per user (one for the
# attributes, one for MemberOf), then a separate Get-ADGroup per
# membership to project DNs to display names. v2 fetches once and
# resolves group names inline so the AD load is halved.
#
# At PR 3 this is a stub. PR 5 fills in the body.
# =============================================================================

function Get-WamUserDetail {
    <#
    .SYNOPSIS
        Fetch one user's WAM-relevant AD attributes and resolve their
        group memberships to display names.

    .DESCRIPTION
        Internal helper. Returns a [pscustomobject] with the same
        shape Test-WamUserExemption expects. Wraps Get-ADUser /
        Get-ADGroup so unit tests can mock this single seam instead
        of mocking the AD module directly.

        Throws [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
        when the identity does not exist. Callers should catch and
        log; v1's catch handler had a bug where $ADAccount carried
        over from the previous loop iteration.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Identity
    )

    throw [System.NotImplementedException]::new(
        'Get-WamUserDetail will be implemented in PR 5 (I/O wrappers).'
    )
}
