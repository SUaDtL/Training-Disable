# =============================================================================
# Public/Get-WamConfiguration.ps1
# =============================================================================
# Diagnostic cmdlet: prints the resolved configuration so the operator
# can see exactly which values would be used for a hypothetical run,
# without actually running it. Useful when debugging "why is it using
# THIS connection string and not THAT one?" -- the output shows the
# resolution path.
#
# At PR 3 this is a stub. PR 6 fills in the body.
# =============================================================================

function Get-WamConfiguration {
    <#
    .SYNOPSIS
        Show the resolved WAM configuration.

    .DESCRIPTION
        Walks the configuration resolution stack (shipped defaults,
        project config, user config, environment variables, parameters)
        and emits the merged result. Useful when troubleshooting "what
        config will the next scheduled run actually use?" or
        "where is this value coming from?"

        The output is the merged hashtable. With -ShowSource the output
        is annotated -- each leaf value is wrapped in an object with
        the resolved value AND the layer it was resolved from.

    .PARAMETER ConfigPath
        Path to a project-level configuration file. When supplied,
        included as the project-config layer.

    .PARAMETER ConnectionString
        Override the SQL connection string at the parameter layer.
        Surfaces in the output so the operator can see the override.

    .PARAMETER ShowSource
        Annotate each leaf value with the resolution layer it came
        from (Default, ProjectConfig, UserConfig, Environment,
        Parameter).

    .EXAMPLE
        Get-WamConfiguration

        Show the resolved configuration the next run would use.

    .EXAMPLE
        Get-WamConfiguration -ShowSource

        Show the resolved config with each value annotated by its
        resolution layer. Useful for debugging "why is this value
        what it is?" questions.

    .EXAMPLE
        Get-WamConfiguration -ConfigPath ./config.test.psd1 |
            ConvertTo-Json -Depth 5

        Render the resolved config as JSON for capture in a
        dry-run audit log.

    .OUTPUTS
        [hashtable] -- the merged configuration.

    .NOTES
        Read-only. Does not connect to SQL or AD; only reads
        configuration files and environment variables.

    .LINK
        Invoke-WamTrainingDisable

    .LINK
        about_WamTrainingDisable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string] $ConfigPath,

        [Parameter()]
        [string] $ConnectionString,

        [Parameter()]
        [switch] $ShowSource
    )

    throw [System.NotImplementedException]::new(
        'Get-WamConfiguration will be implemented in PR 6 (orchestrator wiring).'
    )
}
