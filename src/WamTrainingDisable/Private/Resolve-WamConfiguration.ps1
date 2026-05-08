# =============================================================================
# Private/Resolve-WamConfiguration.ps1
# =============================================================================
# Walks the configuration resolution stack in precedence order and
# returns the merged hashtable.
#
# Layers (lowest precedence first):
#
#   1. Shipped defaults: WamTrainingDisable.config.psd1 next to the
#      module manifest.
#   2. Project config: -ConfigPath (an explicit path supplied by the
#      caller).
#   3. User config:
#        $env:LOCALAPPDATA\WamTrainingDisable\config.psd1   (Windows,
#                                                            and any
#                                                            platform
#                                                            with the
#                                                            env var
#                                                            populated)
#        $HOME/.config/WamTrainingDisable/config.psd1       (Linux/macOS
#                                                            fallback,
#                                                            XDG path)
#   4. Environment variables (WAM_* prefix, see the override map below)
#   5. -ParameterOverrides (highest precedence; supplied by the calling
#      Public cmdlet's parameter-bound values)
#
# Merging is DEEP, key-by-key, including nested hashtables. A higher
# layer's value wins over a lower layer's value for the same key only;
# unspecified keys fall through.
# =============================================================================

function Resolve-WamConfiguration {
    <#
    .SYNOPSIS
        Resolve the WAM configuration from the layered stack.

    .DESCRIPTION
        Internal helper. Reads files and env vars but does no other
        I/O. Used by every Public cmdlet that needs configuration; the
        per-cmdlet param block carries the parameter-layer overrides
        which are passed through here.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string] $ConfigPath,

        [Parameter()]
        [hashtable] $ParameterOverrides = @{}
    )

    # -------------------------------------------------------------------------
    # Nested helper: deep-merge $Source onto $Target.
    # -------------------------------------------------------------------------
    # We define this nested rather than as a separate Private/* file because
    # it is only called from this function and the recursion is short
    # enough that a one-file footprint is easier to follow than a
    # cross-file jump. PR 4's unit tests for this function exercise the
    # merge semantics through Resolve-WamConfiguration's public surface.
    #
    # Both sides are mutated -- specifically, $Target accumulates the
    # merge result. The caller passes in a fresh hashtable each time
    # (loaded from disk) so there is no cross-call state.
    # -------------------------------------------------------------------------
    function Merge-WamConfigLayer {
        param(
            [hashtable] $Target,
            [hashtable] $Source
        )

        foreach ($key in @($Source.Keys)) {
            $sourceValue = $Source[$key]
            $targetHasKey = $Target.ContainsKey($key)
            $targetIsHashtable = $targetHasKey -and ($Target[$key] -is [hashtable])
            $sourceIsHashtable = $sourceValue -is [hashtable]

            if ($targetIsHashtable -and $sourceIsHashtable) {
                # Both sides are nested tables; recurse.
                Merge-WamConfigLayer -Target $Target[$key] -Source $sourceValue
            }
            else {
                # Source wins. Replace whatever was at the key (or
                # create the key if it did not exist on the target).
                $Target[$key] = $sourceValue
            }
        }
    }

    # -------------------------------------------------------------------------
    # Layer 1: shipped defaults.
    # -------------------------------------------------------------------------
    # Every call re-reads the file, so a fresh hashtable is allocated
    # per call. This sidesteps the cross-call mutation hazard of
    # treating the imported defaults as a singleton (which would be
    # shared mutable state between Public cmdlets).
    #
    # The relative path resolves the .config.psd1 next to the module
    # manifest. We assume Resolve-WamConfiguration always loads from
    # under src/WamTrainingDisable/Private/, so '..' takes us to the
    # module root.
    # -------------------------------------------------------------------------
    $defaultPath = Join-Path -Path $PSScriptRoot -ChildPath '..'
    $defaultPath = Join-Path -Path $defaultPath -ChildPath 'WamTrainingDisable.config.psd1'
    $defaultPath = (Resolve-Path -Path $defaultPath).Path

    $config = Import-PowerShellDataFile -Path $defaultPath

    # -------------------------------------------------------------------------
    # Layer 2: project config (-ConfigPath).
    # -------------------------------------------------------------------------
    if ($ConfigPath) {
        if (-not (Test-Path -Path $ConfigPath)) {
            # Loud failure on a typo. Silently falling back to defaults
            # would mask "wait, why is it using the prod connection
            # string?" debugging sessions.
            throw "ConfigPath '$ConfigPath' does not exist."
        }

        $projectConfig = Import-PowerShellDataFile -Path $ConfigPath
        Merge-WamConfigLayer -Target $config -Source $projectConfig
    }

    # -------------------------------------------------------------------------
    # Layer 3: user config.
    # -------------------------------------------------------------------------
    # Path resolution: prefer $env:LOCALAPPDATA when populated (Windows
    # interactive sessions, Windows scheduled tasks), fall back to
    # $HOME/.config on Linux/macOS. We do NOT error on a missing user
    # config -- absence is the common case, not an exception.
    # -------------------------------------------------------------------------
    $userConfigPath = $null
    if ($env:LOCALAPPDATA) {
        $userConfigPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WamTrainingDisable'
        $userConfigPath = Join-Path -Path $userConfigPath -ChildPath 'config.psd1'
    }
    elseif ($env:HOME) {
        $userConfigPath = Join-Path -Path $env:HOME -ChildPath '.config'
        $userConfigPath = Join-Path -Path $userConfigPath -ChildPath 'WamTrainingDisable'
        $userConfigPath = Join-Path -Path $userConfigPath -ChildPath 'config.psd1'
    }

    if ($userConfigPath -and (Test-Path -Path $userConfigPath)) {
        $userConfig = Import-PowerShellDataFile -Path $userConfigPath
        Merge-WamConfigLayer -Target $config -Source $userConfig
    }

    # -------------------------------------------------------------------------
    # Layer 4: environment variables.
    # -------------------------------------------------------------------------
    # Each entry in $envOverrideMap maps a WAM_* env var to a path
    # within the config hashtable plus a coercion type. We build a
    # deeply-nested override hashtable, then merge it on top.
    #
    # The coercion is intentional: env vars are always strings, but
    # the typed config keys (CommandTimeoutSeconds is [int],
    # LegacyTimestamp is [bool]) need the right type for the
    # downstream consumers. A typo'd env var (e.g.
    # WAM_LEGACY_TIMESTAMP=truee) silently coerces to $false; that's a
    # known sharp edge that we accept rather than introducing a
    # validation pass.
    # -------------------------------------------------------------------------
    $envOverrideMap = @(
        @{ EnvVar = 'WAM_SQL_CONNECTION';        Path = @('Sql', 'ConnectionString');        Type = 'string' }
        @{ EnvVar = 'WAM_SQL_STORED_PROCEDURE';  Path = @('Sql', 'StoredProcedure');          Type = 'string' }
        @{ EnvVar = 'WAM_SQL_USERNAME_COLUMN';   Path = @('Sql', 'UsernameColumn');           Type = 'string' }
        @{ EnvVar = 'WAM_SQL_TIMEOUT_SECONDS';   Path = @('Sql', 'CommandTimeoutSeconds');    Type = 'int'    }
        @{ EnvVar = 'WAM_GRACE_PERIOD_DAYS';     Path = @('Policy', 'GracePeriodDays');       Type = 'int'    }
        @{ EnvVar = 'WAM_LOG_DIR';               Path = @('Logging', 'Directory');            Type = 'string' }
        @{ EnvVar = 'WAM_LOG_ENCODING';          Path = @('Logging', 'Encoding');             Type = 'string' }
        @{ EnvVar = 'WAM_LEGACY_TIMESTAMP';      Path = @('Logging', 'LegacyTimestamp');      Type = 'bool'   }
        @{ EnvVar = 'WAM_TIMESTAMP_FORMAT';      Path = @('Logging', 'TimestampFormat');      Type = 'string' }
        @{ EnvVar = 'WAM_VIP_DN_PATTERN';        Path = @('Logging', 'Channels', 'VipDistinguishedNamePattern'); Type = 'string' }
    )

    $envOverrides = @{}
    foreach ($entry in $envOverrideMap) {
        $rawValue = [System.Environment]::GetEnvironmentVariable($entry.EnvVar)
        if ([string]::IsNullOrEmpty($rawValue)) {
            continue
        }

        $coercedValue = switch ($entry.Type) {
            'int' { [int] $rawValue }
            'bool' {
                # Accept '1', 'true', 'yes', 'on' (case-insensitive) as $true;
                # everything else is $false. Matches the convention used in
                # most other shells and Docker.
                $rawValue -match '^(1|true|yes|on)$'
            }
            default { $rawValue }
        }

        # Walk the path, creating nested hashtables as we go, until we
        # land at the leaf and assign the coerced value.
        $cursor = $envOverrides
        for ($i = 0; $i -lt $entry.Path.Length - 1; $i++) {
            $segment = $entry.Path[$i]
            if (-not $cursor.ContainsKey($segment)) {
                $cursor[$segment] = @{}
            }
            $cursor = $cursor[$segment]
        }
        $cursor[$entry.Path[-1]] = $coercedValue
    }

    if ($envOverrides.Count -gt 0) {
        Merge-WamConfigLayer -Target $config -Source $envOverrides
    }

    # -------------------------------------------------------------------------
    # Layer 5: parameter overrides (highest precedence).
    # -------------------------------------------------------------------------
    if ($ParameterOverrides.Count -gt 0) {
        Merge-WamConfigLayer -Target $config -Source $ParameterOverrides
    }

    return $config
}
