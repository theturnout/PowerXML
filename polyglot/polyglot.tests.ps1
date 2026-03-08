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

    $env:polyglotpm = (Join-Path $global:TestDir "polyglotpm")
    New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
}

AfterAll {
    #  Remove-Item -Path $global:TestDir -Recurse -Force
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
        { Copy-SoftwareComposition -sbomPath "nonexistent.xml" -targetComposition "test" } | Should -Throw
    }

    It 'Should pass on valid SBOM file' {
        # load the xml file
        $sbom = [xml](Get-Content -Path "test_data/sbom.xml")
        Test-SBOM $sbom | Should -Be $true
    }

    It 'Should parse a PURL' {
        $purlString = "pkg:maven/org.apache.commons/commons-lang3@3.12.0?classifier=sources"
        $purl = ConvertFrom-PkgUri -uriString $purlString

        $purl.Type | Should -Be "maven"
        $purl.Namespace | Should -Be "org.apache.commons"
        $purl.Name | Should -Be "commons-lang3"
        $purl.Version | Should -Be "3.12.0"
        $purl.QualifiersParsed["classifier"] | Should -Be "sources"
    }

    It 'Should parse a PURL with subpath' {
        $purlString = "pkg:npm/angular/cli@12.0.0#src/app"
        $purl = ConvertFrom-PkgUri -uriString $purlString

        $purl.Type | Should -Be "npm"
        $purl.Namespace | Should -Be "angular"
        $purl.Name | Should -Be "cli"
        $purl.Version | Should -Be "12.0.0"
        $purl.Subpath | Should -Be "#src/app"
    }

    It 'Should parse a PURL with multiple qualifiers' {
        $purlString = "pkg:deb/debian/curl@7.50.3-1?arch=amd64&distro=jessie"
        $purl = ConvertFrom-PkgUri -uriString $purlString

        $purl.Type | Should -Be "deb"
        $purl.Namespace | Should -Be "debian"
        $purl.Name | Should -Be "curl"
        $purl.Version | Should -Be "7.50.3-1"
        $purl.QualifiersParsed["arch"] | Should -Be "amd64"
        $purl.QualifiersParsed["distro"] | Should -Be "jessie"
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
        Mock Get-PackageFromPurl { return @("$localRepository\fake") } -ModuleName polyglot
        Mock Install-Package { return $DownloadedPath } -ModuleName polyglot

        $result = Copy-SoftwareComposition `
            -sbomPath $script:twoCompSbom `
            -localRepository $env:polyglotpm -Verbose 4>&1

        # Verbose stream should mention the first composition's bom-ref
        $verboseMessages = $result | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $verboseMessages | Should -Not -BeNullOrEmpty
        ($verboseMessages | Out-String) | Should -BeLike "*first*"
    }

    It 'Should use explicit targetComposition when provided' {
        Mock Get-PackageFromPurl { return @("$localRepository\fake") } -ModuleName polyglot
        Mock Install-Package { return $DownloadedPath } -ModuleName polyglot

        $result = Copy-SoftwareComposition `
            -sbomPath $script:twoCompSbom `
            -targetComposition 'second' `
            -localRepository $env:polyglotpm -Verbose 4>&1

        # Should NOT emit the auto-select verbose message
        $verboseMessages = $result | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $autoMsg = $verboseMessages | Where-Object { $_.Message -like '*No targetComposition specified*' }
        $autoMsg | Should -BeNullOrEmpty
    }

    It 'Should throw when targetComposition is not specified and SBOM has no compositions' {
        { Copy-SoftwareComposition `
                -sbomPath $script:noCompSbom `
                -localRepository $env:polyglotpm } | Should -Throw '*No compositions found*'
    }

    It 'Should throw when explicit targetComposition is not found' {
        { Copy-SoftwareComposition `
                -sbomPath $script:twoCompSbom `
                -targetComposition 'nonexistent' `
                -localRepository $env:polyglotpm } | Should -Throw '*not found*'
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
                        <hash alg="SHA-256">oldhash000</hash>
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
            $script:capturedPurls += $purl
            return @("$localRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -sbomPath $script:getLatestSbom `
            -targetComposition 'test-latest' `
            -localRepository $env:polyglotpm `
            -GetLatest

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
            $script:capturedPurls += $purl
            return @("$localRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -sbomPath $script:getLatestSbom `
            -targetComposition 'test-latest' `
            -localRepository $env:polyglotpm `
            -GetLatest

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
            return @("$localRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        $result = Copy-SoftwareComposition `
            -sbomPath $script:getLatestSbom `
            -targetComposition 'test-latest' `
            -localRepository $env:polyglotpm `
            -GetLatest -Verbose 4>&1

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
            $script:capturedPurls += $purl
            return @("$localRepository\fake")
        }
        Mock Install-Package -ModuleName polyglot -MockWith { return $DownloadedPath }

        Copy-SoftwareComposition `
            -sbomPath $script:getLatestSbom `
            -targetComposition 'test-latest' `
            -localRepository $env:polyglotpm `
            -GetLatest

        # Version should remain unchanged
        $ghPurl = $script:capturedPurls | Where-Object { $_.Type -eq 'github' }
        $ghPurl.Version | Should -Be '3.0.0-beta7'
    }
}

# Add similar blocks for other scripts/modules as needed
