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
    #$queryParams.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key) = $($_.Value)" }
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

<#
.SYNOPSIS
    Rewrites the version in a Package URL string.
.PARAMETER PurlString
    The original purl URI string.
.PARAMETER OldVersion
    The version to replace.
.PARAMETER NewVersion
    The new version to substitute.
.OUTPUTS
    The modified purl string with version replaced in both the @version segment
    and qualifier values (e.g., filename). Uses boundary-safe matching to avoid
    replacing partial versions (e.g. "1.0" inside "1.0.1").
#>
function Set-PurlVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PurlString,
        [Parameter(Mandatory = $true)]
        [string]$OldVersion,
        [Parameter(Mandatory = $true)]
        [string]$NewVersion
    )

    $escaped = [regex]::Escape($OldVersion)
    # Replace the @version segment (between @ and the next ? # or end-of-string)
    $result = $PurlString -replace "(?<=@)${escaped}(?=[?#]|$)", $NewVersion
    # Replace version in qualifier values (e.g. filename=name-VERSION.ext)
    # Boundary: preceded by non-alphanumeric, followed by .non-digit, non-version-char, or end
    $result = $result -replace "(?<=[^a-zA-Z0-9])${escaped}(?=\.[^0-9]|[^0-9.]|$)", $NewVersion
    return $result
}
