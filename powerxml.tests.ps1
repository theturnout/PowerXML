# Pester tests for powerxml module

# Import the module
Import-Module "$PSScriptRoot\powerxml.psm1" -Force

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
    Context "Run for each XProc processor" -ForEach @("xmlcalabash") {
        It 'Should exist as a function' {
            Get-Command Transform-Xml | Should -Not -BeNullOrEmpty
        }
        # Add more specific tests for Transform-Xml here
        It 'Should run basic pipeline, stderr' {        
            Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\helloWorld.xpl" -Verbose | Should -Be "Hello, World!" 
            #-Processing "xproc" -Processor "xmlcalabash" -TargetComposition "oscal" -InPipe -InPort @{} -OutPort @{} -Catalog "$PSScriptRoot\test_data\catalog.xml" -Passthrough @() -PassthroughJava @()
        }

        It 'Should run basic pipeline with options, stderr' {
            Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\optionalHelloWorld.xpl" -Options @{ name = "John" } | Should -Be "Hello, John!"
        }


        It 'Should be running with xmlcalabash processor' {        
            [xml]$xmlContent = Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\processor.xpl"        
            $xmlContent.supplemental."xproc-engine-name" | Should -Be "XML Calabash"
        } 

        It 'Should generate output to file' {
            $outputFileName = "$TestDrive/output.xml"
            Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\xmlhelloWorld.xpl" -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true
            [xml]$xmlContent = Get-Content $outputFileName -Raw
            $xmlContent.content | Should -Be "Hello, World!"
        } 

        It 'Should generate output to stdout' {    
            $xmlContent = Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\xmlhelloWorld.xpl" 
            ([xml]$xmlContent).content | Should -Be "Hello, World!"
        } 
        It 'Should passthrough input' {
            $inputFileName = "$TestDrive/input.xml"
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
        }

        It 'Should pass input via object' {
            $inputFileName = "$TestDrive/input.xml"
            $outputFileName = "$TestDrive/output.xml"
            [xml]$xmlInput = "<?xml version=`"1.0`" encoding=`"utf-8`"?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFileName)
            Transform-Xml -targetComposition "pester-tests" -Processor $_ -Pipeline "$PSScriptRoot\test_data\xmlpassthru.xpl" -InPort @{"source" = $inputFileName } -OutPort @{"result" = $outputFileName }
            Test-Path $outputFileName | Should -Be $true        
            [xml]$xmlOutput = Get-Content $outputFileName -Raw
            $xmlInput.OuterXml | Should -Be $xmlOutput.OuterXml
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

