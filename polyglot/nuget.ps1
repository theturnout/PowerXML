# NuGet transitive dependency resolution via the AnyPackage.NuGet provider.
#
# The provider (https://github.com/anypackage/nuget) wraps the official NuGet
# client libraries: given a package and a target framework it resolves the
# complete dependency closure with NuGet's own rules (version ranges, nearest
# framework group, lowest applicable version, prerelease handling). This file
# uses it as the resolution oracle and materializes the result in the local
# PolyglotPM repository through the standard Install-Package path, mirroring
# how the Maven handler walks POM files (pom.ps1).
#
# Without AnyPackage.NuGet installed, resolution is skipped with a warning and
# SBOM compositions must list their complete dependency closure; see
# polyglot/README.md ("NuGet Packages").

<#
.SYNOPSIS
    Returns the target framework used for NuGet dependency resolution.
.DESCRIPTION
    Derived from the .NET runtime hosting PowerShell (the consumer of the
    resolved assemblies): PowerShell 7+ on .NET N resolves for netN.0, and
    anything else (Windows PowerShell 5.1 / .NET Framework) falls back to the
    portable netstandard2.0. Override with $env:POWERXML_NUGET_FRAMEWORK to
    cross-target (e.g. "net8.0").
.OUTPUTS
    A target framework moniker such as "net10.0" or "netstandard2.0".
#>
function Get-PXNuGetTargetFramework {
    [CmdletBinding()]
    param()

    if ($env:POWERXML_NUGET_FRAMEWORK) {
        return $env:POWERXML_NUGET_FRAMEWORK
    }
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $runtimeMajor = [System.Environment]::Version.Major
        if ($runtimeMajor -ge 6) {
            return "net$runtimeMajor.0"
        }
    }
    return 'netstandard2.0'
}

<#
.SYNOPSIS
    Determines whether the AnyPackage.NuGet provider is available.
.DESCRIPTION
    True when the module is installed and can be imported. The import is lazy,
    so sessions that never resolve NuGet dependencies are unaffected.
#>
function Test-PXNuGetProvider {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable AnyPackage.NuGet -ErrorAction SilentlyContinue)) {
        return $false
    }
    if (-not (Get-Module AnyPackage.NuGet -ErrorAction SilentlyContinue)) {
        Import-Module AnyPackage.NuGet -ErrorAction SilentlyContinue
    }
    return [bool](Get-Module AnyPackage.NuGet -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Reads a dependency marker file and verifies every listed package is installed.
.DESCRIPTION
    Marker files ({Name}-{Version}.deps.json) record the closure a previous
    resolution produced. Complete means every listed dependency directory is
    present in the local repository.
.OUTPUTS
    @{ Complete = $true/$false; Paths = @(installed dependency directories) }
#>
function Get-PXNuGetMarkerDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $MarkerPath,
        [Parameter(Mandatory = $true)]
        [string] $LocalRepository
    )

    try {
        $marker = Get-Content -Path $MarkerPath -Raw | ConvertFrom-Json
    }
    catch {
        return @{ Complete = $false; Paths = @() }
    }
    $paths = @()
    foreach ($dep in @($marker.dependencies)) {
        if (-not $dep.name) { continue }
        $depDir = Join-Path $LocalRepository "$($dep.name)-$($dep.version)"
        if (Test-Path $depDir -PathType Container) {
            $paths += $depDir
        }
        else {
            return @{ Complete = $false; Paths = @() }
        }
    }
    return @{ Complete = $true; Paths = $paths }
}

<#
.SYNOPSIS
    Installs a NuGet package (and its resolved dependency closure) via AnyPackage.NuGet.
.DESCRIPTION
    Thin seam over the AnyPackage provider call so tests can mock the network
    interaction. Installs into the global packages folder in effect for the
    call ($env:NUGET_PACKAGES). The module-qualified invocation avoids
    colliding with PackageManagement's Install-Package in the session.
#>
function Install-PXNuGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Version,
        [Parameter(Mandatory = $true)]
        [string] $Framework,
        [switch] $Prerelease
    )

    AnyPackage\Install-Package -Name $Name -Version $Version -Provider NuGet `
        -TrustSource -Framework $Framework -Prerelease:$Prerelease.IsPresent -ErrorAction Stop
}

<#
.SYNOPSIS
    Resolves and installs the transitive dependencies of a NuGet package.
.DESCRIPTION
    Uses AnyPackage.NuGet to resolve the dependency closure for the target
    framework (Get-PXNuGetTargetFramework) into a throwaway global packages
    folder, then materializes every resolved package in the local repository
    through Install-Package. The resolved closure is recorded in a marker file
    ({Name}-{Version}.deps.json); while the marker is complete, subsequent
    calls return immediately without touching the network.

    Resolution is skipped silently for an installed package whose directory
    contains no .nuspec and has no marker (a plain unpacked directory that
    never came from a nupkg, e.g. a test fixture), and with a warning when
    AnyPackage.NuGet is not installed or resolution fails — in both cases the
    SBOM's own dependency list is the fallback.
.PARAMETER Name
    The NuGet package id, e.g. "PhoenixmlDb.Xslt".
.PARAMETER Version
    The exact package version.
.PARAMETER LocalRepository
    The PolyglotPM local repository. Defaults to Get-LocalRepositoryPath.
.OUTPUTS
    The installed dependency directories (the root package itself is excluded;
    the caller already handles it).
#>
function Resolve-NuGetDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Version,
        [string] $LocalRepository = (Get-LocalRepositoryPath)
    )

    $markerPath = Join-Path $LocalRepository "$Name-$Version.deps.json"
    $rootDir = Join-Path $LocalRepository "$Name-$Version"

    # Fast path: a previous resolution recorded the closure and every listed
    # dependency is still installed
    if (Test-Path $markerPath -PathType Leaf) {
        $marker = Get-PXNuGetMarkerDependencies -MarkerPath $markerPath -LocalRepository $LocalRepository
        if ($marker.Complete) {
            Write-Verbose "NuGet dependencies of $Name $Version are already resolved (marker: $markerPath)."
            return $marker.Paths
        }
    }

    # An installed directory without a .nuspec and without a marker is a plain
    # unpacked directory (test fixture, hand-made package), not a nupkg
    # extraction: it is not on nuget.org and a resolution attempt would only
    # produce a network error.
    if ((Test-Path $rootDir -PathType Container) -and
        -not (Test-Path $markerPath -PathType Leaf) -and
        -not (Get-ChildItem -Path $rootDir -Filter *.nuspec -File -ErrorAction SilentlyContinue)) {
        Write-Verbose "No .nuspec in '$rootDir' and no dependency marker; skipping NuGet dependency resolution."
        return @()
    }

    if (-not (Test-PXNuGetProvider)) {
        Write-Warning "AnyPackage.NuGet is not installed; transitive dependencies of '$Name $Version' are not resolved. Install it (Install-Module AnyPackage.NuGet) or list the complete dependency closure in the SBOM."
        return @()
    }

    $framework = Get-PXNuGetTargetFramework
    Write-Verbose "Resolving NuGet dependencies of $Name $Version for $framework via AnyPackage.NuGet."

    # Resolve into a throwaway global packages folder: its contents are exactly
    # this package's closure, whatever the machine's real NuGet cache holds.
    $resolveDir = Join-Path ([System.IO.Path]::GetTempPath()) "polyglotpm-nuget-$(New-Guid)"
    $null = New-Item -ItemType Directory -Path $resolveDir -Force
    $previousNugetPackages = $env:NUGET_PACKAGES
    try {
        $env:NUGET_PACKAGES = $resolveDir
        $installParams = @{
            Name      = $Name
            Version   = $Version
            Framework = $framework
        }
        # A prerelease root version needs the provider's prerelease switch
        if ($Version -match '-') { $installParams.Prerelease = $true }
        $null = Install-PXNuGetPackage @installParams

        # Global packages layout: {id-lower}/{version}/ holding the .nupkg and
        # the .nuspec. Both file names are lowercased in the global packages
        # folder, so the canonical package id (used for the local repository
        # directory name) comes from the nuspec's <id> element, falling back
        # to the nuspec filename and then the folder name.
        $resolved = @(Get-ChildItem -Path $resolveDir -Directory | ForEach-Object {
            foreach ($versionDir in @(Get-ChildItem -Path $_.FullName -Directory)) {
                $nuspec = Get-ChildItem -Path $versionDir.FullName -Filter *.nuspec -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                $nupkg = Get-ChildItem -Path $versionDir.FullName -Filter *.nupkg -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                $canonicalId = $null
                if ($nuspec) {
                    try {
                        $nuspecXml = [xml](Get-Content -Path $nuspec.FullName -Raw)
                        $canonicalId = [string]$nuspecXml.package.metadata.id
                    }
                    catch {
                        $canonicalId = $null
                    }
                }
                if (-not $canonicalId -and $nuspec) {
                    $canonicalId = [System.IO.Path]::GetFileNameWithoutExtension($nuspec.Name)
                }
                if (-not $canonicalId) {
                    $canonicalId = $_.Name
                }
                [PSCustomObject]@{
                    Id      = $canonicalId
                    Version = $versionDir.Name
                    Nupkg   = if ($nupkg) { $nupkg.FullName } else { $null }
                }
            }
        })

        # Materialize the closure in the local repository (the root itself is
        # excluded: the caller downloads and installs it). This runs inside
        # the try block on purpose: the finally below removes the throwaway
        # folder, and the .nupkg files it holds are the install sources.
        $dependencies = @()
        $dependencyPaths = @()
        foreach ($pkg in $resolved) {
            if ($pkg.Id -ieq $Name -and $pkg.Version -eq $Version) {
                continue
            }
            $depDir = Join-Path $LocalRepository "$($pkg.Id)-$($pkg.Version)"
            if (-not (Test-Path $depDir -PathType Container)) {
                if (-not $pkg.Nupkg) {
                    Write-Warning "Resolved package '$($pkg.Id) $($pkg.Version)' has no .nupkg in the global packages folder; skipping."
                    continue
                }
                Write-Verbose "Installing resolved dependency $($pkg.Id) $($pkg.Version)."
                $null = Install-Package -DownloadedPath $pkg.Nupkg -Name $pkg.Id -Version $pkg.Version `
                    -LocalRepository $LocalRepository
            }
            $dependencies += @{ name = $pkg.Id; version = $pkg.Version }
            $dependencyPaths += $depDir
        }

        # Record the closure so later calls take the fast path
        $marker = [ordered]@{
            name         = $Name
            version      = $Version
            framework    = $framework
            dependencies = $dependencies
        }
        $marker | ConvertTo-Json -Depth 4 | Set-Content -Path $markerPath -Encoding UTF8

        return $dependencyPaths
    }
    catch {
        Write-Warning "NuGet dependency resolution for '$Name $Version' failed: $($_.Exception.Message). Only the packages listed in the SBOM will be available."
        return @()
    }
    finally {
        $env:NUGET_PACKAGES = $previousNugetPackages
        Remove-Item -LiteralPath $resolveDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
