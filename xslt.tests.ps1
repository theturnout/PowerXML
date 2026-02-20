# Remove and re-import PowerXML module
Remove-Module powerxml -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/powerxml.psm1" -Force
Describe 'Transform-Xml XSLT Processing' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }
    
    Context "Run for each XSLT processor" -ForEach @(
        @{Name = "dotnet"; Description = ".NET XslCompiledTransform" },
        @{Name = "msxml"; Description = "MSXML 6.0 COM" }
    ) {
        BeforeAll {
            # Skip MSXML tests on non-Windows
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and (PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
            }
        }
        
        It "$($_.Name) - Should run identity transform" {
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and (PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
                return
            }
            $inputFile = "$TestDrive/xslt_input.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root><message>Hello, World!</message></root>"
            $xmlInput.Save($inputFile)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                -InPort @{ source = $inputFile }
            
            $result | Should -BeLike "*<root>*"
            $result | Should -BeLike "*<message>Hello, World!</message>*"
        }
        
        It "$($_.Name) - Should output to file" {
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and (PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
                return
            }
            $inputFile = "$TestDrive/xslt_input2.xml"
            $outputFile = "$TestDrive/xslt_output.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root><data>Test Data</data></root>"
            $xmlInput.Save($inputFile)
            
            Transform-Xml `
                -Processing "xslt" `
                -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                -InPort @{ source = $inputFile } `
                -OutPort @{ result = $outputFile }
            
            Test-Path $outputFile | Should -Be $true
            $content = Get-Content $outputFile -Raw
            $content | Should -BeLike "*<data>Test Data</data>*"
        }
        
        It "$($_.Name) - Should pass XSLT parameters" {
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and ($PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
                return
            }
            $inputFile = "$TestDrive/xslt_input3.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root/>"
            $xmlInput.Save($inputFile)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/hello.xsl" `
                -InPort @{ source = $inputFile } `
                -Options @{ greeting = "Hi"; name = "Tester" }
            
            $result | Should -BeLike "*Hi, Tester!*"
        }
        
        It "$($_.Name) - Should use default XSLT parameters when none provided" {
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and ($PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
                return
            }
            $inputFile = "$TestDrive/xslt_input4.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root/>"
            $xmlInput.Save($inputFile)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/hello.xsl" `
                -InPort @{ source = $inputFile }
            
            $result | Should -BeLike "*Hello, World!*"
        }
        
        It "$($_.Name) - Should accept input XML as object" {
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and ($PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
                return
            }
            [xml]$xmlInput = "<?xml version='1.0'?><root><item>Object Test</item></root>"
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor $_.Name `
                -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                -InPort @{ source = $xmlInput }
            
            $result | Should -BeLike "*<item>Object Test</item>*"
        }
        
        It "$($_.Name) - Should accept stylesheet as raw XML string" {
            if ($_.Name -eq "msxml" -and (-not $IsWindows -and ($PSVersionTable.PSEdition -eq 'Core'))) {
                Set-ItResult -Skipped -Because "MSXML is only available on Windows"
                return
            }
            $inputFile = "$TestDrive/xslt_input5.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root><data>String XSL Test</data></root>"
            $xmlInput.Save($inputFile)
            
            $xslString = Get-Content "$PSScriptRoot/test_data/identity.xsl" -Raw
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor $_.Name `
                -Pipeline $xslString `
                -InPort @{ source = $inputFile }
            
            $result | Should -BeLike "*<data>String XSL Test</data>*"
        }
    }
    
    Context "AltovaXML processor (XSLT 2.0)" {
        BeforeAll {
            # Check if AltovaXML is available
            $script:AltovaAvailable = $false
            if ($IsWindows -or $PSVersionTable.PSEdition -ne 'Core') {
                try {
                    $null = New-Object -ComObject AltovaXML.Application
                    $script:AltovaAvailable = $true
                }
                catch {
                    $script:AltovaAvailable = $false
                }
            }
        }
        
        It "altova - Should run identity transform" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/altova_input.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root><message>Hello, Altova!</message></root>"
            $xmlInput.Save($inputFile)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor "altova" `
                -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                -InPort @{ source = $inputFile }
            
            $result | Should -BeLike "*<root>*"
            $result | Should -BeLike "*<message>Hello, Altova!</message>*"
        }
        
        It "altova - Should output to file" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/altova_input2.xml"
            $outputFile = "$TestDrive/altova_output.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root><data>Altova File Test</data></root>"
            $xmlInput.Save($inputFile)
            
            Transform-Xml `
                -Processing "xslt" `
                -Processor "altova" `
                -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                -InPort @{ source = $inputFile } `
                -OutPort @{ result = $outputFile }
            
            Test-Path $outputFile | Should -Be $true
            $content = Get-Content $outputFile -Raw
            $content | Should -BeLike "*<data>Altova File Test</data>*"
        }
        
        It "altova - Should pass XSLT parameters" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/altova_input3.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root/>"
            $xmlInput.Save($inputFile)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor "altova" `
                -Pipeline "$PSScriptRoot/test_data/hello.xsl" `
                -InPort @{ source = $inputFile } `
                -Options @{ greeting = "Greetings"; name = "AltovaUser" }
            
            $result | Should -BeLike "*Greetings, AltovaUser!*"
        }
        
        It "altova - Should use default XSLT parameters when none provided" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/altova_input4.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root/>"
            $xmlInput.Save($inputFile)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor "altova" `
                -Pipeline "$PSScriptRoot/test_data/hello.xsl" `
                -InPort @{ source = $inputFile }
            
            $result | Should -BeLike "*Hello, World!*"
        }
        
        It "altova - Should process schema-aware XSLT 2.0 with typed values" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/order.xml"
            # Create order XML with typed numeric values
            $orderXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<order id="ORD-001">
    <item>
        <name>Widget</name>
        <quantity>5</quantity>
        <price>10.50</price>
    </item>
    <item>
        <name>Gadget</name>
        <quantity>2</quantity>
        <price>25.00</price>
    </item>
    <item>
        <name>Gizmo</name>
        <quantity>10</quantity>
        <price>5.25</price>
    </item>
</order>
"@
            [System.IO.File]::WriteAllText($inputFile, $orderXml, [System.Text.Encoding]::UTF8)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor "altova" `
                -Pipeline "$PSScriptRoot/test_data/order-total.xsl" `
                -InPort @{ source = $inputFile }
            
            # Verify XSLT 2.0 features worked:
            # - sum() with typed integer values: 5 + 2 + 10 = 17
            $result | Should -BeLike "*<item-count>17</item-count>*"
            # - for expression with typed decimal arithmetic: (5*10.50) + (2*25.00) + (10*5.25) = 52.50 + 50.00 + 52.50 = 155.00
            $result | Should -BeLike "*<total-value>155.00</total-value>*"
            # - Sorted by line total descending: Widget (52.50), Gizmo (52.50), Gadget (50.00)
            $result | Should -BeLike "*<order-summary*id=`"ORD-001`"*"
        }
        
        It "altova - Should fail schema-aware XSLT 2.0 when input doesn't match schema" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/invalid_order.xml"
            # Create invalid order XML:
            # - quantity should be xs:integer but contains text
            # - price should be xs:decimal but contains text
            # - missing required 'id' attribute on order element
            $invalidOrderXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<order>
    <item>
        <name>Widget</name>
        <quantity>not-a-number</quantity>
        <price>invalid</price>
    </item>
</order>
"@
            [System.IO.File]::WriteAllText($inputFile, $invalidOrderXml, [System.Text.Encoding]::UTF8)
            
            # Should throw because XML doesn't validate against the imported schema
            { Transform-Xml `
                    -Processing "xslt" `
                    -Processor "altova" `
                    -Pipeline "$PSScriptRoot/test_data/order-total.xsl" `
                    -InPort @{ source = $inputFile } } | Should -Throw
        }
        
        It "altova - Should apply PSVI default attribute values from schema" {
            if (-not $script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is not installed or registered"
                return
            }
            $inputFile = "$TestDrive/product_minimal.xml"
            # Create product XML WITHOUT optional attributes
            # Schema validation via PSVI should inject default attribute values:
            # - @status = "active"
            # - @currency = "USD"
            # - @taxRate = 0.10
            # - @warehouse = "MAIN"
            $productXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<product>
    <name>Test Widget</name>
    <price>100.00</price>
    <quantity>2</quantity>
</product>
"@
            [System.IO.File]::WriteAllText($inputFile, $productXml, [System.Text.Encoding]::UTF8)
            
            $result = Transform-Xml `
                -Processing "xslt" `
                -Processor "altova" `
                -Pipeline "$PSScriptRoot/test_data/product-invoice.xsl" `
                -InPort @{ source = $inputFile }
            
            # Check if PSVI default injection is supported
            # AltovaXML Community Edition does not support this feature
            #  if ($result -like "*<status></status>*") {
            #      Set-ItResult -Skipped -Because "PSVI default value injection requires schema-aware XSLT processor (e.g., Saxon-EE, Altova commercial)"
            #      return
            #  }
            
            # Verify PSVI default attribute values were injected:
            $result | Should -BeLike "*<status>active</status>*"
            $result | Should -BeLike "*<currency>USD</currency>*"
            $result | Should -BeLike "*<warehouse>MAIN</warehouse>*"
            # Tax rate from default @taxRate="0.10" = 10%
            $result | Should -BeLike "*<tax-rate>10%</tax-rate>*"
            # Calculated values using PSVI default taxRate:
            # subtotal = 100.00 * 2 = 200.00
            # total = 200.00 * (1 + 0.10) = 220.00
            $result | Should -BeLike "*<subtotal>200.00</subtotal>*"
            $result | Should -BeLike "*<total>220.00</total>*"
        }
        
        It "altova - Should throw helpful error when not installed" {
            if ($script:AltovaAvailable) {
                Set-ItResult -Skipped -Because "AltovaXML is installed, cannot test missing COM error"
                return
            }
            if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
                Set-ItResult -Skipped -Because "Test only applicable on Windows"
                return
            }
            $inputFile = "$TestDrive/altova_err_input.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root/>"
            $xmlInput.Save($inputFile)
            
            { Transform-Xml `
                    -Processing "xslt" `
                    -Processor "altova" `
                    -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                    -InPort @{ source = $inputFile } } | Should -Throw "*AltovaXML*not be installed*"
        }
    }
    
    Context "Error handling" {
        It "Should throw error for unsupported processor" {
            $inputFile = "$TestDrive/xslt_err_input.xml"
            [xml]$xmlInput = "<?xml version='1.0'?><root/>"
            $xmlInput.Save($inputFile)
            
            { Transform-Xml `
                    -Processing "xslt" `
                    -Processor "unsupported" `
                    -Pipeline "$PSScriptRoot/test_data/identity.xsl" `
                    -InPort @{ source = $inputFile } } | Should -Throw "*Unsupported processor*"
        }
        
        It "Should throw error when no input XML provided" {
            { Transform-Xml `
                    -Processing "xslt" `
                    -Processor "dotnet" `
                    -Pipeline "$PSScriptRoot/test_data/identity.xsl" } | Should -Throw "*requires input XML*"
        }
    }
}