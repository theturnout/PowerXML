<#
.SYNOPSIS
Runs PowerXML's Pester tests and fails when tests or discovery fail.
.PARAMETER TestPath
Optional test files or directories. Defaults to test files in the module root and polyglot.
.PARAMETER ModulePath
The module source directory. Defaults to this script's directory.
.PARAMETER OutputPath
Directory for test results and coverage reports.
.PARAMETER Suite
All runs every test. Unit excludes the processor/network integration files.
Integration runs powerxml.tests.ps1 and *.integration.tests.ps1.
.PARAMETER NoCache
Uses a fresh, invocation-owned dependency repository and removes it after the run.
.PARAMETER NoCoverage
Disables code coverage collection.
.PARAMETER TestName
Filters tests by full name using wildcard patterns.
.PARAMETER RealNetwork
Sets POWERXML_REAL_NETWORK for the run. Suite selection determines which files run.
#>
[CmdletBinding()]
param(
	[string[]]$TestPath,
	[string]$ModulePath,
	[string]$OutputPath,
	[ValidateSet("All", "Unit", "Integration")]
	[string]$Suite = "All",
	[string[]]$TestName,
	[switch]$NoCache,
	[switch]$NoCoverage,
	[switch]$RealNetwork
)

if (-not $PSBoundParameters.ContainsKey("ModulePath")) {
	$ModulePath = $PSScriptRoot
}
if (-not $PSBoundParameters.ContainsKey("OutputPath")) {
	$OutputPath = Join-Path -Path $PSScriptRoot -ChildPath "test_out"
}

$previousTestCache = $env:POWERXML_TEST_CACHE
$previousRealNetwork = $env:POWERXML_REAL_NETWORK
$previousRepository = $env:polyglotpm
$temporaryRepository = $null
$locationChanged = $false

try {
	$importParams = @{
		Name = "Pester"
		MinimumVersion = "5.7.1"
		ErrorAction = "Stop"
	}
	Import-Module @importParams
	$moduleDirectory = (Resolve-Path -LiteralPath $ModulePath -ErrorAction Stop).Path
	if (-not (Test-Path -LiteralPath $moduleDirectory -PathType Container)) {
		throw "ModulePath must be a directory: '$ModulePath'."
	}

	$testParams = @{
		Path = if ($TestPath) { $TestPath } else {
			@(
				(Join-Path -Path $moduleDirectory -ChildPath "*.ps1"),
				(Join-Path -Path $moduleDirectory -ChildPath "polyglot\*.ps1")
			)
		}
		File = $true
		ErrorAction = "Stop"
	}
	if ($TestPath) {
		$testParams.Recurse = $true
		$testParams.Filter = "*.ps1"
	}
	$testFiles = @(Get-ChildItem @testParams | Where-Object { $_.Name -like "*.Tests.ps1" } | Sort-Object -Property FullName -Unique)
	if ($Suite -ne "All") {
		$testFiles = @($testFiles | Where-Object {
			$isIntegration = $_.Name -eq "powerxml.tests.ps1" -or $_.Name -like "*.integration.tests.ps1"
			if ($Suite -eq "Integration") { $isIntegration } else { -not $isIntegration }
		})
	}
	if ($testFiles.Count -eq 0) {
		throw "No test files found for suite '$Suite'."
	}

	$outputParams = @{
		ItemType = "Directory"
		Path = $OutputPath
		Force = $true
		ErrorAction = "Stop"
	}
	New-Item @outputParams | Out-Null
	$outputDirectory = (Resolve-Path -LiteralPath $OutputPath -ErrorAction Stop).Path

	if ($NoCache) {
		$temporaryRepository = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "powerxml-test-deps-$(New-Guid)"
		$repositoryParams = @{
			ItemType = "Directory"
			Path = $temporaryRepository
			ErrorAction = "Stop"
		}
		New-Item @repositoryParams | Out-Null
		$env:POWERXML_TEST_CACHE = $temporaryRepository
	}
	$env:POWERXML_REAL_NETWORK = if ($RealNetwork) { "1" } else { $null }

	$config = New-PesterConfiguration
	$config.Run.Path = @($testFiles.FullName)
	$config.Run.PassThru = $true
	$config.Run.Exit = $false
	$config.Output.Verbosity = "Detailed"
	$config.TestResult.Enabled = $true
	$config.TestResult.OutputPath = Join-Path -Path $outputDirectory -ChildPath "test-results.xml"
	$config.CodeCoverage.Enabled = -not $NoCoverage
	if (-not $NoCoverage) {
		$sourceParams = @{
			Path = @(
				(Join-Path -Path $moduleDirectory -ChildPath "*.ps1"),
				(Join-Path -Path $moduleDirectory -ChildPath "*.psm1"),
				(Join-Path -Path $moduleDirectory -ChildPath "polyglot\*.ps1"),
				(Join-Path -Path $moduleDirectory -ChildPath "polyglot\*.psm1")
			)
			File = $true
			ErrorAction = "Stop"
		}
		$sourceFiles = @(Get-ChildItem @sourceParams | Where-Object { $_.Name -notlike "*.Tests.ps1" })
		$config.CodeCoverage.Path = @($sourceFiles.FullName)
		$config.CodeCoverage.UseBreakpoints = $false
		$config.CodeCoverage.OutputPath = Join-Path -Path $outputDirectory -ChildPath "coverage.xml"
	}
	if ($TestName) {
		$config.Filter.FullName = $TestName
	}

	Push-Location -LiteralPath $moduleDirectory -ErrorAction Stop
	$locationChanged = $true
	$results = Invoke-Pester -Configuration $config -ErrorAction Stop
	$results | Format-Table -Property Result, TotalCount, PassedCount, FailedCount, SkippedCount -AutoSize
	if ($results.TotalCount -eq 0 -or $results.TotalCount -eq $results.NotRunCount) {
		throw "No tests ran for suite '$Suite'. Check the test-name filter and discovery results."
	}
	if ($results.Result -ne "Passed") {
		throw "Pester failed: $($results.FailedCount) failed tests and $($results.FailedContainersCount) failed containers."
	}
}
catch {
	Write-Error -Message "PowerXML test harness failed: $($_.Exception.Message)" -ErrorAction Continue
	throw
}
finally {
	$env:POWERXML_TEST_CACHE = $previousTestCache
	$env:POWERXML_REAL_NETWORK = $previousRealNetwork
	$env:polyglotpm = $previousRepository
	if ($locationChanged) {
		Pop-Location -ErrorAction Stop
	}
	if ($temporaryRepository -and (Test-Path -LiteralPath $temporaryRepository)) {
		$cleanupParams = @{
			LiteralPath = $temporaryRepository
			Recurse = $true
			Force = $true
			ErrorAction = "Stop"
		}
		Remove-Item @cleanupParams
	}
}
