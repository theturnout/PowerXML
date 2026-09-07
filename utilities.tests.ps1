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
        $result = @(Parse-MimeMultipart -MimeString $mime -Boundary $boundary)
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
        $result = @(Parse-MimeMultipart -MimeString $mime -Boundary $boundary)
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

# MIME Torture Test Suite based on Ryan Finnie's MIME Torture Test v1.0
Describe "MIME Torture Test - Parse-MimeMultipart" {
    BeforeAll {
        $script:tortureTestPath = "$PSScriptRoot/test_data/rf-mime-torture-test-1.0.mbox.txt"
        $script:tortureTestContent = Get-Content $tortureTestPath -Raw
        $script:mainBoundary = "=-qYxqvD9rbH0PNeExagh1"
    }

    It "parses boundary with special characters (=-prefix)" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        $parts | Should -Not -BeNullOrEmpty
        $parts.Count | Should -Be 11
    }

    It "correctly identifies Content-Type for all top-level parts" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        
        # Part 0: text/plain intro
        $parts[0].Headers['Content-Type'] | Should -BeLike 'text/plain*'
        
        # Parts 1-10: message/rfc822
        for ($i = 1; $i -lt $parts.Count; $i++) {
            $parts[$i].Headers['Content-Type'] | Should -Be 'message/rfc822'
        }
    }

    It "parses Content-Disposition header" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        
        # All parts have Content-Disposition: inline
        for ($i = 1; $i -lt $parts.Count; $i++) {
            $parts[$i].Headers['Content-Disposition'] | Should -Be 'inline'
        }
    }

    It "parses Content-Description header" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        
        # Part 1 has Futurama quote
        $parts[1].Headers['Content-Description'] | Should -Be "I'll be whatever I wanna do. --Fry"
    }

    It "handles folded (multi-line) headers" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        
        # Part 9 has a folded Content-Description header
        $parts[9].Headers['Content-Description'] | Should -BeLike '*spirit is willing*bruised*Zapp*'
    }

    It "preserves content of text/plain intro part" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        
        $parts[0].Content | Should -BeLike '*Welcome to Ryan Finnie*MIME torture test*'
        $parts[0].Content | Should -BeLike '*Futurama quotes*'
    }

    It "preserves message/rfc822 content with nested headers" {
        $parts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
        
        # Part 1 contains a nested message - should have Subject header in content
        $parts[1].Content | Should -BeLike '*Subject: plain jane message*'
        $parts[1].Content | Should -BeLike '*This is a plain text/plain message*'
    }
}

Describe "MIME Torture Test - Nested Multipart Parsing" {
    BeforeAll {
        $script:tortureTestPath = "$PSScriptRoot/test_data/rf-mime-torture-test-1.0.mbox.txt"
        $script:tortureTestContent = Get-Content $tortureTestPath -Raw
        $script:mainBoundary = "=-qYxqvD9rbH0PNeExagh1"
        $script:topLevelParts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
    }

    It "parses nested multipart/mixed (3 layers deep)" {
        # Part 2 contains nested message with its own multipart/mixed
        $part2Content = $topLevelParts[2].Content
        
        # Extract boundary from nested message headers
        $part2Content | Should -BeLike '*boundary="=-9Brg7LoMERBrIDtMRose"*'
        
        # Parse the nested content (skip the rfc822 headers first)
        $nestedBoundary = "=-9Brg7LoMERBrIDtMRose"
        $nestedParts = Parse-MimeMultipart -MimeString $part2Content -Boundary $nestedBoundary
        
        $nestedParts.Count | Should -Be 2
        $nestedParts[0].Headers['Content-Type'] | Should -BeLike 'text/plain*'
        $nestedParts[1].Headers['Content-Type'] | Should -Be 'message/rfc822'
    }

    It "parses deeply nested message (the original message - 3rd layer)" {
        $part2Content = $topLevelParts[2].Content
        $nestedParts = Parse-MimeMultipart -MimeString $part2Content -Boundary "=-9Brg7LoMERBrIDtMRose"
        
        # The second nested part contains another message/rfc822
        $deeperContent = $nestedParts[1].Content
        $deeperContent | Should -BeLike '*boundary="=-XFYecI7w+0shpolXq8bb"*'
        
        # Parse the deepest layer
        $deepestParts = Parse-MimeMultipart -MimeString $deeperContent -Boundary "=-XFYecI7w+0shpolXq8bb"
        
        $deepestParts.Count | Should -Be 2
        $deepestParts[0].Content | Should -BeLike '*3rd layer deep*'
        $deepestParts[1].Headers['Content-Type'] | Should -BeLike 'application/x-gzip*'
    }

    It "handles base64 encoded attachments" {
        $part2Content = $topLevelParts[2].Content
        $nestedParts = Parse-MimeMultipart -MimeString $part2Content -Boundary "=-9Brg7LoMERBrIDtMRose"
        $deeperContent = $nestedParts[1].Content
        $deepestParts = Parse-MimeMultipart -MimeString $deeperContent -Boundary "=-XFYecI7w+0shpolXq8bb"
        
        # The attachment is base64 encoded gzip
        $deepestParts[1].Headers['Content-Transfer-Encoding'] | Should -Be 'base64'
        $deepestParts[1].Headers['Content-Disposition'] | Should -BeLike '*filename=foo.gz*'
        $deepestParts[1].Content | Should -BeLike 'H4sIAOHBmD8AA4vML1XPyVHISy1LLVJIy8xLUchNVeQCAHbe764WAAAA'
    }

    It "parses multipart/alternative with text and HTML" {
        # Part 6 has multipart/mixed with text/html and text/plain
        $part6Content = $topLevelParts[6].Content
        $part6Content | Should -BeLike '*boundary="=-ZCKMfHzvHMyK1iBu4kff"*'
        
        $nestedParts = Parse-MimeMultipart -MimeString $part6Content -Boundary "=-ZCKMfHzvHMyK1iBu4kff"
        
        $nestedParts.Count | Should -Be 2
        $nestedParts[0].Headers['Content-Type'] | Should -BeLike 'text/html*'
        $nestedParts[0].Content | Should -BeLike '*<!DOCTYPE HTML*'
        $nestedParts[1].Headers['Content-Type'] | Should -BeLike 'text/plain*'
        $nestedParts[1].Content | Should -BeLike '*This is the text part*'
    }

    It "parses complex multipart/signed structure" {
        # Part 9 has multipart/signed with deeply nested structure
        $part9Content = $topLevelParts[9].Content
        $part9Content | Should -BeLike '*multipart/signed*boundary="=-vH3FQO9a8icUn1ROCoAi"*'
        
        $signedParts = Parse-MimeMultipart -MimeString $part9Content -Boundary "=-vH3FQO9a8icUn1ROCoAi"
        
        $signedParts.Count | Should -Be 2
        $signedParts[0].Headers['Content-Type'] | Should -BeLike 'multipart/mixed*'
        $signedParts[1].Headers['Content-Type'] | Should -BeLike 'application/pgp-signature*'
    }

    It "handles PGP signature content" {
        $part9Content = $topLevelParts[9].Content
        $signedParts = Parse-MimeMultipart -MimeString $part9Content -Boundary "=-vH3FQO9a8icUn1ROCoAi"
        
        $signedParts[1].Content | Should -BeLike '*-----BEGIN PGP SIGNATURE-----*'
        $signedParts[1].Content | Should -BeLike '*-----END PGP SIGNATURE-----*'
    }

    It "parses multipart/related with embedded images" {
        # Part 10 has proper alternative/related structure
        $part10Content = $topLevelParts[10].Content
        $part10Content | Should -BeLike '*boundary="=-tyGlQ9JvB5uvPWzozI+y"*'
        
        $altParts = Parse-MimeMultipart -MimeString $part10Content -Boundary "=-tyGlQ9JvB5uvPWzozI+y"
        
        $altParts.Count | Should -Be 2
        $altParts[0].Headers['Content-Type'] | Should -BeLike 'text/plain*'
        $altParts[1].Headers['Content-Type'] | Should -BeLike 'multipart/related*'
        
        # Parse the related part
        $relatedParts = Parse-MimeMultipart -MimeString $altParts[1].Content -Boundary "=-bFkxH1S3HVGcxi+o/5jG"
        
        $relatedParts.Count | Should -Be 2
        $relatedParts[0].Headers['Content-Type'] | Should -BeLike 'text/html*'
        $relatedParts[1].Headers['Content-Type'] | Should -Be 'image/gif'
        $relatedParts[1].Headers['Content-ID'] | Should -Be '<1066973340.4232.46.camel@localhost>'
    }
}

Describe "MIME Torture Test - ConvertTo-NativeType" {
    BeforeAll {
        $script:tortureTestPath = "$PSScriptRoot/test_data/rf-mime-torture-test-1.0.mbox.txt"
        $script:tortureTestContent = Get-Content $tortureTestPath -Raw
        $script:mainBoundary = "=-qYxqvD9rbH0PNeExagh1"
        $script:topLevelParts = Parse-MimeMultipart -MimeString $tortureTestContent -Boundary $mainBoundary
    }

    It "converts text/plain intro to string" {
        $result = ConvertTo-NativeType -MimePart $topLevelParts[0]
        $result | Should -BeOfType [string]
        $result | Should -BeLike '*Welcome to Ryan Finnie*'
    }

    It "wraps message/rfc822 in MimeContent" {
        $result = ConvertTo-NativeType -MimePart $topLevelParts[1]
        $result | Should -BeOfType [PowerXML.MimeContent]
        $result.ContentType | Should -Be 'message/rfc822'
        $result.RawContent | Should -BeLike '*Subject: plain jane message*'
    }

    It "converts nested HTML content to string" {
        # Get HTML from part 6
        $part6Content = $topLevelParts[6].Content
        $nestedParts = Parse-MimeMultipart -MimeString $part6Content -Boundary "=-ZCKMfHzvHMyK1iBu4kff"
        
        $htmlResult = ConvertTo-NativeType -MimePart $nestedParts[0]
        $htmlResult | Should -BeOfType [string]
        $htmlResult | Should -BeLike '*<!DOCTYPE HTML*'
    }

    It "wraps binary image/gif in MimeContent with base64 decoded content" {
        # Get GIF from part 10's nested related part
        $part10Content = $topLevelParts[10].Content
        $altParts = Parse-MimeMultipart -MimeString $part10Content -Boundary "=-tyGlQ9JvB5uvPWzozI+y"
        $relatedParts = Parse-MimeMultipart -MimeString $altParts[1].Content -Boundary "=-bFkxH1S3HVGcxi+o/5jG"
        
        $gifResult = ConvertTo-NativeType -MimePart $relatedParts[1]
        $gifResult | Should -BeOfType [PowerXML.MimeContent]
        $gifResult.ContentType | Should -Be 'image/gif'
        # GIF magic number: 47 49 46 ("GIF")
        $gifResult.BinaryContent[0..2] | Should -Be @(71, 73, 70)
    }

    It "wraps application/pgp-signature in MimeContent" {
        $part9Content = $topLevelParts[9].Content
        $signedParts = Parse-MimeMultipart -MimeString $part9Content -Boundary "=-vH3FQO9a8icUn1ROCoAi"
        
        $sigResult = ConvertTo-NativeType -MimePart $signedParts[1]
        $sigResult | Should -BeOfType [PowerXML.MimeContent]
        $sigResult.ContentType | Should -Be 'application/pgp-signature'
    }
}

Describe "Pipeline Integration" {
    It "supports full pipeline: Parse-MimeMultipart | ConvertTo-NativeType | ForEach-Object" {
        $boundary = "testboundary"
        $mime = @"
--testboundary
Content-Type: application/json

{"id": 1, "name": "first"}
--testboundary
Content-Type: application/json

{"id": 2, "name": "second"}
--testboundary
Content-Type: text/plain

Plain text item
--testboundary--
"@
        # Full pipeline: parse -> convert -> transform
        $results = Parse-MimeMultipart -MimeString $mime -Boundary $boundary |
            ConvertTo-NativeType |
            ForEach-Object {
                if ($_ -is [string]) {
                    @{ Type = 'Text'; Content = $_ }
                } else {
                    @{ Type = 'JSON'; Id = $_.id; Name = $_.name }
                }
            }
        
        $results.Count | Should -Be 3
        
        # Verify we got 2 JSON and 1 Text result
        $jsonResults = @($results | Where-Object { $_.Type -eq 'JSON' })
        $textResults = @($results | Where-Object { $_.Type -eq 'Text' })
        
        $jsonResults.Count | Should -Be 2
        $textResults.Count | Should -Be 1
        $textResults[0].Content | Should -Be 'Plain text item'
        
        # Verify JSON content (order may vary in pipeline)
        ($jsonResults | Where-Object { $_.Id -eq 1 }).Name | Should -Be 'first'
        ($jsonResults | Where-Object { $_.Id -eq 2 }).Name | Should -Be 'second'
    }

    It "supports pipeline with Where-Object filtering" {
        $boundary = "filterboundary"
        $mime = @"
--filterboundary
Content-Type: application/xml

<item><status>active</status></item>
--filterboundary
Content-Type: application/xml

<item><status>inactive</status></item>
--filterboundary
Content-Type: application/xml

<item><status>active</status></item>
--filterboundary--
"@
        # Pipeline with filtering
        $activeItems = Parse-MimeMultipart -MimeString $mime -Boundary $boundary |
            ConvertTo-NativeType |
            Where-Object { $_.SelectSingleNode('//status').InnerText -eq 'active' }
        
        $activeItems.Count | Should -Be 2
    }

    It "supports pipeline from torture test with Select-Object" {
        $content = Get-Content "$PSScriptRoot/test_data/rf-mime-torture-test-1.0.mbox.txt" -Raw
        $boundary = "=-qYxqvD9rbH0PNeExagh1"
        
        # Get just the Content-Types using pipeline
        $contentTypes = Parse-MimeMultipart -MimeString $content -Boundary $boundary |
            ForEach-Object { $_.Headers } |
            ForEach-Object { $_['Content-Type'] }
        
        $contentTypes.Count | Should -Be 11
        $contentTypes[0] | Should -BeLike 'text/plain*'
        ($contentTypes | Where-Object { $_ -eq 'message/rfc822' }).Count | Should -Be 10
    }
}
