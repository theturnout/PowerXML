$dependencyCases = @(
	foreach ($testResult in @("success", "failure", "cancelled", "skipped")) {
		foreach ($packageResult in @("success", "failure", "cancelled", "skipped")) {
			@{
				TestResult = $testResult
				PackageResult = $packageResult
				ShouldPass = ($testResult -eq "success" -and $packageResult -eq "success")
			}
		}
	}
)

Describe "Required CI validation" -Skip:($PSVersionTable.PSEdition -eq "Desktop") {
	BeforeAll {
		$readParams = @{
			LiteralPath = "$PSScriptRoot\.github\workflows\ci.yml"
			Raw = $true
			ErrorAction = "Stop"
		}
		$workflow = Get-Content @readParams
		$pattern = "(?ms)^      - name: Require successful tests and package validation\r?\n.*?^        run: \|\r?\n(?<Script>(?:^          [^\r\n]*(?:\r?\n|$))+)"
		if ($workflow -notmatch $pattern) {
			throw "Cannot locate the required-validation script in the CI workflow."
		}
		$script:ValidationGate = [scriptblock]::Create($Matches.Script)
	}

	BeforeEach {
		$script:OriginalValidationResults = $env:VALIDATION_RESULTS
	}

	AfterEach {
		$env:VALIDATION_RESULTS = $script:OriginalValidationResults
	}

	It "Accepts only successful dependencies: test=<TestResult>, package=<PackageResult>" -ForEach $dependencyCases {
		$results = @{
			test = @{ result = $TestResult }
			package = @{ result = $PackageResult }
		}
		$env:VALIDATION_RESULTS = ConvertTo-Json -InputObject $results -Compress
		if ($ShouldPass) {
			{ & $script:ValidationGate | Out-Null } | Should -Not -Throw
		}
		else {
			{ & $script:ValidationGate | Out-Null } | Should -Throw "*Required validation failed*"
		}
	}

	It "Rejects missing or invalid results: <Name>" -ForEach @(
		@{ Name = "missing package"; Results = '{"test":{"result":"success"}}' }
		@{ Name = "missing test"; Results = '{"package":{"result":"success"}}' }
		@{ Name = "empty results"; Results = "{}" }
		@{ Name = "null results"; Results = "null" }
		@{ Name = "malformed JSON"; Results = "not JSON" }
	) {
		$env:VALIDATION_RESULTS = $Results
		{ & $script:ValidationGate | Out-Null } | Should -Throw
	}
}

Describe "Staged CI package smoke test" -Skip:($PSVersionTable.PSEdition -eq "Desktop") {
	BeforeAll {
		$workflow = Get-Content -LiteralPath "$PSScriptRoot\.github\workflows\ci.yml" -Raw
		$script:PackageScripts = @{}
		foreach ($step in @("Stage module", "Validate staged module in a fresh process")) {
			$pattern = "(?ms)^      - name: $([regex]::Escape($step))\r?\n.*?^        run: \|\r?\n(?<Script>(?:^          [^\r\n]*(?:\r?\n|$))+)"
			if ($workflow -notmatch $pattern) {
				throw "Cannot locate the '$step' script in the CI workflow."
			}
			$script:PackageScripts[$step] = $Matches.Script
		}
		$script:PowerShellExecutable = (Get-Process -Id $PID).Path
	}

	It "Stages and transforms the package in separate fresh processes" {
		$workspace = Join-Path -Path $TestDrive -ChildPath "package workspace"
		New-Item -Path $workspace -ItemType Directory | Out-Null
		$copyParams = @{
			Path = @("$PSScriptRoot\*.ps1", "$PSScriptRoot\*.psd1", "$PSScriptRoot\*.psm1", "$PSScriptRoot\sbom.xml", "$PSScriptRoot\polyglot", "$PSScriptRoot\test_data")
			Destination = $workspace
			Recurse = $true
			ErrorAction = "Stop"
		}
		Copy-Item @copyParams
		Push-Location -LiteralPath $workspace
		try {
			foreach ($step in @("Stage module", "Validate staged module in a fresh process")) {
				$scriptPath = Join-Path -Path $TestDrive -ChildPath "$step.ps1"
				$contentParams = @{
					LiteralPath = $scriptPath
					Value = '$ErrorActionPreference = "Stop"' + "`n" + $script:PackageScripts[$step]
					ErrorAction = "Stop"
				}
				Set-Content @contentParams
				$output = & $script:PowerShellExecutable -NoProfile -NonInteractive -File $scriptPath
				$LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
			}
			Test-Path -LiteralPath (Join-Path -Path $workspace -ChildPath "out\powerxml.psd1") | Should -BeTrue
		}
		finally {
			Pop-Location
		}
	}
}
