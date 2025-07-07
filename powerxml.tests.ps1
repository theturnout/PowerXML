# Pester tests for powerxml module

# Import the module
Import-Module "$PSScriptRoot\powerxml.psm1" -Force

Describe 'Transform-Xml' {
    It 'Should exist as a function' {
        Get-Command Transform-Xml | Should -Not -BeNullOrEmpty
    }
    # Add more specific tests for Transform-Xml here
    It 'Should run basic pipeline' {        
        Transform-Xml -Pipeline "$PSScriptRoot\test_data\helloWorld.xpl" | Should -Be "Hello, World!" 
        #-Processing "xproc" -Processor "xmlcalabash" -TargetComposition "oscal" -InPipe -InPort @{} -OutPort @{} -Catalog "$PSScriptRoot\test_data\catalog.xml" -Passthrough @() -PassthroughJava @()
    }
}

Describe 'Get-PXClassPath' {
    It 'Should exist as a function' {
        Get-Command Get-PXClassPath | Should -Not -BeNullOrEmpty
    }
    # Add more specific tests for Get-PXClassPath here
}

