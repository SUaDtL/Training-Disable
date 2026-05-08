# =============================================================================
# Private/Resolve-WamConfiguration.ps1
# =============================================================================
# Walks the configuration resolution stack in precedence order and
# returns the merged hashtable. The stack (highest precedence first):
#
#   1. Cmdlet parameters (passed in via -ParameterOverrides)
#   2. Environment variables (WAM_SQL_CONNECTION, WAM_LOG_DIR, ...)
#   3. User config: $env:LOCALAPPDATA\WamTrainingDisable\config.psd1
#      on Windows or $HOME/.config/WamTrainingDisable/config.psd1 on
#      Linux
#   4. Project config: -ConfigPath (an explicit project file)
#   5. Shipped defaults: WamTrainingDisable.config.psd1 next to the
#      manifest
#
# Merging is DEEP, key-by-key, including nested hashtables. A higher
# layer's value wins over a lower layer's value for the same key only;
# unspecified keys fall through.
#
# At PR 3 this is a stub. PR 4 fills in the body and the table-driven
# tests for the merge precedence.
# =============================================================================

function Resolve-WamConfiguration {
    <#
    .SYNOPSIS
        Resolve the WAM configuration from the layered stack.

    .DESCRIPTION
        Internal helper. Pure-ish (reads files and env vars but does
        no I/O of its own). Used by every Public cmdlet that needs
        configuration; the per-cmdlet param block carries the
        parameter-layer overrides which are passed through here.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string] $ConfigPath,

        [Parameter()]
        [hashtable] $ParameterOverrides = @{}
    )

    throw [System.NotImplementedException]::new(
        'Resolve-WamConfiguration will be implemented in PR 4 (pure logic extraction).'
    )
}
