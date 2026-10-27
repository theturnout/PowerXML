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
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" -Verbose | Should -BeLike "*Hello, World!" 
            #-Processing "xproc" -Processor "xmlcalabash" -PackageResolution @{TargetComposition = "oscal"} -InPipe -InPort @{} -OutPort @{} -Catalog "$PSScriptRoot/test_data/catalog.xml" -Passthrough @() -PassthroughJava @()
        }

        It "$($_.Name) - Should accept pipeline as raw XML string" {
            $rawXml = Get-Content "$PSScriptRoot/test_data/helloWorld.xpl" -Raw
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $rawXml
            $result | Should -BeLike "*Hello, World!*"
        }

        It "$($_.Name) - Should accept pipeline as .NET XML object" {
            [xml]$xmlObj = Get-Content "$PSScriptRoot/test_data/helloWorld.xpl" -Raw
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $xmlObj
            $result | Should -BeLike "*Hello, World!*"
        }

        It "$($_.Name) - Should run basic pipeline with options, stderr" {
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/optionalHelloWorld.xpl" -Options @{ name = "John" } | Should -BeLike "*Hello, John!"
        }

        It "$($_.Name) - Should be running with correct processor" {        
            [xml]$xmlContent = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/processor.xpl"        
            $xmlContent.supplemental."xproc-engine-name" | Should -Be $_.EngineName
        } 

        It "$($_.Name) - Should generate output to file" {
            $outputFileName = "$TestDrive/output.xml"
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        } 

        It "$($_.Name) - Should generate output to stdout" {    
            $xmlContent = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" 
            ([xml]$xmlContent).content | Should -Be "Hello, World!"
        } 
        It "$($_.Name) - Should passthrough input to output via file" {
            $inputFileName = "$TestDrive/input.xml"
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should pass input via object" {
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $xmlInput } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It "$($_.Name) - Should pass input via object through STDIN" {
            $outputFileName = "$TestDrive/output2.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput | Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It 'Should handle option:opt=value' {
            $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipeline -Options @{ name = "value" } | Should -BeLike "*Hello, value!"
        }
        # It 'Should handle option:Q{http://some-namespace}opt=5+3' {
        #     $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #     Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ 'Q{http://some-namespace}opt' = "5+3" } | Should -BeLike "*Hello, 5+3!"
        # }
        # It 'Should handle option:pre:opt=42' {
        #     $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #     $namespaces = @{ pre = "http://example.com/pre" }
        #     Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = 42 } | Should -BeLike "*Hello, 42!"
        # }
        #  It 'Should handle option:pre:opt=?40+2' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = '?40+2' } | Should -BeLike "*Hello, ?40+2!"
        #  }
        #  It "Should handle option:map=map{'key':'value'}" {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      $map = @{ key = 'value' }
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ map = $map } | Should -BeLike "*Hello, @{key = value}!"
        #  }
        #  It 'Should handle option:date=2020-03-28T13:53:00' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ date = '2020-03-28T13:53:00' } | Should -BeLike "*Hello, 2020-03-28T13:53:00!"
        #  }
        #  It 'Should handle option:name=Q{http://some-namespace}name' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ name = 'Q{http://some-namespace}name' } | Should -BeLike "*Hello, Q{http://some-namespace}name!"
        #  }
        #  It 'Should handle option:doc="parse-xml(/' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ doc = "parse-xml('<node />')" } | Should -BeLike "*Hello, parse-xml('<node />')!"
        #  }
        #  It "Should handle option:numbers='(1, 1+1, 2+1)'" {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1, 1+1, 2+1)' } | Should -BeLike "*Hello, (1, 1+1, 2+1)!"
        #  }
        #  It 'Should handle option:numbers=(1,1+1,2+1,2+2)' {
        #      $pipeline = "$PSScriptRoot/test_data/optionalHelloWorld.xpl"
        #      Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1,1+1,2+1,2+2)' } | Should -BeLike "*Hello, (1,1+1,2+1,2+2)!"
        #  }
        It "$($_.Name) - Should support document sequences on input port - file-based" {
            $inputFile1 = "$TestDrive/input1.xml"
            $inputFile2 = "$TestDrive/input2.xml"
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"
            $xmlInput1.Save($inputFile1)
            $xmlInput2.Save($inputFile2)
            $outputFileName = "$TestDrive/output.xml"
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($inputFile1, $inputFile2) } -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            $xmlOutput = Get-Content $outputFileName -Raw
            $xmlOutput | Should -BeLike "*Doc1*"
            $xmlOutput | Should -BeLike "*Doc2*"
        }
        It "$($_.Name) - Should support document sequences on input port - object-based" {
            [xml]$xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            [xml]$xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"            
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($xmlInput1, $xmlInput2) }
            # result is XmlDocument
            $result[0] | Should -BeOfType [xml]
            $result[1] | Should -BeOfType [xml]            
        }
        It "$($_.Name) - CollectOutput should return output file content when outPort is bound" {
            $inputFileName = "$TestDrive/co_input.xml"
            $outputFileName = "$TestDrive/co_output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>CollectMe</message></root>"
            $xmlInput.Save($inputFileName)
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName } -CollectOutput
            # File should still be written to disk
            Test-Path $outputFileName | Should -Be $true
            # Result should contain the document from the output file
            $result | Should -Not -BeNullOrEmpty
            # Result may be a string or XmlDocument depending on the processor's output format
            $first = @($result) | Select-Object -First 1
            ([xml]$first).root.message | Should -Be "CollectMe"
        }

        It "$($_.Name) - CollectOutput without outPort should behave like normal" {
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -CollectOutput
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
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($inputFile1, $inputFile2) } -OutPort @{ result = $outputFileName } -CollectOutput
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
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort $inputFileName -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should bind single OutPort value to the primary port" {
            $outputFileName = "$TestDrive/defport_output2.xml"
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlhelloWorld.xpl" -OutPort $outputFileName
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        }

        It "$($_.Name) - Should accept an XML object as single InPort value" {
            $outputFileName = "$TestDrive/defport_output3.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>ObjDefaultPort</message></root>"
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -InPort $xmlInput -OutPort @{ result = $outputFileName }
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
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @($inputFile1, $inputFile2) -OutPort @{ result = $outputFileName }
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
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipelineFile -InPort $inputFileName -OutPort @{ result = $outputFileName }
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
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipelineFile -InPort $inputFileName -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should process XPL using invisible XML with the processor in targetComposition" {
            $result = Transform-Xml -PackageResolution @{TargetComposition = "oscal" } -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/ixml.xpl"
            $result | Should -BeLike "*March*"
        }
            

    }
    # It 'Should place output on the pipeline' {
    #     $outputFileName = Join-Path $global:TestDir "output2.xml"
    #     [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
    #     $xmlInput | Transform-Xml -PackageResolution @{TargetComposition = "pester-tests"} -Processor $_ -Pipeline "$PSScriptRoot/test_data/xmlpassthru.xpl" -OutPort @{"result" = $outputFileName}
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
        $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } `
            -Processor "xmlcalabash" `
            -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" `
            -InPort @{ source = @($xmlInput1, $xmlInput2) } 
        # result is XmlDocument
        $result[0] | Should -BeOfType [xml]
        $result[1] | Should -BeOfType [xml]         
    }
}

Describe 'Transform-Xml parameter handling' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }


    It 'Should accept a custom sbomPath via PackageResolution and run pipeline' {
        $customSbom = "$PSScriptRoot/test_data/sbom.xml"
        $result = Transform-Xml `
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

        $result = Transform-Xml `
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
        Get-Namespace | Unregister-Namespace
    }

    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash"; EngineName = "XML Calabash" },
        @{Name = "morganaxproc"; EngineName = "MorganaXProc-IIIse" }
    ) {
        It "$($_.Name) - Should run p:identity directly" {
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" }
            $result | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should run a step with a single-value InPort" {
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort "$PSScriptRoot/test_data/order.xml"
            $result | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should run p:xinclude directly" {
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:xinclude" -InPort @{ source = "$PSScriptRoot/test_data/xinclude-host.xml" }
            $result | Should -BeLike "*Included content here*"
        }

        It "$($_.Name) - Should write step output to a file via outPort" {
            $outputFileName = "$TestDrive/step_output.xml"
            Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" } -OutPort @{ result = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            (Get-Content $outputFileName -Raw) | Should -BeLike "*ORD-001*"
        }
    }

    It "xmlcalabash - Should run p:xslt directly with a stylesheet port" {
        $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" -Step "p:xslt" -InPort @{ source = "$PSScriptRoot/test_data/order.xml"; stylesheet = "$PSScriptRoot/test_data/order-total.xsl" }
        $result | Should -BeLike "*order-summary*"
    }

    It "xmlcalabash - Should default unprefixed step names to the p: namespace" {
        $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" -Step "identity" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" }
        $result | Should -BeLike "*ORD-001*"
    }

    It "Should throw when -Step is used with -Processing xslt" {
        { Transform-Xml -Processing "xslt" -Processor "dotnet" -Step "p:xslt" -InPort "$PSScriptRoot/test_data/order.xml" } | Should -Throw "*only supported for XProc*"
    }

    It "Should throw when both -Step and -Pipeline are supplied" {
        { Transform-Xml -Processor "xmlcalabash" -Step "p:identity" -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl" } | Should -Throw
    }

    It "Should throw for step prefixes that are not bound to a namespace" {
        { Transform-Xml -Processor "xmlcalabash" -Step "cx:dtd-validator" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" } } | Should -Throw "*not bound*"
    }

    It "Should accept a registered extension prefix" {
        Register-Namespace -Prefix "ex" -Uri "http://example.com/ex"
        $global:CapturedStep = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-XmlCalabash -ModuleName powerxml {
            $global:CapturedStep = $Step
            return "ok"
        }

        Transform-Xml -Processor "xmlcalabash" -Step "ex:mystep"

        $global:CapturedStep | Should -Be "ex:mystep"
        Unregister-Namespace -Prefix "ex"
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

        Transform-Xml -Processor "morganaxproc" -Step "p:xslt" -InPort @{ source = "in.xml"; stylesheet = "style.xsl" } -OutPort @{ result = "out.xml" }

        $global:CapturedShell | Should -BeLike "*<p:xslt*"
        $global:CapturedShell | Should -BeLike "*<p:input port=`"source`" primary=`"true`"*"
        $global:CapturedShell | Should -BeLike "*<p:with-input port=`"stylesheet`">*"
        $global:CapturedShell | Should -BeLike "*<p:pipe step=`"pipeline`" port=`"stylesheet`"/>*"
        $global:CapturedShell | Should -BeLike "*<p:output port=`"result`" primary=`"true`"*"
        # The temporary shell should be cleaned up after the run
        Test-Path $global:CapturedShellPath -PathType Leaf | Should -Be $false
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
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:identity" -InPort @{ source = $orderFileUri }
            $result | Should -BeLike "*ORD-001*"
        }

        It "$($_.Name) - Should accept a file URI as Pipeline" {
            $pipelineFileUri = "file:///" + (("$PSScriptRoot/test_data/helloWorld.xpl") -replace "\\", "/")
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $pipelineFileUri
            $result | Should -BeLike "*Hello, World!"
        }
    }

    It "xmlcalabash - Should accept an http URI as InPort source" {
        $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" -Step "p:identity" -InPort @{ source = "https://www.w3.org/2001/xml.xsd" }
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
            $result = Transform-Xml -Processing "xslt" -Processor "dotnet" `
                -Pipeline "pkg:nuget/FakePkg@1.0?filename=transform.xsl" `
                -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml"
            $result | Should -BeLike "*purl-resolved*"
        }

        It 'Should resolve maven purls via the filename qualifier' {
            $result = Transform-Xml -Processing "xslt" -Processor "dotnet" `
                -Pipeline "pkg:maven/org.fake/fake-artifact@1.0?filename=transform.xsl" `
                -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml"
            $result | Should -BeLike "*purl-resolved*"
        }

        It 'Should resolve a purl via the #subpath' {
            $result = Transform-Xml -Processing "xslt" -Processor "dotnet" `
                -Pipeline "pkg:nuget/FakePkg@1.0#deep/transform.xsl" `
                -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml"
            $result | Should -BeLike "*purl-resolved*"
        }

        It 'Should throw when the file is not found in the package' {
            { Transform-Xml -Processing "xslt" -Processor "dotnet" `
                    -Pipeline "pkg:nuget/FakePkg@1.0?filename=nothere.xsl" `
                    -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml" } | Should -Throw "*not found*"
        }

        It 'Should throw when the filename is ambiguous' {
            Set-Content -Path (Join-Path $global:PurlRepo "FakePkg-1.0\twin.xsl") -Value "twin"
            Set-Content -Path (Join-Path $global:PurlRepo "FakePkg-1.0\deep\twin.xsl") -Value "twin"
            { Transform-Xml -Processing "xslt" -Processor "dotnet" `
                    -Pipeline "pkg:nuget/FakePkg@1.0?filename=twin.xsl" `
                    -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml" } | Should -Throw "*ambiguous*"
        }

        It 'Should throw when a directory package has no file selector' {
            { Transform-Xml -Processing "xslt" -Processor "dotnet" `
                    -Pipeline "pkg:nuget/FakePkg@1.0" `
                    -InPort "pkg:nuget/FakePkg@1.0?filename=input.xml" } | Should -Throw "*resolves to a directory*"
        }
    }

    Context "PURL inputs (live, cached)" {
        It 'Should run a pipeline from a real package via purl' {
            $result = Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor "xmlcalabash" `
                -Pipeline "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.40?filename=xmlcalabash-3.0.40.zip#helloWorld.xpl"
            $result | Should -BeLike "*Share and enjoy*"
        }
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
            { Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Pipeline $badPipeline } | Should -Throw "*failed with exit code*"
        }

        It "$($_.Name) - Should throw when the step does not exist" {
            { Transform-Xml -PackageResolution @{TargetComposition = "pester-tests" } -Processor $_.Name -Step "p:nonexistent-step" -InPort @{ source = "$PSScriptRoot/test_data/order.xml" } } | Should -Throw "*failed with exit code*"
        }
    }
}

Describe 'Namespace registry' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }

    BeforeEach {
        # Reset the session registry between tests
        Get-Namespace | Unregister-Namespace
    }

    It 'Should register and get a namespace' {
        Register-Namespace -Prefix "pre" -Uri "http://example.com/pre"
        $result = Get-Namespace
        $result.Prefix | Should -Be "pre"
        $result.Uri | Should -Be "http://example.com/pre"
    }

    It 'Should filter Get-Namespace by prefix' {
        Register-Namespace -Prefix "pre" -Uri "http://example.com/pre"
        Register-Namespace -Prefix "other" -Uri "http://example.com/other"
        (Get-Namespace).Count | Should -Be 2
        (Get-Namespace -Prefix "pre").Uri | Should -Be "http://example.com/pre"
    }

    It 'Should warn and overwrite a conflicting prefix' {
        Register-Namespace -Prefix "pre" -Uri "http://example.com/one"
        Register-Namespace -Prefix "pre" -Uri "http://example.com/two" -WarningAction SilentlyContinue -WarningVariable warnings
        $warnings | Should -Not -BeNullOrEmpty
        (Get-Namespace -Prefix "pre").Uri | Should -Be "http://example.com/two"
    }

    It 'Should be idempotent when re-registering the same URI' {
        Register-Namespace -Prefix "pre" -Uri "http://example.com/pre"
        { Register-Namespace -Prefix "pre" -Uri "http://example.com/pre" } | Should -Not -Throw
        (Get-Namespace).Count | Should -Be 1
    }

    It 'Should unregister namespaces and tolerate unknown prefixes' {
        Register-Namespace -Prefix "pre" -Uri "http://example.com/pre"
        Unregister-Namespace -Prefix "pre"
        (Get-Namespace).Count | Should -Be 0
        { Unregister-Namespace -Prefix "never-registered" } | Should -Not -Throw
    }

    It 'Should merge the registry with -Namespace, parameter winning' {
        Register-Namespace -Prefix "reg" -Uri "http://example.com/reg"
        Register-Namespace -Prefix "both" -Uri "http://example.com/reg-both"

        $global:CapturedNamespace = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-XmlCalabash -ModuleName powerxml {
            $global:CapturedNamespace = $Namespace
            return "ok"
        }

        Transform-Xml `
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
        Register-Namespace -Prefix "solo" -Uri "http://example.com/solo"

        $global:CapturedNamespace = $null
        Mock Copy-SoftwareComposition -ModuleName polyglot { return @("C:/fake-path") }
        Mock Invoke-MorganaXProc -ModuleName powerxml {
            $global:CapturedNamespace = $Namespace
            return "ok"
        }

        Transform-Xml `
            -Processor "morganaxproc" `
            -Pipeline "$PSScriptRoot/test_data/helloWorld.xpl"

        $global:CapturedNamespace["solo"] | Should -Be "http://example.com/solo"
        $global:CapturedNamespace.Count | Should -Be 1
    }
}


