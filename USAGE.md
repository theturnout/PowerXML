# PowerXML Usage Guide

## Transform-Xml Usage Examples

The `Transform-Xml` function allows you to run XProc pipelines using different processors and input types. Below are user-friendly examples for each major piece of functionality.
Note: Some snippet paths (for example `input.xml`, `output.xml`, `input1.xml`, and `input2.xml`) are illustrative; create those files or substitute equivalent paths in your environment.

---

### Run Pipeline with Raw XML String

```powershell
$rawXml = Get-Content "./test_data/helloWorld.xpl" -Raw
Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline $rawXml
```

---

### Run Pipeline with .NET XML Object

```powershell
[xml]$xmlObj = Get-Content "./test_data/helloWorld.xpl" -Raw
Transform-Xml 
	-Processor "morganaxproc" 
	-Pipeline $xmlObj
```

### Pass Options to Pipeline

```powershell
Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/optionalHelloWorld.xpl" 
	-Options @{ name = "John" }
```

### Output Result to File

```powershell
Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlhelloWorld.xpl" 
	-OutPort @{ result = "./output.xml" }
```

---

### Pass Input via File

```powershell
[xml]$xmlInput = "<?xml version='1.0' encoding='utf-8'?><root><message>Hello, World!</message></root>"
$xmlInput.Save("./input.xml")
Transform-Xml 
	-TargetComposition "pester-tests" 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlpassthru.xpl" 
	-InPort @{ "source" = "./input.xml" } 
	-OutPort @{ "result" = "./output.xml" }
```

---

### Bind Single Values to the Default Port

When the pipeline has a primary input or output port, a single value can be passed directly without naming the port:

```powershell
Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlpassthru.xpl" 
	-InPort "./input.xml" 
	-OutPort "./output.xml"
```

The primary port is detected from the pipeline (the `p:input`/`p:output` marked `primary="true"`, or the only declared port), falling back to the conventional `source`/`result` names. Arrays are treated as document sequences on the primary port. For XSLT processing, single values bind to the conventional `source`/`result` ports.

### Pass Input via Object

```powershell
[xml]$xmlInput = "<?xml version='1.0' encoding='utf-8'?><root><message>Hello, World!</message></root>"
Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlpassthru.xpl" 
	-InPort @{ "source" = $xmlInput } 
	-OutPort @{ "result" = "./output.xml" }
```

---

### Specify Namespaced Option

```powershell
$namespaces = @{ pre = "http://example.com/pre" }
Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/optionalHelloWorld.xpl" 
	-Options @{ 'pre:opt' = 42 }
```

### Run a Step Directly

Instead of writing a pipeline, run a single step. Your `-InPort`/`-OutPort` keys define the ports the step sees:

```powershell
# Run p:xslt directly on XML Calabash
Transform-Xml 
	-Processor "xmlcalabash" 
	-Step "p:xslt" 
	-InPort @{ source = "./input.xml"; stylesheet = "./transform.xsl" }

# Unprefixed names get the p: namespace
Transform-Xml 
	-Processor "morganaxproc" 
	-Step "xinclude" 
	-InPort "./input.xml"
```

XML Calabash runs the step natively (`run --step:`); for MorganaXProc, PowerXML synthesizes a wrapper pipeline behind the scenes. Extension steps need their prefix bound first (see Register Namespaces for the Session). Note that in step mode, `-Options` are limited to the step's declared options.

### Register Namespaces for the Session

Namespace prefixes registered for the session are merged into every XProc invocation; explicit `-Namespace` entries take precedence over the registry:

```powershell
Register-Namespace -Prefix "pre" -Uri "http://example.com/pre"

Transform-Xml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/optionalHelloWorld.xpl"
```

### Capture Output as a .NET XML Object

When a pipeline writes XML to stdout, you can cast or assign the result directly to `[xml]` and navigate the DOM with dot notation:

```powershell
[xml]$result = Transform-Xml `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlhelloWorld.xpl"

# Access elements via dot notation
$result.content  # => "Hello, World!"
```

---

### Inspect Processor Metadata via DOM

Because the output is a real `XmlDocument`, you can drill into any element:

```powershell
[xml]$info = Transform-Xml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/processor.xpl"

$info.supplemental."xproc-engine-name"  # => "XML Calabash"
```

---

### Pipe an XML Object into Transform-Xml

You can pipe a .NET `[xml]` object directly into `Transform-Xml` via the PowerShell pipeline:

```powershell
[xml]$xmlInput = "<root><message>Hello, World!</message></root>"

$xmlInput | Transform-Xml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlpassthru.xpl" `
	-OutPort @{ "result" = "./output.xml" }
```

---

### Document Sequences as Object Arrays

When a pipeline produces multiple documents, `Transform-Xml` returns an array of `[xml]` objects. Each element is a fully navigable `XmlDocument`:

```powershell
[xml]$doc1 = "<root><message>Doc1</message></root>"
[xml]$doc2 = "<root><message>Doc2</message></root>"

$results = Transform-Xml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlseqpassthru.xpl" `
	-InPort @{ source = @($doc1, $doc2) }

# Each result is a native [xml] object
$results[0].root.message  # => "Doc1"
$results[1].root.message  # => "Doc2"

# Use standard PowerShell pipeline operations
$results | ForEach-Object { $_.root.message }
```

---

### Chain Transforms with the PowerShell Pipeline

Since inputs and outputs are native .NET objects, you can chain transformations naturally:

```powershell
# Run a pipeline, then query the XML result
$messages = Transform-Xml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlseqpassthru.xpl" `
	-InPort @{ source = @("./input1.xml", "./input2.xml") } |
	ForEach-Object { ([xml]$_).root.message }

# $messages is now a string array: @("Doc1", "Doc2")
```
For more details, see the module documentation or run `Get-Help Transform-Xml` in PowerShell.

## Failure Behavior

When an XProc processor exits with a non-zero code (a failed or invalid pipeline, a missing step, or a connector error), `Transform-Xml` throws with the engine's exit code and captured output instead of returning the error text as a result. Successful runs return the STDOUT documents as usual.

## Using CycloneDX SBOMs

PowerXML uses the CycloneDX Software Bill of Materials (SBOM) as a manifest format. PolyglotPM understands a small subset of CycloneDX structures, primarily components and compositions. Components are defined with Package URLs (PURLs) that specify where to retrieve them from various package ecosystems. Components form a library of artifacts that can be aggregated into compositions, which may be called for by a particular invocation of `Transform-Xml` via the `-TargetComposition` parameter. This allows you to define complex software compositions and their dependencies in a standardized format, and have PolyglotPM handle the retrieval and management of those dependencies automatically.

Notes

- PolyglotPM is only used by `Transform-Xml` when the `-Processing` parameter is set to `xproc`. It cannot retrieve dependencies for other processors or for non-XProc pipelines.

