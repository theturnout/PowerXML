BeforeAll {
    $global:TestDir = "TestDrive:/"
    Import-Module "$PSScriptRoot/../polyglot" -DisableNameChecking -Force

    # Create a minimal test SBOM file
    $script:TestSbomContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://cyclonedx.org/schema/bom/1.5 https://cyclonedx.org/schema/bom-1.5.xsd">
	<components>
		<component type="library" bom-ref="saxon-he-12">
			<name>Saxon-HE</name>
			<purl>pkg:maven/net.sf.saxon/Saxon-HE@12.4</purl>
		</component>
	</components>
	<compositions>
		<composition bom-ref="xslt-tools">
			<aggregate>complete</aggregate>
			<dependencies>
				<dependency ref="saxon-he-12"/>
			</dependencies>
		</composition>
	</compositions>
</bom>
"@
    $script:TestSbomPath = Join-Path $global:TestDir "test-sbom.xml"
    Set-Content -Path $script:TestSbomPath -Value $script:TestSbomContent
}

Describe 'Get-SBOM' {
    It 'Should load a valid SBOM file' {
        $sbom = Get-SBOM -Path $script:TestSbomPath
        $sbom | Should -Not -BeNullOrEmpty
        $sbom.NamespaceManager | Should -Not -BeNullOrEmpty
        $sbom.CdxNamespace | Should -Be "http://cyclonedx.org/schema/bom/1.5"
    }

    It 'Should throw on non-existent file' {
        { Get-SBOM -Path "nonexistent.xml" } | Should -Throw
    }

    It 'Should throw on invalid SBOM' {
        $invalidPath = Join-Path $global:TestDir "invalid.xml"
        Set-Content -Path $invalidPath -Value "<root><notabom/></root>"
        { Get-SBOM -Path $invalidPath } | Should -Throw
    }
}

Describe 'Save-SBOM' {
    It 'Should save SBOM to file' {
        $sbom = Get-SBOM -Path $script:TestSbomPath
        $outputPath = Join-Path $global:TestDir "output-sbom.xml"
        # Convert TestDrive path to real path for .NET APIs
        $realPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outputPath)
        
        Save-SBOM -Sbom $sbom -Path $realPath
        
        Test-Path $outputPath | Should -Be $true
        $reloaded = [xml](Get-Content -Path $outputPath -Raw)
        $reloaded.bom | Should -Not -BeNullOrEmpty
    }
}

Describe 'Add-SBOMComponent' {
    BeforeEach {
        # Fresh SBOM for each test
        Set-Content -Path $script:TestSbomPath -Value $script:TestSbomContent
        $script:Sbom = Get-SBOM -Path $script:TestSbomPath
    }

    It 'Should add a simple Maven component (xerces)' {
        $component = Add-SBOMComponent -Sbom $script:Sbom `
            -BomRef "xerces" `
            -Name "xerces" `
            -Purl "pkg:maven/xerces/xercesImpl@2.12.2"

        $component | Should -Not -BeNullOrEmpty
        $component.GetAttribute("bom-ref") | Should -Be "xerces"
        $component.GetAttribute("type") | Should -Be "library"
        $component.name | Should -Be "xerces"
        $component.purl | Should -Be "pkg:maven/xerces/xercesImpl@2.12.2"
    }

    It 'Should add a component with hash (schXslt)' {
        $component = Add-SBOMComponent -Sbom $script:Sbom `
            -BomRef "schXslt" `
            -Name "schXslt" `
            -Purl "pkg:maven/name.dmaus.schxslt/schxslt@1.10.1" `
            -Hash "FEA69795F40CBCAC4AF05AE78F480D1C426BBD402DB4ACB9BD06B0117C730794"

        $component | Should -Not -BeNullOrEmpty
        $component.hashes.hash.alg | Should -Be "SHA-256"
        $component.hashes.hash.'#text' | Should -Be "FEA69795F40CBCAC4AF05AE78F480D1C426BBD402DB4ACB9BD06B0117C730794"
    }

    It 'Should add a component with distribution URL (xmlcalabash)' {
        $component = Add-SBOMComponent -Sbom $script:Sbom `
            -BomRef "xmlcalabash-3" `
            -Name "xmlcalabash" `
            -Purl "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24" `
            -DistributionUrl "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24?filename=xmlcalabash-3.0.24.zip" `
            -DistributionHash "67e8fa31b76eb5cded20482b711a415e4db9a9d3fce160ed15e4612c333281db"

        $component | Should -Not -BeNullOrEmpty
        $component.externalReferences.reference.GetAttribute("type") | Should -Be "distribution"
        $component.externalReferences.reference.url | Should -Be "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24?filename=xmlcalabash-3.0.24.zip"
        $component.externalReferences.reference.hashes.hash.'#text' | Should -Be "67e8fa31b76eb5cded20482b711a415e4db9a9d3fce160ed15e4612c333281db"
    }

    It 'Should add an application type component' {
        $component = Add-SBOMComponent -Sbom $script:Sbom `
            -BomRef "morganaxproc-1.8" `
            -Name "MorganaXProc-IIIse" `
            -Purl "pkg:sourceforge/morganaxproc-IIIse@1.8" `
            -Type "application"

        $component.GetAttribute("type") | Should -Be "application"
    }

    It 'Should skip duplicate bom-ref and return existing' {
        # saxon-he-12 already exists in test SBOM
        $component = Add-SBOMComponent -Sbom $script:Sbom `
            -BomRef "saxon-he-12" `
            -Name "Different Name" `
            -Purl "pkg:maven/different/purl@1.0" 3>&1

        # Should return existing component, not create new
        $component.name | Should -Be "Saxon-HE"
    }

    It 'Should add component without purl' {
        $component = Add-SBOMComponent -Sbom $script:Sbom `
            -BomRef "custom-tool" `
            -Name "Custom XML Tool"

        $component | Should -Not -BeNullOrEmpty
        $component.name | Should -Be "Custom XML Tool"
        $component.purl | Should -BeNullOrEmpty
    }
}

Describe 'Add-SBOMComposition' {
    BeforeEach {
        Set-Content -Path $script:TestSbomPath -Value $script:TestSbomContent
        $script:Sbom = Get-SBOM -Path $script:TestSbomPath
    }

    It 'Should add a composition with multiple dependencies' {
        # First add some components
        Add-SBOMComponent -Sbom $script:Sbom -BomRef "xerces" -Name "xerces" -Purl "pkg:maven/xerces/xercesImpl@2.12.2"
        Add-SBOMComponent -Sbom $script:Sbom -BomRef "xmlresolver" -Name "xmlresolver" -Purl "pkg:maven/org.xmlresolver/xmlresolver@6.0.12"

        $composition = Add-SBOMComposition -Sbom $script:Sbom `
            -BomRef "xml-validation" `
            -Dependencies @("saxon-he-12", "xerces", "xmlresolver")

        $composition | Should -Not -BeNullOrEmpty
        $composition.GetAttribute("bom-ref") | Should -Be "xml-validation"
        $composition.aggregate | Should -Be "complete"
        $composition.dependencies.dependency.Count | Should -Be 3
    }

    It 'Should skip duplicate composition bom-ref' {
        # xslt-tools already exists
        $composition = Add-SBOMComposition -Sbom $script:Sbom `
            -BomRef "xslt-tools" `
            -Dependencies @("different-dep") 3>&1

        # Should return existing
        $deps = @($composition.dependencies.dependency)
        $deps[0].ref | Should -Be "saxon-he-12"
    }

    It 'Should add composition for XProc pipeline tools' {
        Add-SBOMComponent -Sbom $script:Sbom -BomRef "xmlcalabash-3" -Name "xmlcalabash" -Purl "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24"
        Add-SBOMComponent -Sbom $script:Sbom -BomRef "morganaxproc-1.8" -Name "MorganaXProc" -Purl "pkg:sourceforge/morganaxproc-IIIse@1.8"

        $composition = Add-SBOMComposition -Sbom $script:Sbom `
            -BomRef "xproc-engines" `
            -Dependencies @("xmlcalabash-3", "morganaxproc-1.8")

        $composition | Should -Not -BeNullOrEmpty
        $composition.dependencies.dependency.Count | Should -Be 2
    }
}

Describe 'Add-SBOMCompositionDependency' {
    BeforeEach {
        Set-Content -Path $script:TestSbomPath -Value $script:TestSbomContent
        $script:Sbom = Get-SBOM -Path $script:TestSbomPath
    }

    It 'Should add a dependency to existing composition' {
        Add-SBOMComponent -Sbom $script:Sbom -BomRef "schXslt" -Name "schXslt" -Purl "pkg:maven/name.dmaus.schxslt/schxslt@1.10.1"
        
        $dep = Add-SBOMCompositionDependency -Sbom $script:Sbom `
            -CompositionRef "xslt-tools" `
            -DependencyRef "schXslt"

        $dep | Should -Not -BeNullOrEmpty
        $dep.GetAttribute("ref") | Should -Be "schXslt"
    }

    It 'Should throw on non-existent composition' {
        { Add-SBOMCompositionDependency -Sbom $script:Sbom `
            -CompositionRef "nonexistent" `
            -DependencyRef "saxon-he-12" } | Should -Throw
    }

    It 'Should skip duplicate dependency' {
        # saxon-he-12 already in xslt-tools
        $dep = Add-SBOMCompositionDependency -Sbom $script:Sbom `
            -CompositionRef "xslt-tools" `
            -DependencyRef "saxon-he-12" -WarningAction SilentlyContinue

        $dep.GetAttribute("ref") | Should -Be "saxon-he-12"
    }
}

Describe 'Round-trip SBOM modifications' {
    It 'Should persist changes after save and reload' {
        $sbom = Get-SBOM -Path $script:TestSbomPath
        
        # Add XML tooling components
        Add-SBOMComponent -Sbom $sbom -BomRef "coffeefilter" -Name "coffeefilter" -Purl "pkg:maven/org.nineml/coffeefilter@3.2.9"
        Add-SBOMComponent -Sbom $sbom -BomRef "coffeegrinder" -Name "coffeegrinder" -Purl "pkg:maven/org.nineml/coffeegrinder@3.2.9"
        Add-SBOMComposition -Sbom $sbom -BomRef "ixml-tools" -Dependencies @("coffeefilter", "coffeegrinder")
        
        # Save - convert TestDrive path to real path for .NET APIs
        $outputPath = Join-Path $global:TestDir "roundtrip.xml"
        $realPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outputPath)
        Save-SBOM -Sbom $sbom -Path $realPath
        
        # Reload and verify
        $reloaded = Get-SBOM -Path $outputPath
        
        $coffeefilter = $reloaded.DocumentElement.SelectSingleNode(
            "cdx:components/cdx:component[@bom-ref='coffeefilter']", 
            $reloaded.NamespaceManager
        )
        $coffeefilter | Should -Not -BeNullOrEmpty
        $coffeefilter.purl | Should -Be "pkg:maven/org.nineml/coffeefilter@3.2.9"
        
        $ixmlComposition = $reloaded.DocumentElement.SelectSingleNode(
            "cdx:compositions/cdx:composition[@bom-ref='ixml-tools']",
            $reloaded.NamespaceManager
        )
        $ixmlComposition | Should -Not -BeNullOrEmpty
        $ixmlComposition.dependencies.dependency.Count | Should -Be 2
    }
}
