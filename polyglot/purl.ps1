# Parse a PURL uri in the form of
# pkg:type[/namespace]/name[@version][?qualifiers][#subpath]
function ConvertFrom-PkgUri {
  param(
    [string]$uriString
  )  
 
  $uri = [uri]$uriString

  # Validate the URI starts with "pkg:"
  if ($uri.Scheme -ne "pkg" ) {
    throw "Invalid URI: Must start with 'pkg:'"
  }

  # Parse Path    
  $pathParts = ($uri.AbsolutePath -split '/').Count

  if ($pathParts -eq 2) {
    $type, $name = $uri.AbsolutePath -split '/', 2 
  }
  elseif ($pathParts -eq 3) {
    $type, $namespace, $name = $uri.AbsolutePath -split '/', 3 
  }
  else {
    throw "Invalid path!"
  }
  # will probably blow up if version is omitted
  $name, $version = $name -split '@', 2 
  #$versionParts = $uri.AbsolutePath.Split("@").Get(1)
  #$version = if ($versionParts.Count -gt 1) { $versionParts[1] } else { "" } 
  # parse Qualifiers 
  # Remove leading "?
  $queryString = $uri.Query.TrimStart('?')
  if ($queryString -ne "") {
    # Convert to hashtable
    $queryParams = @{}
    $queryString -split '&' | ForEach-Object {
      $key, $value = $_ -split '=', 2
      $queryParams[$key] = $value
    }
    
    # Display results
    #$queryParams.GetEnumerator() | ForEach-Object { Write-Output "$($_.Key) = $($_.Value)" }
  }
  #Download-Purl
  return [PSCustomObject]@{
    Type             = $type
    Namespace        = $namespace
    Name             = $name
    Version          = $version
    Qualifiers       = $queryString
    QualifiersParsed = $queryParams
    Subpath          = $uri.Fragment
  }
}
 