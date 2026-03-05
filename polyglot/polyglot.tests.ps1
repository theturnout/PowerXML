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

# Add similar blocks for other scripts/modules as needed
