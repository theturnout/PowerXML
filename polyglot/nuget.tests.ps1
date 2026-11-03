# Unit tests for nuget.ps1 (Resolve-NuGetDependencies)

BeforeAll {
    $global:TestDir = "TestDrive:/"
    Import-Module "$PSScriptRoot/../polyglot" -DisableNameChecking -Force

    $env:polyglotpm = (Join-Path $global:TestDir "polyglotpm")
    New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null

    # Builds the fake global-packages layout that a real AnyPackage.NuGet
    # install produces under $env:NUGET_PACKAGES: {id-lower}/{version}/
    # containing the .nupkg plus the extracted contents (lib/{tfm}/ and the
    # canonically-cased .nuspec whose filename gives the canonical package
    # id). Defined in BeforeAll so it exists at run time (Pester 5 discards
    # top-level definitions after discovery) and inside mock bodies.
    function New-FakeGlobalPackage {
        param(
            [string] $PackagesDir,
            [string] $Id,
            [string] $Version,
            [string] $Tfm = 'net8.0'
        )
        $idLower = $Id.ToLowerInvariant()
        $versionDir = Join-Path (Join-Path $PackagesDir $idLower) $Version
        $staging = Join-Path $TestDrive "stage-$(New-Guid)"
        $tfmDir = Join-Path (Join-Path $staging 'lib') $Tfm
        $null = New-Item -ItemType Directory -Path $tfmDir -Force
        Set-Content -Path (Join-Path $tfmDir "$Id.dll") -Value "fake dll" -NoNewline
        # The real global-packages layout lowercases the nuspec file name
        # while the <id> inside keeps canonical casing
        Set-Content -Path (Join-Path $staging "$idLower.nuspec") -Value `
            "<package><metadata><id>$Id</id><version>$Version</version></metadata></package>" -NoNewline

        $null = New-Item -ItemType Directory -Path $versionDir -Force
        $zipPath = Join-Path $versionDir "$idLower.$Version.zip"
        $archiveParams = @{
            Path = (Join-Path $staging "*")
            DestinationPath = $zipPath
            Force = $true
            ErrorAction = "Stop"
        }
        Compress-Archive @archiveParams
        $moveParams = @{
            LiteralPath = $zipPath
            Destination = (Join-Path $versionDir "$idLower.$Version.nupkg")
            ErrorAction = "Stop"
        }
        Move-Item @moveParams
        Copy-Item -Path (Join-Path $staging '*') -Destination $versionDir -Recurse
        Remove-Item -Recurse -Force $staging
    }
}

AfterAll {
    $env:polyglotpm = $null
}

Describe 'Resolve-NuGetDependencies' {

    BeforeEach {
        # Fresh local repository per test
        $script:Repo = Join-Path $TestDrive "nuget-repo-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:Repo -Force | Out-Null
    }

    Context 'Resolution via the provider (mocked)' {

        It 'Should materialize the resolved closure, exclude the root, and write a marker' {
            Mock Test-PXNuGetProvider -ModuleName polyglot { return $true }
            Mock Install-PXNuGetPackage -ModuleName polyglot {
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'RootLib' -Version '1.0.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'J2N' -Version '2.0.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'Antlr4.Runtime.Standard' -Version '4.13.1'
            }

            $deps = Resolve-NuGetDependencies -Name 'RootLib' -Version '1.0.0' `
                -LocalRepository $script:Repo

            @($deps).Count | Should -Be 2
            $deps | Should -Contain (Join-Path $script:Repo 'J2N-2.0.0')
            $deps | Should -Contain (Join-Path $script:Repo 'Antlr4.Runtime.Standard-4.13.1')
            # Extracted content is in place, with the canonical id casing
            Test-Path (Join-Path $script:Repo 'J2N-2.0.0/lib/net8.0/J2N.dll') | Should -Be $true
            # The root package itself is not materialized by resolution
            Test-Path (Join-Path $script:Repo 'RootLib-1.0.0') | Should -Be $false
            # The marker records the closure
            $marker = Get-Content -Path (Join-Path $script:Repo 'RootLib-1.0.0.deps.json') -Raw |
                ConvertFrom-Json
            @($marker.dependencies).Count | Should -Be 2
            $marker.framework | Should -Be (Get-PXNuGetTargetFramework)
            # The throwaway NUGET_PACKAGES scoping is restored
            $env:NUGET_PACKAGES | Should -BeNullOrEmpty
        }

        It 'Should take the fast path when the marker is complete' {
            Mock Test-PXNuGetProvider -ModuleName polyglot { return $true }
            Mock Install-PXNuGetPackage -ModuleName polyglot {
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'RootLib' -Version '1.0.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'J2N' -Version '2.0.0'
            }
            $null = Resolve-NuGetDependencies -Name 'RootLib' -Version '1.0.0' `
                -LocalRepository $script:Repo

            # A second call must not touch the provider at all
            Mock Install-PXNuGetPackage -ModuleName polyglot { throw "provider must not be called" }
            $deps = Resolve-NuGetDependencies -Name 'RootLib' -Version '1.0.0' `
                -LocalRepository $script:Repo

            @($deps).Count | Should -Be 1
            $deps | Should -Contain (Join-Path $script:Repo 'J2N-2.0.0')
        }

        It 'Should re-resolve when a marked dependency directory is missing' {
            $script:ResolveCalls = 0
            Mock Test-PXNuGetProvider -ModuleName polyglot { return $true }
            Mock Install-PXNuGetPackage -ModuleName polyglot {
                $script:ResolveCalls++
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'RootLib' -Version '1.0.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'J2N' -Version '2.0.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'Antlr4.Runtime.Standard' -Version '4.13.1'
            }
            $null = Resolve-NuGetDependencies -Name 'RootLib' -Version '1.0.0' `
                -LocalRepository $script:Repo

            # Damage the cache: remove one resolved dependency
            Remove-Item -Recurse -Force (Join-Path $script:Repo 'J2N-2.0.0')

            $deps = Resolve-NuGetDependencies -Name 'RootLib' -Version '1.0.0' `
                -LocalRepository $script:Repo

            $script:ResolveCalls | Should -Be 2
            Test-Path (Join-Path $script:Repo 'J2N-2.0.0') | Should -Be $true
            @($deps).Count | Should -Be 2
        }
    }

    Context 'Skip conditions' {

        It 'Should skip resolution for an installed fixture without a .nuspec' {
            # A plain unpacked directory that never came from a nupkg
            $fixtureDir = Join-Path $script:Repo 'PlainDir-1.0'
            $null = New-Item -ItemType Directory -Path $fixtureDir -Force
            Set-Content -Path (Join-Path $fixtureDir 'transform.xsl') -Value 'fixture'

            Mock Install-PXNuGetPackage -ModuleName polyglot { throw "provider must not be called" }

            $deps = Resolve-NuGetDependencies -Name 'PlainDir' -Version '1.0' `
                -LocalRepository $script:Repo

            @($deps).Count | Should -Be 0
            Should -Invoke Install-PXNuGetPackage -Times 0 -ModuleName polyglot
        }

        It 'Should resolve for an installed real package without a marker' {
            # A pre-feature install: extracted nupkg contents (with .nuspec),
            # no dependency marker
            $rootDir = Join-Path $script:Repo 'OldRoot-1.0'
            $null = New-Item -ItemType Directory -Path $rootDir -Force
            Set-Content -Path (Join-Path $rootDir 'OldRoot.nuspec') -Value '<package/>'

            Mock Test-PXNuGetProvider -ModuleName polyglot { return $true }
            Mock Install-PXNuGetPackage -ModuleName polyglot {
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'OldRoot' -Version '1.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'J2N' -Version '2.0.0'
            }

            $deps = Resolve-NuGetDependencies -Name 'OldRoot' -Version '1.0' `
                -LocalRepository $script:Repo

            @($deps).Count | Should -Be 1
            $deps | Should -Contain (Join-Path $script:Repo 'J2N-2.0.0')
        }
    }

    Context 'Fallbacks' {

        It 'Should warn and return nothing when the provider is unavailable' {
            Mock Test-PXNuGetProvider -ModuleName polyglot { return $false }

            $deps = Resolve-NuGetDependencies -Name 'SomeLib' -Version '1.0' `
                -LocalRepository $script:Repo -WarningAction SilentlyContinue -WarningVariable warnings

            @($deps).Count | Should -Be 0
            ($warnings | Out-String) | Should -BeLike '*AnyPackage.NuGet is not installed*'
        }

        It 'Should warn and return nothing when the provider install fails' {
            Mock Test-PXNuGetProvider -ModuleName polyglot { return $true }
            Mock Install-PXNuGetPackage -ModuleName polyglot { throw '404 Not Found' }

            $deps = Resolve-NuGetDependencies -Name 'SomeLib' -Version '1.0' `
                -LocalRepository $script:Repo -WarningAction SilentlyContinue -WarningVariable warnings

            @($deps).Count | Should -Be 0
            ($warnings | Out-String) | Should -BeLike '*dependency resolution*failed*'
            # The NUGET_PACKAGES scoping is restored even on failure
            $env:NUGET_PACKAGES | Should -BeNullOrEmpty
        }
    }

    Context 'Get-PackageFromPurl integration' {

        It 'Should append resolved dependencies to the returned paths' {
            # Pre-create the root nupkg so nothing downloads
            $rootNupkg = Join-Path $script:Repo 'RootLib-1.0.0.nupkg'
            Set-Content -Path $rootNupkg -Value 'fake nupkg' -NoNewline

            Mock Invoke-WebRequest -ModuleName polyglot { }
            Mock Test-PXNuGetProvider -ModuleName polyglot { return $true }
            Mock Install-PXNuGetPackage -ModuleName polyglot {
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'RootLib' -Version '1.0.0'
                New-FakeGlobalPackage -PackagesDir $env:NUGET_PACKAGES -Id 'J2N' -Version '2.0.0'
            }

            $purl = ConvertFrom-PkgUri 'pkg:nuget/RootLib@1.0.0'
            $paths = @(Get-PackageFromPurl -Purl $purl -LocalRepository $script:Repo)

            $paths[0] | Should -Be $rootNupkg
            $paths | Should -Contain (Join-Path $script:Repo 'J2N-2.0.0')
        }
    }
}

Describe 'Get-PXNuGetTargetFramework' {

    AfterEach {
        $env:POWERXML_NUGET_FRAMEWORK = $null
    }

    It 'Should honour POWERXML_NUGET_FRAMEWORK when set' {
        $env:POWERXML_NUGET_FRAMEWORK = 'net8.0'
        Get-PXNuGetTargetFramework | Should -Be 'net8.0'
    }

    It 'Should derive a netN.0 moniker from the runtime on PowerShell 7+' {
        if ($PSVersionTable.PSEdition -ne 'Core') {
            Set-ItResult -Skipped -Because 'Requires PowerShell Core'
            return
        }
        $env:POWERXML_NUGET_FRAMEWORK = $null
        Get-PXNuGetTargetFramework | Should -Match '^net\d+\.0$'
    }
}
