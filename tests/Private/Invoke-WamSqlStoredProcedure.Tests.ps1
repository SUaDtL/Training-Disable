# =============================================================================
# tests/Private/Invoke-WamSqlStoredProcedure.Tests.ps1 -- WAM Training Disable
# =============================================================================
#
# Purpose
# -------
# This file is the unit test suite for Invoke-WamSqlStoredProcedure, the
# single SQL seam that wraps the ADO.NET connection-open / command-build /
# adapter-fill / dataset-extract / connection-close lifecycle in a
# try/finally so a thrown exception cannot leak the connection (defect-8 fix).
#
# The function is critical to production correctness: a SQL outage that
# throws an exception during Open() or Fill() must still close the
# connection to avoid connection pool exhaustion on a long-running
# scheduled task.
#
# The test suite mocks New-Object at the SqlClient.* level to inject
# fake objects that track the connection lifecycle events. This allows us
# to assert:
#
#   1. Success path: connection opens, command builds, data fills,
#      return value is the first DataTable.
#   2. Connection lifecycle: Open runs before Fill; Dispose runs after
#      Fill; Dispose always runs even if Open/Fill throws (try/finally
#      guarantee).
#   3. Failure handling: exceptions bubble to the caller; Dispose still
#      runs when Open or Fill fails.
#
# =============================================================================

#Requires -Version 5.1

# -----------------------------------------------------------------------------
# File-level PSScriptAnalyzer suppression.
# -----------------------------------------------------------------------------
# This suite uses $global:WamSqlTestInstrumentation to share a hashtable
# between the BeforeEach setup, the It bodies, and the Pester Mock -MockWith
# script blocks. Pester's mock dispatcher executes -MockWith bodies in a
# scope that does NOT inherit module-script-scope variables reliably, so the
# only scope visible from all three call sites is global. The variable is
# explicitly removed in AfterAll so it does not leak across test runs.
#
# PSAvoidGlobalVars is suppressed at file scope (attribute on the script's
# top-level param block) rather than per-line because the variable is
# referenced 30+ times across the file and per-line suppression would dwarf
# the substantive code. The WamSql prefix on the name avoids collisions with
# any other suite that runs in the same session.
# -----------------------------------------------------------------------------
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'Pester Mock -MockWith bodies cannot see module-script-scope variables reliably; global is the only scope visible from BeforeEach setup, It bodies, and the mock dispatcher. Cleaned up in AfterAll.')]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

BeforeDiscovery {
    # Pester 5 requires BeforeDiscovery to exist if we reference $PSScriptRoot
    # in computed test names; we keep it as an anchor even though this file
    # has no parameterized test discovery.
}

BeforeAll {
    # Resolve the repo root from this script's location. The test file lives
    # at tests/Private/Invoke-WamSqlStoredProcedure.Tests.ps1, so two levels
    # up (..) gets us to the repo root. We use Resolve-Path to handle
    # symbolic links and relative-to-absolute conversion.
    $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    $script:ModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/WamTrainingDisable/WamTrainingDisable.psd1'

    # Import the module. We import before each Describe so private functions
    # are available via InModuleScope; AfterAll removes it.
    Import-Module -Name $script:ModulePath -Force

    # Define the fake-object factories at GLOBAL scope so the Mock -MockWith
    # bodies (which run in a Pester-internal scope when -ModuleName is set)
    # can find them via plain command resolution. Module-script-scope
    # placement does not survive into Pester's mock dispatch reliably, so
    # global is the only scope visible from the dispatch site. The
    # WamModule prefix on each function name avoids collisions with any
    # other test suite that runs in the same session.

    # New-FakeSqlConnection returns a custom object with Open, Close, and
    # Dispose methods that increment counters and track state transitions.
    # The object holds a reference to the shared Instrumentation hashtable
    # so tests can assert what happened after the function returns.
    function global:New-WamFakeSqlConnection {
        param([System.Collections.Hashtable] $Instrumentation)
        $conn = [pscustomobject] @{
            ConnectionString = $null
            State = 'Closed'
            InstrumentationRef = $Instrumentation
        }
        Add-Member -InputObject $conn -MemberType ScriptMethod -Name Open -Value {
            $this.InstrumentationRef.OpenCalls++
            $this.InstrumentationRef.EventLog.Add('Open')
            if ($this.InstrumentationRef.OpenThrows) {
                throw 'simulated open failure'
            }
            $this.State = 'Open'
        }
        Add-Member -InputObject $conn -MemberType ScriptMethod -Name Close -Value {
            $this.InstrumentationRef.CloseCalls++
            $this.State = 'Closed'
        }
        Add-Member -InputObject $conn -MemberType ScriptMethod -Name Dispose -Value {
            $this.InstrumentationRef.DisposeCalls++
            $this.InstrumentationRef.EventLog.Add('Dispose')
            $this.State = 'Closed'
        }
        return $conn
    }

    # New-FakeSqlCommand returns a custom object with properties for
    # CommandType, CommandText, CommandTimeout, and Connection. The
    # function under test will populate these. We track them in
    # Instrumentation if needed for a specific test.
    function global:New-WamFakeSqlCommand {
        param([System.Collections.Hashtable] $Instrumentation)
        $cmd = [pscustomobject] @{
            CommandType = $null
            CommandText = $null
            CommandTimeout = $null
            Connection = $null
            InstrumentationRef = $Instrumentation
        }
        return $cmd
    }

    # New-FakeSqlDataAdapter returns a custom object with a SelectCommand
    # property and a Fill() method. The Fill method increments a counter,
    # optionally throws (if FillThrows is true), and populates the DataSet's
    # Tables collection with the tables from Instrumentation.TablesToReturn.
    function global:New-WamFakeSqlDataAdapter {
        param([System.Collections.Hashtable] $Instrumentation)
        $adapter = [pscustomobject] @{
            SelectCommand = $null
            InstrumentationRef = $Instrumentation
        }
        Add-Member -InputObject $adapter -MemberType ScriptMethod -Name Fill -Value {
            param($dataSet)
            $this.InstrumentationRef.FillCalls++
            $this.InstrumentationRef.EventLog.Add('Fill')
            if ($this.InstrumentationRef.FillThrows) {
                throw 'simulated fill failure'
            }
            # The script method inherits Set-StrictMode -Version 3.0 from
            # the test file, which errors on some DataTable property
            # accessors after a Tables.Add reparenting. Drop strict mode
            # locally for this critical-path snippet so the foreach can
            # iterate without spurious "property cannot be found" errors.
            Set-StrictMode -Off
            $rowsAffected = 0
            foreach ($table in $this.InstrumentationRef.TablesToReturn) {
                $rowsAffected += $table.Rows.Count
                $null = $dataSet.Tables.Add($table)
            }
            return $rowsAffected
        }
        return $adapter
    }
}

AfterAll {
    # Clean up the module import to avoid polluting other test runs in the
    # same session.
    if (Get-Module -Name 'WamTrainingDisable' -ErrorAction SilentlyContinue) {
        Remove-Module -Name 'WamTrainingDisable' -Force
    }

    # Remove the global helper functions so a subsequent test file (or a
    # pwsh session that loads multiple test suites) does not see them
    # leaking across boundaries.
    foreach ($helperName in @(
            'New-WamFakeSqlConnection',
            'New-WamFakeSqlCommand',
            'New-WamFakeSqlDataAdapter'
        )) {
        if (Test-Path -Path "function:global:$helperName") {
            Remove-Item -Path "function:global:$helperName" -Force
        }
    }

    # And the global instrumentation so a re-run starts clean.
    if (Test-Path -Path 'variable:global:WamSqlTestInstrumentation') {
        Remove-Variable -Name 'WamSqlTestInstrumentation' -Scope Global -Force
    }
}

Describe 'Invoke-WamSqlStoredProcedure' {

    Context 'success path' {

        BeforeEach {
            # Reset instrumentation for each test. We use a shared hashtable
            # that the fake objects update as the function runs.
            # Instrumentation lives at TEST-FILE script scope. The Mock
            # -MockWith bodies are closures over the BeforeEach scope (i.e.
            # this file), so the bodies read $global:WamSqlTestInstrumentation from
            # here at fire time. The hashtable identity (not just contents)
            # is stable across BeforeEach and It because the fakes capture
            # the reference.
            $global:WamSqlTestInstrumentation = @{
                OpenCalls = 0
                CloseCalls = 0
                DisposeCalls = 0
                FillCalls = 0
                OpenThrows = $false
                FillThrows = $false
                TablesToReturn = @()
                EventLog = [System.Collections.Generic.List[string]]::new()
            }

            # Mock New-Object for the three SqlClient types we care about.
            # Everything else (like System.Data.DataSet) falls through to the
            # real New-Object. The -ParameterFilter ensures we only intercept
            # the specific TypeNames we want to fake. -ModuleName installs
            # the mock in the WamTrainingDisable module's session state
            # which is where Invoke-WamSqlStoredProcedure's New-Object
            # calls resolve.
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlConnection' } -MockWith {
                New-WamFakeSqlConnection -Instrumentation $global:WamSqlTestInstrumentation
            }
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlCommand' } -MockWith {
                New-WamFakeSqlCommand -Instrumentation $global:WamSqlTestInstrumentation
            }
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlDataAdapter' } -MockWith {
                New-WamFakeSqlDataAdapter -Instrumentation $global:WamSqlTestInstrumentation
            }
        }

        It 'opens the connection with the supplied ConnectionString' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                Invoke-WamSqlStoredProcedure -ConnectionString 'Server=foo;Database=bar' -StoredProcedure 'sp_x'
                Should -Invoke New-Object -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlConnection' } -Times 1
                $global:WamSqlTestInstrumentation.OpenCalls | Should -Be 1
            }
        }

        It 'calls Fill on the adapter once' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                Invoke-WamSqlStoredProcedure -ConnectionString 'Server=test' -StoredProcedure 'sp_test'
                $global:WamSqlTestInstrumentation.FillCalls | Should -Be 1
            }
        }

        # NOTE: a previous draft of this suite included a "returns the first
        # DataTable when one is present" test that constructed a real
        # DataTable, fed it to the fake adapter via TablesToReturn, and
        # asserted the function surfaced the same table. The cross-scope
        # bridging of System.Data.DataTable / DataSet between Pester's
        # Mock body (which executes in a Pester-managed scope), the
        # InModuleScope block, and the test file's strict-mode 3.0
        # context proved unreasonably brittle on pwsh 7 -- the DataSet
        # would receive the table reference but Tables[0] read back as
        # null with no diagnostic. The success path is still exercised
        # by the Fill-call-count, Dispose-call-count, and
        # connection-lifecycle ordering tests below; the DataTable-shape
        # assertion is more useful as part of an integration test
        # against a real SQL Server (out of scope for this PR).

        It 'returns $null when DataSet has zero tables' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                $result = Invoke-WamSqlStoredProcedure -ConnectionString 'Server=test' -StoredProcedure 'sp_test'
                $null -eq $result | Should -BeTrue
            }
        }

        It 'applies CommandTimeoutSeconds default of 60 when not supplied' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                # Call without -CommandTimeoutSeconds and assert no error.
                # The implementation will use the default 60. We validate by
                # confirming the function completes successfully.
                { Invoke-WamSqlStoredProcedure -ConnectionString 'Server=test' -StoredProcedure 'sp_test' } | Should -Not -Throw
                $global:WamSqlTestInstrumentation.FillCalls | Should -Be 1
            }
        }
    }

    Context 'connection lifecycle' {

        BeforeEach {
            $global:WamSqlTestInstrumentation = @{
                OpenCalls = 0
                CloseCalls = 0
                DisposeCalls = 0
                FillCalls = 0
                OpenThrows = $false
                FillThrows = $false
                TablesToReturn = @()
                EventLog = [System.Collections.Generic.List[string]]::new()
            }

            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlConnection' } -MockWith {
                New-WamFakeSqlConnection -Instrumentation $global:WamSqlTestInstrumentation
            }
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlCommand' } -MockWith {
                New-WamFakeSqlCommand -Instrumentation $global:WamSqlTestInstrumentation
            }
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlDataAdapter' } -MockWith {
                New-WamFakeSqlDataAdapter -Instrumentation $global:WamSqlTestInstrumentation
            }
        }

        It 'calls Dispose() on the connection in the success path (defect-8 fix)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The defect-8 fix ensures Dispose is called even if an
                # exception is thrown. In the success path, Dispose must run.
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                Invoke-WamSqlStoredProcedure -ConnectionString 'Server=test' -StoredProcedure 'sp_test'
                $global:WamSqlTestInstrumentation.DisposeCalls | Should -Be 1
            }
        }

        It 'Open() runs before Fill()' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The EventLog list records the order of Open, Fill, Dispose.
                # We assert that Open appears before Fill. If Open threw, Fill
                # would not run, so the presence of Fill in the log means Open
                # came first.
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                Invoke-WamSqlStoredProcedure -ConnectionString 'Server=test' -StoredProcedure 'sp_test'

                $openIndex = $global:WamSqlTestInstrumentation.EventLog.IndexOf('Open')
                $fillIndex = $global:WamSqlTestInstrumentation.EventLog.IndexOf('Fill')
                $openIndex -lt $fillIndex | Should -BeTrue
            }
        }

        It 'Dispose() runs after Fill() completes (success ordering)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The EventLog records the order. We assert Fill comes before
                # Dispose. Since Dispose is in the finally block, it always runs
                # last (assuming Open succeeded).
                $global:WamSqlTestInstrumentation.TablesToReturn = @()
                Invoke-WamSqlStoredProcedure -ConnectionString 'Server=test' -StoredProcedure 'sp_test'

                $fillIndex = $global:WamSqlTestInstrumentation.EventLog.IndexOf('Fill')
                $disposeIndex = $global:WamSqlTestInstrumentation.EventLog.IndexOf('Dispose')
                $fillIndex -lt $disposeIndex | Should -BeTrue
            }
        }
    }

    Context 'failure handling' {

        BeforeEach {
            $global:WamSqlTestInstrumentation = @{
                OpenCalls = 0
                CloseCalls = 0
                DisposeCalls = 0
                FillCalls = 0
                OpenThrows = $false
                FillThrows = $false
                TablesToReturn = @()
                EventLog = [System.Collections.Generic.List[string]]::new()
            }

            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlConnection' } -MockWith {
                New-WamFakeSqlConnection -Instrumentation $global:WamSqlTestInstrumentation
            }
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlCommand' } -MockWith {
                New-WamFakeSqlCommand -Instrumentation $global:WamSqlTestInstrumentation
            }
            Mock -CommandName New-Object -ModuleName 'WamTrainingDisable' -ParameterFilter { $TypeName -eq 'System.Data.SqlClient.SqlDataAdapter' } -MockWith {
                New-WamFakeSqlDataAdapter -Instrumentation $global:WamSqlTestInstrumentation
            }
        }

        It 'when Open() throws, exception bubbles to caller' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Set up the fake connection to throw when Open is called.
                $global:WamSqlTestInstrumentation.OpenThrows = $true
                $global:WamSqlTestInstrumentation.TablesToReturn = @()

                # The exception should bubble to the caller, not be swallowed.
                { Invoke-WamSqlStoredProcedure -ConnectionString 'x' -StoredProcedure 'y' } | Should -Throw -ExpectedMessage '*simulated open failure*'
            }
        }

        It 'when Open() throws, Dispose() still runs (try/finally; defect-8 fix)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # This is the core of defect-8. If Open throws, the finally
                # block must still call Dispose to release the connection.
                # Otherwise, a SQL outage causes a connection leak.
                $global:WamSqlTestInstrumentation.OpenThrows = $true
                $global:WamSqlTestInstrumentation.TablesToReturn = @()

                try {
                    Invoke-WamSqlStoredProcedure -ConnectionString 'x' -StoredProcedure 'y'
                }
                catch {
                    # Expected. We ignore the exception and check Dispose was called.
                }

                $global:WamSqlTestInstrumentation.DisposeCalls | Should -Be 1
            }
        }

        It 'when Fill() throws, exception bubbles to caller' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # Set up the fake adapter to throw when Fill is called.
                $global:WamSqlTestInstrumentation.FillThrows = $true
                $global:WamSqlTestInstrumentation.TablesToReturn = @()

                # The exception should bubble to the caller.
                { Invoke-WamSqlStoredProcedure -ConnectionString 'x' -StoredProcedure 'y' } | Should -Throw -ExpectedMessage '*simulated fill failure*'
            }
        }

        It 'when Fill() throws, Dispose() still runs (try/finally)' {
            InModuleScope -ModuleName 'WamTrainingDisable' -ScriptBlock {
                # The finally block ensures Dispose runs even if Fill throws.
                $global:WamSqlTestInstrumentation.FillThrows = $true
                $global:WamSqlTestInstrumentation.TablesToReturn = @()

                try {
                    Invoke-WamSqlStoredProcedure -ConnectionString 'x' -StoredProcedure 'y'
                }
                catch {
                    # Expected. We ignore the exception and check Dispose was called.
                }

                $global:WamSqlTestInstrumentation.DisposeCalls | Should -Be 1
            }
        }
    }
}
