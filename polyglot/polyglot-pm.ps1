# Polyglot Package Manager using CycloneDX XML

#  $session = New-PSSession -ConfigurationName 'PowerShell.7'
#   Enter-PSSession $session

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
#>
function Copy-SoftwareComposition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string] $sbomPath,
    [Parameter(Mandatory = $true)]
    [string] $targetComposition,
    [string] $localRepository = "$HOME/.polyglotpm"    
  )

  $file = Resolve-Path $sbomPath
  [xml]$xmlContent = Get-Content -Path $file
  # TODO schema validation
  $bom = $xmlContent.bom;
  $composition = $bom.compositions.composition | Where-Object { $_."bom-ref" -eq $targetComposition }
  if (!$composition) {
    Write-Host "Fatal: Target composition $targetComposition not found" -ForegroundColor Red
    exit 1
  }
  
  $composition.dependencies.dependency | ForEach-Object {
    $cur = $_.ref
    $currentComposition = $bom.components.component | Where-Object { $_."bom-ref" -eq $cur }
    # TODO better XPath
    # pull the distribution version preferrentially over the pkg mgr version
    $distribution = $currentComposition.externalReferences.reference.url
    if ($distribution) {
      Write-Verbose "Distribution $distribution"
      $purl = ConvertFrom-PkgUri($distribution)
    }
    else {
      Write-Verbose "Package $($currentComposition.purl)"
      $purl = ConvertFrom-PkgUri($currentComposition.purl)
    }

    # $purl | Format-List
    # Write-Output "------------------------------------"
    # try to download files
    $paths = Get-PackageFromPurl -purl $purl
    
    return $paths 
  }
} 
function Get-PackageFromPurl {
  param(
    [Parameter(Mandatory = $true)]
    $purl
  )
      
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
    
    $downloadPath = "$localRepository"
    
    
    $paths = @("$downloadPath\$artifactId-$version")
    
    # Main Execution
    $rootPom = Get-MavenArtifact -groupId $groupId `
      -artifactId $artifactId `
      -version $version `
      -repoUrl $repoUrl `
      -downloadPath $downloadPath

    if ($rootPom) {
      $currentPaths = Resolve-Dependencies -pomFile $rootPom `
        -repoUrl $MAVEN_CENTRAL `
        -downloadPath $downloadPath
      if ($currentPaths) {
        $paths += $currentPaths
      }
    }
    Write-Verbose "Maven dependencies downloaded to: $downloadPath"
  }
  elseif ($purl.Type -eq "sourceforge") {    
    $name = $purl.Name
    $filePath = $purl.QualifiersParsed["filename"]
    DownloadArtifact -name $purl.Name -version $purl.Version `
      -urlTemplate "https://sourceforge.net/projects/$name/files/$filePath" `
      -libPath $localRepository    
  }
  elseif ($purl.Type -eq "github") {
   $paths += Download-GitHubRelease -RepoOwner $purl.Namespace `
      -RepoName $purl.Name `
      -Version $purl.Version `
      -LibPath $localRepository
  }
  elseif ($purl.Type -eq "codeberg") {
  $paths +=  Download-GitHubRelease -RepoOwner $purl.Namespace `
      -RepoName $purl.Name `
      -Version $purl.Version `
      -LibPath $localRepository `
      -ApiPath "https://codeberg.org/api/v1"
  }
  else {
    Write-Host "$($purl.Type) not supported yet" -ForegroundColor Yellow				
  }
  return $paths
}
