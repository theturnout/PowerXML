# Polyglot Package Manager — Internals

## Overview

The polyglot package manager resolves and downloads dependencies declared in a
[CycloneDX](https://cyclonedx.org/) SBOM XML file. Each dependency is identified
by a [Package URL (purl)](https://github.com/package-url/purl-spec). The entry
point is `Copy-SoftwareComposition` in `polyglot-pm.ps1`, which is called by
`Transform-Xml` (in `powerxml.ps1`) before invoking an XProc or XSLT processor.

## Call chain

```
Transform-Xml  -PackageResolution @{ sbomPath; targetComposition; GetLatest }
  └─ Copy-SoftwareComposition  (polyglot-pm.ps1)
       ├─ ConvertFrom-PkgUri   (purl.ps1)         — parse purl string
       ├─ Resolve-LatestVersion (download-deps.ps1) — optional, when -GetLatest
       ├─ Set-PurlVersion       (purl.ps1)          — rewrite purl with resolved version
       ├─ Get-PackageFromPurl   (polyglot-pm.ps1)  — dispatch download by type
       │    ├─ Copy-GitHubRelease  — github / codeberg
       │    ├─ Get-MavenArtifact   — maven
       │    ├─ Invoke-WebRequest   — sourceforge
       │    └─ Invoke-WebRequest   — nuget (NuGet v3 flat-container API)
       └─ Install-Package      (install-package.ps1) — extract, verify hashes
```

## Package resolution flow

For each dependency listed in the selected SBOM composition:

1. **Select purl source** — the `externalReferences/reference/url` (distribution
   purl) is preferred over the component-level `<purl>` element. The distribution
   purl typically includes a `filename` qualifier pointing to a specific release
   asset.

2. **GetLatest resolution** (when `-GetLatest` is set) — applies to
   `github`, `codeberg`, and `nuget` purl types. Other types (`maven`,
   `sourceforge`) fall back to their SBOM-pinned version with a warning.
   For `nuget`, the flat-container index at
   `https://api.nuget.org/v3-flatcontainer/{id-lower}/index.json` is queried
   and the last listed version is returned.

   a. The component's purl is parsed to extract Type, Namespace, and Name.
   b. `Resolve-LatestVersion` calls `{ApiPath}/repos/{Namespace}/{Name}/releases/latest`
      and returns the `tag_name`.
   c. If the resolved version differs from the SBOM version, `Set-PurlVersion`
      rewrites both the `@version` segment and any version string in qualifier
      values (e.g. `filename=xmlcalabash-3.0.24.zip`). Hash validation is
      skipped for rewritten components since the SBOM hashes correspond to the
      original pinned version.

3. **Download** — `Get-PackageFromPurl` dispatches to the appropriate downloader
   based on purl type. `Copy-GitHubRelease` implements a local-first strategy:
   if the extracted asset directory already exists, the API call and download are
   skipped entirely.

4. **Install and verify** — `Install-Package` extracts archives and validates
   file hashes against the SBOM (unless hash validation was skipped by GetLatest).

## Version cache

`Resolve-LatestVersion` maintains an in-memory cache (`$Script:LatestVersionCache`)
keyed by `Type/Namespace/Name`. Each entry stores the resolved version and a
timestamp.

- **TTL** — controlled by `$env:POWERXML_CACHE_TTL_HOURS`. Defaults to **3 hours**.
  Entries older than the TTL are evicted on the next lookup and re-fetched.
- **Scope** — the cache lives for the duration of the module's import (i.e. the
  PowerShell session). It is not persisted to disk.
- **Clearing** — call `Clear-LatestVersionCache` to force re-resolution on the
  next invocation.

## Purl version rewriting

`Set-PurlVersion` uses two regex replacements to rewrite a version string in a
purl without corrupting adjacent text:

1. **`@version` segment** — `(?<=@)OldVersion(?=[?#]|$)` targets only the
   version between `@` and the next qualifier/fragment/end delimiter.
2. **Qualifier filenames** — `(?<=[^a-zA-Z0-9])OldVersion(?=\.[^0-9]|[^0-9.]|$)`
   matches the version when preceded by a non-alphanumeric character and followed
   by a file extension or end-of-string. This prevents partial replacement
   (e.g. `1.0` inside `1.0.1`).

## Key files

| File | Responsibility |
|---|---|
| `polyglot-pm.ps1` | `Copy-SoftwareComposition`, `Get-PackageFromPurl`, orchestration |
| `purl.ps1` | `ConvertFrom-PkgUri`, `Set-PurlVersion` |
| `download-deps.ps1` | `Copy-GitHubRelease`, `Resolve-LatestVersion`, `Clear-LatestVersionCache` |
| `install-package.ps1` | Archive extraction, hash verification |
| `sbom.ps1` | SBOM XML validation (`Test-SBOM`) |
| `cyclonedx.ps1` | SBOM creation / mutation helpers |
| `pom.ps1` | Maven POM parsing and transitive dependency resolution |
