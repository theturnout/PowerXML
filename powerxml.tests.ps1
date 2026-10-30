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
        $tempBase = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
        $env:polyglotpm = Join-Path $tempBase "powerxml-test-deps"
    }
    if (-not (Test-Path $env:polyglotpm)) {
        New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
    }
}

AfterAll {
    $env:polyglotpm = $null
}

Describe 'Transform-PXXml' {
    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash"; EngineName = "XML Calabash" }, @{Name = "morganaxproc"; EngineName = "MorganaXProc-IIIse" }
    ) {
        It "$($_.Name) - Reimport module" {
            Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
        }
        It "$($_.Name) - Should exist as a function" {
            Get-Command Transform-PXXml | Should -Not -BeNullOrEmpty
        }
        # Add more specific tests for Transform-PXXml here
        It "$($_.Name) - Should run basic pipeline, stderr" {        
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" -Verbose | Should -BeLike "*Hello, World!" 
            #-Processing "xproc" -Processor "xmlcalabash" -PackageResolution @{TargetComposition = "oscal"} -InPipe -InPort @{} -OutPort @{} -Catalog "$PSScriptRoot/test_data/catalog.xml" -Passthrough @() -PassthroughJava @()
        }

        It "$($_.Name) - Should accept pipeline as raw XML string" {
            $rawXml = Get-Content "$PSScriptRoot/test_data/helloWorld.xpl" -Raw
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $rawXml
            $result | Should -BeLike "*Hello, World!*"
        }

        It "$($_.Name) - Should accept pipeline as .NET XML object" {
            [xml]$xmlObj = Get-Content "$PSScriptRoot/test_data/helloWorld.xpl" -Raw
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $xmlObj
            $result | Should -BeLike "*Hello, World!*"
        }

        It "$($_.Name) - Should run basic pipeline with options, stderr" {
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/optionalHelloWorld.xpl" -Options @{ name = "John" } | Should -BeLike "*Hello, John!"
        }

        It "$($_.Name) - Should be running with correct processor" {        
            [xml]$xmlContent = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/processor.xpl"        
            $xmlContent.supplemental."xproc-engine-name" | Should -Be $_.EngineName
        } 

        It "$($_.Name) - Should generate output to file" {
            $outputFileName = "$TestDrive/output.xml"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        } 

        It "$($_.Name) - Should generate output to stdout" {    
            $xmlContent = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" 
            ([xml]$xmlContent).content | Should -Be "Hello, World!"
        } 
        It "$($_.Name) - Should passthrough input to output via file" {
            $inputFileName = "$TestDrive/input.xml"
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should pass input via object" {
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $xmlInput } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It "$($_.Name) - Should pass input via object through STDIN" {
            $outputFileName = "$TestDrive/output2.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput | Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It 'Should handle option:opt=value' {
            $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipeline -Options @{ name = "value" } | Should -BeLike "*Hello, value!"
        }
        # It 'Should handle option:Q{http://some-namespace}opt=5+3' {
        #     $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #     Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ 'Q{http://some-namespace}opt' = "5+3" } | Should -BeLike "*Hello, 5+3!"
        # }
        # It 'Should handle option:pre:opt=42' {
        #     $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #     $namespaces = @{ pre = "http://example.com/pre" }
        #     Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = 42 } | Should -BeLike "*Hello, 42!"
        # }
        #  It 'Should handle option:pre:opt=?40+2' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = '?40+2' } | Should -BeLike "*Hello, ?40+2!"
        #  }
        #  It "Should handle option:map=map{'key':'value'}" {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      $map = @{ key = 'value' }
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ map = $map } | Should -BeLike "*Hello, @{key = value}!"
        #  }
        #  It 'Should handle option:date=2020-03-28T13:53:00' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ date = '2020-03-28T13:53:00' } | Should -BeLike "*Hello, 2020-03-28T13:53:00!"
        #  }
        #  It 'Should handle option:name=Q{http://some-namespace}name' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ name = 'Q{http://some-namespace}name' } | Should -BeLike "*Hello, Q{http://some-namespace}name!"
        #  }
        #  It 'Should handle option:doc="parse-xml(/' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ doc = "parse-xml('<node />')" } | Should -BeLike "*Hello, parse-xml('<node />')!"
        #  }
        #  It "Should handle option:numbers='(1, 1+1, 2+1)'" {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1, 1+1, 2+1)' } | Should -BeLike "*Hello, (1, 1+1, 2+1)!"
        #  }
        #  It 'Should handle option:numbers=(1,1+1,2+1,2+2)' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1,1+1,2+1,2+2)' } | Should -BeLike "*Hello, (1,1+1,2+1,2+2)!"
        #  }
        It "$($_.Name) - Should support document sequences on input port - file-based" {
            $inputFile1 = "$TestDrive/input1.xml"
            $inputFile2 = "$TestDrive/input2.xml"
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"
            $xmlInput1.Save($inputFile1)
            $xmlInput2.Save($inputFile2)
            $outputFileName = "$TestDrive/output.xml"
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($inputFile1, $inputFile2) } -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            $xmlOutput = Get-Content $outputFileName -Raw
            $xmlOutput | Should -BeLike "*Doc1*"
            $xmlOutput | Should -BeLike "*Doc2*"
        }
        It "$($_.Name) - Should support document sequences on input port - object-based" {
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"            
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($xmlInput1, $xmlInput2) }
            # result is XmlDocument
            $result[0] | Should -BeOfType [xml]
            $result[1] | Should -BeOfType [xml]            
        }
        It "$($_.Name) - CollectOutput should return output file content when outPort is bound" {
            $inputFileName = "$TestDrive/co_input.xml"
            $outputFileName = "$TestDrive/co_output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>CollectMe</message></root>"
            $xmlInput.Save($inputFileName)
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName } -CollectOutput
            # File should still be written to disk
            Test-Path $outputFileName | Should -Be $true
            # Result should contain the document from the output file
            $result | Should -Not -BeNullOrEmpty
            # Result may be a string or XmlDocument depending on the processor's output format
            $first = @($result) | Select-Object -First 1
            ([xml]$first).root.message | Should -Be "CollectMe"
        }

        It "$($_.Name) - CollectOutput without outPort should behave like normal" {
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -CollectOutput
            ([xml]$result).content | Should -Be "Hello, World!"
        }

        It "$($_.Name) - CollectOutput with sequences should return file and stdout content" {
            $inputFile1 = "$TestDrive/co_seq_input1.xml"
            $inputFile2 = "$TestDrive/co_seq_input2.xml"
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>SeqDoc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>SeqDoc2</message></root>"
            $xmlInput1.Save($inputFile1)
            $xmlInput2.Save($inputFile2)
            $outputFileName = "$TestDrive/co_seq_output.xml"
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($inputFile1, $inputFile2) } -OutPort @{ result = $outputFileName } -CollectOutput
            # File should exist on disk
            Test-Path $outputFileName | Should -Be $true
            # Result should contain XML documents from the collected output
            $result | Should -Not -BeNullOrEmpty
            $xmlDocs = @($result | Where-Object { $_ -is [System.Xml.XmlDocument] })
            $xmlDocs.Count | Should -BeGreaterOrEqual 1
        }

        It "$($_.Name) - Should bind single InPort value to the primary port" {
            $inputFileName = "$TestDrive/defport_input.xml"
            $outputFileName = "$TestDrive/defport_output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>DefaultPort</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort $inputFileName -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should bind single OutPort value to the primary port" {
            $outputFileName = "$TestDrive/defport_output2.xml"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -OutPort $outputFileName
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        }

        It "$($_.Name) - Should accept an XML object as single InPort value" {
            $outputFileName = "$TestDrive/defport_output3.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>ObjDefaultPort</message></root>"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort $xmlInput -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should bind an array of documents to the primary port" {
            $inputFile1 = "$TestDrive/defport_input1.xml"
            $inputFile2 = "$TestDrive/defport_input2.xml"
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>DefDoc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>DefDoc2</message></root>"
            $xmlInput1.Save($inputFile1)
            $xmlInput2.Save($inputFile2)
            $outputFileName = "$TestDrive/defport_seq_output.xml"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @($inputFile1, $inputFile2) -OutPort @{ result = $outputFileName }
            $xmlOutput = Get-Content $outputFileName -Raw
            $xmlOutput | Should -BeLike "*DefDoc1*"
            $xmlOutput | Should -BeLike "*DefDoc2*"
        }

        It "$($_.Name) - Should bind to the primary port when multiple ports are declared" {
            $pipelineXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc" name="pipeline" version="3.0">
    <p:input port="doc" primary="false" sequence="true">
        <p:empty/>
    </p:input>
    <p:input port="source" primary="true"/>
    <p:output port="result" primary="true" />
    <p:identity />
</p:declare-step>
'@
            $pipelineFile = "$TestDrive/defport_multi.xpl"
            Set-Content -Path $pipelineFile -Value $pipelineXml
            $inputFileName = "$TestDrive/defport_multi_input.xml"
            $outputFileName = "$TestDrive/defport_multi_output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>MultiPort</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipelineFile -InPort $inputFileName -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should bind to the only declared port when none is marked primary" {
            $pipelineXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc" name="pipeline" version="3.0">
    <p:input port="doc" primary="false"/>
    <p:output port="result" primary="true" />
    <p:identity>
        <p:with-input>
            <p:pipe step="pipeline" port="doc"/>
        </p:with-input>
    </p:identity>
</p:declare-step>
'@
            $pipelineFile = "$TestDrive/defport_single.xpl"
            Set-Content -Path $pipelineFile -Value $pipelineXml
            $inputFileName = "$TestDrive/defport_single_input.xml"
            $outputFileName = "$TestDrive/defport_single_output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>SinglePort</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipelineFile -InPort $inputFileName -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should process XPL using invisible XML with the processor in targetComposition" {
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "oscal" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/ixml.xpl"
            $result | Should -BeLike "*March*"
        }
            

    }
    # It 'Should place output on the pipeline' {
    #     $outputFileName = Join-Path $global:TestDir "output2.xml"
    #     [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
    #     $xmlInput | Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_ -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -OutPort @{"result" = $outputFileName}
    #     Test-Path $outputFileName | Should -Be $true        
    #     [xml]$xmlOutput = Get-Content $outputFileName -Raw
    #     $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
    # }
}

Describe 'XmlCalabash Specific Tests' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    It 'Should handle XML Calabash specific options' {
        [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
        [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"            
        $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } `
            -Processor "xmlcalabash" `
            -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" `
            -InPort @{ source = @($xmlInput1, $xmlInput2) } 
        # result is XmlDocument
        $result[0] | Should -BeOfType [xml]
        $result[1] | Should -BeOfType [xml]         
    }
}

Describe 'Transform-PXXml parameter handling' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }


    It 'Should accept a custom sbomPath via PackageResolution and run pipeline' {
        $customSbom = "$PSScriptRoot/test_data/sbom.xml"
        $result = Transform-PXXml `
            -PackageResolution @{SbomPath = $customSbom; targetComposition = 'pester-tests' } `
            -Processor 'xmlcalabash' `
            -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"
        $result | Should -BeLike "*Hello, World!"
    }

    It 'Should auto-select first composition when targetComposition is omitted' {
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

        $result = Transform-PXXml `
            -PackageResolution @{SbomPath = $tempSbom } `
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

Describe 'Direct step execution' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
        Get-PXNamespace | Unregister-PXNamespace
    }

    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash"; EngineName = "XML Calabash" },
        @{Name = "morganaxproc"; EngineName = "MorganaXProc-IIIse" }
    ) {
        It "$($_.Name) - Should run p:identity directly" {
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" }
            $result | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should run a step with a single-value InPort" {
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort "$PSScriptRoot/test_data/order.xml"
            $result | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should run p:xinclude directly" {
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:xinclude" -InPort @{ source = "$PSScriptRoot/test_data/xinclude-host.xml" }
            $result | Should -BeLike "*Included content here*"
        }

        It "$($_.Name) - Should write step output to a file via outPort" {
            $outputFileName = "$TestDrive/step_output.xml"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" } -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            (Get-Content $outputFileName -Raw) | Should -BeLike "*ORD-001*"
        }
    }

    It "xmlcalabash - Should run p:xslt directly with a stylesheet port" {
        $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" -Step "p:xslt" -InPort @{ source = "$PSScriptRoot/test_data/order.xml"; stylesheet = "$PSScriptRoot/test_data/order-total.xsl" }
        $result | Should -BeLike "*order-summary*"
    }

    It "xmlcalabash - Should default unprefixed step names to the p: namespace" {
        $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" -Step "identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" }
        $result | Should -BeLike "*ORD-001*"
    }

    It "Should throw when -Step is used with -Processing xslt" {
        { Transform-PXXml -Processing "xslt" -Processor "dotnet" -Step "p:xslt" -InPort "$PSScriptRoot/test_data/order.xml" } | Should -Throw "*only supported for XProc*"
    }

    It "Should throw when both -Step and -Pipeline are supplied" {
        { Transform-PXXml -Processor "xmlcalabash" -Step "p:identity" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" } | Should -Throw
    }

    It "Should throw for step prefixes that are not bound to a namespace" {
        { Transform-PXXml -Processor "xmlcalabash" -Step "cx:dtd-validator" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" } } | Should -Throw "*not bound*"
    }

    It "Should accept a registered extension prefix" {
        Register-PXNamespace -Prefix "ex" -Uri "http://example.com/ex"
        $global:CapturedStep = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-XmlCalabash -ModuleName powerxml {
            $global:CapturedStep = $Step
            return "ok"
        }

        Transform-PXXml -Processor "xmlcalabash" -Step "ex:mystep"

        $global:CapturedStep | Should -Be "ex:mystep"
        Unregister-PXNamespace -Prefix "ex"
    }

    It "Should synthesize a shell for morganaxproc step runs" {
        $global:CapturedShell = $null
        $global:CapturedShellPath = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-MorganaXProc -ModuleName powerxml {
            $global:CapturedShellPath = $Pipeline
            $global:CapturedShell = Get-Content -Path $Pipeline -Raw
            return "ok"
        }

        Transform-PXXml -Processor "morganaxproc" -ClassPath "fake.jar" -Step "p:xslt" -InPort @{ source = "in.xml"; stylesheet = "style.xsl" } -OutPort @{ result = "out.xml" }

        $global:CapturedShell | Should -BeLike "*<p:xslt*"
        $global:CapturedShell | Should -BeLike "*<p:input port=`"source`" primary=`"true`"*"
        $global:CapturedShell | Should -BeLike "*<p:with-input port=`"stylesheet`">*"
        $global:CapturedShell | Should -BeLike "*<p:pipe step=`"pipeline`" port=`"stylesheet`"/>*"
        $global:CapturedShell | Should -BeLike "*<p:output port=`"result`" primary=`"true`"*"
        $global:CapturedShell | Should -Not -BeLike "*<p:option *"
        $global:CapturedShell | Should -Not -BeLike "*<p:with-option *"
        # The temporary shell should be cleaned up after the run
        Test-Path $global:CapturedShellPath -PathType Leaf | Should -Be $false
    }

    It "Should declare and forward morganaxproc step options" {
        $global:CapturedShell = $null
        $global:CapturedOptions = $null
        Mock Invoke-MorganaXProc -ModuleName powerxml {
            $global:CapturedShell = Get-Content -Path $Pipeline -Raw
            $global:CapturedOptions = $Options
            return "ok"
        }
        $options = @{ href = 'input.xml?name="quoted"&other=1'; 'ex:mode' = 'custom' }

        Transform-PXXml -Processor "morganaxproc" -ClassPath "fake.jar" -Step "p:load" `
            -Options $options -Namespace @{ ex = "http://example.com/options" }

        [xml]$shell = $global:CapturedShell
        $ns = [System.Xml.XmlNamespaceManager]::new($shell.NameTable)
        $ns.AddNamespace("p", "http://www.w3.org/ns/xproc")
        $shell.DocumentElement.GetNamespaceOfPrefix("ex") | Should -Be "http://example.com/options"
        @($shell.SelectNodes("/p:declare-step/p:option", $ns)).Count | Should -Be 2
        @($shell.SelectNodes("/p:declare-step/p:load/p:with-option", $ns)).Count | Should -Be 2
        foreach ($name in $options.Keys) {
            $declaration = $shell.SelectSingleNode("/p:declare-step/p:option[@name='$name']", $ns)
            $declaration.required | Should -Be "true"
            $binding = $shell.SelectSingleNode("/p:declare-step/p:load/p:with-option[@name='$name']", $ns)
            $binding.select | Should -Be ('$' + $name)
            $global:CapturedOptions[$name] | Should -Be $options[$name]
        }
        $global:CapturedShell | Should -Not -BeLike "*quoted*"
    }
}

Describe 'Input resolution' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    Context "Run URI inputs for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash" },
        @{Name = "morganaxproc" }
    ) {
        It "$($_.Name) - Should accept a file URI as InPort source" {
            $orderFileUri = "file:///" + (("$PSScriptRoot/test_data/order.xml") -replace "\\", "/")
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort @{ source = $orderFileUri }
            $result | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should accept a file URI as Pipeline" {
            $pipelineFileUri = "file:///" + (("$PSScriptRoot/test_data/helloWorld.xpl") -replace "\\", "/")
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipelineFileUri
            $result | Should -BeLike "*Hello, World!"
        }
    }

    It "xmlcalabash - Should accept an http URI as InPort source" {
        $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" -Step "p:identity" -InPort @{ source = "https://www.w3.org/2001/xml.xsd" }
        $first = @($result) | Select-Object -First 1
        $content = if ($first -is [System.Xml.XmlDocument]) { $first.OuterXml } else { [string]$first }
        $content | Should -BeLike "*schema*"
    }

    Context "PURL inputs (deterministic, .NET XSLT path)" {
        BeforeAll {
            # Isolated PolyglotPM repository with pre-installed packages so
            # resolution is fully local (nuget/maven branches have cache checks)
            $script:PreviousPolyglotpm = $env:polyglotpm
            $global:PurlRepo = Join-Path $TestDrive "purl-repo"
            New-Item -ItemType Directory -Path $global:PurlRepo -Force | Out-Null
            $env:polyglotpm = $global:PurlRepo
        }

        AfterAll {
            $env:polyglotpm = $script:PreviousPolyglotpm
        }

        BeforeEach {
            # Fake nuget package: installed dir with a stylesheet deep inside plus input
            $nugetDir = Join-Path $global:PurlRepo "FakePkg-1.0"
            $deepDir = Join-Path $nugetDir "deep"
            New-Item -ItemType Directory -Path $deepDir -Force | Out-Null
            Set-Content -Path (Join-Path $deepDir "transform.xsl") -Value @'
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:template match="/"><purl-result><xsl:value-of select="/root/message"/></purl-result></xsl:template>
</xsl:stylesheet>
'@
            Set-Content -Path (Join-Path $nugetDir "input.xml") -Value "<root><message>purl-resolved</message></root>"

            # Fake maven artifact: jar and pom decoys (so nothing downloads) plus a stylesheet
            $mavenDir = Join-Path $global:PurlRepo "fake-artifact-1.0"
            New-Item -ItemType Directory -Path $mavenDir -Force | Out-Null
            Set-Content -Path (Join-Path $mavenDir "fake-artifact-1.0.jar") -Value "fake jar"
            Set-Content -Path (Join-Path $mavenDir "pom.xml") -Value @'
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>org.fake</groupId>
    <artifactId>fake-artifact</artifactId>
    <version>1.0</version>
    <dependencies/>
</project>
'@
            Set-Content -Path (Join-Path $mavenDir "transform.xsl") -Value (Get-Content -Path (Join-Path $deepDir "transform.xsl") -Raw)
        }

        It 'Should resolve nuget purls via the filename qualifier (recursive search)' {
            $result = Transform-PXXml -Processing "xslt" -Processor "dotnet" `
                -Pipeline "pkg:nuget/FakePkg@1.0?filename=transform.xsl" `
                -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml"
            $result | Should -BeLike "*purl-resolved*"
        }

        It 'Should resolve maven purls via the filename qualifier' {
            $result = Transform-PXXml -Processing "xslt" -Processor "dotnet" `
                -Pipeline "pkg:maven/org.fake/fake-artifact@1.0?filename=transform.xsl" `
                -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml"
            $result | Should -BeLike "*purl-resolved*"
        }

        It 'Should resolve a purl via the #subpath' {
            $result = Transform-PXXml -Processing "xslt" -Processor "dotnet" `
                -Pipeline "pkg:nuget/FakePkg@1.0#deep/transform.xsl" `
                -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml"
            $result | Should -BeLike "*purl-resolved*"
        }

        It 'Should throw when the file is not found in the package' {
            { Transform-PXXml -Processing "xslt" -Processor "dotnet" `
                    -Pipeline "pkg:nuget/FakePkg@1.0?filename=nothere.xsl" `
                    -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml" } | Should -Throw "*not found*"
        }

        It 'Should throw when the filename is ambiguous' {
            Set-Content -Path (Join-Path $global:PurlRepo "FakePkg-1.0\twin.xsl") -Value "twin"
            Set-Content -Path (Join-Path $global:PurlRepo "FakePkg-1.0\deep\twin.xsl") -Value "twin"
            { Transform-PXXml -Processing "xslt" -Processor "dotnet" `
                    -Pipeline "pkg:nuget/FakePkg@1.0?filename=twin.xsl" `
                    -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml" } | Should -Throw "*ambiguous*"
        }

        It 'Should throw when a directory package has no file selector' {
            { Transform-PXXml -Processing "xslt" -Processor "dotnet" `
                    -Pipeline "pkg:nuget/FakePkg@1.0" `
                    -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml" } | Should -Throw "*resolves to a directory*"
        }
    }

    Context "PURL inputs (live, cached)" {
        It 'Should run a pipeline from a real package via purl' {
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" `
                -Pipeline "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.40?filename=xmlcalabash-3.0.40.zip#helloWorld.xpl"
            $result | Should -BeLike "*Share and enjoy*"
        }
    }
}

Describe 'Manual classpath' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash" },
        @{Name = "morganaxproc" }
    ) {
        It "$($_.Name) - Should run with a caller-provided classpath and no dependency resolution" {
            $script:PreviousPolyglotpm = $env:polyglotpm
            $emptyRepo = Join-Path $TestDrive "empty-repo"
            New-Item -ItemType Directory -Path $emptyRepo | Out-Null
            $env:polyglotpm = $emptyRepo
            try {
                # Build the classpath from the standard test cache
                $deps = if ($env:POWERXML_TEST_CACHE) { $env:POWERXML_TEST_CACHE } else { Join-Path $env:TEMP "powerxml-test-deps" }
                if ($_.Name -eq "xmlcalabash") {
                    $procDir = (Get-ChildItem $deps -Directory -Filter "xmlcalabash-*" | Select-Object -First 1).FullName
                    $cp = "$procDir\*;$procDir\lib\*;$procDir\extra\*"
                }
                else {
                    # Pick a Morgana install that actually contains the engine jar
                    # (the cache may hold partial/phantom downloads)
                    $procDir = (Get-ChildItem $deps -Directory -Filter "morganaxproc-IIIse*" |
                        Where-Object { Test-Path (Join-Path $_.FullName "MorganaXProc-IIIse.jar") } |
                        Select-Object -First 1).FullName
                    $libDir = (Get-ChildItem $procDir -Directory -Filter "*lib*" | Select-Object -First 1).FullName
                    $cp = "$procDir\MorganaXProc-IIIse.jar;$libDir\*"
                }

                $result = Transform-PXXml -Processor $_.Name -ClassPath $cp -Step "p:identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" }

                $resultText = (@($result) | ForEach-Object { if ($_ -is [System.Xml.XmlDocument]) { $_.OuterXml } else { [string]$_ } }) -join " "
                $resultText | Should -BeLike "*ORD-001*"
                # Nothing was resolved or downloaded into the repository
                (Get-ChildItem $emptyRepo | Measure-Object).Count | Should -Be 0
            }
            finally {
                $env:polyglotpm = $script:PreviousPolyglotpm
            }
        }
    }

    It "morganaxproc - Should pass a configuration file through with a manual classpath" {
        $deps = if ($env:POWERXML_TEST_CACHE) { $env:POWERXML_TEST_CACHE } else { Join-Path $env:TEMP "powerxml-test-deps" }
        $procDir = (Get-ChildItem $deps -Directory -Filter "morganaxproc-IIIse*" |
            Where-Object { Test-Path (Join-Path $_.FullName "MorganaXProc-IIIse.jar") } |
            Select-Object -First 1).FullName
        $libDir = (Get-ChildItem $procDir -Directory -Filter "*lib*" | Select-Object -First 1).FullName
        $cp = "$procDir\MorganaXProc-IIIse.jar;$libDir\*"
        $userConfig = Join-Path $TestDrive "manual-morgana-config.xml"
        Set-Content -Path $userConfig -Value '<?xml version="1.0" encoding="UTF-8"?><morgana-config xmlns="http://www.xml-project.com/morganaxproc"/>'

        $result = Transform-PXXml -Processor "morganaxproc" -ClassPath $cp -Configuration $userConfig `
            -Step "p:identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" }

        $resultText = (@($result) | ForEach-Object { if ($_ -is [System.Xml.XmlDocument]) { $_.OuterXml } else { [string]$_ } }) -join " "
        $resultText | Should -BeLike "*ORD-001*"
    }

    It 'Should throw when -ClassPath is used with -Processing xslt' {
        { Transform-PXXml -Processing "xslt" -Processor "dotnet" -Step "p:xslt" -InPort "$PSScriptRoot/test_data/order.xml" -ClassPath "foo" } | Should -Throw "*only supported for XProc*"
    }

    It 'Should skip composition resolution when -ClassPath is given' {
        $global:CapturedPaths = $null
        $global:CapturedClassPath = $null
        Mock Invoke-XmlCalabash -ModuleName powerxml {
            $global:CapturedPaths = $Paths
            $global:CapturedClassPath = $ClassPath
            return "ok"
        }

        Transform-PXXml -Processor "xmlcalabash" -ClassPath "C:/some/jars/*" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"

        @($global:CapturedPaths).Count | Should -Be 0
        $global:CapturedClassPath | Should -Be "C:/some/jars/*"
    }
}

Describe 'Multipart MIME' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    BeforeEach {
        # An XSLT 3.0 stylesheet that echoes the order id (works on both engines)
        $script:RoutedXsl = Join-Path $TestDrive "routed.xsl"
        Set-Content -Path $script:RoutedXsl -Value @'
<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:template match="/"><routed><xsl:value-of select="/order/@id"/></routed></xsl:template>
</xsl:stylesheet>
'@
    }

    Context "Run multipart input for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash" },
        @{Name = "morganaxproc" }
    ) {
        It "$($_.Name) - Should route MIME parts to ports by X-Port header" {
            $mimePath = Join-Path $TestDrive "routed.mime"
            ConvertTo-PXMimeMultipart -Path $mimePath -Parts @(
                @{ Port = "source"; ContentType = "application/xml"; Content = ([xml](Get-Content "$PSScriptRoot/test_data/order.xml" -Raw)) },
                @{ Port = "stylesheet"; ContentType = "application/xml"; Content = ([xml](Get-Content $script:RoutedXsl -Raw)) }
            ) | Out-Null

            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name `
                -Step "p:xslt" -InPort @{ source = $mimePath }

            $resultText = (@($result) | ForEach-Object { if ($_ -is [System.Xml.XmlDocument]) { $_.OuterXml } else { [string]$_ } }) -join " "
            $resultText | Should -BeLike "*routed*"
            $resultText | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should bind parts without X-Port to the bound port as a sequence" {
            $mimePath = Join-Path $TestDrive "sequence.mime"
            ConvertTo-PXMimeMultipart -Path $mimePath -Parts @(
                @{ ContentType = "application/xml"; Content = "<root><message>SeqMime1</message></root>" },
                @{ ContentType = "application/xml"; Content = "<root><message>SeqMime2</message></root>" }
            ) | Out-Null

            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = $mimePath }

            @($result).Count | Should -Be 2
            $sequenceText = (@($result) | ForEach-Object { if ($_ -is [System.Xml.XmlDocument]) { $_.OuterXml } else { [string]$_ } }) -join " "
            $sequenceText | Should -BeLike "*SeqMime1*"
            $sequenceText | Should -BeLike "*SeqMime2*"
        }

        It "$($_.Name) - Should write all outputs to a multiplex file with X-Port headers" {
            $mimeOut = Join-Path $TestDrive "out.mime"
            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name `
                -Step "p:xslt" `
                -InPort @{ source = "$PSScriptRoot/test_data/order.xml"; stylesheet = $script:RoutedXsl } `
                -MultiplexOutput $mimeOut

            $result | Should -BeLike "*routed*"
            Test-Path $mimeOut | Should -Be $true
            $message = Get-Content -Path $mimeOut -Raw
            $boundary = (($message -split "`n" | Select-Object -First 1).Trim()).Substring(2)
            $parts = @(Parse-PXMimeMultipart -MimeString $message -Boundary $boundary)
            $parts.Count | Should -Be 1
            $parts[0].Headers["X-Port"] | Should -Be "result"
            $parts[0].Content | Should -BeLike "*routed*"
        }

        It "$($_.Name) - Should round-trip a multiplex file back as input" {
            $mimeOut = Join-Path $TestDrive "roundtrip.mime"
            Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name `
                -Step "p:xslt" `
                -InPort @{ source = "$PSScriptRoot/test_data/order.xml"; stylesheet = $script:RoutedXsl } `
                -MultiplexOutput $mimeOut | Out-Null

            $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/resultpassthru.xpl" -InPort @{ result = $mimeOut }

            $result | Should -BeLike "*routed*"
        }
    }

    It 'Should throw when -MultiplexOutput is used with -Processing xslt' {
        { Transform-PXXml -Processing "xslt" -Processor "dotnet" -Step "p:xslt" -InPort "$PSScriptRoot/test_data/order.xml" -MultiplexOutput "out.mime" } | Should -Throw "*only supported for XProc*"
    }
}

Describe 'Multiplex output collection' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    Context '<Name>' -ForEach @(
        @{ Name = 'xmlcalabash'; Command = 'Invoke-XmlCalabash' }
        @{ Name = 'morganaxproc'; Command = 'Invoke-MorganaXProc' }
    ) {
        BeforeEach {
            Mock $Command -ModuleName powerxml {
                if ($Options.EmitStdout) {
                    '<stdout/>'
                }
                if ($CollectOutput) {
                    foreach ($filePath in $OutPort.Values) {
                        Get-Content -Path $filePath -Raw | Get-PXMultiXmlDocuments
                    }
                }
            }
        }

        It 'Preserves routing and return values: collect=<Collect>, multiplex=<Multiplex>, stdout=<EmitStdout>' -ForEach @(
            foreach ($collect in @($false, $true)) {
                foreach ($multiplex in @($false, $true)) {
                    foreach ($emitStdout in @($false, $true)) {
                        @{ Collect = $collect; Multiplex = $multiplex; EmitStdout = $emitStdout }
                    }
                }
            }
        ) {
            $firstPath = Join-Path $TestDrive 'first.xml'
            $secondPath = Join-Path $TestDrive 'second.xml'
            Set-Content -Path $firstPath -Value '<first/>'
            Set-Content -Path $secondPath -Value '<?xml version="1.0"?><second/><?xml version="1.0"?><third/>'
            $parameters = @{
                Processor = $Name
                ClassPath = 'unused'
                Pipeline = "$PSScriptRoot/test_data/helloWorld.xpl"
                OutPort = @{ secondary = $firstPath; sequence = $secondPath }
                Options = @{ EmitStdout = $EmitStdout }
                CollectOutput = $Collect
            }
            $mimePath = Join-Path $TestDrive 'collected.mime'
            if ($Multiplex) {
                $parameters.MultiplexOutput = $mimePath
            }

            $result = @(Transform-PXXml @parameters)
            $expectedCount = [int]$EmitStdout + (3 * [int]$Collect)
            $result.Count | Should -Be $expectedCount
            if ($EmitStdout) {
                $result[0] | Should -Be '<stdout/>'
            }
            if ($Collect) {
                $resultText = ($result | ForEach-Object { if ($_ -is [System.Xml.XmlDocument]) { $_.OuterXml } else { [string]$_ } }) -join "`n"
                $resultText | Should -BeLike '*first*'
                $resultText | Should -BeLike '*second*'
                $resultText | Should -BeLike '*third*'
            }
            if ($Multiplex) {
                $message = Get-Content -Path $mimePath -Raw
                $boundary = (($message -split "`n")[0].Trim()).Substring(2)
                $parts = @(Parse-PXMimeMultipart -MimeString $message -Boundary $boundary)
                $parts.Count | Should -Be (3 + [int]$EmitStdout)
                foreach ($part in $parts) {
                    $part.Headers['Content-Type'] | Should -Be 'application/xml'
                    (ConvertTo-PXNativeType -MimePart $part) | Should -BeOfType [System.Xml.XmlDocument]
                }
                @($parts | Where-Object { $_.Headers['X-Port'] -eq 'result' }).Count | Should -Be ([int]$EmitStdout)
                $secondary = @($parts | Where-Object { $_.Headers['X-Port'] -eq 'secondary' })
                $secondary.Count | Should -Be 1
                $secondary[0].Content | Should -Be '<first/>'
                $sequence = @($parts | Where-Object { $_.Headers['X-Port'] -eq 'sequence' })
                $sequence.Count | Should -Be 2
                $sequence[0].Content | Should -BeLike '*second*'
                $sequence[1].Content | Should -BeLike '*third*'
            }
        }
    }
}

Describe 'Morgana configuration' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    BeforeEach {
        $xslt30 = Join-Path $TestDrive "xslt30.xsl"
        Set-Content -Path $xslt30 -Value @'
<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:template match="/"><auto-config><xsl:value-of select="name(/*)"/></auto-config></xsl:template>
</xsl:stylesheet>
'@
    }

    It 'Should auto-detect the Saxon connector from the composition paths' {
        $fakeComp = Join-Path $TestDrive "fake-comp"
        New-Item -ItemType Directory -Path $fakeComp -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $fakeComp "Saxon-HE-12.9.jar") -Force | Out-Null
        $config = Get-PXMorganaAutoConfig -Paths @($fakeComp)
        $config["xslt-connector"] | Should -Be "Saxon12-3"
        $config["xquery-connector"] | Should -Be "Saxon12-3"
        $config["ixml-connector"].Count | Should -Be 2
    }

    It 'Should leave connectors unset when no Saxon jar is present' {
        $fakeComp = Join-Path $TestDrive "empty-comp"
        New-Item -ItemType Directory -Path $fakeComp -Force | Out-Null
        $config = Get-PXMorganaAutoConfig -Paths @($fakeComp)
        $config.ContainsKey("xslt-connector") | Should -Be $false
        $config["ixml-connector"].Count | Should -Be 2
    }

    It 'Should generate config XML from a hashtable (1-1 with JSON)' {
        $configPath = ConvertTo-PXXmlConfig -Config @{
            "xslt-connector" = "Saxon12-3"
            "ixml-connector" = @("One", "Two")
            "mediatype-mapping" = @{ "@file-extension" = "ixml"; "@media-type" = "text/plain" }
        } -Root "morgana-config" -Namespace "http://www.xml-project.com/morganaxproc"
        $content = Get-Content -Path $configPath -Raw
        $content | Should -BeLike "*<morgana-config xmlns=`"http://www.xml-project.com/morganaxproc`">*"
        $content | Should -BeLike "*<xslt-connector>Saxon12-3</xslt-connector>*"
        $content | Should -Match "<ixml-connector>One</ixml-connector>[\s\S]*<ixml-connector>Two</ixml-connector>"
        $content | Should -BeLike "*<mediatype-mapping file-extension=`"ixml`" media-type=`"text/plain`"/>*"
        Remove-Item $configPath -Force
    }

    It "morganaxproc - Should run XSLT 3.0 with the auto-injected config" {
        $result = Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "morganaxproc" -Step "p:xslt" -InPort @{ source = "$PSScriptRoot/test_data/order.xml"; stylesheet = $xslt30 }
        $result | Should -BeLike "*auto-config*"
    }

    It "morganaxproc - Should let a -Configuration hashtable override auto-detection" {
        { Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "morganaxproc" -Step "p:xslt" -InPort @{ source = "$PSScriptRoot/test_data/order.xml"; stylesheet = $xslt30 } -Configuration @{ "xslt-connector" = "Saxon10" } } | Should -Throw "*failed with exit code*"
    }

    It "morganaxproc - Should pass a configuration file path through unchanged" {
        $userConfig = Join-Path $TestDrive "user-config.xml"
        Set-Content -Path $userConfig -Value '<?xml version="1.0" encoding="UTF-8"?><morgana-config xmlns="http://www.xml-project.com/morganaxproc"/>'
        $global:CapturedConfig = $null
        Mock Invoke-MorganaXProc -ModuleName powerxml {
            $global:CapturedConfig = $Configuration
            return "ok"
        }

        Transform-PXXml -Processor "morganaxproc" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" -Configuration $userConfig

        $global:CapturedConfig | Should -Be $userConfig
        Test-Path $userConfig | Should -Be $true
    }
}

Describe 'Processor failure handling' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash" },
        @{Name = "morganaxproc" }
    ) {
        It "$($_.Name) - Should throw when the pipeline is invalid" {
            $badPipeline = Join-Path $TestDrive "bad-port.xpl"
            Set-Content -Path $badPipeline -Value "<?xml version=`"1.0`" encoding=`"UTF-8`"?><p:declare-step xmlns:p=`"http://www.w3.org/ns/xproc`" name=`"pipeline`" version=`"3.0`"><p:identity><p:with-input port=`"nope`"/></p:identity></p:declare-step>"
            { Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $badPipeline } | Should -Throw "*failed with exit code*"
        }

        It "$($_.Name) - Should throw when the step does not exist" {
            { Transform-PXXml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:nonexistent-step" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" } } | Should -Throw "*failed with exit code*"
        }
    }
}

Describe 'Composition registry' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    BeforeEach {
        # Reset registry state between tests (unregistering the default clears the selection)
        Get-PXComposition | Unregister-PXComposition
    }

    It 'Should register and get a composition' {
        Register-PXComposition -Name "test-comp" -TargetComposition "pester-tests" -SbomPath "custom.xml" -GetLatest
        $entry = Get-PXComposition -Name "test-comp"

        $entry.Name | Should -Be "test-comp"
        $entry.TargetComposition | Should -Be "pester-tests"
        $entry.SbomPath | Should -Be "custom.xml"
        $entry.GetLatest | Should -Be $true
        $entry.Resolved | Should -Be $false
        $entry.IsDefault | Should -Be $false
    }

    It 'Should warn when overwriting an existing composition' {
        Register-PXComposition -Name "test-comp" -TargetComposition "one"
        Register-PXComposition -Name "test-comp" -TargetComposition "two" -WarningAction SilentlyContinue -WarningVariable warnings

        $warnings | Should -Not -BeNullOrEmpty
        (Get-PXComposition -Name "test-comp").TargetComposition | Should -Be "two"
    }

    It 'Should unregister compositions and tolerate unknown names' {
        Register-PXComposition -Name "test-comp" -TargetComposition "pester-tests"
        Unregister-PXComposition -Name "test-comp"
        (Get-PXComposition).Count | Should -Be 0
        { Unregister-PXComposition -Name "never-registered" } | Should -Not -Throw
    }

    It 'Should throw when selecting an unregistered composition' {
        { Select-PXComposition -Name "never-registered" } | Should -Throw "*not registered*"
    }

    It 'Should run through the session default composition and cache resolved paths' {
        Register-PXComposition -Name "default-comp" -TargetComposition "pester-tests"
        Select-PXComposition -Name "default-comp"

        $result = Transform-PXXml -Processor "xmlcalabash" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"
        $result | Should -BeLike "*Hello, World!*"

        $entry = Get-PXComposition -Name "default-comp"
        $entry.Resolved | Should -Be $true
        $entry.Paths.Count | Should -BeGreaterThan 0

        # A second run must reuse the cached paths: point PolyglotPM at an empty
        # repository — re-resolution would fail or download, caching just runs
        $script:PreviousPolyglotpm = $env:polyglotpm
        $emptyRepo = Join-Path $TestDrive "p12-empty-repo"
        New-Item -ItemType Directory -Path $emptyRepo | Out-Null
        $env:polyglotpm = $emptyRepo
        try {
            $result2 = Transform-PXXml -Processor "xmlcalabash" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"
            $result2 | Should -BeLike "*Hello, World!*"
            (Get-ChildItem $emptyRepo | Measure-Object).Count | Should -Be 0
        }
        finally {
            $env:polyglotpm = $script:PreviousPolyglotpm
        }
    }

    It 'Should let explicit -PackageResolution win over the session default' {
        Register-PXComposition -Name "bogus-default" -TargetComposition "no-such-composition"
        Select-PXComposition -Name "bogus-default"

        $result = Transform-PXXml -Processor "xmlcalabash" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" -PackageResolution @{TargetComposition = "pester-tests" }
        $result | Should -BeLike "*Hello, World!*"
    }

    It 'Should clear the default when it is unregistered' {
        Register-PXComposition -Name "default-comp" -TargetComposition "pester-tests"
        Select-PXComposition -Name "default-comp"
        (Get-PXComposition -Name "default-comp").IsDefault | Should -Be $true

        Unregister-PXComposition -Name "default-comp"

        (Get-PXComposition | Where-Object { $_.IsDefault }) | Should -BeNullOrEmpty
    }
}

Describe 'Namespace registry' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    BeforeEach {
        # Reset the session registry between tests
        Get-PXNamespace | Unregister-PXNamespace
    }

    It 'Should register and get a namespace' {
        Register-PXNamespace -Prefix "pre" -Uri "http://example.com/pre"
        $result = Get-PXNamespace
        $result.Prefix | Should -Be "pre"
        $result.Uri | Should -Be "http://example.com/pre"
    }

    It 'Should filter Get-PXNamespace by prefix' {
        Register-PXNamespace -Prefix "pre" -Uri "http://example.com/pre"
        Register-PXNamespace -Prefix "other" -Uri "http://example.com/other"
        (Get-PXNamespace).Count | Should -Be 2
        (Get-PXNamespace -Prefix "pre").Uri | Should -Be "http://example.com/pre"
    }

    It 'Should warn and overwrite a conflicting prefix' {
        Register-PXNamespace -Prefix "pre" -Uri "http://example.com/one"
        Register-PXNamespace -Prefix "pre" -Uri "http://example.com/two" -WarningAction SilentlyContinue -WarningVariable warnings
        $warnings | Should -Not -BeNullOrEmpty
        (Get-PXNamespace -Prefix "pre").Uri | Should -Be "http://example.com/two"
    }

    It 'Should be idempotent when re-registering the same URI' {
        Register-PXNamespace -Prefix "pre" -Uri "http://example.com/pre"
        { Register-PXNamespace -Prefix "pre" -Uri "http://example.com/pre" } | Should -Not -Throw
        (Get-PXNamespace).Count | Should -Be 1
    }

    It 'Should unregister namespaces and tolerate unknown prefixes' {
        Register-PXNamespace -Prefix "pre" -Uri "http://example.com/pre"
        Unregister-PXNamespace -Prefix "pre"
        (Get-PXNamespace).Count | Should -Be 0
        { Unregister-PXNamespace -Prefix "never-registered" } | Should -Not -Throw
    }

    It 'Should merge the registry with -Namespace, parameter winning' {
        Register-PXNamespace -Prefix "reg" -Uri "http://example.com/reg"
        Register-PXNamespace -Prefix "both" -Uri "http://example.com/reg-both"

        $global:CapturedNamespace = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-XmlCalabash -ModuleName powerxml {
            $global:CapturedNamespace = $Namespace
            return "ok"
        }

        Transform-PXXml `
            -Processor "xmlcalabash" `
            -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" `
            -Namespace @{ both = "http://example.com/param-both"; paramOnly = "http://example.com/param-only" }

        $global:CapturedNamespace | Should -Not -BeNullOrEmpty
        $global:CapturedNamespace["reg"] | Should -Be "http://example.com/reg"
        $global:CapturedNamespace["both"] | Should -Be "http://example.com/param-both"
        $global:CapturedNamespace["paramOnly"] | Should -Be "http://example.com/param-only"
        $global:CapturedNamespace.Count | Should -Be 3
    }

    It 'Should pass only the registry when -Namespace is omitted' {
        Register-PXNamespace -Prefix "solo" -Uri "http://example.com/solo"

        $global:CapturedNamespace = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-MorganaXProc -ModuleName powerxml {
            $global:CapturedNamespace = $Namespace
            return "ok"
        }

        Transform-PXXml `
            -Processor "morganaxproc" `
            -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"

        $global:CapturedNamespace["solo"] | Should -Be "http://example.com/solo"
        $global:CapturedNamespace.Count | Should -Be 1
    }
}
