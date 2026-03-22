# Remove and re-import PowerXML module
Remove-Module powerxml -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/powerxml.psm1" -Force
Describe 'Transform-Xml XProc Processing' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }
    
    Context "XmlCalabash standard out" {
        
        It "Should parse into multiple documents" {
            $thing = @"
=== result :: 1 :: file:/d:/LocalTemp/tmpd3l3sd.xml ====================
<?xml version="1.0" encoding="windows-1252"?>
<root>
   <message>Doc1</message>
</root>
========================================================================
=== result :: 2 :: file:/d:/LocalTemp/tmpvfvtoj.xml ====================
<?xml version="1.0" encoding="windows-1252"?>
<root>
   <message>Doc2</message>
</root>
========================================================================
"@
            $result = $thing | Get-MultiXmlDocuments
            $result[0] | Should -BeOfType [xml]
            $result[1] | Should -BeOfType [xml]
        }
    }

    Context "Multipart MIME output" {

        It "Should parse MIME multipart into multiple XML documents" {
            $mime = @"
--boundary123
Content-Type: application/xml; charset=UTF-8

<?xml version="1.0" encoding="UTF-8"?>
<root><message>MimeDoc1</message></root>
--boundary123
Content-Type: application/xml; charset=UTF-8

<?xml version="1.0" encoding="UTF-8"?>
<root><message>MimeDoc2</message></root>
--boundary123--
"@
            $result = $mime | Get-MultiXmlDocuments
            $result[0] | Should -BeOfType [xml]
            $result[1] | Should -BeOfType [xml]
            $result[0].root.message | Should -Be 'MimeDoc1'
            $result[1].root.message | Should -Be 'MimeDoc2'
        }

        It "Should parse MIME multipart with mixed content types" {
            $mime = @"
--mixedBoundary
Content-Type: application/xml

<root><item>XmlPart</item></root>
--mixedBoundary
Content-Type: text/plain

Hello plain text
--mixedBoundary--
"@
            $result = $mime | Get-MultiXmlDocuments
            $result[0] | Should -BeOfType [xml]
            $result[1] | Should -BeOfType [string]
        }
    }

    Context "Format detection heuristic" {

        It "Should detect XmlCalabash format when input starts with '=== result'" {
            $calabash = @"
=== result :: 1 :: file:/tmp/test.xml ====================
<root/>
========================================================================
"@
            $result = $calabash | Get-MultiXmlDocuments
            $result | Should -BeOfType [xml]
        }

        It "Should detect MIME format when input starts with '--'" {
            $mime = @"
--someBoundary
Content-Type: application/xml

<root/>
--someBoundary--
"@
            $result = $mime | Get-MultiXmlDocuments
            $result | Should -BeOfType [xml]
        }

        It "Should return single document when input matches neither format" {
            $plain = '<root><child>solo</child></root>'
            $result = $plain | Get-MultiXmlDocuments
            $result | Should -Be $plain
        }
    }
}