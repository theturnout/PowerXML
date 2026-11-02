# Unit tests for install-package.ps1

BeforeAll {
    $global:TestDir = "TestDrive:/"
    Import-Module "$PSScriptRoot/../polyglot" -DisableNameChecking -Force

    $env:polyglotpm = (Join-Path $global:TestDir "polyglotpm")
    New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
}

AfterAll {
    $env:polyglotpm = $null
}

Describe 'Install-Package' {

    BeforeEach {
        # Fresh local repo for each test
        $script:LocalRepo = Join-Path $global:TestDir "install-test-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:LocalRepo | Out-Null
    }

    Context 'Idempotent skip' {
        It 'Should return existing directory without re-installing' {
            $targetDir = Join-Path $script:LocalRepo "mylib-1.0.0"
            New-Item -ItemType Directory -Path $targetDir | Out-Null

            Mock Expand-Archive -ModuleName polyglot
            Mock Test-FileHash -ModuleName polyglot

            $result = Install-Package -DownloadedPath "nonexistent.zip" `
                -Name "mylib" -Version "1.0.0" `
                -LocalRepository $script:LocalRepo

            $result | Should -Be $targetDir
            Should -Invoke Expand-Archive -Times 0 -ModuleName polyglot
            Should -Invoke Test-FileHash -Times 0 -ModuleName polyglot
        }
    }

    Context 'Missing artifact' {
        It 'Should throw when downloaded file does not exist' {
            $fakePath = Join-Path $script:LocalRepo "does-not-exist.zip"

            { Install-Package -DownloadedPath $fakePath `
                    -Name "mylib" -Version "1.0.0" `
                    -LocalRepository $script:LocalRepo } | Should -Throw "*not found*"
        }
    }

    Context 'Hash verification' {
        It 'Should call Test-FileHash for each hash in Hashes' {
            $zipPath = Join-Path $script:LocalRepo "mylib-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Test-FileHash -ModuleName polyglot -MockWith { return $ExpectedHash }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "mylib-1.0.0") -Force | Out-Null
            }

            $hashes = @(
                [PSCustomObject]@{ Algorithm = 'SHA256'; Hash = 'ABCD1234' }
            )
            Install-Package -DownloadedPath $zipPath `
                -Name "mylib" -Version "1.0.0" `
                -Hashes $hashes `
                -LocalRepository $script:LocalRepo

            Should -Invoke Test-FileHash -Times 1 -ModuleName polyglot -ParameterFilter {
                $ExpectedHash -eq "ABCD1234" -and $Algorithm -eq "SHA256"
            }
        }

        It 'Should verify multiple hashes when provided' {
            $zipPath = Join-Path $script:LocalRepo "multi-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Test-FileHash -ModuleName polyglot -MockWith { return $ExpectedHash }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "multi-1.0.0") -Force | Out-Null
            }

            $hashes = @(
                [PSCustomObject]@{ Algorithm = 'SHA256'; Hash = 'HASH256' },
                [PSCustomObject]@{ Algorithm = 'SHA512'; Hash = 'HASH512' }
            )
            Install-Package -DownloadedPath $zipPath `
                -Name "multi" -Version "1.0.0" `
                -Hashes $hashes `
                -LocalRepository $script:LocalRepo

            Should -Invoke Test-FileHash -Times 1 -ModuleName polyglot -ParameterFilter {
                $ExpectedHash -eq "HASH256" -and $Algorithm -eq "SHA256"
            }
            Should -Invoke Test-FileHash -Times 1 -ModuleName polyglot -ParameterFilter {
                $ExpectedHash -eq "HASH512" -and $Algorithm -eq "SHA512"
            }
        }

        It 'Should not call Test-FileHash when Hashes is empty' {
            $zipPath = Join-Path $script:LocalRepo "mylib-2.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Test-FileHash -ModuleName polyglot
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "mylib-2.0.0") -Force | Out-Null
            }

            Install-Package -DownloadedPath $zipPath `
                -Name "mylib" -Version "2.0.0" `
                -LocalRepository $script:LocalRepo

            Should -Invoke Test-FileHash -Times 0 -ModuleName polyglot
        }

        It 'Should propagate Test-FileHash failure' {
            $zipPath = Join-Path $script:LocalRepo "badlib-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Test-FileHash -ModuleName polyglot -MockWith {
                throw "Hash mismatch"
            }

            $hashes = @(
                [PSCustomObject]@{ Algorithm = 'SHA256'; Hash = 'WRONG' }
            )
            { Install-Package -DownloadedPath $zipPath `
                    -Name "badlib" -Version "1.0.0" `
                    -Hashes $hashes `
                    -LocalRepository $script:LocalRepo } | Should -Throw "*Hash mismatch*"
        }

        It 'Should fail on first bad hash even when multiple provided' {
            $zipPath = Join-Path $script:LocalRepo "partbad-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Test-FileHash -ModuleName polyglot -MockWith {
                if ($ExpectedHash -eq 'BAD') { throw "Hash mismatch" }
                return $ExpectedHash
            }

            $hashes = @(
                [PSCustomObject]@{ Algorithm = 'SHA256'; Hash = 'BAD' },
                [PSCustomObject]@{ Algorithm = 'SHA512'; Hash = 'GOOD' }
            )
            { Install-Package -DownloadedPath $zipPath `
                    -Name "partbad" -Version "1.0.0" `
                    -Hashes $hashes `
                    -LocalRepository $script:LocalRepo } | Should -Throw "*Hash mismatch*"
        }
    }

    Context 'Zip extraction' {
        It 'Should extract zip and return target directory' {
            $zipPath = Join-Path $script:LocalRepo "pkg-3.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "pkg-3.0.0") -Force | Out-Null
            }

            $result = Install-Package -DownloadedPath $zipPath `
                -Name "pkg" -Version "3.0.0" `
                -LocalRepository $script:LocalRepo

            $expected = Join-Path $script:LocalRepo "pkg-3.0.0"
            $result | Should -Be $expected
            Should -Invoke Expand-Archive -Times 1 -ModuleName polyglot
        }

        It 'Should keep zip file after extraction' {
            $zipPath = Join-Path $script:LocalRepo "cleanup-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "cleanup-1.0.0") -Force | Out-Null
            }

            Install-Package -DownloadedPath $zipPath `
                -Name "cleanup" -Version "1.0.0" `
                -LocalRepository $script:LocalRepo

            Test-Path $zipPath | Should -Be $true
        }
    }

    Context 'rootZip rename' {
        It 'Should rename extracted directory when ZipRoot differs from Name-Version' {
            $zipPath = Join-Path $script:LocalRepo "morgana-1.6.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Expand-Archive -ModuleName polyglot -MockWith {
                # Simulate zip containing a differently-named root directory
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "MorganaXProc-IIIse-1.6.7") -Force | Out-Null
            }

            $result = Install-Package -DownloadedPath $zipPath `
                -Name "morgana" -Version "1.6" `
                -ZipRoot "MorganaXProc-IIIse-1.6.7" `
                -LocalRepository $script:LocalRepo

            $expected = Join-Path $script:LocalRepo "morgana-1.6"
            $result | Should -Be $expected
            Test-Path $expected -PathType Container | Should -Be $true
        }

        It 'Should skip rename when ZipRoot matches Name-Version' {
            $zipPath = Join-Path $script:LocalRepo "exact-2.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "exact-2.0.0") -Force | Out-Null
            }
            Mock Rename-Item -ModuleName polyglot

            Install-Package -DownloadedPath $zipPath `
                -Name "exact" -Version "2.0.0" `
                -ZipRoot "exact-2.0.0" `
                -LocalRepository $script:LocalRepo

            Should -Invoke Rename-Item -Times 0 -ModuleName polyglot
        }

        It 'Should warn when ZipRoot directory not found after extraction' {
            $zipPath = Join-Path $script:LocalRepo "missing-root-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Expand-Archive -ModuleName polyglot -MockWith {
                # Extract a directory with a different name than ZipRoot
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "unexpected-dir") -Force | Out-Null
            }

            Install-Package -DownloadedPath $zipPath `
                -Name "missing-root" -Version "1.0.0" `
                -ZipRoot "expected-root" `
                -LocalRepository $script:LocalRepo `
                -WarningAction SilentlyContinue -WarningVariable warnings

            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Non-zip file handling' {
        It 'Should create target directory and move file into it' {
            $jarPath = Join-Path $script:LocalRepo "mylib-4.0.0.jar"
            Set-Content -Path $jarPath -Value "fake jar" -NoNewline

            $result = Install-Package -DownloadedPath $jarPath `
                -Name "mylib" -Version "4.0.0" `
                -LocalRepository $script:LocalRepo

            $expected = Join-Path $script:LocalRepo "mylib-4.0.0"
            $result | Should -Be $expected
            Test-Path $expected -PathType Container | Should -Be $true
            Test-Path (Join-Path $expected "mylib-4.0.0.jar") | Should -Be $true
        }
    }

    Context 'Custom hash algorithm' {
        It 'Should pass algorithm to Test-FileHash' {
            $zipPath = Join-Path $script:LocalRepo "alg-1.0.0.zip"
            Set-Content -Path $zipPath -Value "fake" -NoNewline

            Mock Test-FileHash -ModuleName polyglot -MockWith { return "HASH512" }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                New-Item -ItemType Directory -Path (Join-Path $DestinationPath "alg-1.0.0") -Force | Out-Null
            }

            $hashes = @(
                [PSCustomObject]@{ Algorithm = 'SHA512'; Hash = 'HASH512' }
            )
            Install-Package -DownloadedPath $zipPath `
                -Name "alg" -Version "1.0.0" `
                -Hashes $hashes `
                -LocalRepository $script:LocalRepo

            Should -Invoke Test-FileHash -Times 1 -ModuleName polyglot -ParameterFilter {
                $Algorithm -eq "SHA512"
            }
        }
    }

    Context 'Archive root auto-detection' {
        BeforeEach {
            # Real wrapper-style archive: every entry lives under mywrapper-9.9.9/
            $wrapperBase = Join-Path $TestDrive "wrapsrc-$(New-Guid)"
            $wrapperDir = Join-Path $wrapperBase "mywrapper-9.9.9"
            New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
            Set-Content -Path (Join-Path $wrapperDir "lib.jar") -Value "jar content" -NoNewline
            $script:wrapperZip = Join-Path $script:LocalRepo "mylib-9.9.9.zip"
            Compress-Archive -Path (Join-Path $wrapperBase "*") -DestinationPath $script:wrapperZip -Force

            # Real flat archive: entries at the archive root (no wrapper)
            $script:flatBase = Join-Path $TestDrive "flatsrc-$(New-Guid)"
            New-Item -ItemType Directory -Path $script:flatBase -Force | Out-Null
            Set-Content -Path (Join-Path $script:flatBase "root-file.txt") -Value "root" -NoNewline
            $flatSub = Join-Path $script:flatBase "sub"
            New-Item -ItemType Directory -Path $flatSub -Force | Out-Null
            Set-Content -Path (Join-Path $flatSub "nested-file.txt") -Value "nested" -NoNewline
            $script:flatZip = Join-Path $script:LocalRepo "mylib-8.8.8.zip"
            Compress-Archive -Path (Join-Path $script:flatBase "*") -DestinationPath $script:flatZip -Force
        }

        It 'Should auto-detect and rename a wrapper directory without ZipRoot' {
            $result = Install-Package -DownloadedPath $script:wrapperZip `
                -Name "mylib" -Version "9.9.9" `
                -LocalRepository $script:LocalRepo

            $expected = Join-Path $script:LocalRepo "mylib-9.9.9"
            $result | Should -Be $expected
            Test-Path $expected -PathType Container | Should -Be $true
            Test-Path (Join-Path $expected "lib.jar") | Should -Be $true
            Test-Path (Join-Path $script:LocalRepo "mywrapper-9.9.9") | Should -Be $false
        }

        It 'Should extract a no-wrapper archive directly into the canonical directory' {
            $result = Install-Package -DownloadedPath $script:flatZip `
                -Name "mylib" -Version "8.8.8" `
                -LocalRepository $script:LocalRepo

            $expected = Join-Path $script:LocalRepo "mylib-8.8.8"
            $result | Should -Be $expected
            Test-Path (Join-Path $expected "root-file.txt") | Should -Be $true
            Test-Path (Join-Path $expected "sub/nested-file.txt") | Should -Be $true
            # Nothing sprayed into the repository root
            Test-Path (Join-Path $script:LocalRepo "root-file.txt") | Should -Be $false
        }

        It 'Should preserve an installed package whose name matches the archive wrapper' {
            $existingDir = Join-Path $script:LocalRepo "mywrapper-9.9.9"
            New-Item -ItemType Directory -Path $existingDir | Out-Null
            Set-Content -Path (Join-Path $existingDir "lib.jar") -Value "original jar" -NoNewline
            Set-Content -Path (Join-Path $existingDir "existing.txt") -Value "existing" -NoNewline

            $result = Install-Package -DownloadedPath $script:wrapperZip `
                -Name "mylib" -Version "9.9.9" `
                -LocalRepository $script:LocalRepo

            Get-Content (Join-Path $existingDir "lib.jar") -Raw | Should -Be "original jar"
            Get-Content (Join-Path $existingDir "existing.txt") -Raw | Should -Be "existing"
            Get-Content (Join-Path $result "lib.jar") -Raw | Should -Be "jar content"
            Test-Path (Join-Path $result "existing.txt") | Should -Be $false
            @(Get-ChildItem $script:LocalRepo -Directory).Count | Should -Be 2
        }

        It 'Should clean up staging when wrapper extraction fails' {
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                Set-Content -Path (Join-Path $DestinationPath "partial.txt") -Value "partial"
                throw "Extraction failed"
            }

            { Install-Package -DownloadedPath $script:wrapperZip `
                    -Name "mylib" -Version "9.9.9" `
                    -LocalRepository $script:LocalRepo } | Should -Throw "*Extraction failed*"

            @(Get-ChildItem $script:LocalRepo -Directory).Count | Should -Be 0
            Test-Path $script:wrapperZip | Should -Be $true
        }

        It 'Should install a wrapper that already has the canonical name' {
            $result = Install-Package -DownloadedPath $script:wrapperZip `
                -Name "mywrapper" -Version "9.9.9" `
                -LocalRepository $script:LocalRepo

            Get-Content (Join-Path $result "lib.jar") -Raw | Should -Be "jar content"
            @(Get-ChildItem $script:LocalRepo -Directory).Count | Should -Be 1
        }

        It 'Should warn and use the detected root when ZipRoot disagrees' {
            Install-Package -DownloadedPath $script:wrapperZip `
                -Name "mylib" -Version "9.9.9" `
                -ZipRoot "wrong-root-9.9.9" `
                -LocalRepository $script:LocalRepo `
                -WarningAction SilentlyContinue -WarningVariable warnings

            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -BeLike "*wrong-root-9.9.9*"
            Test-Path (Join-Path $script:LocalRepo "mylib-9.9.9") -PathType Container | Should -Be $true
        }

        It 'Should warn when ZipRoot is set but the archive has no wrapper' {
            Install-Package -DownloadedPath $script:flatZip `
                -Name "mylib" -Version "8.8.8" `
                -ZipRoot "some-wrapper" `
                -LocalRepository $script:LocalRepo `
                -WarningAction SilentlyContinue -WarningVariable warnings

            $warnings | Should -Not -BeNullOrEmpty
            Test-Path (Join-Path $script:LocalRepo "mylib-8.8.8") -PathType Container | Should -Be $true
        }

        It 'Should perform a case-only rename to the canonical name' {
            $caseBase = Join-Path $TestDrive "casesrc-$(New-Guid)"
            $caseDir = Join-Path $caseBase "MYLIB-7.7.7"
            New-Item -ItemType Directory -Path $caseDir -Force | Out-Null
            Set-Content -Path (Join-Path $caseDir "inner.txt") -Value "x" -NoNewline
            $caseZip = Join-Path $script:LocalRepo "mylib-7.7.7.zip"
            Compress-Archive -Path (Join-Path $caseBase "*") -DestinationPath $caseZip -Force

            Install-Package -DownloadedPath $caseZip `
                -Name "mylib" -Version "7.7.7" `
                -LocalRepository $script:LocalRepo

            (Get-ChildItem $script:LocalRepo -Directory |
                Where-Object { $_.Name -ceq "mylib-7.7.7" }).Name | Should -Be "mylib-7.7.7"
        }

        It 'Should extract a <Layout> nupkg using a temporary zip and clean it up' -TestCases @(
            @{ Layout = 'flat'; ArchiveVariable = 'flatZip'; Payload = 'root-file.txt'; Content = 'root' }
            @{ Layout = 'wrapped'; ArchiveVariable = 'wrapperZip'; Payload = 'lib.jar'; Content = 'jar content' }
        ) {
            param($Layout, $ArchiveVariable, $Payload, $Content)

            $nupkg = Join-Path $script:LocalRepo "mylib-6.6.6.nupkg"
            Copy-Item -Path (Get-Variable -Name $ArchiveVariable -ValueOnly) -Destination $nupkg
            $originalHash = (Get-FileHash $nupkg).Hash
            $extraction = @{ Path = $null }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                param($Path, $DestinationPath)
                $extraction.Path = $Path
                if ([System.IO.Path]::GetExtension($Path) -ne '.zip') {
                    throw 'Only .zip archives are supported'
                }
                Microsoft.PowerShell.Archive\Expand-Archive -Path $Path -DestinationPath $DestinationPath -Force -ErrorAction Stop
            }

            $result = Install-Package -DownloadedPath $nupkg `
                -Name "mylib" -Version "6.6.6" `
                -LocalRepository $script:LocalRepo

            $result | Should -Be (Join-Path $script:LocalRepo "mylib-6.6.6")
            Get-Content (Join-Path $result $Payload) -Raw | Should -Be $Content
            $extraction.Path | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $extraction.Path | Should -Be $false
            (Get-FileHash $nupkg).Hash | Should -Be $originalHash
            @(Get-ChildItem $script:LocalRepo -Directory).Count | Should -Be 1
        }

        It 'Should clean up the temporary zip when <Layout> nupkg extraction fails' -TestCases @(
            @{ Layout = 'flat'; ArchiveVariable = 'flatZip' }
            @{ Layout = 'wrapped'; ArchiveVariable = 'wrapperZip' }
        ) {
            param($Layout, $ArchiveVariable)

            $nupkg = Join-Path $script:LocalRepo "mylib-6.6.6.nupkg"
            Copy-Item -Path (Get-Variable -Name $ArchiveVariable -ValueOnly) -Destination $nupkg
            $extraction = @{ Path = $null }
            Mock Expand-Archive -ModuleName polyglot -MockWith {
                param($Path)
                $extraction.Path = $Path
                throw 'Extraction failed'
            }

            { Install-Package -DownloadedPath $nupkg `
                    -Name "mylib" -Version "6.6.6" `
                    -LocalRepository $script:LocalRepo } | Should -Throw '*Extraction failed*'

            $extraction.Path | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $extraction.Path | Should -Be $false
            Test-Path -LiteralPath $nupkg | Should -Be $true
            @(Get-ChildItem $script:LocalRepo -Directory).Count | Should -Be 0
        }
    }
}
