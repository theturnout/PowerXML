# Comparing XProc Processors

Notes for the XProc User's Group presentation on PowerXML.

## Output Behavior

- **XmlCalabash** places messages on STDOUT, while **MorganaXProc** places messages on STDERR. PowerXML normalizes this so the caller gets a consistent experience.
- **XmlCalabash** outputs multi-document results using a custom `=== result` delimiter format.
- **MorganaXProc** outputs multi-document results as MIME multipart messages. PowerXML's `Parse-MimeMultipart` and `ConvertTo-NativeType` utilities handle both formats transparently.

## Performance

- **MorganaXProc** has significantly faster invocation time (~600–800ms) compared to **XmlCalabash** (~2–3s), largely due to JVM startup differences.
- Both processors support document sequences on input ports.

## Unified Interface

PowerXML wraps both processors behind a single `Transform-Xml` function:

```powershell
# Same API, different processor
Transform-Xml -Processor "xmlcalabash" -Pipeline "./test_data/helloWorld.xpl"
Transform-Xml -Processor "morganaxproc" -Pipeline "./test_data/helloWorld.xpl"
```

## Dependency Management

- Dependencies are declared in a CycloneDX SBOM (`sbom.xml`) using Package URLs (PURLs).
- The Polyglot package manager downloads processor JARs from GitHub, Codeberg, Maven Central, and SourceForge.
- Named "compositions" group dependencies for different use cases (e.g., testing vs. production).
