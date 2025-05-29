# Polyglot Package Manager using CycloneDX XML

#  $session = New-PSSession -ConfigurationName 'PowerShell.7'
#   Enter-PSSession $session

. "$PSScriptRoot\purl.ps1"
. "$PSScriptRoot\download-deps.ps1"
. "$PSScriptRoot\pom.ps1"


$MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2"

function Copy-Software-Composition {
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
  
  $paths = [System.Collections.ArrayList]::new()
  $composition.dependencies.dependency | ForEach-Object {
    $cur = $_.ref
    $currComp = $bom.components.component | Where-Object { $_."bom-ref" -eq $cur }
    # TODO better XPath
    # pull the distribution version preferrentially over the pkg mgr version
    $distribution = $currComp.externalReferences.reference.url
    if ($distribution) {
      Write-Host $distribution
      $purl = ConvertFrom-PkgUri($distribution)
    }
    else {
      Write-Host $currComp.purl
      $purl = ConvertFrom-PkgUri($currComp.purl)
    }

   # $purl | Format-List
   # Write-Output "------------------------------------"
    # try to download files

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


      $paths.Add("$downloadPath\$artifactId-$version")

      # Main Execution
      $rootPom = Get-MavenArtifact -groupId $groupId -artifactId $artifactId -version $version -repoUrl $repoUrl -downloadPath $downloadPath
      if ($rootPom) {
        $paths.AddRange((Resolve-Dependencies -pomFile $rootPom -repoUrl $MAVEN_CENTRAL -downloadPath $downloadPath))
      }
      Write-Host "Maven dependencies downloaded to: $downloadPath"
    }
    elseif ($purl.Type -eq "sourceforge") {

      $name = $purl.Name
      $filePath = $purl.QualifiersParsed["filename"]
      DownloadArtifact -name $purl.Name -version $purl.Version `
        -urlTemplate "https://sourceforge.net/projects/$name/files/$filePath" `
        -libPath $localRepository
      #-zipRoot "MorganaXProc-IIIse-1.2" `
      #-expectedHash "2BA1C4A57488429C734D80C32E4CE242A4F5230CAC20D2592D786873DCEEFA97"
  
    }
    elseif ($purl.Type -eq "github") {
      Download-GitHubRelease -RepoOwner $purl.Namespace -RepoName $purl.Name -Version $purl.Version -LibPath $localRepository
    }
    else {
      Write-Host "not supported yet" -ForegroundColor Yellow				
    }
    
    return $paths 
  }
}