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
}
