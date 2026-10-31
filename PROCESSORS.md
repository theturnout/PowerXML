# Non-.NET XSLT Processors

PowerXML currently supports `XslCompiledTransform` (XSLT 1.0), MSXML 6.0 (XSLT 1.0), AltovaXML (XSLT 2.0), and xsltproc (XSLT 1.0) for XSLT, plus XML Calabash 3 and MorganaXProc IIIse for XProc. Below are non-.NET processors worth adding, ordered by recommendation priority.

## Access Methods

Every processor is reached through `Transform-PXXml`. The `-Processing` parameter selects the technology (`xslt` or `xproc`), the `-Processor` parameter selects the engine, and additional libraries are resolved automatically by PolyglotPM where noted. For example, XSLT processing gives access to .NET engines, while XProc processing gives access to Java engines.

Supported today:

| Processor | Processing (processor ID) | Runtime | Addl libraries |
|-----------|----------------------------|---------|----------------|
| DotNetXML (`XslCompiledTransform`) | XSLT (`dotnet`) | .NET, in-process | none |
| MSXML 6.0 | XSLT (`msxml`) | Windows COM | none (OS component) |
| AltovaXML Community | XSLT (`altova`) | Windows COM | altovaxml (installer) |
| xsltproc (libxslt) | XSLT (`xsltproc`) | native CLI | xsltproc on PATH |
| PhoenixmlDb.Xslt | XSLT (`phoenixml`) | .NET, in-process | NuGet: PhoenixmlDb.Core, .XQuery, .Xslt (auto-resolved) |
| XML Calabash 3 | XProc (`xmlcalabash`) | Java | SBOM composition (e.g. `xmlcalabash-3.0.40`) |
| MorganaXProc IIIse | XProc (`morganaxproc`) | Java | SBOM composition (e.g. `morganaxproc-1.8.2`) |

Candidates from the processor survey (detailed in the sections below):

| Processor | Processing | Addl libraries | Notes |
|-----------|-------------|----------------|-------|
| SAXON-HE | XSLT (Java) | saxon-he jar | Top recommendation; XSLT 3.0. SBOM already carries `saxon-he-11` |
| SAXON-PE | XSLT (Java) | saxon-pe jar | Commercial; adds packaging convenience |
| SAXON-EE | XSLT (Java) | saxon-ee jar | Commercial, schema-aware; SBOM already carries `saxon-ee-12` |
| SaxonC-HE | XSLT (native) | SaxonC build | No JVM required |
| Xalan | XSLT (Java) | xalan jar | Maintenance mode; Saxon-HE preferred |
| Xerces | XProc/XSLT (Java) | xerces jar | XML parser; already bundled in XProc compositions |
| MSXML 4.0 | XSLT | none | Legacy; MSXML 6.0 already supported |
| DotNetXML | XSLT | none | Already supported via `dotnet` |

## iXML Engine Selection

The `p:invisible-xml` step needs a grammar-processing engine. How that engine is chosen differs by XProc processor.

### XML Calabash

PowerXML performs no selection: Calabash implements `p:invisible-xml` internally with the NineML (coffeefilter) stack bundled in its own `lib/` directory. The configuration PowerXML generates for Calabash declares only a mimetype mapping (`extensions="ixml pdf inp"` → `text/plain`) so that grammar files load as plain text; the engine itself is whatever Calabash ships.

### MorganaXProc

MorganaXProc loads iXML engines through connector classes declared in its configuration. The auto-generated config from `Get-PXAutoConfig` (`xproc.ps1`) registers both known connectors, in this order:

1. `com.xml_project.morganaxproc3.ninemlConnector.NineMLConnector` — requires the `org.nineml` coffeefilter/coffeegrinder jars
2. `com.xml_project.morganaxproc3.markupblitzConnector.MarkupBlitzConnector` — requires the `de.bottlecaps` markup-blitz jar

There is no version detection here, unlike the Saxon XSLT/XQuery connectors (where the Saxon jar on the classpath is parsed and mapped to `Saxon12-3`/`Saxon12`/`Saxon11`/`Saxon10`). Instead, two properties make unconditional registration of both connectors safe and effective:

- **Lazy initialization.** Morgana initializes connectors on first use, so an entry whose classes are not on the classpath is inert rather than fatal. Registering both is safe on any composition.
- **The composition is the selector.** Whichever connector's dependencies the SBOM composition actually supplies is the one that runs. The `oscal` composition, for example, ships coffeefilter/coffeegrinder (NineML) *and* markup-blitz, so either engine can serve; a composition carrying only markup-blitz gets MarkupBlitz. When both are present, the listed order gives NineML precedence.

The two engines are not strictly interchangeable — they track different NineML component versions — which is why the auto-config registers both rather than picking one. Both have been verified to produce identical, correct output on the `test_data/ixml.xpl` date-grammar pipeline under the `oscal` composition.

### Forcing a specific engine

Explicit `-Configuration` entries always win over the auto-detected defaults:

```powershell
Transform-PXXml `
    -Processor "morganaxproc" `
    -Pipeline "./date.xpl" `
    -Configuration @{ "ixml-connector" = "com.xml_project.morganaxproc3.markupblitzConnector.MarkupBlitzConnector" }
```

Note that with `-ClassPath` (manual mode) no configuration is generated at all — supply `-Configuration` yourself if you need iXML connectors in that mode.

## Recommended

### Saxon-HE (Java)

The gold-standard XSLT processor. Created by Michael Kay, editor of the XSLT 2.0 and 3.0 specs.

- **XSLT version:** 3.0 (backwards-compatible with 1.0 and 2.0), plus selective XSLT 4.0 support
- **Latest release:** 12.9 (September 2025)
- **License:** MPL-2.0 (open source)
- **Platforms:** Any platform with a JVM
- **CLI:** `java -jar saxon-he-12.0.jar -s:input.xml -xsl:style.xsl -o:output.xml`
- **Popularity:** The most widely used XSLT 3.0 processor in the industry. Continuously maintained since 1999.
- **Notes:** Requires a JVM. Also supports XPath 3.1 and XQuery 3.1. Commercial editions (PE/EE) add schema-aware processing and streaming.

### xsltproc (libxslt)

The standard XSLT CLI tool on Unix-like systems. Written in C, extremely fast and lightweight.

- **XSLT version:** 1.0 (with EXSLT extensions)
- **Latest release:** Actively maintained as part of libxslt/GNOME
- **License:** MIT
- **Platforms:** Linux, macOS, Windows (via Cygwin/MSYS2/WSL); pre-installed on most Linux distros and macOS
- **CLI:** `xsltproc --output output.xml style.xsl input.xml`
- **Popularity:** Extremely high. Default XSLT processor for PHP, Perl, Python (via bindings). Used by WebKit.
- **Notes:** XSLT 1.0 only — no path to 2.0/3.0. But for 1.0 workloads it is the fastest option and has zero runtime dependencies beyond the C library.

### SaxonC-HE (C/C++)

Native-compiled Saxon — same engine as Saxon-HE Java, but no JVM required.

- **XSLT version:** 3.0
- **Latest release:** 12 series (SaxonC 11.7 released July 2025)
- **License:** MPL-2.0 (HE edition)
- **Platforms:** Linux, macOS, Windows (64-bit)
- **CLI:** `./transform -s:input.xml -xsl:style.xsl -o:output.xml` (after compiling `Transform.c`)
- **Popularity:** Growing. Also has Python and PHP bindings.
- **Notes:** The CLI requires building from source (a build script is provided). Heavier install footprint than xsltproc. Same command-line interface as Saxon-HE Java. The `transform` path shown is illustrative; your built executable name/location may differ.

## Worth Considering

### SaxonJS (Node.js)

Saxon reimplemented in JavaScript for browser and Node.js environments.

- **XSLT version:** 3.0 (most mandatory + optional parts of the spec)
- **Latest release:** 3.0.0-beta2 (June 2025)
- **License:** Free to use, but **not open source**. Source access requires a paid service package.
- **Platforms:** Any platform with Node.js
- **CLI:** `npx xslt3 -xsl:style.xsl -s:input.xml -o:output.xml` (via the `xslt3` npm package)
- **Popularity:** Niche — mainly used for browser-side XSLT.
- **Notes:** Not FOSS. Useful if Node.js is already in the toolchain and JVM is not available.

### XMLStarlet

A Swiss-army knife CLI toolkit for XML, not just an XSLT processor. Uses libxslt internally.

- **XSLT version:** 1.0 (via libxslt)
- **Latest release:** 1.6.1 (actively packaged in distro repos)
- **License:** MIT
- **Platforms:** Linux, macOS, Windows
- **CLI:** `xmlstarlet tr style.xsl input.xml`
- **Popularity:** Very popular for shell-scripted XML manipulation.
- **Notes:** Same XSLT engine as xsltproc but bundled with XPath querying, validation, editing, and formatting commands. Adds convenience but no new XSLT capability beyond xsltproc.

## Not Recommended

### Apache Xalan-J (Java)

- **XSLT version:** 1.0 only
- **Latest release:** 2.7.3 (April 2023) — security/maintenance fix
- **License:** Apache 2.0
- **Status:** Mature but effectively in maintenance mode. An experimental XSLT 3.0 branch exists on GitHub (`xalan-j_xslt3.0_mvn`) but has never been released. The project has had difficulty attracting committers.
- **Reason to skip:** XSLT 1.0 only with no realistic path to 3.0, and Saxon-HE covers the same JVM niche with far better standards support.

### Apache Xalan-C (C++)

- **XSLT version:** 1.0 only
- **Latest release:** 1.12 (June 2020)
- **License:** Apache 2.0
- **Status:** Essentially dormant. The test platform is outdated and the project has acknowledged insufficient active membership for binding votes.
- **Reason to skip:** xsltproc covers the same native-C XSLT 1.0 niche and is far more actively maintained.

## Summary

For the best coverage with minimal additions:

1. **Saxon-HE** — adds XSLT 3.0 (and 2.0) support via a single jar. Easiest win.
2. **xsltproc** — adds a fast, zero-dependency XSLT 1.0 processor available on virtually every Unix system. Likely already installed on the user's machine.
3. **SaxonC-HE** — adds XSLT 3.0 without requiring a JVM, at the cost of a more involved setup.
