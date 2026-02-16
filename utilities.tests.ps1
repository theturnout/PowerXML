## Utilities MIME Multipart Parser Tests

# Import the PowerXML module

# Remove and re-import PowerXML module
Remove-Module powerxml -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/powerxml.psm1" -Force

# Confirm function is loaded
if (-not (Get-Command Parse-MimeMultipart -ErrorAction SilentlyContinue)) {
    throw "Parse-MimeMultipart function not loaded from PowerXML module"
}
Describe "Parse-MimeMultipart" {
    It "parses a simple multipart message with two parts" {
        $boundary = "myboundary"
        $mime = @"
--myboundary
Content-Type: text/plain

Hello World
--myboundary
Content-Type: text/html

<html><body>Hi</body></html>
--myboundary--
"@
        $result = Parse-MimeMultipart -MimeString $mime -Boundary $boundary
        $result.Count | Should -Be 2
        $result[0].Headers["Content-Type"] | Should -Be "text/plain"
        $result[0].Content | Should -Be "Hello World"
        $result[1].Headers["Content-Type"] | Should -Be "text/html"
        $result[1].Content | Should -Be "<html><body>Hi</body></html>"
    }

    It "handles missing headers and whitespace" {
        $boundary = "b"
        $mime = @"
--b

Just content
--b--
"@
        $result = Parse-MimeMultipart -MimeString $mime -Boundary $boundary
        $result.Count | Should -Be 1
        $result[0].Headers.Count | Should -Be 0
        $result[0].Content | Should -Be "Just content"
    }

    It "parses headers with extra spaces and multiple lines" {
        $boundary = "test"
        $mime = @"
--test
Content-Type: application/json  
X-Custom:  value

{"foo": "bar"}
--test--
"@
        $result = Parse-MimeMultipart -MimeString $mime -Boundary $boundary
        $result.Count | Should -Be 1
        $result[0].Headers["Content-Type"] | Should -Be "application/json"
        $result[0].Headers["X-Custom"] | Should -Be "value"
        $result[0].Content | Should -Be '{"foo": "bar"}'
    }
}

Describe "ConvertTo-NativeType" {
    It "converts application/xml to XmlDocument" {
        $part = @{
            Headers = @{ "Content-Type" = "application/xml; charset=UTF-8" }
            Content = "<doc>Dotless i: ı.</doc>"
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [System.Xml.XmlDocument]
        $result.DocumentElement.Name | Should -Be "doc"
        $result.DocumentElement.InnerText | Should -Be "Dotless i: ı."
    }

    It "converts text/xml to XmlDocument" {
        $part = @{
            Headers = @{ "Content-Type" = "text/xml" }
            Content = "<root><child>value</child></root>"
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [System.Xml.XmlDocument]
        $result.SelectSingleNode("//child").InnerText | Should -Be "value"
    }

    It "converts application/json to PSCustomObject" {
        $part = @{
            Headers = @{ "Content-Type" = "application/json; charset=UTF-8" }
            Content = '{"cat":"😸"}'
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [PSCustomObject]
        $result.cat | Should -Be "😸"
    }

    It "returns text/plain as string" {
        $part = @{
            Headers = @{ "Content-Type" = "text/plain; charset=UTF-8" }
            Content = "Dotless i: ı."
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [string]
        $result | Should -Be "Dotless i: ı."
    }

    It "returns text/html as string" {
        $part = @{
            Headers = @{ "Content-Type" = "text/html" }
            Content = "<html><body>Hello</body></html>"
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [string]
        $result | Should -Be "<html><body>Hello</body></html>"
    }

    It "wraps unknown MIME types in MimeContent" {
        $part = @{
            Headers = @{ 
                "Content-Type" = "application/octet-stream"
                "Content-Disposition" = "attachment"
                "Content-Description" = "file:/test/binary.dat"
            }
            Content = "SGVsbG8gV29ybGQ="  # Base64 for "Hello World"
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [PowerXML.MimeContent]
        $result.ContentType | Should -Be "application/octet-stream"
        $result.ContentDisposition | Should -Be "attachment"
        $result.RawContent | Should -Be "SGVsbG8gV29ybGQ="
        # Base64 decoded binary content
        [System.Text.Encoding]::UTF8.GetString($result.BinaryContent) | Should -Be "Hello World"
    }

    It "wraps custom/unknown types in MimeContent" {
        $part = @{
            Headers = @{ "Content-Type" = "application/x-custom-type" }
            Content = "custom data"
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [PowerXML.MimeContent]
        $result.ContentType | Should -Be "application/x-custom-type"
        $result.RawContent | Should -Be "custom data"
    }

    It "handles parts with no Content-Type header" {
        $part = @{
            Headers = @{}
            Content = "No content type"
        }
        $result = ConvertTo-NativeType -MimePart $part
        $result | Should -BeOfType [PowerXML.MimeContent]
        $result.ContentType | Should -BeNullOrEmpty
        $result.RawContent | Should -Be "No content type"
    }

    It "parses and converts the full multipart test case" {
        $boundary = "B52044cd8-6960-4acf-98ab-81d69f2aa824:91c0a06a-2398-4e55-ac68-797f0e1cf3b4"
        $mime = @"
--B52044cd8-6960-4acf-98ab-81d69f2aa824:91c0a06a-2398-4e55-ac68-797f0e1cf3b4
Content-Disposition: attachment
Content-Type: application/xml; charset=UTF-8
Content-Description: file:/Volumes/Projects/xproc/xmlcalabash3/app/doc.xml

<doc>Dotless i: ı.</doc>

--B52044cd8-6960-4acf-98ab-81d69f2aa824:91c0a06a-2398-4e55-ac68-797f0e1cf3b4
Content-Disposition: attachment
Content-Type: application/json; charset=UTF-8
Content-Description: file:/Volumes/Projects/xproc/xmlcalabash3/app/doc.json

{"cat":"😸"}
--B52044cd8-6960-4acf-98ab-81d69f2aa824:91c0a06a-2398-4e55-ac68-797f0e1cf3b4
Content-Disposition: attachment
Content-Type: text/plain; charset=UTF-8
Content-Description: file:/Volumes/Projects/xproc/xmlcalabash3/app/doc.txt

Dotless i: ı.

--B52044cd8-6960-4acf-98ab-81d69f2aa824:91c0a06a-2398-4e55-ac68-797f0e1cf3b4--
"@
        $parts = Parse-MimeMultipart -MimeString $mime -Boundary $boundary
        $parts.Count | Should -Be 3

        # Convert each part
        $xmlResult = ConvertTo-NativeType -MimePart $parts[0]
        $xmlResult | Should -BeOfType [System.Xml.XmlDocument]
        $xmlResult.DocumentElement.InnerText | Should -Be "Dotless i: ı."

        $jsonResult = ConvertTo-NativeType -MimePart $parts[1]
        $jsonResult | Should -BeOfType [PSCustomObject]
        $jsonResult.cat | Should -Be "😸"

        $textResult = ConvertTo-NativeType -MimePart $parts[2]
        $textResult | Should -BeOfType [string]
        $textResult | Should -Be "Dotless i: ı."
    }

    It "supports pipeline input" {
        $parts = @(
            @{ Headers = @{ "Content-Type" = "text/plain" }; Content = "text1" },
            @{ Headers = @{ "Content-Type" = "application/json" }; Content = '{"a":1}' }
        )
        $results = $parts | ConvertTo-NativeType
        $results.Count | Should -Be 2
        $results[0] | Should -Be "text1"
        $results[1].a | Should -Be 1
    }
}
