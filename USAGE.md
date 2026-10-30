# PowerXML Usage Guide

## Transform-PXXml Usage Examples

The `Transform-PXXml` function allows you to run XProc pipelines using different processors and input types. Below are user-friendly examples for each major piece of functionality.
Note: Some snippet paths (for example `input.xml`, `output.xml`, `input1.xml`, and `input2.xml`) are illustrative; create those files or substitute equivalent paths in your environment.

---

### Run Pipeline with Raw XML String

```powershell
$rawXml = Get-Content "./test_data/helloWorld.xpl" -Raw
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline $rawXml
```

---

### Run Pipeline with .NET XML Object

```powershell
[xml]$xmlObj = Get-Content "./test_data/helloWorld.xpl" -Raw
Transform-PXXml 
	-Processor "morganaxproc" 
	-Pipeline $xmlObj
```

### Pass Options to Pipeline

```powershell
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/optionalHelloWorld.xpl" 
	-Options @{ name = "John" }
```

### Output Result to File

```powershell
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlhelloWorld.xpl" 
	-OutPort @{ result = "./output.xml" }
```

---

### Pass Input via File

```powershell
[xml]$xmlInput = "<?xml version='1.0' encoding='utf-8'?><root><message>Hello, World!</message></root>"
$xmlInput.Save("./input.xml")
Transform-PXXml 
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
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlpassthru.xpl" 
	-InPort "./input.xml" 
	-OutPort "./output.xml"
```

The primary port is detected from the pipeline (the `p:input`/`p:output` marked `primary="true"`, or the only declared port), falling back to the conventional `source`/`result` names. Arrays are treated as document sequences on the primary port. For XSLT processing, single values bind to the conventional `source`/`result` ports.

### Pass Input via Object

```powershell
[xml]$xmlInput = "<?xml version='1.0' encoding='utf-8'?><root><message>Hello, World!</message></root>"
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/xmlpassthru.xpl" 
	-InPort @{ "source" = $xmlInput } 
	-OutPort @{ "result" = "./output.xml" }
```

---

### Specify Namespaced Option

```powershell
$namespaces = @{ pre = "http://example.com/pre" }
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/optionalHelloWorld.xpl" 
	-Options @{ 'pre:opt' = 42 }
```

### Run a Step Directly

Instead of writing a pipeline, run a single step. Your `-InPort`/`-OutPort` keys define the ports the step sees:

```powershell
# Run p:xslt directly on XML Calabash
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Step "p:xslt" 
	-InPort @{ source = "./input.xml"; stylesheet = "./transform.xsl" }

# Unprefixed names get the p: namespace
Transform-PXXml 
	-Processor "morganaxproc" 
	-Step "xinclude" 
	-InPort "./input.xml"
```

XML Calabash runs the step natively (`run --step:`); for MorganaXProc, PowerXML synthesizes a wrapper pipeline behind the scenes. Extension steps need their prefix bound first (see Register Namespaces for the Session). Note that in step mode, `-Options` are limited to the step's declared options.

### Register Namespaces for the Session

Namespace prefixes registered for the session are merged into every XProc invocation; explicit `-Namespace` entries take precedence over the registry:

```powershell
Register-PXNamespace -Prefix "pre" -Uri "http://example.com/pre"

Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/optionalHelloWorld.xpl"
```

### Capture Output as a .NET XML Object

When a pipeline writes XML to stdout, you can cast or assign the result directly to `[xml]` and navigate the DOM with dot notation:

```powershell
[xml]$result = Transform-PXXml `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlhelloWorld.xpl"

# Access elements via dot notation
$result.content  # => "Hello, World!"
```

---

### Inspect Processor Metadata via DOM

Because the output is a real `XmlDocument`, you can drill into any element:

```powershell
[xml]$info = Transform-PXXml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/processor.xpl"

$info.supplemental."xproc-engine-name"  # => "XML Calabash"
```

---

### Pipe an XML Object into Transform-PXXml

You can pipe a .NET `[xml]` object directly into `Transform-PXXml` via the PowerShell pipeline:

```powershell
[xml]$xmlInput = "<root><message>Hello, World!</message></root>"

$xmlInput | Transform-PXXml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlpassthru.xpl" `
	-OutPort @{ "result" = "./output.xml" }
```

---

### Document Sequences as Object Arrays

When a pipeline produces multiple documents, `Transform-PXXml` returns an array of `[xml]` objects. Each element is a fully navigable `XmlDocument`:

```powershell
[xml]$doc1 = "<root><message>Doc1</message></root>"
[xml]$doc2 = "<root><message>Doc2</message></root>"

$results = Transform-PXXml `
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
$messages = Transform-PXXml `
	-TargetComposition "pester-tests" `
	-Processor "xmlcalabash" `
	-Pipeline "./test_data/xmlseqpassthru.xpl" `
	-InPort @{ source = @("./input1.xml", "./input2.xml") } |
	ForEach-Object { ([xml]$_).root.message }

# $messages is now a string array: @("Doc1", "Doc2")
```
For more details, see the module documentation or run `Get-Help Transform-PXXml` in PowerShell.

## Input Resolution

`Transform-PXXml` accepts inputs in several forms, resolved in this order:

- **Filesystem paths** via `-Pipeline` / `-InPort` (the default)
- **Direct XML content** via a parameter — strings and .NET XML objects are written to a temporary file automatically
- **STDIN** via the PowerShell pipeline (piped input is passed to the processor's default port)
- **URIs** — passed through to the processor, which fetches them. PowerXML does not validate or restrict URI schemes: what is supported depends on the target engine (the Java resource resolution used by the XProc processors, .NET/MSXML/libxml2 for the XSLT engines). `file://` and `http(s)://` are verified to work on both XProc processors
- **Package URLs** — values starting with `pkg:` are resolved through PolyglotPM into the local repository. Select a file inside the package with the `filename` qualifier (maven and nuget packages, where it has no download meaning) or a `#subpath` (any package type; for github/codeberg/sourceforge purls, where `filename` names the downloadable asset, use `#subpath`)

```powershell
# A pipeline shipped inside a package, referenced by purl
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.40?filename=xmlcalabash-3.0.40.zip#helloWorld.xpl"

# A stylesheet shipped inside a maven package, selected by filename
Transform-PXXml 
	-Processing "xslt" -Processor "dotnet" 
	-Pipeline "pkg:maven/nist.gov/oscal-thing?filename=convert.xsl"

# A file URI as input
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Step "p:identity" 
	-InPort @{ source = "file:///C:/path/input.xml" }
```

When a purl resolves to a directory, a file selector is required; ambiguous `filename` matches throw. Single-file artifacts are used directly. Purls that fail to resolve throw a clear error naming the purl and the expected selectors.

## Running Without PolyglotPM

Tools that manage their own jars (or ship a processor layout that PolyglotPM's directory conventions do not match) can pass a ready-made Java classpath with `-ClassPath` (XProc only). The classpath is used verbatim — order is preserved — and dependency resolution, processor discovery, and config generation are all bypassed:

```powershell
Transform-PXXml 
	-Processor "morganaxproc" 
	-ClassPath "C:/tools/lib/xercesImpl.jar;C:/tools/libraries/*;C:/tools/MorganaXProc-IIIse.jar" 
	-Configuration "C:/tools/config/morgana.xml" 
	-Step "p:xslt" 
	-InPort @{ source = "./input.xml"; stylesheet = "./style.xsl" }
```

Use `-PassthroughJava` for JVM options such as javaagents. When `-ClassPath` is given without `-Configuration`, no processor config is generated — supply your own if you need connectors.

## Multipart MIME

Documents can travel in and out of `Transform-PXXml` as a single `multipart/mixed` file, with an `X-Port` header naming the port each part belongs to.

**As input** — any `-InPort` value that points at a multipart file is detected automatically: parts are parsed and routed to the ports named by their `X-Port` headers (parts without an `X-Port` go to the port the file was bound to, in order, as a sequence):

```powershell
# routed.mime contains parts labeled X-Port: source and X-Port: stylesheet
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Step "p:xslt" 
	-InPort @{ source = "./routed.mime" }
```

**As output** — `-MultiplexOutput` writes every output (STDOUT documents plus any bound output ports) to one multipart file, STDOUT documents labeled with the conventional `result` port:

```powershell
Transform-PXXml 
	-Processor "xmlcalabash" 
	-Step "p:xslt" 
	-InPort @{ source = "./input.xml"; stylesheet = "./style.xsl" } 
	-MultiplexOutput "./out.mime"
```

Use `ConvertTo-PXMimeMultipart` to build such files yourself from parts with `Port`, `Content`, and `ContentType` properties. This works identically on both XProc processors (PowerXML handles the multipart format itself rather than relying on engine-specific options).

## Composition Registry

Register a named composition once per session and select it as the default; `Transform-PXXml` then uses it whenever no `-PackageResolution` is given, resolving it a single time and caching the resolved paths (so the PolyglotPM engine does not run on every call):

```powershell
Register-PXComposition -Name "my-work" -TargetComposition "oscal" -GetLatest
Select-PXComposition -Name "my-work"

Transform-PXXml 
	-Processor "xmlcalabash" 
	-Pipeline "./test_data/helloWorld.xpl"
```

Explicit `-PackageResolution` always wins over the session default. Re-register a composition to refresh its cached paths (relevant with `-GetLatest`).

## Configuration

`-Configuration` accepts three forms for the XProc processors:

- **Omitted** — MorganaXProc gets an auto-generated config: the XSLT/XQuery connector is auto-detected from the Saxon jar on the classpath (Saxon 12.3+ uses `Saxon12-3`, earlier 12.x uses `Saxon12`, etc.) and the NineML/MarkupBlitz invisible-XML connectors are registered (harmless when their jars are absent). XML Calabash generates its own mimetype configuration internally.
- **A hashtable** — settings 1-1 with the engine's XML/JSON shape, merged over the auto-detected defaults (explicit entries win):

```powershell
Transform-PXXml 
	-Processor "morganaxproc" 
	-Step "p:xslt" 
	-InPort @{ source = "./input.xml"; stylesheet = "./style.xsl" } 
	-Configuration @{ "xslt-connector" = "Saxon12-3" }
```

- **A file path** — used as-is with no merging.

Use `ConvertTo-PXXmlConfig` to build a config file from a hashtable yourself (keys become elements, `'@'`-prefixed keys become attributes), and `Get-PXMorganaAutoConfig -Paths <array>` to inspect what would be auto-detected.

## Failure Behavior

When an XProc processor exits with a non-zero code (a failed or invalid pipeline, a missing step, or a connector error), `Transform-PXXml` throws with the engine's exit code and captured output instead of returning the error text as a result. Successful runs return the STDOUT documents as usual.

## Using CycloneDX SBOMs

PowerXML uses the CycloneDX Software Bill of Materials (SBOM) as a manifest format. PolyglotPM understands a small subset of CycloneDX structures, primarily components and compositions. Components are defined with Package URLs (PURLs) that specify where to retrieve them from various package ecosystems. Components form a library of artifacts that can be aggregated into compositions, which may be called for by a particular invocation of `Transform-PXXml` via the `-TargetComposition` parameter. This allows you to define complex software compositions and their dependencies in a standardized format, and have PolyglotPM handle the retrieval and management of those dependencies automatically.

Notes

- PolyglotPM is only used by `Transform-PXXml` when the `-Processing` parameter is set to `xproc`. It cannot retrieve dependencies for other processors or for non-XProc pipelines.

