# PowerXML - XProc and XSLT Processing Toolkit for PowerShell (Core and Windows)

A PowerShell toolkit for XML transformations using XProc 3.0 and XSLT processors with integrated dependency management.

## Overview

PowerXML provides a unified interface for executing XML transformations from PowerShell, supporting multiple processing engines:

**XProc 3.0 Processors:**
- [XML Calabash 3](https://xmlcalabash.com/) (default)
- [Morgana XProc IIIse](https://www.xml-project.com/morganaxproc-iii.html)

**XSLT Processors:**
- .NET `XslCompiledTransform` (XSLT 1.0)
- MSXML 6.0 COM (Windows only, XSLT 1.0)
- AltovaXML Community COM (Windows only, XSLT 2.0, Schema-aware)
- [xsltproc](https://man.freebsd.org/cgi/man.cgi?query=xsltproc&sektion=1&manpath=FreeBSD+5.2.1-RELEASE+and+Ports) (libxslt, XSLT 1.0)

## Features

- **Unified API** – Single `Transform-Xml` CmdLet supports both XProc and XSLT processing
- **Flexible Input** – Accept file paths, XML strings, or .NET XML objects as input
- **Port Binding** – Route multiple inputs/outputs through named ports
- **Polyglot Package Manager** – Automatic dependency resolution using CycloneDX SBOM

## Requirements

- Windows PowerShell or [PowerShell Core 7.5+](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.5) 
- [Java JDK 17](https://learn.microsoft.com/en-us/java/openjdk/download)+ (for XProc processors)

## Installation

```powershell
# Clone the repository
git clone https://github.com/theturnout/PowerXML.git

# Import the module
Import-Module ./powerxml.psm1 -Force
```

Future releases will be available via package manager.

## Quick Start

### XProc Pipeline

```powershell
# Run a simple XProc pipeline
Transform-Xml -Pipeline "./test_data/helloWorld.xpl"

# With input and output ports
Transform-Xml -Pipeline "./test_data/xmlpassthru.xpl" `
    -InPort @{ source = "./test_data/order.xml" } `
    -OutPort @{ result = "./test_data/out/order-total.out.xml" }

# Pass options to the pipeline
Transform-Xml -Pipeline "./test_data/optionalHelloWorld.xpl" `
    -Options @{ name = "World" }
```

### XSLT Transformation

```powershell
# Using .NET XSLT processor
Transform-Xml -Processing "xslt" -Processor "dotnet" `
    -Pipeline "./test_data/hello.xsl" `
    -InPort @{ source = "./test_data/order.xml" }

# Using MSXML (Windows)
Transform-Xml -Processing "xslt" -Processor "msxml" `
    -Pipeline "./test_data/hello.xsl" `
    -InPort @{ source = "./test_data/order.xml" } `
    -OutPort @{ result = "./test_data/out/hello.out.xml" }
```

### Working with XML Objects

```powershell
# Pass .NET XML object as pipeline
[xml]$pipeline = Get-Content "./test_data/helloWorld.xpl" -Raw
Transform-Xml -Pipeline $pipeline

# Pass XML string as input
$xmlInput = "<root><item>Hello</item></root>"
Transform-Xml -Pipeline "./test_data/xmlpassthru.xpl" `
    -InPort @{ source = $xmlInput }
```
See [USAGE.md](USAGE.md) for more examples and advanced usage scenarios.

## API Reference

### Transform-Xml

Main function for XML transformations. Full documentation available via `Get-Help Transform-Xml`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Pipeline` | string/xml | XProc pipeline or XSLT stylesheet (file path, XML string, or object) |
| `-Processing` | string | Processing type: `xproc` (default) or `xslt` |
| `-Processor` | string | Processor to use: `xmlcalabash`, `morganaxproc`, `dotnet`, `msxml`, `altova`, `xsltproc`, `phoenixml` |
| `-InPort` | hashtable | Input port bindings: `@{ portName = "./test_data/order.xml" }` |
| `-OutPort` | hashtable | Output port bindings: `@{ portName = "./test_data/out/order-total.out.xml" }` |
| `-Options` | hashtable | Pipeline options/parameters |
| `-TargetComposition` | string | SBOM composition for dependency resolution |
| `-Namespace` | hashtable | Namespace bindings: `@{ prefix = "uri" }` |
| `-Catalog` | string | XML catalog file path |
| `-Passthrough` | array | Arguments passed directly to the processor |
| `-PassthroughJava` | array | Arguments passed to the JVM |

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
    <aggregate>complete</aggregate>
    <dependencies>
        <dependency ref="xmlcalabash-3.0.40"/>
        <dependency ref="morganaxproc-1.8.2"/>
    </dependencies>
</composition>
```

Use the `-TargetComposition` parameter to select a composition:

```powershell
Transform-Xml -Pipeline "./test_data/helloWorld.xpl" -TargetComposition "pester-tests"
```

## Project Structure

```
PowerXML/
├── powerxml.psm1       # Module definition
├── powerxml.psd1       # Module manifest
├── powerxml.ps1        # Core Transform-Xml function
├── xproc.ps1           # XProc processor wrappers (XML Calabash, Morgana)
├── xslt.ps1            # XSLT processor wrappers (.NET, MSXML, Altova, xsltproc)
├── utilities.ps1       # MIME parsing, type conversion, helpers
├── sbom.xml            # CycloneDX dependency manifest (default)
├── test-harness.ps1    # Pester test runner with code coverage
├── polyglot/           # Package manager module
│   ├── polyglot-pm.ps1    # Main package manager
│   ├── cyclonedx.ps1      # CycloneDX SBOM manipulation
│   ├── download-deps.ps1  # Download utilities (GitHub, Codeberg, Maven, SourceForge)
│   ├── install-package.ps1 # Package installation and extraction
│   ├── sbom.ps1           # SBOM validation
│   ├── pom.ps1            # Maven POM resolution
│   └── purl.ps1           # Package URL (purl) parsing
└── test_data/          # Sample pipelines, stylesheets, and test fixtures
```

## Testing

PowerXML uses [Pester](https://pester.dev/) for testing. Run the full suite with code coverage:

```powershell
pwsh ./test-harness.ps1
```

Or run individual test files:

```powershell
Invoke-Pester ./powerxml.tests.ps1
Invoke-Pester ./xslt.tests.ps1
Invoke-Pester ./xproc.tests.ps1
Invoke-Pester ./utilities.tests.ps1
```

## See Also

- [USAGE.md](USAGE.md) – Additional usage examples
- [PROCESSORS.md](PROCESSORS.md) – Processor access methods and evaluation of candidate processors
- [XProc 3.0 Specification](https://spec.xproc.org/3.0/xproc/)
- [XSLT 1.0 Specification](https://www.w3.org/TR/xslt-10/)

## License

See LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
