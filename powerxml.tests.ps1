# Pester tests for powerxml module

# Import the module

BeforeAll {
    # TODO: clear .polyglotpm cache
    #$global:TestDir = Join-Path $env:TEMP "pester-test-$(New-Guid)"
    #New-Item -ItemType Directory -Path $TestDir | Out-Null
    $global:TestDir = $TestDrive
    $env:polyglotpm = (Join-Path $global:TestDir "polyglotpm")
    New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
}


AfterAll {
    #  Remove-Item -Path $global:TestDir -Recurse -Force
    $env:polyglotpm = $null
}

Describe 'Transform-Xml' {
    Context "Run for each XProc processor" -ForEach @(
        @{Name = "xmlcalabash"; EngineName = "XML Calabash" }, @{Name = "morganaxproc"; EngineName = "MorganaXProc-IIIse" }
    ) {
        It "$($_.Name) - Reimport module" {
            Import-Module "$PSScriptRoot\powerxml.psm1" -Force -DisableNameChecking
        }
        It "$($_.Name) - Should exist as a function" {
            Get-Command Transform-Xml | Should -Not -BeNullOrEmpty
        }
        # Add more specific tests for Transform-Xml here
        It "$($_.Name) - Should run basic pipeline, stderr" {        
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\helloWorld.xpl" -Verbose | Should -BeLike "*Hello, World!" 
            #-Processing "xproc" -Processor "xmlcalabash" -TargetComposition "oscal" -InPipe -InPort @{} -OutPort @{} -Catalog "$PSScriptRoot\test_data\catalog.xml" -Passthrough @() -PassthroughJava @()
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
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\optionalHelloWorld.xpl" -Options @{ name = "John" } | Should -BeLike "*Hello, John!"
        }


        It "$($_.Name) - Should be running with correct processor" {        
            [xml]$xmlContent = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\processor.xpl"        
            $xmlContent.supplemental."xproc-engine-name" | Should -Be $_.EngineName
        } 

        It "$($_.Name) - Should generate output to file" {
            $outputFileName = "$TestDrive/output.xml"
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\xmlhelloWorld.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        } 

        It "$($_.Name) - Should generate output to stdout" {    
            $xmlContent = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\xmlhelloWorld.xpl" 
            ([xml]$xmlContent).content | Should -Be "Hello, World!"
        } 
        It "$($_.Name) - Should passthrough input via file" {
            $inputFileName = "$TestDrive/input.xml"
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It "$($_.Name) - Should pass input via object" {
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot\test_data\xmlpassthru.xpl" -InPort @{"source" = $xmlInput } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }
        It 'Should handle option:opt=value' {
            $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
            Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ name = "value" } | Should -BeLike "*Hello, value!"
        }
        # It 'Should handle option:Q{http://some-namespace}opt=5+3' {
        #     $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #     Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ 'Q{http://some-namespace}opt' = "5+3" } | Should -BeLike "*Hello, 5+3!"
        # }
        # It 'Should handle option:pre:opt=42' {
        #     $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #     $namespaces = @{ pre = "http://example.com/pre" }
        #     Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = 42 } | Should -BeLike "*Hello, 42!"
        # }
        #  It 'Should handle option:pre:opt=?40+2' {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ 'pre:opt' = '?40+2' } | Should -BeLike "*Hello, ?40+2!"
        #  }
        #  It "Should handle option:map=map{'key':'value'}" {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #      $map = @{ key = 'value' }
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ map = $map } | Should -BeLike "*Hello, @{key = value}!"
        #  }
        #  It 'Should handle option:date=2020-03-28T13:53:00' {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ date = '2020-03-28T13:53:00' } | Should -BeLike "*Hello, 2020-03-28T13:53:00!"
        #  }
        #  It 'Should handle option:name=Q{http://some-namespace}name' {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ name = 'Q{http://some-namespace}name' } | Should -BeLike "*Hello, Q{http://some-namespace}name!"
        #  }
        #  It 'Should handle option:doc="parse-xml(\' {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ doc = "parse-xml('<node />')" } | Should -BeLike "*Hello, parse-xml('<node />')!"
        #  }
        #  It "Should handle option:numbers='(1, 1+1, 2+1)'" {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
        #      Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline $pipeline -Options @{ numbers = '(1, 1+1, 2+1)' } | Should -BeLike "*Hello, (1, 1+1, 2+1)!"
        #  }
        #  It 'Should handle option:numbers=(1,1+1,2+1,2+2)' {
        #      $pipeline = "$PSScriptRoot\test_data\optionalHelloWorld.xpl"
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
        It "$($_.Name) - Should support document sequences on input port - STDOUT" {
            $xmlInput1 = "<?xml version='1.0'?><root><message>Doc1</message></root>"
            $xmlInput2 = "<?xml version='1.0'?><root><message>Doc2</message></root>"            
            $result = Transform-Xml -targetComposition "pester-tests" -Processor $_.Name -Pipeline "$PSScriptRoot/test_data/xmlseqpassthru.xpl" -InPort @{ source = @($xmlInput1, $xmlInput2) }
            $result | Should -BeLike "*Doc1*"
            $result | Should -BeLike "*Doc2*"            
        }
            
    }


    # It 'Should place output on the pipeline' {
    #     $outputFileName = Join-Path $global:TestDir "output2.xml"
    #     [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
    #     $xmlInput | Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\xmlpassthru.xpl" -InPipe -OutPort @{"result" = $outputFileName}
    #     Test-Path $outputFileName | Should -Be $true        
    #     [xml]$xmlOutput = Get-Content $outputFileName -Raw
    #     $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
    # }
}

Describe 'Get-PXClassPath' {
    It 'Should exist as a function' {
        Get-Command Get-PXClassPath | Should -Not -BeNullOrEmpty
    }

    # Add more specific tests for Get-PXClassPath here
}


