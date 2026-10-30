# Import the main module if needed
# . "$PSScriptRoot/download-deps.ps1"
# . "$PSScriptRoot/polyglot-pm.ps1"
# . "$PSScriptRoot/purl.ps1"
# . "$PSScriptRoot/sbom.ps1"

BeforeAll {
    # TODO: clear .polyglotpm cache
    #$global:TestDir = Join-Path $env:TEMP "pester-test-$(New-Guid)"
    #New-Item -ItemType Directory -Path $TestDir | Out-Null
    $global:TestDir = "TestDrive:/"
    Import-Module "$PSScriptRoot/../polyglot" -DisableNameChecking

    # Save the pre-test repository location so it can be restored afterwards
    $global:PreviousPolyglotpm = $env:polyglotpm
    $env:polyglotpm = (Join-Path $global:TestDir "polyglotpm")
    New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
}

AfterAll {
    # Restore the pre-test repository location. Without this, the session keeps
    # pointing at the Pester TestDrive, which does not exist outside a test run.
    $env:polyglotpm = $global:PreviousPolyglotpm
}
Describe 'polyglot.psm1' {
    It 'Should import without errors' {
        { Import-Module "$PSScriptRoot/../polyglot" -Force -ErrorAction Stop } | Should -Not -Throw
    }
    # Add more tests for exported functions here
}


Describe 'SBOM Support' {
    It 'Should have Copy-SoftwareComposition function' {
        Get-Command Copy-SoftwareComposition | Should -Not -BeNullOrEmpty
    }

    It 'Should fail on missing SBOM file' {
        { Copy-SoftwareComposition -SbomPath "nonexistent.xml" -TargetComposition "test" } | Should -Throw
    }

    It 'Should pass on valid SBOM file' {
        # load the xml file
        $sbom = [xml](Get-Content -Path "test_data/sbom.xml")
        Test-SBOM $sbom | Should -Be $true
    }

    It 'Should parse a PURL' {
        $purlString = "pkg:maven/org.apache.commons/commons-lang3@3.12.0?classifier=sources"
        $Purl = ConvertFrom-PkgUri -uriString $purlString

        $Purl.Type | Should -Be "maven"
        $Purl.Namespace | Should -Be "org.apache.commons"
        $Purl.Name | Should -Be "commons-lang3"
        $Purl.Version | Should -Be "3.12.0"
        $Purl.QualifiersParsed["classifier"] | Should -Be "sources"
    }

    It 'Should parse a PURL with subpath' {
        $purlString = "pkg:npm/angular/cli@12.0.0#src/app"
        $Purl = ConvertFrom-PkgUri -uriString $purlString

        $Purl.Type | Should -Be "npm"
        $Purl.Namespace | Should -Be "angular"
        $Purl.Name | Should -Be "cli"
        $Purl.Version | Should -Be "12.0.0"
        $Purl.Subpath | Should -Be "#src/app"
    }

    It 'Should parse a PURL with multiple qualifiers' {
        $purlString = "pkg:deb/debian/curl@7.50.3-1?arch=amd64&distro=jessie"
        $Purl = ConvertFrom-PkgUri -uriString $purlString

        $Purl.Type | Should -Be "deb"
        $Purl.Namespace | Should -Be "debian"
        $Purl.Name | Should -Be "curl"
        $Purl.Version | Should -Be "7.50.3-1"
        $Purl.QualifiersParsed["arch"] | Should -Be "amd64"
        $Purl.QualifiersParsed["distro"] | Should -Be "jessie"
    }

    # Add more specific tests for Copy-SoftwareComposition here
}

Describe 'Copy-SoftwareComposition composition selection' {
    BeforeAll {
        # Minimal SBOM with two compositions
        $twoCompXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="comp-a">
            <name>comp-a</name>
            <purl>pkg:maven/org.example/a@1.0</purl>
        </component>
        <component type="library" bom-ref="comp-b">
            <name>comp-b</name>
            <purl>pkg:maven/org.example/b@2.0</purl>
        </component>
    </components>
    <compositions>
        <composition bom-ref="first">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="comp-a"/>
            </dependencies>
        </composition>
        <composition bom-ref="second">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="comp-b"/>
            </dependencies>
        </composition>
    </compositions>
</bom>
'@
        $script:twoCompSbom = Join-Path $TestDrive 'two-comp-sbom.xml'
        Set-Content -Path $script:twoCompSbom -Value $twoCompXml -Encoding UTF8

        # SBOM with no compositions
        $noCompXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="comp-a">
            <name>comp-a</name>
            <purl>pkg:maven/org.example/a@1.0</purl>
        </component>
    </components>
</bom>
'@
        $script:noCompSbom = Join-Path $TestDrive 'no-comp-sbom.xml'
        Set-Content -Path $script:noCompSbom -Value $noCompXml -Encoding UTF8
    }

    It 'Should use first composition when targetComposition is not specified' {
        # Mock Get-PackageFromPurl so we don't actually download anything
        Mock Get-PackageFromPurl { return @("$LocalRepository\fake") } -ModuleName polyglot
        Mock Install-Package { return $DownloadedPath } -ModuleName polyglot

        $result = Copy-SoftwareComposition `
            -SbomPath $script:twoCompSbom `
            -LocalRepository $env:polyglotpm -ValidateSbom -Verbose 4>&1

        # Verbose stream should mention the first composition's bom-ref
        $verboseMessages = $result | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $verboseMessages | Should -Not -BeNullOrEmpty
        ($verboseMessages | Out-String) | Should -BeLike "*first*"
    }

    It 'Should use explicit targetComposition when provided' {
        Mock Get-PackageFromPurl { return @("$LocalRepository\fake") } -ModuleName polyglot
        Mock Install-Package { return $DownloadedPath } -ModuleName polyglot

        $result = Copy-SoftwareComposition `
            -SbomPath $script:twoCompSbom `
            -TargetComposition 'second' `
            -LocalRepository $env:polyglotpm -ValidateSbom -Verbose 4>&1

        # Should NOT emit the auto-select verbose message
        $verboseMessages = $result | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $autoMsg = $verboseMessages | Where-Object { $_.Message -like '*No targetComposition specified*' }
        $autoMsg | Should -BeNullOrEmpty
    }

    It 'Should throw when targetComposition is not specified and SBOM has no compositions' {
        { Copy-SoftwareComposition `
                -SbomPath $script:noCompSbom `
                -LocalRepository $env:polyglotpm -ValidateSbom } | Should -Throw '*No compositions found*'
    }

    It 'Should throw when explicit targetComposition is not found' {
        { Copy-SoftwareComposition `
                -SbomPath $script:twoCompSbom `
                -TargetComposition 'nonexistent' `
                -LocalRepository $env:polyglotpm -ValidateSbom } | Should -Throw '*not found*'
    }
}

Describe 'Set-PurlVersion' {
    It 'Should replace version in simple purl' {
        $result = Set-PurlVersion -PurlString 'pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24' `
            -OldVersion '3.0.24' -NewVersion '3.0.41'
        $result | Should -Be 'pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.41'
    }

    It 'Should replace version in purl with filename qualifier' {
        $result = Set-PurlVersion `
            -PurlString 'pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta7?filename=xmlcalabash-3.0.0-beta7.zip' `
            -OldVersion '3.0.0-beta7' -NewVersion '3.0.0-beta8'
        $result | Should -Be 'pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta8?filename=xmlcalabash-3.0.0-beta8.zip'
    }

    It 'Should replace version in polyglot filename qualifier' {
        $result = Set-PurlVersion `
            -PurlString 'pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta7?filename=polyglot-3.0.0-beta7.zip' `
            -OldVersion '3.0.0-beta7' -NewVersion '3.0.0-beta8'
        $result | Should -Be 'pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta8?filename=polyglot-3.0.0-beta8.zip'
    }

    It 'Should not replace partial version (1.0 inside 1.0.1)' {
        $result = Set-PurlVersion `
            -PurlString 'pkg:maven/org.example/tool@1.0.1?filename=tool-1.0.1.zip' `
            -OldVersion '1.0' -NewVersion '2.0'
        # Neither @version nor filename should change
        $result | Should -Be 'pkg:maven/org.example/tool@1.0.1?filename=tool-1.0.1.zip'
    }

    It 'Should handle purl without qualifiers' {
        $result = Set-PurlVersion -PurlString 'pkg:maven/org.nineml/coffeefilter@3.2.9' `
            -OldVersion '3.2.9' -NewVersion '4.0.0'
        $result | Should -Be 'pkg:maven/org.nineml/coffeefilter@4.0.0'
    }

    It 'Should be a no-op when OldVersion equals NewVersion' {
        $original = 'pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24'
        $result = Set-PurlVersion -PurlString $original -OldVersion '3.0.24' -NewVersion '3.0.24'
        $result | Should -Be $original
    }
}

Describe 'Resolve-LatestVersion' {
    BeforeEach {
        Clear-LatestVersionCache
    }

    It 'Should call correct API URL for github type' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = 'v2.0.0' }
        }

        $result = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo'
        $result | Should -Be 'v2.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
            $Uri -eq 'https://api.github.com/repos/owner/repo/releases/latest'
        }
    }

    It 'Should use custom ApiPath' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = '3.0.0-beta8' }
        }

        $result = Resolve-LatestVersion -Type 'github' -Namespace 'xmlcalabash' -Name 'xmlcalabash3' `
            -ApiPath 'https://custom.example.com/api/v1'
        $result | Should -Be '3.0.0-beta8'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
            $Uri -eq 'https://custom.example.com/api/v1/repos/xmlcalabash/xmlcalabash3/releases/latest'
        }
    }

    It 'Should return $null and warn for unsupported type' {
        $result = Resolve-LatestVersion -Type 'sourceforge' -Namespace 'proj' -Name 'pkg' `
            -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $warnings | Should -BeLike "*not supported*sourceforge*"
    }

    It 'Should return $null and warn on API failure' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith { throw 'API error' }

        $result = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo' `
            -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $warnings | Should -BeLike "*Failed to resolve*"
    }
}

Describe 'Resolve-LatestVersion caching' {
    BeforeEach {
        Clear-LatestVersionCache
        $env:POWERXML_CACHE_TTL_HOURS = $null
    }

    AfterAll {
        Clear-LatestVersionCache
        $env:POWERXML_CACHE_TTL_HOURS = $null
    }

    It 'Should call API on first invocation (cache miss)' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = 'v1.0.0' }
        }

        $result = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo'
        $result | Should -Be 'v1.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot
    }

    It 'Should return cached value without calling API on second invocation' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = 'v1.0.0' }
        }

        Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo' | Out-Null
        $result = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo'
        $result | Should -Be 'v1.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot
    }

    It 'Should re-fetch when cache entry has expired' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = 'v2.0.0' }
        }

        # Seed the cache with an expired entry (4 hours old)
        $cacheKey = 'github/owner/repo'
        $stale = (Get-Date).AddHours(-4)
        & (Get-Module polyglot) {
            $Script:LatestVersionCache['github/owner/repo'] = @{
                Version   = 'v1.0.0'
                Timestamp = $args[0]
            }
        } $stale

        $result = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo'
        $result | Should -Be 'v2.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot
    }

    It 'Should respect POWERXML_CACHE_TTL_HOURS environment variable' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = 'v3.0.0' }
        }

        # Set a very short TTL so the seeded entry is expired
        $env:POWERXML_CACHE_TTL_HOURS = '0.001'  # ~3.6 seconds

        # Seed cache with an entry from 1 minute ago (well past 3.6s)
        $stale = (Get-Date).AddMinutes(-1)
        & (Get-Module polyglot) {
            $Script:LatestVersionCache['github/owner/repo'] = @{
                Version   = 'v2.0.0'
                Timestamp = $args[0]
            }
        } $stale

        $result = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo'
        $result | Should -Be 'v3.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot
    }

    It 'Should clear cache with Clear-LatestVersionCache' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ tag_name = 'v1.0.0' }
        }

        Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo' | Out-Null
        Clear-LatestVersionCache
        Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repo' | Out-Null

        # API should have been called twice since cache was cleared in between
        Should -Invoke Invoke-RestMethod -Times 2 -ModuleName polyglot
    }

    It 'Should cache different packages independently' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            if ($Uri -like '*repoA*') { return [PSCustomObject]@{ tag_name = 'a1.0' } }
            return [PSCustomObject]@{ tag_name = 'b2.0' }
        }

        $a = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repoA'
        $b = Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repoB'
        $a | Should -Be 'a1.0'
        $b | Should -Be 'b2.0'
        Should -Invoke Invoke-RestMethod -Times 2 -ModuleName polyglot

        # Second call for each should be cached
        Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repoA' | Out-Null
        Resolve-LatestVersion -Type 'github' -Namespace 'owner' -Name 'repoB' | Out-Null
        Should -Invoke Invoke-RestMethod -Times 2 -ModuleName polyglot
    }
}

Describe 'Copy-SoftwareComposition -GetLatest' {
    BeforeAll {
        # SBOM with a GitHub component (xmlcalabash3 on GitHub is frozen at 3.0.0-beta8,
        # so "latest" is stable and won't change) and a sourceforge component.
        $getLatestXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="gh-comp">
            <name>xmlcalabash</name>
            <purl>pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta7</purl>
            <externalReferences>
                <reference type="distribution">
                    <url>pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta7?filename=xmlcalabash-3.0.0-beta7.zip</url>
                    <hashes>
                        <hash alg="SHA-256">0000000000000000000000000000000000000000000000000000000000000000</hash>
                    </hashes>
                </reference>
            </externalReferences>
        </component>
        <component type="library" bom-ref="sf-comp">
            <name>morganaxproc</name>
            <purl>pkg:sourceforge/morganaxproc-IIIse@1.8.2</purl>
            <externalReferences>
                <reference type="distribution">
                    <url>pkg:sourceforge/morganaxproc-IIIse@1.8.2?filename=MorganaXProc-IIIse-1.8.2/MorganaXProc-IIIse-1.8.2.zip</url>
                </reference>
            </externalReferences>
        </component>
    </components>
    <compositions>
        <composition bom-ref="test-latest">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="gh-comp"/>
                <dependency ref="sf-comp"/>
            </dependencies>
        </composition>
    </compositions>
</bom>
'@
        $script:getLatestSbom = Join-Path $TestDrive 'get-latest-sbom.xml'
        Set-Content -Path $script:getLatestSbom -Value $getLatestXml -Encoding UTF8
    }

    It 'Should rewrite github purl to resolved latest version' {
        Mock Resolve-LatestVersion -ModuleName polyglot -MockWith {
            if ($Type -eq 'github') { return '3.0.0-beta8' }
            return $null
        }
        # Capture the purl passed to Get-PackageFromPurl
        $script:capturedPurls = @()
        Mock Get-PackageFromPurl -ModuleName polyglot -MockWith {
            $script:capturedPurls += $Purl
            return @("$LocalRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -SbomPath $script:getLatestSbom `
            -TargetComposition 'test-latest' `
            -LocalRepository $env:polyglotpm `
            -GetLatest -ValidateSbom

        # The github component should have the resolved version
        $ghPurl = $script:capturedPurls | Where-Object { $_.Type -eq 'github' }
        $ghPurl.Version | Should -Be '3.0.0-beta8'
    }

    It 'Should fall back to pinned version for unsupported types' {
        Mock Resolve-LatestVersion -ModuleName polyglot -MockWith {
            if ($Type -eq 'github') { return '3.0.0-beta8' }
            return $null
        }
        $script:capturedPurls = @()
        Mock Get-PackageFromPurl -ModuleName polyglot -MockWith {
            $script:capturedPurls += $Purl
            return @("$LocalRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -SbomPath $script:getLatestSbom `
            -TargetComposition 'test-latest' `
            -LocalRepository $env:polyglotpm `
            -GetLatest -ValidateSbom

        # The sourceforge component should keep its pinned version
        $sfPurl = $script:capturedPurls | Where-Object { $_.Type -eq 'sourceforge' }
        $sfPurl.Version | Should -Be '1.8.2'
    }

    It 'Should skip hash validation when version was rewritten' {
        Mock Resolve-LatestVersion -ModuleName polyglot -MockWith {
            if ($Type -eq 'github') { return '3.0.0-beta8' }
            return $null
        }
        Mock Get-PackageFromPurl -ModuleName polyglot -MockWith {
            return @("$LocalRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        $result = Copy-SoftwareComposition `
            -SbomPath $script:getLatestSbom `
            -TargetComposition 'test-latest' `
            -LocalRepository $env:polyglotpm `
            -GetLatest -ValidateSbom -Verbose 4>&1

        $verboseMessages = $result | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        ($verboseMessages | Out-String) | Should -BeLike '*Skipping SBOM hash validation*gh-comp*'
    }

    It 'Should not rewrite when resolved version matches SBOM version' {
        Mock Resolve-LatestVersion -ModuleName polyglot -MockWith {
            if ($Type -eq 'github') { return '3.0.0-beta7' }  # same as SBOM
            return $null
        }
        $script:capturedPurls = @()
        Mock Get-PackageFromPurl -ModuleName polyglot -MockWith {
            $script:capturedPurls += $Purl
            return @("$LocalRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -SbomPath $script:getLatestSbom `
            -TargetComposition 'test-latest' `
            -LocalRepository $env:polyglotpm `
            -GetLatest -ValidateSbom

        # Version should remain unchanged
        $ghPurl = $script:capturedPurls | Where-Object { $_.Type -eq 'github' }
        $ghPurl.Version | Should -Be '3.0.0-beta7'
    }
}

Describe 'Merge-AdditionalPackages' {
    BeforeAll {
        # Build a reusable SBOM template for each test
        $script:mergeTemplate = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="gh-comp">
            <name>xmlcalabash</name>
            <hashes>
                <hash alg="SHA-256">def456</hash>
            </hashes>
            <purl>pkg:github/xmlcalabash/xmlcalabash3@3.0.40</purl>
            <externalReferences>
                <reference type="distribution">
                    <url>pkg:github/xmlcalabash/xmlcalabash3@3.0.40?filename=xmlcalabash-3.0.40.zip</url>
                    <hashes>
                        <hash alg="SHA-256">abc123</hash>
                    </hashes>
                </reference>
            </externalReferences>
        </component>
    </components>
    <compositions>
        <composition bom-ref="test-merge">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="gh-comp"/>
            </dependencies>
        </composition>
    </compositions>
</bom>
'@
    }

    It 'Should rewrite version for matching component' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages @('pkg:github/xmlcalabash/xmlcalabash3@3.0.39') `
            -CompositionRef 'test-merge'

        $comp = $sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'gh-comp' }
        $comp.purl | Should -BeLike '*@3.0.39*'
    }

    It 'Should override the component referenced by the selected composition' {
        [xml]$sbom = Get-Content -Raw -Path "$PSScriptRoot/../sbom.xml"
        $unusedComponent = $sbom.bom.components.component |
            Where-Object { $_."bom-ref" -eq 'xmlcalabash-3.0.54' }
        $unusedXml = $unusedComponent.OuterXml

        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages 'pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.39' `
            -CompositionRef 'pester-tests'

        $selectedComponent = $sbom.bom.components.component |
            Where-Object { $_."bom-ref" -eq 'xmlcalabash-3.0.40' }
        $selectedComponent.purl | Should -Be 'pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.39'
        $selectedComponent.externalReferences.reference.url |
            Should -Be 'pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.39?filename=xmlcalabash-3.0.39.zip'
        $selectedComponent.SelectSingleNode("*[local-name()='hashes']") | Should -BeNullOrEmpty
        $unusedComponent.OuterXml | Should -Be $unusedXml
    }

    It 'Should include a package that exists only outside the selected composition' {
        [xml]$sbom = $script:mergeTemplate
        $composition = $sbom.bom.compositions.composition
        $composition.dependencies.RemoveAll()
        $originalXml = $sbom.bom.components.component.OuterXml

        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages 'pkg:github/xmlcalabash/xmlcalabash3@3.0.39' `
            -CompositionRef 'test-merge'

        $dependency = @($composition.dependencies.dependency)
        $dependency.Count | Should -Be 1
        $includedComponent = $sbom.bom.components.component |
            Where-Object { $_."bom-ref" -eq $dependency[0].ref }
        $includedComponent.purl | Should -Be 'pkg:github/xmlcalabash/xmlcalabash3@3.0.39'
        ($sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'gh-comp' }).OuterXml |
            Should -Be $originalXml
    }

    It 'Should match across all components when no composition is specified' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages 'pkg:github/xmlcalabash/xmlcalabash3@3.0.39'

        $sbom.bom.components.component.purl | Should -Be 'pkg:github/xmlcalabash/xmlcalabash3@3.0.39'
        @($sbom.bom.components.component).Count | Should -Be 1
    }

    It 'Should rewrite distribution URL version' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages @('pkg:github/xmlcalabash/xmlcalabash3@3.0.39') `
            -CompositionRef 'test-merge'

        $comp = $sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'gh-comp' }
        $distUrl = $comp.externalReferences.reference.url
        $distUrl | Should -BeLike '*@3.0.39*'
        $distUrl | Should -BeLike '*xmlcalabash-3.0.39.zip*'
    }

    It 'Should remove component-level and distribution hashes' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages @('pkg:github/xmlcalabash/xmlcalabash3@3.0.39') `
            -CompositionRef 'test-merge'

        $comp = $sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'gh-comp' }
        # Component-level hashes should be gone
        $comp.SelectSingleNode("*[local-name()='hashes']") | Should -BeNullOrEmpty
        # Distribution reference hashes should be gone
        $refNode = $comp.SelectSingleNode(
            "*[local-name()='externalReferences']/*[local-name()='reference']")
        $refNode.SelectSingleNode("*[local-name()='hashes']") | Should -BeNullOrEmpty
    }

    It 'Should add new component when no match exists' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages @('pkg:github/owner/newpkg@1.0.0') `
            -CompositionRef 'test-merge'

        $newComp = $sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'newpkg-additional' }
        $newComp | Should -Not -BeNullOrEmpty
        $newComp.purl | Should -Be 'pkg:github/owner/newpkg@1.0.0'

        # Should also be added to the composition
        $deps = $sbom.bom.compositions.composition.dependencies.dependency
        ($deps | Where-Object { $_.ref -eq 'newpkg-additional' }) | Should -Not -BeNullOrEmpty
    }

    It 'Should be a no-op when version already matches' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages @('pkg:github/xmlcalabash/xmlcalabash3@3.0.40') `
            -CompositionRef 'test-merge'

        $comp = $sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'gh-comp' }
        $comp.purl | Should -BeLike '*@3.0.40*'
        # Hashes should still be present (no rewrite occurred)
        $comp.SelectSingleNode("*[local-name()='hashes']") | Should -Not -BeNullOrEmpty
    }

    It 'Should accept a single purl string' {
        [xml]$sbom = $script:mergeTemplate
        Merge-AdditionalPackages -Sbom $sbom `
            -AdditionalPackages 'pkg:github/xmlcalabash/xmlcalabash3@3.0.39' `
            -CompositionRef 'test-merge'

        $comp = $sbom.bom.components.component | Where-Object { $_."bom-ref" -eq 'gh-comp' }
        $comp.purl | Should -BeLike '*@3.0.39*'
    }
}

Describe 'Copy-SoftwareComposition -AdditionalPackages' {
    It 'Should merge version override into existing SBOM' {
        $script:capturedPurls = @()
        Mock Get-PackageFromPurl -ModuleName polyglot -MockWith {
            $script:capturedPurls += $Purl
            return @("$LocalRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        # Reuse the -GetLatest SBOM fixture (has gh-comp at 3.0.0-beta7)
        $sbomXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="gh-comp">
            <name>xmlcalabash</name>
            <purl>pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta7</purl>
        </component>
    </components>
    <compositions>
        <composition bom-ref="test">
            <aggregate>complete</aggregate>
            <dependencies><dependency ref="gh-comp"/></dependencies>
        </composition>
    </compositions>
</bom>
'@
        $sbomFile = Join-Path $TestDrive 'addpkg-sbom.xml'
        Set-Content -Path $sbomFile -Value $sbomXml -Encoding UTF8

        Copy-SoftwareComposition `
            -SbomPath $sbomFile `
            -TargetComposition 'test' `
            -LocalRepository $env:polyglotpm `
            -AdditionalPackages @('pkg:github/xmlcalabash/xmlcalabash3@3.0.0-beta6') `
            -ValidateSbom

        $ghPurl = $script:capturedPurls | Where-Object { $_.Type -eq 'github' }
        $ghPurl.Version | Should -Be '3.0.0-beta6'
    }

    It 'Should create interstitial SBOM when no sbomPath exists' {
        $script:capturedPurls = @()
        Mock Get-PackageFromPurl -ModuleName polyglot -MockWith {
            $script:capturedPurls += $Purl
            return @("$LocalRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -SbomPath (Join-Path $TestDrive 'nonexistent-sbom.xml') `
            -LocalRepository $env:polyglotpm `
            -AdditionalPackages @('pkg:github/owner/newpkg@2.0.0') `
            -ValidateSbom

        $script:capturedPurls.Count | Should -Be 1
        $script:capturedPurls[0].Name | Should -Be 'newpkg'
        $script:capturedPurls[0].Version | Should -Be '2.0.0'
    }

    It 'Should still throw when no sbomPath and no AdditionalPackages' {
        { Copy-SoftwareComposition `
            -SbomPath 'nonexistent-sbom.xml' `
            -LocalRepository $env:polyglotpm -ValidateSbom } | Should -Throw
    }
}

Describe 'Test-SBOM -ValidateSchema' {
    It 'Should pass for a valid CycloneDX 1.5 SBOM' {
        [xml]$validSbom = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="comp-a">
            <name>comp-a</name>
            <purl>pkg:maven/org.example/a@1.0</purl>
        </component>
    </components>
    <compositions>
        <composition bom-ref="test">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="comp-a"/>
            </dependencies>
        </composition>
    </compositions>
</bom>
'@
        Test-SBOM $validSbom -ValidateSchema | Should -Be $true
    }

    It 'Should throw for an SBOM with invalid component (missing type attribute)' {
        [xml]$invalidSbom = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component bom-ref="bad">
            <name>bad-component</name>
        </component>
    </components>
</bom>
'@
        { Test-SBOM $invalidSbom -ValidateSchema } | Should -Throw '*schema validation failed*'
    }

    It 'Should pass without schema validation even when SBOM is schema-invalid' {
        [xml]$invalidSbom = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component bom-ref="bad">
            <name>bad-component</name>
        </component>
    </components>
</bom>
'@
        # Without -ValidateSchema, only the namespace check runs
        Test-SBOM $invalidSbom | Should -Be $true
    }
}

Describe 'NuGet PURL support' {
    It 'Should parse a NuGet PURL without namespace' {
        $purlString = "pkg:nuget/PhoenixmlDb.Xslt@1.0.0"
        $Purl = ConvertFrom-PkgUri -uriString $purlString

        $Purl.Type | Should -Be "nuget"
        $Purl.Name | Should -Be "PhoenixmlDb.Xslt"
        $Purl.Version | Should -Be "1.0.0"
    }

    It 'Should parse a NuGet PURL with qualifiers' {
        $purlString = "pkg:nuget/Newtonsoft.Json@13.0.3?repository_url=https://github.com/JamesNK/Newtonsoft.Json"
        $Purl = ConvertFrom-PkgUri -uriString $purlString

        $Purl.Type | Should -Be "nuget"
        $Purl.Name | Should -Be "Newtonsoft.Json"
        $Purl.Version | Should -Be "13.0.3"
    }
}

Describe 'Get-PackageFromPurl NuGet handler' {
    It 'Should download nupkg from NuGet API' {
        Mock Invoke-WebRequest -ModuleName polyglot -MockWith {}

        $Purl = [PSCustomObject]@{
            Type             = 'nuget'
            Namespace        = $null
            Name             = 'PhoenixmlDb.Xslt'
            Version          = '1.0.0'
            Qualifiers       = ''
            QualifiersParsed = @{}
            Subpath          = ''
        }

        $result = Get-PackageFromPurl -Purl $Purl -LocalRepository $env:polyglotpm

        $expectedPath = Join-Path $env:polyglotpm 'PhoenixmlDb.Xslt-1.0.0.nupkg'
        $result | Should -Contain $expectedPath
        Should -Invoke Invoke-WebRequest -Times 1 -ModuleName polyglot -ParameterFilter {
            $Uri -eq 'https://api.nuget.org/v3-flatcontainer/phoenixmldb.xslt/1.0.0/phoenixmldb.xslt.1.0.0.nupkg'
        }
    }

    It 'Should skip download when nupkg already present' {
        # Create fake nupkg
        $nupkgPath = Join-Path $env:polyglotpm 'TestPkg-2.0.0.nupkg'
        Set-Content -Path $nupkgPath -Value 'fake'

        Mock Invoke-WebRequest -ModuleName polyglot -MockWith {}

        $Purl = [PSCustomObject]@{
            Type             = 'nuget'
            Namespace        = $null
            Name             = 'TestPkg'
            Version          = '2.0.0'
            Qualifiers       = ''
            QualifiersParsed = @{}
            Subpath          = ''
        }

        $result = Get-PackageFromPurl -Purl $Purl -LocalRepository $env:polyglotpm

        Should -Invoke Invoke-WebRequest -Times 0 -ModuleName polyglot
        $result | Should -Contain $nupkgPath
    }

    It 'Should return installed path when package already extracted' {
        # Create fake installed directory
        $installedDir = Join-Path $env:polyglotpm 'InstalledPkg-3.0.0'
        New-Item -ItemType Directory -Path $installedDir -Force | Out-Null

        Mock Invoke-WebRequest -ModuleName polyglot -MockWith {}

        $Purl = [PSCustomObject]@{
            Type             = 'nuget'
            Namespace        = $null
            Name             = 'InstalledPkg'
            Version          = '3.0.0'
            Qualifiers       = ''
            QualifiersParsed = @{}
            Subpath          = ''
        }

        $result = Get-PackageFromPurl -Purl $Purl -LocalRepository $env:polyglotpm

        Should -Invoke Invoke-WebRequest -Times 0 -ModuleName polyglot
        $result | Should -Contain $installedDir
    }
}

Describe 'Resolve-LatestVersion NuGet' {
    BeforeEach {
        Clear-LatestVersionCache
    }

    It 'Should query NuGet flat-container API' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ versions = @('1.0.0', '1.1.0', '2.0.0') }
        }

        $result = Resolve-LatestVersion -Type 'nuget' -Namespace '' -Name 'PhoenixmlDb.Xslt'
        $result | Should -Be '2.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot -ParameterFilter {
            $Uri -eq 'https://api.nuget.org/v3-flatcontainer/phoenixmldb.xslt/index.json'
        }
    }

    It 'Should return single version when only one exists' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ versions = @('1.0.0') }
        }

        $result = Resolve-LatestVersion -Type 'nuget' -Namespace '' -Name 'SomePackage'
        $result | Should -Be '1.0.0'
    }

    It 'Should cache NuGet results' {
        Mock Invoke-RestMethod -ModuleName polyglot -MockWith {
            return [PSCustomObject]@{ versions = @('1.0.0') }
        }

        Resolve-LatestVersion -Type 'nuget' -Namespace '' -Name 'CachedPkg' | Out-Null
        $result = Resolve-LatestVersion -Type 'nuget' -Namespace '' -Name 'CachedPkg'
        $result | Should -Be '1.0.0'
        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName polyglot
    }
}

# Add similar blocks for other scripts/modules as needed

Describe 'Get-LocalRepositoryPath' {
    BeforeAll {
        # Preserve the repository location configured by the file-level BeforeAll
        $script:OriginalPolyglotpm = $env:polyglotpm
    }

    AfterAll {
        $env:polyglotpm = $script:OriginalPolyglotpm
    }

    It 'Should create the repository directory when it does not exist' {
        $env:polyglotpm = Join-Path $TestDrive "repo-missing"
        Test-Path $env:polyglotpm | Should -Be $false

        $result = Get-LocalRepositoryPath

        Test-Path $env:polyglotpm -PathType Container | Should -Be $true
        $result | Should -Not -BeNullOrEmpty
    }

    It 'Should resolve PSDrive paths to real filesystem paths' {
        $env:polyglotpm = Join-Path $TestDrive "repo-resolve"

        $result = Get-LocalRepositoryPath

        $result | Should -Not -BeLike "TestDrive*"
    }

    It 'Should create the default repository when no environment variable is set' {
        $env:polyglotpm = $null
        $defaultPath = Join-Path $HOME ".polyglotpm"

        $result = Get-LocalRepositoryPath

        $result | Should -Not -BeNullOrEmpty
        Test-Path $defaultPath -PathType Container | Should -Be $true
    }

    It 'Should be idempotent when the repository already exists' {
        $env:polyglotpm = Join-Path $TestDrive "repo-exists"
        New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null

        { Get-LocalRepositoryPath } | Should -Not -Throw
    }
}

Describe 'Test-Composition' {
    BeforeAll {
        $script:sbomFile = Join-Path $TestDrive 'test-composition-sbom.xml'
    }

    BeforeEach {
        $script:repo = Join-Path $TestDrive "tc-repo-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:repo | Out-Null

        # Sourceforge-style package: zip + installed dir
        $zipPath = Join-Path $script:repo 'mylib-1.0.0.zip'
        Set-Content -Path $zipPath -Value 'fake zip content' -NoNewline
        $script:zipHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'mylib-1.0.0') | Out-Null

        # Hashless package: installed dir only
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'nohashlib-2.0.0') | Out-Null

        # GitHub-style package: asset zip + extracted dir
        $ghZipPath = Join-Path $script:repo 'ghlib-3.0.0.zip'
        Set-Content -Path $ghZipPath -Value 'fake gh zip content' -NoNewline
        $script:ghZipHash = (Get-FileHash -Path $ghZipPath -Algorithm SHA256).Hash
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'ghlib-3.0.0') | Out-Null

        $sbomXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="sf-comp">
            <name>mylib</name>
            <purl>pkg:sourceforge/mylib@1.0.0</purl>
            <externalReferences>
                <reference type="distribution">
                    <url>pkg:sourceforge/mylib@1.0.0?filename=mylib-1.0.0.zip</url>
                    <hashes>
                        <hash alg="SHA-256">$($script:zipHash)</hash>
                    </hashes>
                </reference>
            </externalReferences>
        </component>
        <component type="library" bom-ref="nohash-comp">
            <name>nohashlib</name>
            <purl>pkg:sourceforge/nohashlib@2.0.0</purl>
        </component>
        <component type="library" bom-ref="gh-comp">
            <name>ghlib</name>
            <purl>pkg:github/owner/ghlib@3.0.0?filename=ghlib-3.0.0.zip</purl>
            <externalReferences>
                <reference type="distribution">
                    <url>pkg:github/owner/ghlib@3.0.0?filename=ghlib-3.0.0.zip</url>
                    <hashes>
                        <hash alg="SHA-256">$($script:ghZipHash)</hash>
                    </hashes>
                </reference>
            </externalReferences>
        </component>
    </components>
    <compositions>
        <composition bom-ref="comp-a">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="sf-comp"/>
                <dependency ref="nohash-comp"/>
                <dependency ref="ghost-comp"/>
            </dependencies>
        </composition>
        <composition bom-ref="comp-b">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="gh-comp"/>
            </dependencies>
        </composition>
    </compositions>
</bom>
"@
        Set-Content -Path $script:sbomFile -Value $sbomXml -Encoding UTF8
    }

    It 'Should report Installed with verified hash for a matching sourceforge package' {
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-a' -LocalRepository $script:repo
        $sf = $results | Where-Object { $_.BomRef -eq 'sf-comp' }
        $sf.Status | Should -Be 'Installed'
        $sf.HashVerified | Should -Be $true
        $sf.InstalledPath | Should -Be (Join-Path $script:repo 'mylib-1.0.0')
    }

    It 'Should report HashMismatch when the archive does not match the SBOM' {
        Set-Content -Path (Join-Path $script:repo 'mylib-1.0.0.zip') -Value 'corrupted zip content' -NoNewline
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-a' -LocalRepository $script:repo
        $sf = $results | Where-Object { $_.BomRef -eq 'sf-comp' }
        $sf.Status | Should -Be 'HashMismatch'
        $sf.HashVerified | Should -Be $false
        $sf.Detail | Should -BeLike '*Hash mismatch*'
    }

    It 'Should report Missing when the installed directory is absent' {
        Remove-Item (Join-Path $script:repo 'mylib-1.0.0') -Recurse -Force
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-a' -LocalRepository $script:repo
        $sf = $results | Where-Object { $_.BomRef -eq 'sf-comp' }
        $sf.Status | Should -Be 'Missing'
        $sf.Detail | Should -BeLike '*still present*'
    }

    It 'Should report NoHashes when the SBOM carries no hashes' {
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-a' -LocalRepository $script:repo
        $nohash = $results | Where-Object { $_.BomRef -eq 'nohash-comp' }
        $nohash.Status | Should -Be 'NoHashes'
        $nohash.HashVerified | Should -Be $false
    }

    It 'Should report UnknownComponent for unresolvable bom-refs' {
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-a' -LocalRepository $script:repo
        $ghost = $results | Where-Object { $_.BomRef -eq 'ghost-comp' }
        $ghost.Status | Should -Be 'UnknownComponent'
    }

    It 'Should verify github packages against the asset filename' {
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-b' -LocalRepository $script:repo
        $gh = $results | Where-Object { $_.BomRef -eq 'gh-comp' }
        $gh.Status | Should -Be 'Installed'
        $gh.HashVerified | Should -Be $true
        $gh.InstalledPath | Should -Be (Join-Path $script:repo 'ghlib-3.0.0')
    }

    It 'Should report Installed but unverified when the artifact was removed' {
        Remove-Item (Join-Path $script:repo 'mylib-1.0.0.zip') -Force
        $results = Test-Composition -SbomPath $script:sbomFile -TargetComposition 'comp-a' -LocalRepository $script:repo
        $sf = $results | Where-Object { $_.BomRef -eq 'sf-comp' }
        $sf.Status | Should -Be 'Installed'
        $sf.HashVerified | Should -Be $false
        $sf.Detail | Should -BeLike '*no longer present*'
    }

    It 'Should use the first composition when TargetComposition is omitted' {
        $results = Test-Composition -SbomPath $script:sbomFile -LocalRepository $script:repo
        ($results | Where-Object { $_.BomRef -eq 'gh-comp' }) | Should -BeNullOrEmpty
        ($results | Where-Object { $_.BomRef -eq 'sf-comp' }).Status | Should -Be 'Installed'
    }

    It 'Should throw when TargetComposition is not found' {
        { Test-Composition -SbomPath $script:sbomFile -TargetComposition 'nonexistent' -LocalRepository $script:repo } | Should -Throw '*not found*'
    }

    It 'Should throw when the SBOM file does not exist' {
        { Test-Composition -SbomPath (Join-Path $TestDrive 'does-not-exist.xml') -LocalRepository $script:repo } | Should -Throw '*not found*'
    }

    It 'Should never download anything' {
        Mock Invoke-WebRequest -ModuleName polyglot
        Mock Invoke-RestMethod -ModuleName polyglot
        Mock Get-PackageFromPurl -ModuleName polyglot
        Mock Install-Package -ModuleName polyglot

        Test-Composition -SbomPath $script:sbomFile -LocalRepository $script:repo | Out-Null

        Should -Invoke Invoke-WebRequest -Times 0 -ModuleName polyglot
        Should -Invoke Invoke-RestMethod -Times 0 -ModuleName polyglot
        Should -Invoke Get-PackageFromPurl -Times 0 -ModuleName polyglot
        Should -Invoke Install-Package -Times 0 -ModuleName polyglot
    }
}
