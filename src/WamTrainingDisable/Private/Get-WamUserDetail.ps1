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

    # -------------------------------------------------------------------------
    # Single Get-ADUser call -- the v1 double-fetch defect (defect 4).
    # -------------------------------------------------------------------------
    # v1's WAM-ADSearch:
    #
    #   $ADAccount = Get-ADUser -Identity $User -Properties Department,
    #       OfficePhone, whenCreated, MemberOf
    #   ...
    #   $ADgroups = (Get-ADUser $ADAccount -Properties memberof) |
    #       select -ExpandProperty memberof | ForEach-Object {
    #           (Get-ADGroup $_).name
    #       }
    #
    # The second Get-ADUser is redundant: MemberOf was already requested
    # in the first call. v2 makes one Get-ADUser call with the union of
    # properties and resolves group names from the result.
    #
    # ErrorAction Stop here turns the AD module's "Cannot find an object"
    # warning into a terminating error that propagates up to the
    # orchestrator's try/catch. The caller (Invoke-WamTrainingDisable in
    # PR 6) is responsible for logging "user not found" and continuing
    # with the next identity.
    # -------------------------------------------------------------------------
    $adUser = Get-ADUser `
        -Identity $Identity `
        -Properties Department, OfficePhone, whenCreated, MemberOf, Description, DistinguishedName, Enabled `
        -ErrorAction Stop

    # -------------------------------------------------------------------------
    # Resolve MemberOf DNs to display names.
    # -------------------------------------------------------------------------
    # Test-WamUserExemption (the consumer of this function) compares
    # group names by case-insensitive equality, so we project DNs to
    # CN-derived display names here. v1 used Get-ADGroup per DN; v2
    # keeps that pattern because the strongly-typed return surface is
    # easier to reason about than parsing CN out of the DN ourselves.
    #
    # Why ErrorAction SilentlyContinue on Get-ADGroup: a stale MemberOf
    # entry (the user was removed from a group that was then deleted,
    # but AD has not yet replicated the cleanup) is a known production
    # quirk. v1 would let that throw and skip the user entirely; v2
    # treats a missing group as "not exempt via this group" by emitting
    # nothing for it, which is the safer default for a disable script.
    # -------------------------------------------------------------------------
    $groupNames = @()
    if ($adUser.MemberOf) {
        foreach ($groupDn in $adUser.MemberOf) {
            $groupRecord = Get-ADGroup -Identity $groupDn -ErrorAction SilentlyContinue
            if ($null -ne $groupRecord) {
                $groupNames += [string] $groupRecord.Name
            }
        }
    }

    # -------------------------------------------------------------------------
    # Project to the shape Test-WamUserExemption expects.
    # -------------------------------------------------------------------------
    # The MemberOf field on the returned object is now an array of group
    # NAMES, not DNs. This is a deliberate contract: the exemption
    # function compares names, not DNs, and the projection happens
    # exactly once (here) instead of being repeated on every comparison.
    # -------------------------------------------------------------------------
    return [pscustomobject] @{
        SamAccountName = $adUser.SamAccountName
        Name = $adUser.Name
        Enabled = [bool] $adUser.Enabled
        whenCreated = [datetime] $adUser.whenCreated
        Department = $adUser.Department
        OfficePhone = $adUser.OfficePhone
        Description = $adUser.Description
        DistinguishedName = $adUser.DistinguishedName
        MemberOf = $groupNames
    }
}
