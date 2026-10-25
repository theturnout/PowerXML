# Polyglot Package Manager using CycloneDX XML

. "$PSScriptRoot\purl.ps1"
. "$PSScriptRoot\download-deps.ps1"
. "$PSScriptRoot\pom.ps1"

$MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2"

<#
.SYNOPSIS
  Merges additional package URLs into an in-memory CycloneDX SBOM.
.DESCRIPTION
  For each purl in AdditionalPackages, matches existing components by
  type/namespace/name. When a match is found the version is rewritten
  (in both the component purl and its distribution URL) and hashes are
  removed. Unmatched purls are added as new components and appended to
  the specified composition.
.PARAMETER Sbom
  The in-memory SBOM XmlDocument to modify.
.PARAMETER AdditionalPackages
  One or more Package URL strings to merge.
.PARAMETER CompositionRef
  The bom-ref of the composition that new (non-matching) components
  should be added to.
#>
function Merge-AdditionalPackages {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [xml]$Sbom,
    [Parameter(Mandatory = $true)]
    [string[]]$AdditionalPackages,
    [string]$CompositionRef
  )

  $ns = $Sbom.DocumentElement.NamespaceURI

  foreach ($purlString in $AdditionalPackages) {
    $addPurl = ConvertFrom-PkgUri $purlString

    # Find existing component with matching type/namespace/name
    $matchingComponent = $null
    $existingPurl = $null
    foreach ($comp in @($Sbom.bom.components.component)) {
      if (-not $comp.purl) { continue }
      $compPurl = ConvertFrom-PkgUri ([string]$comp.purl)
      if ($compPurl.Type -eq $addPurl.Type -and
          $compPurl.Namespace -eq $addPurl.Namespace -and
          $compPurl.Name -eq $addPurl.Name) {
        $matchingComponent = $comp
        $existingPurl = $compPurl
        break
      }
    }

    if ($matchingComponent) {
      if ($existingPurl.Version -ne $addPurl.Version) {
        Write-Verbose "AdditionalPackages: rewriting '$($matchingComponent."bom-ref")' version $($existingPurl.Version) -> $($addPurl.Version)"

        # Rewrite component purl
        $matchingComponent.purl = Set-PurlVersion -PurlString ([string]$matchingComponent.purl) `
          -OldVersion $existingPurl.Version -NewVersion $addPurl.Version

        # Rewrite distribution URL if present
        $refNode = $matchingComponent.SelectSingleNode(
          "*[local-name()='externalReferences']/*[local-name()='reference']")
        if ($refNode) {
          $urlNode = $refNode.SelectSingleNode("*[local-name()='url']")
          if ($urlNode) {
            $urlNode.InnerText = Set-PurlVersion -PurlString $urlNode.InnerText `
              -OldVersion $existingPurl.Version -NewVersion $addPurl.Version
          }
          # Remove distribution reference hashes
          $refHashes = $refNode.SelectSingleNode("*[local-name()='hashes']")
          if ($refHashes) { $refNode.RemoveChild($refHashes) | Out-Null }
        }

        # Remove component-level hashes
        $componentHashes = $matchingComponent.SelectSingleNode("*[local-name()='hashes']")
        if ($componentHashes) { $matchingComponent.RemoveChild($componentHashes) | Out-Null }
      }
    }
    else {
      # Add new component
      $bomRef = "$($addPurl.Name)-additional"
      $component = $Sbom.CreateElement("component", $ns)
      $component.SetAttribute("type", "library")
      $component.SetAttribute("bom-ref", $bomRef)

      $nameEl = $Sbom.CreateElement("name", $ns)
      $nameEl.InnerText = $addPurl.Name
      $component.AppendChild($nameEl) | Out-Null

      $purlEl = $Sbom.CreateElement("purl", $ns)
      $purlEl.InnerText = $purlString
      $component.AppendChild($purlEl) | Out-Null

      $componentsNode = $Sbom.DocumentElement.SelectSingleNode("*[local-name()='components']")
      $componentsNode.AppendChild($component) | Out-Null

      # Add to composition
      if ($CompositionRef) {
        $compNode = $Sbom.bom.compositions.composition |
          Where-Object { $_."bom-ref" -eq $CompositionRef }
        if ($compNode) {
          $dep = $Sbom.CreateElement("dependency", $ns)
          $dep.SetAttribute("ref", $bomRef)
          $depsContainer = $compNode.SelectSingleNode("*[local-name()='dependencies']")
          if (-not $depsContainer) {
            $depsContainer = $Sbom.CreateElement("dependencies", $ns)
            $compNode.AppendChild($depsContainer) | Out-Null
          }
          $depsContainer.AppendChild($dep) | Out-Null
        }
      }
    }
  }
}

<#
.SYNOPSIS
  Copies software composition from a CycloneDX SBOM XML file to a local repository.
.PARAMETER SbomPath
  Path to the CycloneDX SBOM XML file. When omitted (and AdditionalPackages is
  supplied) an interstitial SBOM is created in memory.
.PARAMETER TargetComposition
  The specific composition to copy from the SBOM.
.PARAMETER LocalRepository
  The local repository path where the dependencies will be copied.
.PARAMETER GetLatest
  When specified, resolves the latest version for supported package types (codeberg, github)
  by calling their release API. The resolved version replaces the SBOM-pinned version in the
  purl before downloading. SBOM hash validation is skipped for rewritten components.
  Unsupported types (sourceforge, maven) fall back to their pinned version with a warning.
.PARAMETER AdditionalPackages
  One or more Package URL strings to merge into the SBOM. Matching components
  (same type/namespace/name) have their version replaced and hashes removed.
  Non-matching purls are added as new components.
.OUTPUTS
  A list of objects containing the PURL and local path of each downloaded package.
#>
function Copy-SoftwareComposition {
  [CmdletBinding()]
  param(
    [string] $SbomPath,
    [string] $TargetComposition,
    [string] $LocalRepository = (Get-LocalRepositoryPath),
    [switch] $GetLatest,
    [string[]] $AdditionalPackages,
    [switch] $ValidateSbom
  )

  # Load existing SBOM or create an interstitial one from AdditionalPackages
  if ($SbomPath -and (Test-Path $SbomPath)) {
    $file = Resolve-Path $SbomPath
    [xml]$xmlContent = Get-Content -Path $file
    if (-not (Test-SBOM $xmlContent -ValidateSchema:$ValidateSbom)) {
      Write-Host "Fatal: Invalid SBOM file $SbomPath" -ForegroundColor Red
      exit 1
    }
  }
  elseif ($AdditionalPackages) {
    Write-Verbose "No SBOM file found; creating interstitial SBOM from AdditionalPackages."
    [xml]$xmlContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.5">
  <components/>
  <compositions>
    <composition bom-ref="additional">
      <aggregate>complete</aggregate>
      <dependencies/>
    </composition>
  </compositions>
</bom>
'@
  }
  else {
    # Preserve existing error behaviour: Resolve-Path throws on missing file
    Resolve-Path $SbomPath -ErrorAction Stop
    return
  }

  $bom = $xmlContent.bom

  if (-not $TargetComposition) {
    # Pick the first composition in the SBOM
    $allCompositions = @($bom.compositions.composition)
    if ($allCompositions.Count -eq 0 -or $null -eq $allCompositions[0]) {
      throw "No compositions found in SBOM '$SbomPath'."
    }
    $composition = $allCompositions[0]
    Write-Verbose "No targetComposition specified; using first composition '$($composition."bom-ref")'."
  }
  else {
    $composition = $bom.compositions.composition | Where-Object { $_."bom-ref" -eq $TargetComposition }
    if (!$composition) {
      throw "Target composition '$TargetComposition' not found in SBOM '$SbomPath'."
    }
  }

  # Merge AdditionalPackages into the interstitial SBOM
  if ($AdditionalPackages) {
    Merge-AdditionalPackages -Sbom $xmlContent `
      -AdditionalPackages $AdditionalPackages `
      -CompositionRef $composition."bom-ref"
  }
  
  $composition.dependencies.dependency | ForEach-Object {
    $cur = $_.ref
    $currentComposition = $bom.components.component | Where-Object { $_."bom-ref" -eq $cur }
    if (!$currentComposition) {
      Write-Host "Warning: Component with bom-ref $cur not found in SBOM components list" -ForegroundColor Yellow
      continue
    }
    # pull the distribution version preferentially over the pkg mgr version
    $distribution = $currentComposition.externalReferences.reference.url
    if ($distribution) {
      Write-Verbose "Distribution $distribution"
      $purlString = $distribution
    }
    else {
      Write-Verbose "Package $($currentComposition.purl)"
      $purlString = [string]$currentComposition.purl
    }

    # GetLatest: resolve and rewrite version for supported types
    $skipHashes = $false
    if ($GetLatest) {
      $componentPurl = ConvertFrom-PkgUri([string]$currentComposition.purl)
      if ($componentPurl.Type -in @('codeberg', 'github', 'nuget')) {
        $apiPath = switch ($componentPurl.Type) {
          "codeberg" { "https://codeberg.org/api/v1" }
          default    { "https://api.github.com" }
        }
        $latestVersion = Resolve-LatestVersion -Type $componentPurl.Type `
          -Namespace $componentPurl.Namespace `
          -Name $componentPurl.Name `
          -ApiPath $apiPath
        if ($latestVersion -and $latestVersion -ne $componentPurl.Version) {
          Write-Verbose "Rewriting $cur version $($componentPurl.Version) -> $latestVersion"
          $purlString = Set-PurlVersion -PurlString $purlString `
            -OldVersion $componentPurl.Version `
            -NewVersion $latestVersion
          $skipHashes = $true
        }
      }
      else {
        Write-Warning "GetLatest is not supported for package type '$($componentPurl.Type)'. Using pinned version for '$cur'."
      }
    }

    $Purl = ConvertFrom-PkgUri($purlString)
    # Download the package
    $downloadResult = Get-PackageFromPurl -Purl $Purl -LocalRepository $LocalRepository

    # Extract SBOM-level metadata for post-processing
    $zipRoot = ($currentComposition.properties.property | Where-Object { $_.name -eq "rootZip" }).InnerText
    # Collect all hash nodes from SBOM (externalReferences and component-level)
    $hashNodes = @()
    $extRefHashes = $currentComposition.externalReferences.reference.hashes.hash
    if ($extRefHashes) { $hashNodes += @($extRefHashes) }
    $componentHashes = $currentComposition.hashes.hash
    if ($componentHashes) { $hashNodes += @($componentHashes) }

    $verifiableHashes = @()
    if ($skipHashes) {
      Write-Verbose "Skipping SBOM hash validation for '$cur' (version was resolved to latest)."
    }
    elseif ($hashNodes.Count -eq 0) {
      Write-Warning "No hashes found for component '$cur' in SBOM."
    }
    else {
      $supportedAlgorithms = @('MD5', 'SHA1', 'SHA256', 'SHA384', 'SHA512')
      $allHashes = @($hashNodes | ForEach-Object {
        [PSCustomObject]@{
          Algorithm = ($_.alg -replace '-', '')
          Hash      = $_.InnerText
        }
      })
      $verifiableHashes = @($allHashes | Where-Object { $_.Algorithm -in $supportedAlgorithms })
      if ($verifiableHashes.Count -eq 0) {
        $foundAlgs = ($allHashes | ForEach-Object { $_.Algorithm }) -join ', '
        throw "Component '$cur' has hashes but none use a verifiable algorithm. Found: $foundAlgs"
      }
    }

    # Post-process with Install-Package when download result is a file (not yet installed)
    $mainPath = if ($downloadResult -is [array]) { $downloadResult[0] } else { $downloadResult }
    if ($mainPath -and (Test-Path $mainPath -PathType Leaf)) {
      $installParams = @{
        DownloadedPath  = $mainPath
        Name            = $Purl.Name
        Version         = $Purl.Version
        LocalRepository = $LocalRepository
      }
      if ($zipRoot) { $installParams.ZipRoot = $zipRoot }
      if ($verifiableHashes.Count -gt 0) {
        $installParams.Hashes = $verifiableHashes
      }
      $installedPath = Install-Package @installParams
      if ($downloadResult -is [array]) { $downloadResult[0] = $installedPath }
      else { $downloadResult = $installedPath }
    }

    return $downloadResult 
  }
} 
<#
.SYNOPSIS
  Validates that a software composition from a CycloneDX SBOM is installed in the local repository.
.DESCRIPTION
  Reports per-dependency status without downloading anything: whether the installed
  directory is present, and where possible whether the downloaded artifact still
  matches the hashes recorded in the SBOM. Useful for detecting corrupted
  (different files with the same name) or deleted dependencies.
.PARAMETER SbomPath
  Path to the CycloneDX SBOM XML file.
.PARAMETER TargetComposition
  The specific composition to validate. Defaults to the first composition in the SBOM.
.PARAMETER LocalRepository
  The local repository path where the dependencies are installed.
.PARAMETER ValidateSbom
  When specified, runs XSD schema validation when loading the SBOM.
.OUTPUTS
  One object per composition dependency with BomRef, Name, Version, Type, Status,
  HashVerified, InstalledPath, and Detail properties. Status is one of:
  Installed, Missing, HashMismatch, NoHashes, or UnknownComponent.
#>
function Test-Composition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $SbomPath,
    [string] $TargetComposition,
    [string] $LocalRepository = (Get-LocalRepositoryPath),
    [switch] $ValidateSbom
  )

  if (-not (Test-Path $SbomPath)) {
    throw "SBOM file not found: '$SbomPath'."
  }
  $file = Resolve-Path $SbomPath
  [xml]$xmlContent = Get-Content -Path $file
  if (-not (Test-SBOM $xmlContent -ValidateSchema:$ValidateSbom)) {
    throw "Invalid SBOM file '$SbomPath'."
  }
  $bom = $xmlContent.bom

  if (-not $TargetComposition) {
    $allCompositions = @($bom.compositions.composition)
    if ($allCompositions.Count -eq 0 -or $null -eq $allCompositions[0]) {
      throw "No compositions found in SBOM '$SbomPath'."
    }
    $composition = $allCompositions[0]
    Write-Verbose "No TargetComposition specified; using first composition '$($composition."bom-ref")'."
  }
  else {
    $composition = $bom.compositions.composition | Where-Object { $_."bom-ref" -eq $TargetComposition }
    if (!$composition) {
      throw "Target composition '$TargetComposition' not found in SBOM '$SbomPath'."
    }
  }

  foreach ($dep in @($composition.dependencies.dependency)) {
    $cur = $dep.ref
    $component = $bom.components.component | Where-Object { $_."bom-ref" -eq $cur }
    if (!$component) {
      Write-Warning "Component with bom-ref $cur not found in SBOM components list"
      [PSCustomObject]@{
        BomRef        = $cur
        Name          = $cur
        Version       = $null
        Type           = $null
        Status        = "UnknownComponent"
        HashVerified  = $false
        InstalledPath = $null
        Detail        = "Component not found in the SBOM components list."
      }
      continue
    }

    # pull the distribution version preferentially over the pkg mgr version
    $distribution = $component.externalReferences.reference.url
    if ($distribution) {
      $purlString = $distribution
    }
    else {
      $purlString = [string]$component.purl
    }
    $purl = ConvertFrom-PkgUri($purlString)

    # Collect verifiable hashes from the SBOM (externalReferences and component-level)
    $hashNodes = @()
    $extRefHashes = $component.externalReferences.reference.hashes.hash
    if ($extRefHashes) { $hashNodes += @($extRefHashes) }
    $componentHashes = $component.hashes.hash
    if ($componentHashes) { $hashNodes += @($componentHashes) }
    $supportedAlgorithms = @("MD5", "SHA1", "SHA256", "SHA384", "SHA512")
    $hashes = @($hashNodes | ForEach-Object {
      [PSCustomObject]@{
        Algorithm = ($_.alg -replace "-", "")
        Hash      = $_.InnerText
      }
    } | Where-Object { $_.Algorithm -in $supportedAlgorithms })

    # Resolve the installed directory and the artifact to hash-verify by package type
    # (purls without qualifiers leave QualifiersParsed unset)
    $fileName = if ($null -ne $purl.QualifiersParsed) { $purl.QualifiersParsed["filename"] } else { $null }
    $installedPath = Join-Path $LocalRepository "$($purl.Name)-$($purl.Version)"
    $verifyPath = $null
    switch ($purl.Type) {
      "github" {
        if ($fileName) {
          $installedPath = Join-Path $LocalRepository ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
          $verifyPath = Join-Path $LocalRepository $fileName
        }
      }
      "codeberg" {
        if ($fileName) {
          $installedPath = Join-Path $LocalRepository ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
          $verifyPath = Join-Path $LocalRepository $fileName
        }
      }
      "sourceforge" {
        $verifyPath = Join-Path $LocalRepository "$($purl.Name)-$($purl.Version).zip"
      }
      "nuget" {
        $verifyPath = Join-Path $LocalRepository "$($purl.Name)-$($purl.Version).nupkg"
      }
      "maven" {
        $verifyPath = Join-Path $installedPath "$($purl.Name)-$($purl.Version).jar"
      }
      default {
        Write-Warning "Package type '$($purl.Type)' is not supported for hash verification; checking existence only."
      }
    }

    if (-not (Test-Path $installedPath -PathType Container)) {
      $detail = "Installed directory not found."
      if ($verifyPath -and (Test-Path $verifyPath -PathType Leaf)) {
        $detail += " The downloaded artifact is still present."
      }
      [PSCustomObject]@{
        BomRef        = $cur
        Name          = $purl.Name
        Version       = $purl.Version
        Type          = $purl.Type
        Status        = "Missing"
        HashVerified  = $false
        InstalledPath = $null
        Detail        = $detail
      }
      continue
    }

    if ($hashes.Count -eq 0) {
      [PSCustomObject]@{
        BomRef        = $cur
        Name          = $purl.Name
        Version       = $purl.Version
        Type          = $purl.Type
        Status        = "NoHashes"
        HashVerified  = $false
        InstalledPath = $installedPath
        Detail        = "Installed, but the SBOM carries no verifiable hashes for this component."
      }
      continue
    }

    if (-not ($verifyPath -and (Test-Path $verifyPath -PathType Leaf))) {
      [PSCustomObject]@{
        BomRef        = $cur
        Name          = $purl.Name
        Version       = $purl.Version
        Type          = $purl.Type
        Status        = "Installed"
        HashVerified  = $false
        InstalledPath = $installedPath
        Detail        = "Installed, but the artifact to hash-verify is no longer present."
      }
      continue
    }

    $verified = $true
    $firstFailure = $null
    foreach ($h in $hashes) {
      try {
        $null = Test-FileHash -Path $verifyPath -ExpectedHash $h.Hash -Algorithm $h.Algorithm
      }
      catch {
        $verified = $false
        if (-not $firstFailure) { $firstFailure = $_.Exception.Message }
      }
    }
    if ($verified) {
      [PSCustomObject]@{
        BomRef        = $cur
        Name          = $purl.Name
        Version       = $purl.Version
        Type          = $purl.Type
        Status        = "Installed"
        HashVerified  = $true
        InstalledPath = $installedPath
        Detail        = "Hash verified against the SBOM."
      }
    }
    else {
      [PSCustomObject]@{
        BomRef        = $cur
        Name          = $purl.Name
        Version       = $purl.Version
        Type          = $purl.Type
        Status        = "HashMismatch"
        HashVerified  = $false
        InstalledPath = $installedPath
        Detail        = $firstFailure
      }
    }
  }
}
<#
.SYNOPSIS
Downloads a package and its dependencies based on the provided Package URL (PURL)
.PARAMETER Purl
The Package URL object representing the package to download.
.RETURNS
A object with the Purl and local path of the downloaded package.
  #>
function Get-PackageFromPurl {  
  param(
    [Parameter(Mandatory = $true)]
    $Purl,
    [string] $LocalRepository = (Get-LocalRepositoryPath)
  )

  $paths = @()
      
  if ($Purl.Type -eq "maven") {
    $groupId = $Purl.Namespace
    $artifactId = $Purl.Name
    # version may not always exist
    $version = $Purl.Version
    # TODO doesn't fix issues with overall resolution of saxon-ee deps
    if ($groupId -eq "com.saxonica") {
      $repoUrl = "https://maven.saxonica.com/maven"
    }
    else {
      $repoUrl = "https://repo1.maven.org/maven2"
    }
    
    $paths = @("$LocalRepository\$artifactId-$version")
    
    # Main Execution
    $rootPom = Get-MavenArtifact -groupId $groupId `
      -artifactId $artifactId `
      -version $version `
      -repoUrl $repoUrl `
      -downloadPath $LocalRepository

    if ($rootPom) {
      $currentPaths = Resolve-Dependencies -pomFile $rootPom `
        -repoUrl $MAVEN_CENTRAL `
        -downloadPath $LocalRepository
      if ($currentPaths) {
        $paths += $currentPaths
      }
    }
    Write-Verbose "Maven dependencies downloaded to: $LocalRepository"
  }
  elseif ($Purl.Type -eq "sourceforge") {
    $name = $Purl.Name
    $version = $Purl.Version
    $filePath = $Purl.QualifiersParsed["filename"]
    $downloadUrl = "https://sourceforge.net/projects/$name/files/$filePath"
    $zipPath = Join-Path $LocalRepository "$name-$version.zip"
    $installedPath = Join-Path $LocalRepository "$name-$version"

    # Already installed (by a previous Install-Package call)
    if (Test-Path $installedPath -PathType Container) {
      Write-Verbose "$name $version already installed."
      $paths = @($installedPath)
    }
    else {
      # Download the zip if not already present
      if (-not (Test-Path $zipPath)) {
        Write-Host "Downloading $name-$version ..."
        Invoke-WebRequest -UserAgent "Wget" -Uri $downloadUrl -OutFile $zipPath
      }
      else {
        Write-Verbose "$name $version already downloaded."
      }
      $paths = @($zipPath)
    }
  }
  elseif ($Purl.Type -eq "github") {
    $paths += Copy-GitHubRelease -RepoOwner $Purl.Namespace `
      -RepoName $Purl.Name `
      -Version $Purl.Version `
      -LibPath $LocalRepository
  }
  elseif ($Purl.Type -eq "codeberg") {
    if ($Purl.QualifiersParsed["filename"]) {
      $fileName = $Purl.QualifiersParsed["filename"]
    }
    
    $paths += Copy-GitHubRelease -RepoOwner $Purl.Namespace `
      -RepoName $Purl.Name `
      -Version $Purl.Version `
      -LibPath $LocalRepository `
      -ApiPath "https://codeberg.org/api/v1" `
      -Assets @($fileName)
  }
  elseif ($Purl.Type -eq "nuget") {
    $name = $Purl.Name
    $version = $Purl.Version
    $idLower = $name.ToLowerInvariant()
    $nupkgFile = "$idLower.$version.nupkg"
    $downloadUrl = "https://api.nuget.org/v3-flatcontainer/$idLower/$version/$nupkgFile"
    $nupkgPath = Join-Path $LocalRepository "$name-$version.nupkg"
    $installedPath = Join-Path $LocalRepository "$name-$version"

    # Already installed (by a previous Install-Package call)
    if (Test-Path $installedPath -PathType Container) {
      Write-Verbose "$name $version already installed."
      $paths = @($installedPath)
    }
    else {
      # Download the nupkg if not already present
      if (-not (Test-Path $nupkgPath)) {
        Write-Host "Downloading $name $version from NuGet..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $nupkgPath -UseBasicParsing
      }
      else {
        Write-Verbose "$name $version already downloaded."
      }
      $paths = @($nupkgPath)
    }
  }
  else {
    Write-Host "$($Purl.Type) not supported yet" -ForegroundColor Yellow				
  }
  return $paths
}

function Get-LocalRepositoryPath {
  $path = if ($env:polyglotpm) { $env:polyglotpm } else { "$HOME/.polyglotpm" }
  # Ensure the repository exists so first-time users do not hit download
  # or extraction errors on a missing directory
  if (-not (Test-Path $path)) {
    try {
      New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
      Write-Verbose "Created local repository at '$path'."
    }
    catch {
      Write-Error "Failed to create local repository at '$path': $($_.Exception.Message)"
      return $path
    }
  }
  # Resolve PSDrive paths (e.g. TestDrive:\) to real filesystem paths
  # so non-PowerShell consumers like Java can use them
  if (Test-Path $path) {
    return (Convert-Path $path)
  }
  return $path
}
