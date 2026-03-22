# Modern Pester 5 Test Harness for PowerXML PowerShell Module
# Runs all tests, generates code coverage, and prints a summary by file
<#
.PARAMETER TestPath
    Path to the test files. Default is current directory.
.PARAMETER ModulePath
    Path to the module source code for code coverage analysis. Default is current directory.
.PARAMETER OutputPath
    Path to save the test results and code coverage report. Default is "./test_out".
.PARAMETER NoCache
    If set, will not use any cached PolyglotPM repositories and will always fetch from source. Avoid this unless you 
    want to test package retrieve logic or ensure you have the latest dependencies.
.PARAMETER NoCoverage
    If set, will disable code coverage collection.
.PARAMETER TestName
    Filter which tests to run by full name (supports wildcard patterns). For example, '*MIME*' runs only tests with MIME in the name.
#>
param(
    [string]$TestPath = "./",
    [string]$ModulePath = "./",
    [string]$OutputPath = "./test_out",
    [string[]]$TestName,
    [switch]$NoCache,
    [switch]$NoCoverage,
    [switch]$RealNetwork
)
# Save previous environment variable values
$prevTestCache = $env:POWERXML_TEST_CACHE
$prevRealNetwork = $env:POWERXML_REAL_NETWORK
if ($NoCache) {
    $env:POWERXML_TEST_CACHE = "TestDrive:/"
}
if ($RealNetwork) {
    $env:POWERXML_REAL_NETWORK = "1"
}
else {
    $env:POWERXML_REAL_NETWORK = $null
}
# Ensure Pester 5 is loaded
Import-Module Pester -Force
$VerbosePreference = 'SilentlyContinue'


# Configure Pester run
$pesterConfig = @{
    Run          = @{ Path = $TestPath; PassThru = $true }
    CodeCoverage = @{ Enabled = -not $NoCoverage; Path = $ModulePath; UseBreakpoints = $false; OutputPath = "$OutputPath/coverage.xml" }
    Output       = @{ Verbosity = 'Detailed' }
    TestResult   = @{ Enabled = $true; OutputPath = "$OutputPath/test-results.xml" }
    Should       = @{ ErrorAction = 'Continue' }
}
if ($TestName) {
    $pesterConfig.Filter = @{ FullName = $TestName }
}
$config = New-PesterConfiguration -Hashtable $pesterConfig

# Use Pester's native timing feature if available, otherwise use a stopwatch
$pesterSupportsTiming = ($config.PSObject.Properties.Name -contains 'Timing')
if ($pesterSupportsTiming) {
    $config.Timing = @{ Enabled = $true }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = Invoke-Pester -Configuration $config
$stopwatch.Stop()

Write-Host "Test run complete. Results:"
$results | Format-Table -AutoSize

# Print timing information
if ($pesterSupportsTiming -and $results.Timing) {
    $duration = $results.Timing.Duration
    Write-Host ("Test duration (Pester native): {0}" -f $duration)
}
else {
    Write-Host ("Test duration: {0}" -f $stopwatch.Elapsed)
}
$env:POWERXML_TEST_CACHE = $prevTestCache
$env:POWERXML_REAL_NETWORK = $prevRealNetwork