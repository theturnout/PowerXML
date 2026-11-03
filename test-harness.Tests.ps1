BeforeAll {
	$script:Harness = Join-Path -Path $PSScriptRoot -ChildPath "test-harness.ps1"
	$script:PowerShellExecutable = (Get-Process -Id $PID).Path
}

Describe "Test harness configuration and cleanup" {
	BeforeEach {
		$script:OriginalTestCache = $env:POWERXML_TEST_CACHE
		$script:OriginalRealNetwork = $env:POWERXML_REAL_NETWORK
		$script:OriginalRepository = $env:polyglotpm
		$script:OriginalLocation = Get-Location
		$script:HarnessState = @{
			CapturedConfig = $null
			CapturedRepository = $null
			FakeResult = [PSCustomObject]@{
				Result = "Passed"
				TotalCount = 1
				PassedCount = 1
				FailedCount = 0
				FailedContainersCount = 0
				SkippedCount = 0
				NotRunCount = 0
			}
		}
		$script:Fixture = Join-Path -Path $TestDrive -ChildPath "fixture.Tests.ps1"
		Set-Content -LiteralPath $script:Fixture -Value 'Describe "fixture" { It "passes" { $true | Should -BeTrue } }'
		$script:HarnessParams = @{
			TestPath = @($script:Fixture)
			OutputPath = (Join-Path -Path $TestDrive -ChildPath "reports")
			NoCoverage = $true
		}
		Mock Invoke-Pester {
			$HarnessState.CapturedConfig = $Configuration
			$HarnessState.CapturedRepository = $env:POWERXML_TEST_CACHE
			return $HarnessState.FakeResult
		}
	}

	AfterEach {
		$env:POWERXML_TEST_CACHE = $script:OriginalTestCache
		$env:POWERXML_REAL_NETWORK = $script:OriginalRealNetwork
		$env:polyglotpm = $script:OriginalRepository
		Set-Location -LiteralPath $script:OriginalLocation.Path
	}

	It "selects the requested files and generates a report path" {
		& $script:Harness @script:HarnessParams | Out-Null
		$script:HarnessState.CapturedConfig.Run.Path.Value | Should -Contain $script:Fixture
		$script:HarnessState.CapturedConfig.TestResult.Enabled.Value | Should -BeTrue
		$script:HarnessState.CapturedConfig.TestResult.OutputPath.Value | Should -BeLike "*test-results.xml"
		$script:HarnessState.CapturedConfig.Run.Exit.Value | Should -BeFalse
		$script:HarnessState.CapturedConfig.CodeCoverage.Enabled.Value | Should -BeFalse
	}

	It "excludes integration files from the unit suite without hiding other tests" {
		$script:HarnessParams.Remove("TestPath")
		$script:HarnessParams.Suite = "Unit"
		& $script:Harness @script:HarnessParams | Out-Null
		$names = @($script:HarnessState.CapturedConfig.Run.Path.Value | ForEach-Object { Split-Path -Path $_ -Leaf })
		$names | Should -Contain "utilities.tests.ps1"
		$names | Should -Contain "nuget.tests.ps1"
		$names | Should -Contain "test-harness.Tests.ps1"
		$names | Should -Not -Contain "powerxml.tests.ps1"
		$names | Should -Not -Contain "polyglot.integration.tests.ps1"
	}

	It "selects both integration test files" {
		$script:HarnessParams.Remove("TestPath")
		$script:HarnessParams.Suite = "Integration"
		& $script:Harness @script:HarnessParams | Out-Null
		$names = @($script:HarnessState.CapturedConfig.Run.Path.Value | ForEach-Object { Split-Path -Path $_ -Leaf })
		$names | Should -HaveCount 2
		$names | Should -Contain "powerxml.tests.ps1"
		$names | Should -Contain "polyglot.integration.tests.ps1"
	}

	It "includes both suites by default and scopes coverage to module scripts" {
		$script:HarnessParams.Remove("TestPath")
		$script:HarnessParams.Remove("NoCoverage")
		& $script:Harness @script:HarnessParams | Out-Null
		$names = @($script:HarnessState.CapturedConfig.Run.Path.Value | ForEach-Object { Split-Path -Path $_ -Leaf })
		$names | Should -Contain "powerxml.tests.ps1"
		$names | Should -Contain "utilities.tests.ps1"
		$script:HarnessState.CapturedConfig.CodeCoverage.Enabled.Value | Should -BeTrue
		$coveragePaths = @($script:HarnessState.CapturedConfig.CodeCoverage.Path.Value)
		@($coveragePaths | Where-Object { $_ -like "*.Tests.ps1" -or $_ -like "*\dotnet\*" }) | Should -HaveCount 0
		$coveragePaths | Should -Contain (Join-Path -Path $PSScriptRoot -ChildPath "powerxml.ps1")
	}

	It "forwards the full-name filter" {
		$script:HarnessParams.TestName = @("*MIME*", "*namespace*")
		& $script:Harness @script:HarnessParams | Out-Null
		$script:HarnessState.CapturedConfig.Filter.FullName.Value | Should -Be @("*MIME*", "*namespace*")
	}

	It "throws when assertions fail" {
		$script:HarnessState.FakeResult.Result = "Failed"
		$script:HarnessState.FakeResult.FailedCount = 1
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*1 failed tests*"
	}

	It "throws on failed discovery containers even without failed assertions" {
		$script:HarnessState.FakeResult.Result = "Failed"
		$script:HarnessState.FakeResult.FailedContainersCount = 1
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*1 failed containers*"
	}

	It "rejects a filter that runs no tests" {
		$script:HarnessState.FakeResult.TotalCount = 0
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*No tests ran*"
	}

	It "rejects discovered tests that are all excluded by the filter" {
		$script:HarnessState.FakeResult.NotRunCount = 1
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*No tests ran*"
	}

	It "rejects a selection without test files" {
		$emptyDirectory = Join-Path -Path $TestDrive -ChildPath "empty"
		New-Item -Path $emptyDirectory -ItemType Directory | Out-Null
		$script:HarnessParams.TestPath = @($emptyDirectory)
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*No test files found*"
		Should -Invoke Invoke-Pester -Times 0
	}

	It "restores environment and location and removes its fresh cache after a failure" {
		$env:POWERXML_TEST_CACHE = "previous-cache"
		$env:POWERXML_REAL_NETWORK = "previous-network"
		$env:polyglotpm = "previous-repository"
		$script:HarnessParams.NoCache = $true
		$script:HarnessParams.RealNetwork = $true
		$script:HarnessState.FakeResult.Result = "Failed"
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*Pester failed*"
		$env:POWERXML_TEST_CACHE | Should -Be "previous-cache"
		$env:POWERXML_REAL_NETWORK | Should -Be "previous-network"
		$env:polyglotpm | Should -Be "previous-repository"
		(Get-Location).Path | Should -Be $script:OriginalLocation.Path
		$script:HarnessState.CapturedRepository | Should -Not -Be "previous-cache"
		Test-Path -LiteralPath $script:HarnessState.CapturedRepository | Should -BeFalse
	}

	It "restores state when the runner throws" {
		Mock Invoke-Pester {
			$env:polyglotpm = "changed-by-tests"
			throw "Runner failure"
		}
		{ & $script:Harness @script:HarnessParams } | Should -Throw "*Runner failure*"
		$env:polyglotpm | Should -Be $script:OriginalRepository
		(Get-Location).Path | Should -Be $script:OriginalLocation.Path
	}
}

Describe "Test harness process exit codes" {
	It "returns the correct process status and writes results for <Case>" -ForEach @(
		@{ Case = "passing assertions"; Assertion = '$true | Should -BeTrue'; TestName = $null; ExpectedExitCode = 0 },
		@{ Case = "failing assertions"; Assertion = '$false | Should -BeTrue'; TestName = $null; ExpectedExitCode = 1 },
		@{ Case = "an unmatched filter"; Assertion = '$true | Should -BeTrue'; TestName = "does-not-exist"; ExpectedExitCode = 1 }
	) {
		$fixture = Join-Path -Path $TestDrive -ChildPath "process.Tests.ps1"
		$reports = Join-Path -Path $TestDrive -ChildPath "process reports"
		Set-Content -LiteralPath $fixture -Value "Describe `"process`" { It `"asserts`" { $Assertion } }"
		$arguments = @("-NoProfile", "-NonInteractive", "-File", $script:Harness, "-TestPath", $fixture, "-OutputPath", $reports, "-NoCoverage")
		if ($TestName) {
			$arguments += @("-TestName", $TestName)
		}
		$output = & $script:PowerShellExecutable @arguments 2>&1
		$LASTEXITCODE | Should -Be $ExpectedExitCode -Because ($output -join "`n")
		Test-Path -LiteralPath (Join-Path -Path $reports -ChildPath "test-results.xml") | Should -BeTrue
	}
}
