# PowerXML

A PowerShell toolkit for XML transformations using XProc 3.0 and XSLT processors with integrated dependency management.

## Overview

PowerXML provides a unified interface for executing XML transformations from PowerShell, supporting multiple processing engines:

**XProc 3.0 Processors:**
- [XML Calabash 3](https://xmlcalabash.com/) (default)
- [Morgana XProc IIIse](https://www.xml-project.com/morganaxproc-iiise/)

**XSLT Processors:**
- .NET `XslCompiledTransform` (XSLT 1.0)
- MSXML 6.0 COM (Windows only, XSLT 1.0)
- AltovaXML COM (Windows only, XSLT 2.0)

## Features

- **Unified API** – Single `Transform-Xml` function supports both XProc and XSLT processing
- **Flexible Input** – Accept file paths, XML strings, or .NET XML objects as input
- **Port Binding** – Route multiple inputs/outputs through named ports
- **Polyglot Package Manager** – Automatic dependency resolution using CycloneDX SBOM
- **MIME Multipart Parsing** – Parse and convert multipart responses to native PowerShell types

## Requirements

- [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.5) Core 7.5+
- [Java JDK 17](https://learn.microsoft.com/en-us/java/openjdk/download)+ (for XProc processors)

## Installation

```powershell
# Clone the repository
git clone https://github.com/your-username/PowerXML.git

# Import the module
Import-Module ./PowerXML/powerxml.psm1 -Force
```

## Quick Start

### XProc Pipeline

```powershell
# Run a simple XProc pipeline
Transform-Xml -Pipeline "./pipelines/hello.xpl"

# With input and output ports
Transform-Xml -Pipeline "./pipelines/transform.xpl" `
    -InPort @{ source = "./input.xml" } `
    -OutPort @{ result = "./output.xml" }

# Pass options to the pipeline
Transform-Xml -Pipeline "./pipelines/greet.xpl" `
    -Options @{ name = "World" }
```

### XSLT Transformation

```powershell
# Using .NET XSLT processor
Transform-Xml -Processing "xslt" -Processor "dotnet" `
    -Pipeline "./styles/transform.xsl" `
    -InPort @{ source = "./data.xml" }

# Using MSXML (Windows)
Transform-Xml -Processing "xslt" -Processor "msxml" `
    -Pipeline "./styles/transform.xsl" `
    -InPort @{ source = "./data.xml" } `
    -OutPort @{ result = "./output.xml" }
```

### Working with XML Objects

```powershell
# Pass .NET XML object as pipeline
[xml]$pipeline = Get-Content "./pipeline.xpl" -Raw
Transform-Xml -Pipeline $pipeline

# Pass XML string as input
$xmlInput = "<root><item>Hello</item></root>"
Transform-Xml -Pipeline "./transform.xpl" `
    -InPort @{ source = $xmlInput }
```

## API Reference

### Transform-Xml

Main function for XML transformations. Full documentation available via `Get-Help Transform-Xml`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Pipeline` | string/xml | XProc pipeline or XSLT stylesheet (file path, XML string, or object) |
| `-Processing` | string | Processing type: `xproc` (default) or `xslt` |
| `-Processor` | string | Processor to use: `xmlcalabash`, `morganaxproc`, `dotnet`, `msxml`, `altova` |
| `-InPort` | hashtable | Input port bindings: `@{ portName = "file.xml" }` |
| `-OutPort` | hashtable | Output port bindings: `@{ portName = "output.xml" }` |
| `-Options` | hashtable | Pipeline options/parameters |
| `-targetComposition` | string | SBOM composition for dependency resolution |
| `-Namespace` | hashtable | Namespace bindings: `@{ prefix = "uri" }` |
| `-catalog` | string | XML catalog file path |
| `-passthrough` | array | Arguments passed directly to the processor |
| `-passthroughJava` | array | Arguments passed to the JVM |

### Parse-MimeMultipart

Parses MIME multipart messages into structured parts.

```powershell
$parts = Parse-MimeMultipart -MimeString $response -Boundary "----boundary123"
$parts | ConvertTo-NativeType | ForEach-Object {
    # Process each part as native type (XmlDocument, PSObject, string, etc.)
}
```

## Dependency Management

PowerXML uses CycloneDX SBOM format (`sbom.xml`) to declare and manage Java dependencies. Dependencies are automatically downloaded from:

- Maven Central
- GitHub Releases  
- Codeberg Releases
- SourceForge

Dependencies are stored in `~/.polyglotpm` by default. Set the `$env:polyglotpm` environment variable to customize the location.

### Software Compositions

The SBOM defines named "compositions" that group dependencies for specific use cases:

```xml
<composition bom-ref="pester-tests">
    <dependencies>
        <dependency ref="xmlcalabash-3"/>
        <dependency ref="morganaxproc-1.8"/>
    </dependencies>
</composition>
```

Use the `-targetComposition` parameter to select a composition:

```powershell
Transform-Xml -Pipeline "./test.xpl" -targetComposition "pester-tests"
```

## Project Structure

```
PowerXML/
├── powerxml.ps1        # Core transformation functions
├── powerxml.psm1       # Module definition
├── xproc.ps1           # XProc processor wrappers (XML Calabash, Morgana)
├── xslt.ps1            # XSLT processor wrappers (.NET, MSXML, Altova)
├── utilities.ps1       # MIME parsing, retry logic, helpers
├── sbom.xml            # CycloneDX dependency manifest
├── polyglot/           # Package manager module
│   ├── polyglot-pm.ps1    # Main package manager
│   ├── download-deps.ps1  # Download utilities for GitHub/SourceForge
│   ├── pom.ps1            # Maven POM resolution
│   └── purl.ps1           # Package URL (purl) parsing
└── test_data/          # Sample pipelines and test data
```

## Testing

PowerXML uses Pester for testing:

```powershell
Invoke-Pester ./powerxml.tests.ps1
Invoke-Pester ./xslt.tests.ps1
Invoke-Pester ./utilities.tests.ps1
```

## See Also

- [USAGE.md](USAGE.md) – Additional usage examples
- [XProc 3.0 Specification](https://spec.xproc.org/3.0/xproc/)
- [XSLT 1.0 Specification](https://www.w3.org/TR/xslt-10/)

## License

See LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
