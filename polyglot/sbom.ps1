function Test-SBOM {
    [CmdletBinding()]
    param (
        [xml]$sbom,
        [switch]$ValidateSchema,
        [string]$SchemaPath
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

    if ($ValidateSchema) {
        if (-not $SchemaPath) {
            $SchemaPath = Join-Path $PSScriptRoot 'resources\cyclonedx\bom-1.5.xsd'
        }
        $resolvedXsd = Resolve-Path $SchemaPath -ErrorAction Stop

        $schemaSet = New-Object System.Xml.Schema.XmlSchemaSet
        # Add a minimal SPDX stub so the xs:import in the CycloneDX XSD is satisfied
        # without requiring network access.
        $spdxStub = '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" ' +
            'targetNamespace="http://cyclonedx.org/schema/spdx">' +
            '<xs:simpleType name="licenseId"><xs:restriction base="xs:string"/>' +
            '</xs:simpleType></xs:schema>'
        $spdxReader = [System.Xml.XmlReader]::Create(
            [System.IO.StringReader]::new($spdxStub))
        try { $schemaSet.Add('http://cyclonedx.org/schema/spdx', $spdxReader) | Out-Null } finally { $spdxReader.Close() }

        $xsdReader = [System.Xml.XmlReader]::Create([string]$resolvedXsd)
        try { $schemaSet.Add('http://cyclonedx.org/schema/bom/1.5', $xsdReader) | Out-Null } finally { $xsdReader.Close() }
        $schemaSet.Compile()

        $validationErrors = [System.Collections.Generic.List[string]]::new()
        $sbom.Schemas = $schemaSet
        $sbom.Validate({
            param($sender, $e)
            $validationErrors.Add($e.Message)
        })

        if ($validationErrors.Count -gt 0) {
            $errorList = $validationErrors -join "`n"
            throw "SBOM schema validation failed:`n$errorList"
        }
    }

    return $true
}
