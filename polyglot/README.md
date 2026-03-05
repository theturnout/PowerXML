# Polyglot

A PowerShell module for polyglot package management using [CycloneDX](https://cyclonedx.org/) Software Bill of Materials (SBOM) and [Package URL (PURL)](https://github.com/package-url/purl-spec) specifications.

## Overview

Polyglot enables downloading and managing software dependencies from multiple package ecosystems through a unified interface. It uses CycloneDX SBOM files to define software compositions and resolves dependencies via PURL identifiers.

## Features

- **PURL Support**: Parse and resolve Package URLs for multiple ecosystems:
  - Maven Central & custom Maven repositories
  - GitHub Releases
  - Codeberg Releases
  - SourceForge
- **CycloneDX SBOM**: Define software compositions in CycloneDX 1.x XML format
- **Maven Dependency Resolution**: Recursively resolve and download transitive dependencies from POM files
- **Local Repository**: Cache downloaded artifacts in a local repository

## Installation

Import the module directly:

```powershell
Import-Module ./polyglot
```

## Configuration

Set the local repository path via environment variable (defaults to `~/.polyglotpm`):

```powershell
$env:polyglotpm = "C:\path\to\your\repo"
```

## Usage

### Download a Package via PURL

```powershell
# Maven artifact
$purl = ConvertFrom-PkgUri "pkg:maven/org.xmlresolver/xmlresolver@6.0.12"
Get-PackageFromPurl -purl $purl

# GitHub release
$purl = ConvertFrom-PkgUri "pkg:github/nineml/coffeefilter@3.3.4"
Get-PackageFromPurl -purl $purl

# Codeberg release with specific asset
$purl = ConvertFrom-PkgUri "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24?filename=xmlcalabash-3.0.24.zip"
Get-PackageFromPurl -purl $purl
```

### Download from SBOM Composition

```powershell
Copy-SoftwareComposition -sbomPath "sbom.xml" -targetComposition "oscal"
```

### Download GitHub Release Directly

```powershell
Copy-GitHubRelease -RepoOwner "nineml" -RepoName "coffeefilter" `
    -Version "3.3.4" `
    -Assets @("coffeefilter-3.3.4.zip") `
    -libPath "./lib"
```

### List GitHub Releases

```powershell
Get-GitHubReleases -RepoOwner "nineml" -RepoName "coffeefilter"
```

### Manipulate CycloneDX SBOMs

```powershell
# Load an existing SBOM
$sbom = Get-SBOM -Path "sbom.xml"

# Add a component with distribution URL and hash
Add-SBOMComponent -Sbom $sbom `
    -BomRef "my-library" `
    -Name "My Library" `
    -Purl "pkg:maven/com.example/my-library@1.0.0" `
    -DistributionUrl "pkg:github/example/my-library@1.0.0?filename=my-library-1.0.0.zip" `
    -DistributionHash "67e8fa31b76eb5cded20482b711a415e4db9a9d3fce160ed15e4612c333281db"

# Add a component with component-level hash
Add-SBOMComponent -Sbom $sbom `
    -BomRef "other-lib" `
    -Name "Other Library" `
    -Purl "pkg:maven/org.example/other@2.0" `
    -Hash "abc123..."

# Add a composition referencing components
Add-SBOMComposition -Sbom $sbom `
    -BomRef "my-app" `
    -Dependencies @("my-library", "other-lib")

# Add a dependency to an existing composition
Add-SBOMCompositionDependency -Sbom $sbom `
    -CompositionRef "my-app" `
    -DependencyRef "new-dependency"

# Save the SBOM
Save-SBOM -Sbom $sbom -Path "output-sbom.xml"
```

## Module Structure

| File | Purpose |
|------|---------|
| `polyglot.psm1` | Main module entry point |
| `cyclonedx.ps1` | CycloneDX SBOM manipulation (add components/compositions) |
| `polyglot-pm.ps1` | Core package manager logic |
| `purl.ps1` | PURL parsing (`ConvertFrom-PkgUri`) |
| `pom.ps1` | Maven POM parsing and dependency resolution |
| `sbom.ps1` | CycloneDX SBOM validation |
| `download-deps.ps1` | Artifact downloading utilities |

## Exported Functions

| Function | Description |
|----------|-------------|
| `ConvertFrom-PkgUri` | Parse a PURL string into a structured object |
| `Get-PackageFromPurl` | Download a package and its dependencies from a PURL |
| `Copy-SoftwareComposition` | Download all dependencies from an SBOM composition |
| `Copy-GitHubRelease` | Download release assets from GitHub |
| `Get-GitHubReleases` | List available releases for a GitHub repository |
| `Get-MavenArtifact` | Download a Maven artifact (JAR + POM) |
| `Resolve-Dependencies` | Recursively resolve Maven dependencies |
| `Test-SBOM` | Validate a CycloneDX SBOM document |
| `Get-SBOM` | Load an existing CycloneDX SBOM file |
| `Save-SBOM` | Save an SBOM document to a file |
| `Add-SBOMComponent` | Add a component (with optional hash, distribution URL) |
| `Add-SBOMComposition` | Add a composition with dependencies |
| `Add-SBOMCompositionDependency` | Add a dependency to an existing composition |

## SBOM Format

The module expects CycloneDX 1.x XML format. Example structure:

```xml
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
  <components>
    <component type="library" bom-ref="my-lib">
      <name>my-library</name>
      <purl>pkg:maven/org.example/my-library@1.0.0</purl>
    </component>
  </components>
  <compositions>
    <composition bom-ref="my-composition">
      <dependencies>
        <dependency ref="my-lib"/>
      </dependencies>
    </composition>
  </compositions>
</bom>
```

## Testing

Tests use the [Pester](https://pester.dev/) framework:

```powershell
# Unit tests
Invoke-Pester ./polyglot.tests.ps1

# Integration tests (downloads real artifacts)
Invoke-Pester ./polyglot.integration.tests.ps1
```

## Limitations

- Parent POM resolution is not currently supported
- Dependency management sections in POMs are parsed but not fully resolved
- Some package ecosystems (npm, pypi, etc.) are not yet implemented

## License

Part of the [PowerXML](https://github.com/John/PowerXML) project.
