function Test-SBOM {
    [CmdletBinding()]
    param (
        [xml]$sbom
    )

    if (-Not $sbom) {
        Write-Error "Invalid SBOM content."
        return $false
    }

    
    #check schema NS like "http://cyclonedx.org/schema/bom/1.X"
    if ($sbom.DocumentElement.NamespaceURI -notlike 'http://cyclonedx.org/schema/bom/1.?') {
        Write-Error "Invalid CycloneDX SBOM file: $FilePath"
        return $false
    }

    return $true
}