
# Unit tests for download-deps.ps1
# By default, tests requiring network connectivity are skipped unless $env:POWERXML_REAL_NETWORK is set.

BeforeAll {
    $global:TestDir = "TestDrive:/"
    Import-Module "$PSScriptRoot/../polyglot" -DisableNameChecking -Force

    # Mock tests should always run, no need to set RequiresNetwork
}

Describe 'Test-FileHash' {
    BeforeEach {
        # Create a file with known content and compute its hash for reference
        $script:TestFile = Join-Path $global:TestDir "hashtest.txt"
        Set-Content -Path $script:TestFile -Value "hello world" -NoNewline
        $script:KnownHash = (Get-FileHash -Path $script:TestFile -Algorithm SHA256).Hash
    }

    It 'Should pass when hash matches' {
        { Test-FileHash -Path $script:TestFile -ExpectedHash $script:KnownHash } | Should -Not -Throw
    }

    It 'Should return the computed hash on success' {
        $result = Test-FileHash -Path $script:TestFile -ExpectedHash $script:KnownHash
        $result | Should -Be $script:KnownHash
    }

    It 'Should throw on hash mismatch' {
        $badHash = "0000000000000000000000000000000000000000000000000000000000000000"
        { Test-FileHash -Path $script:TestFile -ExpectedHash $badHash } | Should -Throw "*Hash mismatch*"
    }

    It 'Should include expected and actual hash in error message' {
        $badHash = "DEADBEEF00000000000000000000000000000000000000000000000000000000"
        try {
            Test-FileHash -Path $script:TestFile -ExpectedHash $badHash
        }
        catch {
            $_.Exception.Message | Should -Match "Expected: $badHash"
            $_.Exception.Message | Should -Match "Actual: $($script:KnownHash)"
            return
        }
        throw "Expected Test-FileHash to throw"
    }

    It 'Should be case-insensitive for hash comparison' {
        $lowerHash = $script:KnownHash.ToLower()
        { Test-FileHash -Path $script:TestFile -ExpectedHash $lowerHash } | Should -Not -Throw
    }

    It 'Should throw on non-existent file' {
        { Test-FileHash -Path (Join-Path $global:TestDir "nonexistent.bin") -ExpectedHash "abc" } | Should -Throw
    }

    It 'Should support alternative algorithms' {
        $sha512Hash = (Get-FileHash -Path $script:TestFile -Algorithm SHA512).Hash
        $result = Test-FileHash -Path $script:TestFile -ExpectedHash $sha512Hash -Algorithm SHA512
        $result | Should -Be $sha512Hash
    }

    It 'Should detect single-byte difference' {
        $altFile = Join-Path $global:TestDir "hashtest-alt.txt"
        Set-Content -Path $altFile -Value "hello worlD" -NoNewline
        { Test-FileHash -Path $altFile -ExpectedHash $script:KnownHash } | Should -Throw "*Hash mismatch*"
    }
}

# --- Copy-GitHubRelease tests ---

Describe 'Copy-GitHubRelease' {
    BeforeAll {
        $script:LibPath = Join-Path $global:TestDir "ghrelease-lib"
    }

    BeforeEach {
        if (Test-Path $script:LibPath) {
            Remove-Item $script:LibPath -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:LibPath | Out-Null
    }

    Context 'Cache hit - all assets already present' {
        It 'Should return cached paths without making API calls' {
            Mock Invoke-RestMethod -ModuleName polyglot

            # Pre-create cached directory (simulates previously extracted asset)
            $cachedDir = Join-Path $script:LibPath "test-asset"
            New-Item -ItemType Directory -Path $cachedDir | Out-Null

            $result = Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("test-asset.zip") -libPath $script:LibPath

            $result | Should -Contain $cachedDir
            Should -Invoke Invoke-RestMethod -Times 0 -ModuleName polyglot
        }

        It 'Should return multiple cached paths when all assets are cached' {
            Mock Invoke-RestMethod -ModuleName polyglot

            $dir1 = Join-Path $script:LibPath "asset-a"
            $dir2 = Join-Path $script:LibPath "asset-b"
            New-Item -ItemType Directory -Path $dir1 | Out-Null
            New-Item -ItemType Directory -Path $dir2 | Out-Null

            $result = Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("asset-a.zip", "asset-b.zip") -libPath $script:LibPath

            $result | Should -HaveCount 2
            Should -Invoke Invoke-RestMethod -Times 0 -ModuleName polyglot
        }

        It 'Should call API when at least one asset is missing from cache' {

            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    assets   = @(
                        [PSCustomObject]@{ name = "cached.zip"; browser_download_url = "https://example.com/cached.zip" },
                        [PSCustomObject]@{ name = "missing.zip"; browser_download_url = "https://example.com/missing.zip" }
                    )
                }
            }
            Mock Invoke-WebRequest -ModuleName polyglot -MockWith {
                if ($OutFile) { New-Item -ItemType File -Path $OutFile -Force | Out-Null }
            }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                    [System.IO.Path]::GetFileName($Path))
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath $baseName) -Force | Out-Null
            }

            # Only create one cached directory
            New-Item -ItemType Directory -Path (Join-Path $script:LibPath "cached") | Out-Null

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("cached.zip", "missing.zip") -libPath $script:LibPath

            Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot
        }
    }

    Context 'Download latest release' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    assets   = @(
                        [PSCustomObject]@{
                            name                 = "tool-v1.zip"
                            browser_download_url = "https://example.com/tool-v1.zip"
                        },
                        [PSCustomObject]@{
                            name                 = "tool-v1.tar.gz"
                            browser_download_url = "https://example.com/tool-v1.tar.gz"
                        }
                    )
                }
            }
            Mock Invoke-WebRequest -ModuleName polyglot -MockWith {
                if ($OutFile) { New-Item -ItemType File -Path $OutFile -Force | Out-Null }
            }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                    [System.IO.Path]::GetFileName($Path))
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath $baseName) -Force | Out-Null
            }
        }

        It 'Should call API with latest URL' {

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool-v1.zip") -libPath $script:LibPath

            Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
                $Uri -like "*/repos/owner/repo/releases/latest"
            }
        }

        It 'Should download the requested asset via Invoke-WebRequest' {

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool-v1.zip") -libPath $script:LibPath

            Should -Invoke Invoke-WebRequest -Times 1 -ModuleName polyglot
        }

        It 'Should extract ZIP assets via Expand-Archive' {

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool-v1.zip") -libPath $script:LibPath

            Should -Invoke Expand-Archive -Times 1 -ModuleName polyglot
        }

        It 'Should return extracted directory paths' {

            $result = Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool-v1.zip") -libPath $script:LibPath

            $expected = Join-Path $script:LibPath "tool-v1"
            $result | Should -Contain $expected
        }

        It 'Should not extract non-ZIP files' {

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool-v1.tar.gz") -libPath $script:LibPath -ErrorAction SilentlyContinue

            Should -Invoke Expand-Archive -Times 0 -ModuleName polyglot
        }

        It 'Should skip download when file already exists on disk' {

            # Pre-create the zip file (simulates already-downloaded but not-yet-extracted)
            New-Item -ItemType File -Path (Join-Path $script:LibPath "tool-v1.zip") -Force | Out-Null

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool-v1.zip") -libPath $script:LibPath

            Should -Invoke Invoke-WebRequest -Times 0 -ModuleName polyglot
        }
    }

	Context "GitHub API authentication and failures" {
		BeforeEach {
			$script:PreviousGitHubToken = $env:GITHUB_TOKEN
			$env:GITHUB_TOKEN = "powerxml-test-token"
			Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
				[pscustomobject]@{
					tag_name = "v1"
					assets = @(
						[pscustomobject]@{
							name = "authenticated-tool.zip"
							browser_download_url = "https://example.com/authenticated-tool.zip"
						}
					)
				}
			}
			Mock Invoke-WebRequest -ModuleName polyglot -MockWith {
				New-Item -ItemType File -Path $OutFile | Out-Null
			}
			Mock Expand-Archive -ModuleName polyglot -MockWith {
				New-Item -ItemType Directory -Path (Join-Path -Path $DestinationPath -ChildPath "authenticated-tool") | Out-Null
			}
		}

		AfterEach {
			$env:GITHUB_TOKEN = $script:PreviousGitHubToken
		}

		It "Authenticates GitHub metadata but not asset downloads" {
			$copyParams = @{
				RepoOwner = "owner"
				RepoName = "repo"
				Assets = @("authenticated-tool.zip")
				LibPath = $script:LibPath
			}
			Copy-GitHubRelease @copyParams | Should -Not -BeNullOrEmpty
			$invokeParams = @{
				CommandName = "Invoke-RestMethod"
				ModuleName = "polyglot"
				Times = 1
				Exactly = $true
				ParameterFilter = { $Headers.Authorization -eq "Bearer powerxml-test-token" -and $ErrorAction -eq "Stop" }
			}
			Should -Invoke @invokeParams
			$invokeParams.CommandName = "Invoke-WebRequest"
			$invokeParams.ParameterFilter = { -not $Headers -or -not $Headers.ContainsKey("Authorization") }
			Should -Invoke @invokeParams
		}

		It "Does not send the GitHub token to <ApiPath>" -ForEach @(
			@{ ApiPath = "https://codeberg.org/api/v1" }
			@{ ApiPath = "http://api.github.com" }
			@{ ApiPath = "https://api.github.com.example.com" }
			@{ ApiPath = "https://api.github.com:8443" }
		) {
			$copyParams = @{
				RepoOwner = "owner"
				RepoName = "repo"
				Assets = @("authenticated-tool.zip")
				LibPath = $script:LibPath
				ApiPath = $ApiPath
			}
			Copy-GitHubRelease @copyParams | Should -Not -BeNullOrEmpty
			$invokeParams = @{
				CommandName = "Invoke-RestMethod"
				ModuleName = "polyglot"
				Times = 1
				Exactly = $true
				ParameterFilter = { -not $Headers -or -not $Headers.ContainsKey("Authorization") }
			}
			Should -Invoke @invokeParams
		}

		It "Supports anonymous requests when GITHUB_TOKEN is absent" {
			$env:GITHUB_TOKEN = $null
			$copyParams = @{
				RepoOwner = "owner"
				RepoName = "repo"
				Assets = @("authenticated-tool.zip")
				LibPath = $script:LibPath
			}
			Copy-GitHubRelease @copyParams | Should -Not -BeNullOrEmpty
			$invokeParams = @{
				CommandName = "Invoke-RestMethod"
				ModuleName = "polyglot"
				Times = 1
				Exactly = $true
				ParameterFilter = { -not $Headers -or -not $Headers.ContainsKey("Authorization") }
			}
			Should -Invoke @invokeParams
		}

		It "Propagates API errors with release context and does not download assets" {
			Mock Invoke-RestMethod -ModuleName polyglot { throw "403 rate limit exceeded" }
			$copyParams = @{
				RepoOwner = "owner"
				RepoName = "repo"
				Version = "v1"
				LibPath = $script:LibPath
			}
			{ Copy-GitHubRelease @copyParams } | Should -Throw "*Failed to download release 'v1' for 'owner/repo':*403 rate limit exceeded*"
			$invokeParams = @{
				CommandName = "Invoke-WebRequest"
				ModuleName = "polyglot"
				Times = 0
				Exactly = $true
			}
			Should -Invoke @invokeParams
		}

		It "Stops on asset download errors without attempting extraction" {
			Mock Invoke-WebRequest -ModuleName polyglot {
				throw "Asset download failed"
			}
			$copyParams = @{
				RepoOwner = "owner"
				RepoName = "repo"
				Version = "v1"
				Assets = @("authenticated-tool.zip")
				LibPath = $script:LibPath
			}
			{ Copy-GitHubRelease @copyParams } | Should -Throw "*Failed to download release 'v1' for 'owner/repo':*Asset download failed*"
			$invokeParams = @{
				CommandName = "Invoke-WebRequest"
				ModuleName = "polyglot"
				Times = 1
				Exactly = $true
				ParameterFilter = { $ErrorAction -eq "Stop" }
			}
			Should -Invoke @invokeParams
			$invokeParams = @{
				CommandName = "Expand-Archive"
				ModuleName = "polyglot"
				Times = 0
				Exactly = $true
			}
			Should -Invoke @invokeParams
		}
	}

    Context 'Download specific version' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v2.0.0"
                    assets   = @(
                        [PSCustomObject]@{
                            name                 = "tool-v2.zip"
                            browser_download_url = "https://example.com/tool-v2.zip"
                        }
                    )
                }
            }
            Mock Invoke-WebRequest -ModuleName polyglot -MockWith {
                if ($OutFile) { New-Item -ItemType File -Path $OutFile -Force | Out-Null }
            }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                    [System.IO.Path]::GetFileName($Path))
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath $baseName) -Force | Out-Null
            }
        }

        It 'Should call API with version tag URL' {

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Version "v2.0.0" -Assets @("tool-v2.zip") -libPath $script:LibPath

            Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
                $Uri -like "*/repos/owner/repo/releases/tags/v2.0.0"
            }
        }
    }

    Context 'Custom API path' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    assets   = @(
                        [PSCustomObject]@{
                            name                 = "tool.zip"
                            browser_download_url = "https://custom.example.com/tool.zip"
                        }
                    )
                }
            }
            Mock Invoke-WebRequest -ModuleName polyglot -MockWith {
                if ($OutFile) { New-Item -ItemType File -Path $OutFile -Force | Out-Null }
            }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                    [System.IO.Path]::GetFileName($Path))
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath $baseName) -Force | Out-Null
            }
        }

        It 'Should use custom ApiPath in URL' {

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool.zip") -libPath $script:LibPath `
                -ApiPath "https://custom.api.example.com"

            Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
                $Uri -like "https://custom.api.example.com/*"
            }
        }
    }

    Context 'Hash validation' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    assets   = @(
                        [PSCustomObject]@{
                            name                 = "tool.zip"
                            browser_download_url = "https://example.com/tool.zip"
                        }
                    )
                }
            }
            Mock Invoke-WebRequest -ModuleName polyglot -MockWith {
                if ($OutFile) { Set-Content -Path $OutFile -Value "dummy" -NoNewline }
            }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension(
                    [System.IO.Path]::GetFileName($Path))
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath $baseName) -Force | Out-Null
            }
        }

        It 'Should call Test-FileHash when ExpectedHashes is provided' {

            Mock Test-FileHash -ModuleName polyglot -MockWith { return "FAKEHASH" }

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool.zip") -libPath $script:LibPath `
                -ExpectedHashes @{ "tool.zip" = "FAKEHASH" }

            Should -Invoke Test-FileHash -Times 1 -ModuleName polyglot
        }

        It 'Should not call Test-FileHash when no hashes provided' {
            if (-not $script:MockNetwork) { Set-ItResult -Skipped -Because "Real network mode" }

            Mock Test-FileHash -ModuleName polyglot

            Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("tool.zip") -libPath $script:LibPath

            Should -Invoke Test-FileHash -Times 0 -ModuleName polyglot
        }
    }

    Context 'No matching assets' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    assets   = @(
                        [PSCustomObject]@{
                            name                 = "other-tool.zip"
                            browser_download_url = "https://example.com/other-tool.zip"
                        }
                    )
                }
            }
        }

        It 'Should return nothing when requested assets are not found' {
            if (-not $script:MockNetwork) { Set-ItResult -Skipped -Because "Real network mode" }

            $result = Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -Assets @("nonexistent.zip") -libPath $script:LibPath -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'No releases or assets in response' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    assets   = @()
                }
            }
        }

        It 'Should handle empty assets gracefully' {

            $result = Copy-GitHubRelease -RepoOwner "owner" -RepoName "repo" `
                -libPath $script:LibPath

            $result | Should -BeNullOrEmpty
        }
    }
}

# --- Get-GitHubReleases tests ---

Describe 'Get-GitHubReleases' {
    Context 'When releases exist' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                return @(
                    [PSCustomObject]@{
                        tag_name     = "v2.0.0"
                        name         = "Release 2.0"
                        published_at = "2025-01-01T00:00:00Z"
                        html_url     = "https://github.com/owner/repo/releases/tag/v2.0.0"
                    },
                    [PSCustomObject]@{
                        tag_name     = "v1.0.0"
                        name         = "Release 1.0"
                        published_at = "2024-06-01T00:00:00Z"
                        html_url     = "https://github.com/owner/repo/releases/tag/v1.0.0"
                    }
                )
            }
        }

        It 'Should call GitHub API with correct URL' {

            Get-GitHubReleases -RepoOwner "owner" -RepoName "repo"

            Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
                $Uri -eq "https://api.github.com/repos/owner/repo/releases"
            }
        }
    }

    Context 'When no releases found' {
        BeforeEach {
            if ($script:MockNetwork) {
                Mock Invoke-RestMethod -ModuleName polyglot -MockWith { return @() }
            }
        }

        It 'Should not throw when response is empty' {
            if (-not $script:MockNetwork) { Set-ItResult -Skipped -Because "Real network mode" }

            { Get-GitHubReleases -RepoOwner "owner" -RepoName "repo" } | Should -Not -Throw
        }
    }

    Context 'When API call fails' {
        BeforeEach {
            if ($script:MockNetwork) {
                Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
                    throw "API rate limit exceeded"
                }
            }
        }

        It 'Should handle API errors gracefully (no unhandled throw)' {

            { Get-GitHubReleases -RepoOwner "owner" -RepoName "repo" } | Should -Not -Throw
        }
    }
}
