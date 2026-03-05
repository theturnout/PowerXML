# Polyglot Package Manager using CycloneDX XML

. "$PSScriptRoot\purl.ps1"
. "$PSScriptRoot\download-deps.ps1"
. "$PSScriptRoot\pom.ps1"

$MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2"
<#
.SYNOPSIS
  Copies software composition from a CycloneDX SBOM XML file to a local repository.
  .PARAMETER sbomPath
  Path to the CycloneDX SBOM XML file.
  .PARAMETER targetComposition
  The specific composition to copy from the SBOM.
  .PARAMETER localRepository
  The local repository path where the dependencies will be copied.
  .OUTPUTS
  A list of objects containing the PURL and local path of each downloaded package.
#>
function Copy-SoftwareComposition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $sbomPath,
    [string] $targetComposition,
    [string] $localRepository = (Get-LocalRepositoryPath)    
  )

  # Assumes cycloneDX XML 1.X
  $file = Resolve-Path $sbomPath
  [xml]$xmlContent = Get-Content -Path $file
  if (-not (Test-SBOM $xmlContent)) {
    Write-Host "Fatal: Invalid SBOM file $sbomPath" -ForegroundColor Red
    exit 1
  }
  $bom = $xmlContent.bom;

  if (-not $targetComposition) {
    # Pick the first composition in the SBOM
    $allCompositions = @($bom.compositions.composition)
    if ($allCompositions.Count -eq 0 -or $null -eq $allCompositions[0]) {
      throw "No compositions found in SBOM '$sbomPath'."
    }
    $composition = $allCompositions[0]
    Write-Verbose "No targetComposition specified; using first composition '$($composition."bom-ref")'."
  }
  else {
    $composition = $bom.compositions.composition | Where-Object { $_."bom-ref" -eq $targetComposition }
    if (!$composition) {
      throw "Target composition '$targetComposition' not found in SBOM '$sbomPath'."
    }
  }
  
  $composition.dependencies.dependency | ForEach-Object {
    $cur = $_.ref
    $currentComposition = $bom.components.component | Where-Object { $_."bom-ref" -eq $cur }
    if (!$currentComposition) {
      Write-Host "Warning: Component with bom-ref $cur not found in SBOM components list" -ForegroundColor Yellow
      continue
    }
    # TODO better XPath
    # pull the distribution version preferentially over the pkg mgr version
    $distribution = $currentComposition.externalReferences.reference.url
    if ($distribution) {
      Write-Verbose "Distribution $distribution"
      $purl = ConvertFrom-PkgUri($distribution)
    }
    else {
      Write-Verbose "Package $($currentComposition.purl)"
      $purl = ConvertFrom-PkgUri($currentComposition.purl)
    }
    # Download the package
    $downloadResult = Get-PackageFromPurl -purl $purl -localRepository $localRepository

    # Extract SBOM-level metadata for post-processing
    $zipRoot = ($currentComposition.properties.property | Where-Object { $_.name -eq "rootZip" }).InnerText
    # Collect all hash nodes from SBOM (externalReferences and component-level)
    $hashNodes = @()
    $extRefHashes = $currentComposition.externalReferences.reference.hashes.hash
    if ($extRefHashes) { $hashNodes += @($extRefHashes) }
    $componentHashes = $currentComposition.hashes.hash
    if ($componentHashes) { $hashNodes += @($componentHashes) }

    $verifiableHashes = @()
    if ($hashNodes.Count -eq 0) {
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
        Name            = $purl.Name
        Version         = $purl.Version
        LocalRepository = $localRepository
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
Downloads a package and its dependencies based on the provided Package URL (PURL)
.PARAMETER purl
The Package URL object representing the package to download.
.RETURNS
A object with the Purl and local path of the downloaded package.
  #>
function Get-PackageFromPurl {  
  param(
    [Parameter(Mandatory = $true)]
    $purl,
    [string] $localRepository = (Get-LocalRepositoryPath)
  )

  $paths = @()
      
  if ($purl.Type -eq "maven") {
    $groupId = $purl.Namespace
    $artifactId = $purl.Name
    # version may not always exist
    $version = $purl.Version
    # TODO doesn't fix issues with overall resolution of saxon-ee deps
    if ($groupId -eq "com.saxonica") {
      $repoUrl = "https://maven.saxonica.com/maven"
    }
    else {
      $repoUrl = "https://repo1.maven.org/maven2"
    }
    
    $paths = @("$localRepository\$artifactId-$version")
    
    # Main Execution
    $rootPom = Get-MavenArtifact -groupId $groupId `
      -artifactId $artifactId `
      -version $version `
      -repoUrl $repoUrl `
      -downloadPath $localRepository

    if ($rootPom) {
      $currentPaths = Resolve-Dependencies -pomFile $rootPom `
        -repoUrl $MAVEN_CENTRAL `
        -downloadPath $localRepository
      if ($currentPaths) {
        $paths += $currentPaths
      }
    }
    Write-Verbose "Maven dependencies downloaded to: $localRepository"
  }
  elseif ($purl.Type -eq "sourceforge") {
    $name = $purl.Name
    $version = $purl.Version
    $filePath = $purl.QualifiersParsed["filename"]
    $downloadUrl = "https://sourceforge.net/projects/$name/files/$filePath"
    $zipPath = Join-Path $localRepository "$name-$version.zip"
    $installedPath = Join-Path $localRepository "$name-$version"

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
  elseif ($purl.Type -eq "github") {
    $paths += Copy-GitHubRelease -RepoOwner $purl.Namespace `
      -RepoName $purl.Name `
      -Version $purl.Version `
      -LibPath $localRepository
  }
  elseif ($purl.Type -eq "codeberg") {
    if ($purl.QualifiersParsed["filename"]) {
      $fileName = $purl.QualifiersParsed["filename"]
    }
    
    $paths += Copy-GitHubRelease -RepoOwner $purl.Namespace `
      -RepoName $purl.Name `
      -Version $purl.Version `
      -LibPath $localRepository `
      -ApiPath "https://codeberg.org/api/v1" `
      -Assets @($fileName)
  }
  else {
    Write-Host "$($purl.Type) not supported yet" -ForegroundColor Yellow				
  }
  return $paths
}

function Get-LocalRepositoryPath {
  $path = if ($env:polyglotpm) { $env:polyglotpm } else { "$HOME/.polyglotpm" }
  # Resolve PSDrive paths (e.g. TestDrive:\) to real filesystem paths
  # so non-PowerShell consumers like Java can use them
  if (Test-Path $path) {
    return (Convert-Path $path)
  }
  return $path
}
