# Modern Pester 5 Test Harness for PowerXML PowerShell Module
# Runs all tests, generates code coverage, and prints a summary by file

param(
    [string]$TestPath = "./",
    [string]$ModulePath = "./",
    [string]$CoverageOutput = "./coverage.json",
    [switch]$NoCache
)
if ($NoCache) {
    $env:POWERXML_TEST_CACHE = "TestDrive:/"
}
# Ensure Pester 5 is loaded
Import-Module Pester -Force
$VerbosePreference = 'SilentlyContinue'


# Configure Pester run
$config = New-PesterConfiguration -Hashtable @{
    Run          = @{ Path = $TestPath; PassThru = $true }
    CodeCoverage = @{ Enabled = $true; Path = $ModulePath }
    Output       = @{ Verbosity = 'Detailed' }
    TestResult   = @{ Enabled = $true }
}

Write-Host "Running Pester tests with code coverage..."

# Use Pester's native timing feature if available, otherwise use a stopwatch
$pesterSupportsTiming = ($config.PSObject.Properties.Name -contains 'Timing')
if ($pesterSupportsTiming) {
    $config.Timing = @{ Enabled = $true }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = Invoke-Pester -Configuration $config
$stopwatch.Stop()


# Save coverage report as JSON
if ($results.CodeCoverage) {
    $results.CodeCoverage | ConvertTo-Json -Depth 5 | Set-Content -Path $CoverageOutput
    $coverageData = $results.CodeCoverage.Files | Sort-Object PercentageCovered -Descending
    Write-Host "\nCode Coverage Overview by File:"
    $table = $coverageData | Select-Object @{Name = 'File'; Expression = { $_.Path } },
    @{Name = 'Covered'; Expression = { $_.Covered } },
    @{Name = 'Total'; Expression = { $_.Total } },
    @{Name = 'Percent'; Expression = { "{0:N2}%" -f $_.PercentageCovered } }
    $table | Format-Table -AutoSize
    $overall = $results.CodeCoverage
    Write-Host ("\nOverall Coverage: {0:N2}% ({1} of {2} commands covered)" -f $overall.PercentageCovered, $overall.Covered, $overall.Total)
    Write-Host "\nCoverage report saved to $CoverageOutput"
}
else {
    Write-Host "No code coverage data available."
}

Write-Host "\nTest run complete. Results:"
$results | Format-Table -AutoSize

# Print timing information
if ($pesterSupportsTiming -and $results.Timing) {
    $duration = $results.Timing.Duration
    Write-Host ("Test duration (Pester native): {0}" -f $duration)
}
else {
    Write-Host ("Test duration: {0}" -f $stopwatch.Elapsed)
}
