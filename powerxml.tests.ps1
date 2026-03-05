# Pester tests for powerxml module

# Import the module

BeforeAll {
    $global:TestDir = $TestDrive
    # Dependency cache: use POWERXML_TEST_CACHE env var, or fall back to a persistent temp directory.
    # Set POWERXML_TEST_CACHE=TestDrive:/ for ephemeral (clean) runs.
    if ($env:POWERXML_TEST_CACHE) {
        $env:polyglotpm = $env:POWERXML_TEST_CACHE
    }
    else {
        $env:polyglotpm = Join-Path ($env:TEMP ?? $env:TMPDIR ?? "/tmp") "powerxml-test-deps"
    }
    if (-not (Test-Path $env:polyglotpm)) {
        New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
    }
}

AfterAll {
    $env:polyglotpm = $null
}

Describe 'Transform-Xml' {
    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash"; EngineName = "XML Calabash" }, @{Name = "morganaxproc"; EngineName = "MorganaXProc-IIIse" }
    ) {
        It "$($_.Name) - Reimport module" {
            Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
        }
        It "$($_.Name) - Should exist as a function" {
            Get-Command Transform-Xml | Should -Not -BeNullOrEmpty
        }
        # Add more specific tests for Transform-Xml here
        It "$($_.Name) - Should run basic pipeline, stderr" {        
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" -Verbose | Should -BeLike "*Hello, World!" 
            #-Processing "xproc" -Processor "xmlcalabash" -TargetComposition "oscal" -InPipe -InPort @{} -OutPort @{} -Catalog "$PSScriptRoot/test_data/catalog.xml" -Passthrough @() -PassthroughJava @()
        }

        It "$($_.Name) - Should accept pipeline as raw XML string" {
            $rawXml = Get-Content "$PSScriptRoot/test_data/helloWorld.xpl" -Raw
            $result = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $rawXml
            $result | Should -BeLike "*Hello, World!*"
        }

        It "$($_.Name) - Should accept pipeline as .NET XML object" {
            [xml]$xmlObj = Get-Content "$PSScriptRoot/test_data/helloWorld.xpl" -Raw
            $result = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $xmlObj
            $result | Should -BeLike "*Hello, World!*"
        }

        It "$($_.Name) - Should run basic pipeline with options, stderr" {
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/optionalHelloWorld.xpl" -Options @{ name = "John" } | Should -BeLike "*Hello, John!"
        }

        It "$($_.Name) - Should be running with correct processor" {        
            [xml]$xmlContent = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/processor.xpl"        
            $xmlContent.supplemental."xproc-engine-name" | Should -Be $_.EngineName
        } 

        It "$($_.Name) - Should generate output to file" {
            $outputFileName = "$TestDrive/output.xml"
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        } 

        It "$($_.Name) - Should generate output to stdout" {    
            $xmlContent = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" 
            ([xml]$xmlContent).content | Should -Be "Hello, World!"
        } 
        It "$($_.Name) - Should passthrough input to output via file" {
            $inputFileName = "$TestDrive/input.xml"
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should pass input via object" {
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $xmlInput } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It "$($_.Name) - Should pass input via object through STDIN" {
            $outputFileName = "$TestDrive/output2.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput | Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It 'Should handle option:opt=value' {
            $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ name = "value" } | Should -BeLike "*Hello, value!"
        }
        # It 'Should handle option:Q{http://some-namespace}opt=5+3' {
        #     $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #     Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ 'Q{http://some-namespace}opt' = "5+3" } | Should -BeLike "*Hello, 5+3!"
        # }
        # It 'Should handle option:pre:opt=42' {
        #     $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #     $namespaces = @{ pre = "http://example.com/pre" }
        #     Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = 42 } | Should -BeLike "*Hello, 42!"
        # }
        #  It 'Should handle option:pre:opt=?40+2' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = '?40+2' } | Should -BeLike "*Hello, ?40+2!"
        #  }
        #  It "Should handle option:map=map{'key':'value'}" {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      $map = @{ key = 'value' }
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ map = $map } | Should -BeLike "*Hello, @{key = value}!"
        #  }
        #  It 'Should handle option:date=2020-03-28T13:53:00' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ date = '2020-03-28T13:53:00' } | Should -BeLike "*Hello, 2020-03-28T13:53:00!"
        #  }
        #  It 'Should handle option:name=Q{http://some-namespace}name' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ name = 'Q{http://some-namespace}name' } | Should -BeLike "*Hello, Q{http://some-namespace}name!"
        #  }
        #  It 'Should handle option:doc="parse-xml(/' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ doc = "parse-xml('<node />')" } | Should -BeLike "*Hello, parse-xml('<node />')!"
        #  }
        #  It "Should handle option:numbers='(1, 1+1, 2+1)'" {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1, 1+1, 2+1)' } | Should -BeLike "*Hello, (1, 1+1, 2+1)!"
        #  }
        #  It 'Should handle option:numbers=(1,1+1,2+1,2+2)' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1,1+1,2+1,2+2)' } | Should -BeLike "*Hello, (1,1+1,2+1,2+2)!"
        #  }
        It "$($_.Name) - Should support document sequences on input port - file-based" {
            $inputFile1 = "$TestDrive/input1.xml"
            $inputFile2 = "$TestDrive/input2.xml"
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"
            $xmlInput1.Save($inputFile1)
            $xmlInput2.Save($inputFile2)
            $outputFileName = "$TestDrive/output.xml"
            $result = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($inputFile1, $inputFile2) } -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            $xmlOutput = Get-Content $outputFileName -Raw
            $xmlOutput | Should -BeLike "*Doc1*"
            $xmlOutput | Should -BeLike "*Doc2*"
        }
        It "$($_.Name) - Should support document sequences on input port - object-based" {
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"            
            $result = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($xmlInput1, $xmlInput2) }
            # result is XmlDocument
            $result[0] | Should -BeOfType [xml]
            $result[1] | Should -BeOfType [xml]            
        }


    }
    # It 'Should place output on the pipeline' {
    #     $outputFileName = Join-Path $global:TestDir "output2.xml"
    #     [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
    #     $xmlInput | Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -OutPort @{"result" = $outputFileName}
    #     Test-Path $outputFileName | Should -Be $true        
    #     [xml]$xmlOutput = Get-Content $outputFileName -Raw
    #     $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
    # }
}

Describe 'Transform-Xml parameter handling' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    It 'Should have an sbomPath parameter' {
        $param = (Get-Command Transform-Xml).Parameters['sbomPath']
        $param | Should -Not -BeNullOrEmpty
        $param.ParameterType.Name | Should -Be 'String'
    }

    It 'Should have a non-mandatory targetComposition parameter' {
        $param = (Get-Command Transform-Xml).Parameters['targetComposition']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
        } | Should -BeNullOrEmpty
    }

    It 'Should accept a custom sbomPath and run pipeline' {
        # The pester-tests composition in the project SBOM works with default path;
        # verify we can point sbomPath to the test_data copy and it still resolves.
        $customSbom = "$PSScriptRoot/test_data/sbom.xml"
        $result = Transform-Xml -sbomPath $customSbom `
            -targetComposition 'pester-tests' `
            -Processor 'xmlcalabash' `
            -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"
        $result | Should -BeLike "*Hello, World!"
    }

    It 'Should auto-select first composition when targetComposition is omitted' {
        # Build a minimal SBOM whose first composition is "pester-tests" pointing at
        # the same components as the real one, so the pipeline actually runs.
        $sbomContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
    <components>
        <component type="library" bom-ref="xmlcalabash-3.0.24">
            <name>xmlcalabash</name>
            <purl>pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24</purl>
            <externalReferences>
                <reference type="distribution">
                    <url>pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24?filename=xmlcalabash-3.0.24.zip</url>
                    <hashes>
                        <hash alg="SHA-256">67e8fa31b76eb5cded20482b711a415e4db9a9d3fce160ed15e4612c333281db</hash>
                    </hashes>
                </reference>
            </externalReferences>
        </component>
    </components>
    <compositions>
        <composition bom-ref="auto-first">
            <aggregate>complete</aggregate>
            <dependencies>
                <dependency ref="xmlcalabash-3.0.24"/>
            </dependencies>
        </composition>
    </compositions>
</bom>
'@
        $tempSbom = Join-Path $TestDrive 'auto-first-sbom.xml'
        Set-Content -Path $tempSbom -Value $sbomContent -Encoding UTF8

        $result = Transform-Xml -sbomPath $tempSbom `
            -Processor 'xmlcalabash' `
            -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"
        $result | Should -BeLike "*Hello, World!"
    }
}

Describe 'Get-PXClassPath' {
    It 'Should exist as a function' {
        Get-Command Get-PXClassPath | Should -Not -BeNullOrEmpty
    }

    # Add more specific tests for Get-PXClassPath here
}


