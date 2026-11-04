# Remove and re-import PowerXML module
Remove-Module powerxml -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/powerxml.psm1" -Force
Describe 'Transform-Xml XProc Processing' {
    BeforeAll {
        Import-Module "$PSScriptRoot/powerxml.psm1" -Force -DisableNameChecking
    }
    
    Context "XmlCalabash standard out" {
		It "Preserves separator-like lines inside an XML document" {
			$stdout = @(
				"=== result :: 1 :: file:/long/temporary/path/first.xml ==="
				"<root>"
				"==="
				"========================================================================"
				"</root>"
				("=" * 82)
				""
			) -join "`n"
			$result = @($stdout | Get-PXMultiXmlDocuments)
			$result.Count | Should -Be 1
			$result[0] | Should -BeOfType [xml]
			$result[0].root | Should -BeExactly "`n===`n========================================================================`n"
		}

		It "Parses a short header separator and variable-width trailers (<LineEnding>, <Width>)" -ForEach @(
			@{ LineEnding = "LF"; Newline = "`n"; Width = 82 }
			@{ LineEnding = "CRLF"; Newline = "`r`n"; Width = 90 }
			@{ LineEnding = "LF"; Newline = "`n"; Width = 60 }
		) {
			$trailer = "=" * $Width
			$stdout = @(
				"=== result :: 1 :: file:/long/temporary/path/first.xml ==="
				"<root><message>Doc1</message></root>"
				$trailer
				"=== result :: 2 :: file:/long/temporary/path/second.xml ==="
				"<root><message>Doc2</message></root>"
				$trailer
			) -join $Newline
			$result = @($stdout | Get-PXMultiXmlDocuments)
			$result.Count | Should -Be 2
			$result[0] | Should -BeOfType [xml]
			$result[1] | Should -BeOfType [xml]
			$result[0].root.message | Should -BeExactly "Doc1"
			$result[1].root.message | Should -BeExactly "Doc2"
		}
        
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
            $result = $thing | Get-PXMultiXmlDocuments
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
            $result = $mime | Get-PXMultiXmlDocuments
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
            $result = $mime | Get-PXMultiXmlDocuments
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
            $result = $calabash | Get-PXMultiXmlDocuments
            $result | Should -BeOfType [xml]
        }

        It "Should detect MIME format when input starts with '--'" {
            $mime = @"
--someBoundary
Content-Type: application/xml

<root/>
--someBoundary--
"@
            $result = $mime | Get-PXMultiXmlDocuments
            $result | Should -BeOfType [xml]
        }

        It "Should return single document when input matches neither format" {
            $plain = '<root><child>solo</child></root>'
            $result = $plain | Get-PXMultiXmlDocuments
            $result | Should -Be $plain
        }
    }

	Context "Dependency classpaths" {
		It "Uses absolute paths for JARs outside the working directory" {
			$dependencyDirectory = Join-Path -Path $TestDrive -ChildPath "dependency directory"
			New-Item -Path $dependencyDirectory -ItemType Directory | Out-Null
			$jarPath = Join-Path -Path $dependencyDirectory -ChildPath "dependency.jar"
			Set-Content -LiteralPath $jarPath -Value "fixture"
			$classPath = Get-PXClassPath -Paths @($dependencyDirectory)
			$entries = @($classPath -split [regex]::Escape([string][System.IO.Path]::PathSeparator) | Where-Object { $_ })
			$entries.Count | Should -Be 1
			$entries[0] | Should -BeExactly (Get-Item -LiteralPath $jarPath).FullName
		}
	}

	Describe "XProc option normalization" {
		BeforeAll {
			$importParams = @{
				Name = "$PSScriptRoot\powerxml.psd1"
				Force = $true
				ErrorAction = "Stop"
			}
			Import-Module @importParams
		}

		It "Converts <Name> to an explicit XPath literal" -ForEach @(
			@{ Name = "empty string"; Value = ""; Expected = "''" }
			@{ Name = "ordinary string"; Value = "John"; Expected = "'John'" }
			@{ Name = "apostrophe"; Value = "O'Brien"; Expected = "'O''Brien'" }
			@{ Name = "double quote"; Value = "say `"hello`""; Expected = "'say `"hello`"'" }
			@{ Name = "expression-looking string"; Value = "?5 + 3"; Expected = "'?5 + 3'" }
			@{ Name = "already quoted string"; Value = "'John'"; Expected = "'''John'''" }
			@{ Name = "Unicode"; Value = ("caf" + [char]0x00E9 + " " + [char]::ConvertFromUtf32(0x1F642)); Expected = "codepoints-to-string((99,97,102,233,32,128578))" }
			@{ Name = "true"; Value = $true; Expected = "true()" }
			@{ Name = "false"; Value = $false; Expected = "false()" }
			@{ Name = "integer"; Value = 42; Expected = "42" }
			@{ Name = "decimal"; Value = [decimal]25; Expected = "Q{http://www.w3.org/2001/XMLSchema}decimal('25')" }
			@{ Name = "float"; Value = [single]1.5; Expected = "Q{http://www.w3.org/2001/XMLSchema}float('1.5')" }
			@{ Name = "double"; Value = [double]1.5; Expected = "Q{http://www.w3.org/2001/XMLSchema}double('1.5')" }
			@{ Name = "NaN"; Value = [double]::NaN; Expected = "Q{http://www.w3.org/2001/XMLSchema}double('NaN')" }
		) {
			$scopeParams = @{
				ModuleName = "powerxml"
				Parameters = @{ Value = $Value; Expected = $Expected }
				ScriptBlock = {
					param($Value, $Expected)
					ConvertTo-PXXPathLiteral -Value $Value | Should -BeExactly $Expected
				}
			}
			InModuleScope @scopeParams
		}

		It "Writes generated <Kind> as UTF-8 without a BOM" -ForEach @(
			@{ Kind = "configuration" }
			@{ Kind = "step shell" }
			@{ Kind = "XML input" }
		) {
			$scopeParams = @{
				ModuleName = "powerxml"
				Parameters = @{ Kind = $Kind }
				ScriptBlock = {
					param($Kind)
					$path = if ($Kind -eq "configuration") {
						$configParams = @{
							Config = @{ setting = "value" }
							Root = "config"
							Namespace = "urn:powerxml:test"
						}
						ConvertTo-PXXmlConfig @configParams
					}
					elseif ($Kind -eq "step shell") {
						New-PXStepShell -Step "p:identity"
					}
					else {
						Resolve-PXXmlInput -InputObject "<root/>"
					}
					try {
						$bytes = [System.IO.File]::ReadAllBytes($path)
						($bytes[0..2] -join ",") | Should -Not -Be "239,187,191"
						[xml]$document = [System.Text.Encoding]::UTF8.GetString($bytes)
						$document.DocumentElement | Should -Not -BeNullOrEmpty
					}
					finally {
						$cleanupParams = @{
							LiteralPath = @($path, [System.IO.Path]::ChangeExtension($path, ".tmp"))
							ErrorAction = "Stop"
						}
						Remove-Item @cleanupParams
					}
				}
			}
			InModuleScope @scopeParams
		}

		It "Rejects unsupported literal <Name>" -ForEach @(
			@{ Name = "null"; Value = $null }
			@{ Name = "array"; Value = @(1, 2) }
			@{ Name = "map"; Value = @{ label = "value" } }
			@{ Name = "object"; Value = [pscustomobject]@{ label = "value" } }
		) {
			$scopeParams = @{
				ModuleName = "powerxml"
				Parameters = @{ Value = $Value }
				ScriptBlock = {
					param($Value)
					{ ConvertTo-PXXPathLiteral -Value $Value } | Should -Throw "*Unsupported literal XProc option type*"
				}
			}
			InModuleScope @scopeParams
		}

		It "Rejects duplicate expanded option names before resolving input" {
			Mock Resolve-PXXmlInput -ModuleName powerxml { throw "Unexpected input resolution" }
			$transformParams = @{
				Pipeline = "missing.xpl"
				Namespace = @{ opt = "urn:powerxml:options" }
				Options = @{ "opt:label" = "literal" }
				OptionExpressions = @{ "Q{urn:powerxml:options}label" = "'expression'" }
			}
			{ Transform-PXXml @transformParams } | Should -Throw "*specified more than once*"
			$invokeParams = @{
				Invoke = $true
				CommandName = "Resolve-PXXmlInput"
				ModuleName = "powerxml"
				Times = 0
			}
			Should @invokeParams
		}

		It "Does not probe inline XML as a MIME file under Stop error preference" {
			$ErrorActionPreference = "Stop"
			Mock Resolve-PXXmlInput -ModuleName powerxml { $InputObject }
			Mock Invoke-XmlCalabash -ModuleName powerxml { "<result/>" }
			$transformParams = @{
				Processor = "xmlcalabash"
				ClassPath = "caller-owned-classpath"
				Step = "p:identity"
				InPort = @{ source = '<root label="inline"/>' }
			}
			Transform-PXXml @transformParams | Should -BeExactly "<result/>"
			$invokeParams = @{
				Invoke = $true
				CommandName = "Invoke-XmlCalabash"
				ModuleName = "powerxml"
				Times = 1
				Exactly = $true
			}
			Should @invokeParams
		}

		It "Rejects non-string or empty expressions before resolving input" -ForEach @(
			@{ Expression = $null }
			@{ Expression = "" }
			@{ Expression = "   " }
			@{ Expression = 42 }
		) {
			Mock Resolve-PXXmlInput -ModuleName powerxml { throw "Unexpected input resolution" }
			$transformParams = @{
				Pipeline = "missing.xpl"
				OptionExpressions = @{ value = $Expression }
			}
			{ Transform-PXXml @transformParams } | Should -Throw "*must be a nonempty string*"
			$invokeParams = @{
				Invoke = $true
				CommandName = "Resolve-PXXmlInput"
				ModuleName = "powerxml"
				Times = 0
			}
			Should @invokeParams
		}

		It "Rejects expression options for XSLT without changing literal XSLT parameters" {
			$transformParams = @{
				Processing = "xslt"
				Processor = "dotnet"
				Pipeline = "missing.xsl"
				OptionExpressions = @{ value = "5 + 3" }
			}
			{ Transform-PXXml @transformParams } | Should -Throw "*only supported for*XProc processors*"
		}

		It "Rejects unbound option prefixes before resolving input" {
			$transformParams = @{
				Pipeline = "missing.xpl"
				Options = @{ "unbound:label" = "value" }
			}
			{ Transform-PXXml @transformParams } | Should -Throw "*Option namespace prefix*not bound*"
		}
	}
}