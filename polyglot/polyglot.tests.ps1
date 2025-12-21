# Import the main module if needed
# . "$PSScriptRoot\download-deps.ps1"
# . "$PSScriptRoot\polyglot-pm.ps1"
# . "$PSScriptRoot\purl.ps1"
# . "$PSScriptRoot\sbom.ps1"

BeforeAll {
    # TODO: clear .polyglotpm cache
    #$global:TestDir = Join-Path $env:TEMP "pester-test-$(New-Guid)"
    #New-Item -ItemType Directory -Path $TestDir | Out-Null
    $global:TestDir = "TestDrive:\"
    Import-Module "$PSScriptRoot/../polyglot"

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
        Test-SBOM ".\test_data\sbom.xml" | Should -Be $true
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


# Add similar blocks for other scripts/modules as needed
