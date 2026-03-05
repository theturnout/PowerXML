# CycloneDX SBOM XML manipulation functions
# This module provides only the functionality requires by Polyglot Package Manager

<#
.SYNOPSIS
    Loads a CycloneDX SBOM XML file.
.PARAMETER Path
    Path to the CycloneDX SBOM XML file.
#>
function Get-SBOM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = Resolve-Path $Path -ErrorAction Stop
    [xml]$sbom = Get-Content -Path $resolvedPath -Raw

    if (-not (Test-SBOM $sbom)) {
        throw "Invalid CycloneDX SBOM file: $Path"
    }

    # Attach namespace manager for XPath queries
    $nsManager = New-Object System.Xml.XmlNamespaceManager($sbom.NameTable)
    $nsManager.AddNamespace("cdx", $sbom.DocumentElement.NamespaceURI)
    
    $sbom | Add-Member -NotePropertyName "NamespaceManager" -NotePropertyValue $nsManager -Force
    $sbom | Add-Member -NotePropertyName "CdxNamespace" -NotePropertyValue $sbom.DocumentElement.NamespaceURI -Force

    return $sbom
}

<#
.SYNOPSIS
    Saves a CycloneDX SBOM XML document to a file.
.PARAMETER Sbom
    The SBOM XmlDocument to save.
.PARAMETER Path
    The file path where the SBOM should be saved.
#>
function Save-SBOM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [xml]$Sbom,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "`t"
    $settings.Encoding = [System.Text.Encoding]::UTF8

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Sbom.Save($writer)
    }
    finally {
        $writer.Close()
    }
}

<#
.SYNOPSIS
    Adds a component to a CycloneDX SBOM.
.PARAMETER Sbom
    The SBOM XmlDocument.
.PARAMETER BomRef
    Unique identifier for the component within the BOM.
.PARAMETER Name
    Component name.
.PARAMETER Purl
    Package URL for the component.
.PARAMETER Type
    Component type. Defaults to "library".
.PARAMETER Hash
    SHA-256 hash of the component (optional).
.PARAMETER DistributionUrl
    Distribution URL for external reference (optional).
.PARAMETER DistributionHash
    SHA-256 hash for the distribution (optional, used with DistributionUrl).
#>
function Add-SBOMComponent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [xml]$Sbom,
        [Parameter(Mandatory = $true)]
        [string]$BomRef,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Purl,
        [ValidateSet("application", "library")]
        [string]$Type = "library",
        [string]$Hash,
        [string]$DistributionUrl,
        [string]$DistributionHash
    )

    $ns = $Sbom.CdxNamespace
    if (-not $ns) {
        $ns = $Sbom.DocumentElement.NamespaceURI
    }

    # Ensure components container exists
    $components = $Sbom.DocumentElement.SelectSingleNode("cdx:components", $Sbom.NamespaceManager)
    if (-not $components) {
        $components = $Sbom.CreateElement("components", $ns)
        $Sbom.DocumentElement.AppendChild($components) | Out-Null
    }

    # Check for duplicate bom-ref
    $existing = $components.SelectSingleNode("cdx:component[@bom-ref='$BomRef']", $Sbom.NamespaceManager)
    if ($existing) {
        Write-Warning "Component with bom-ref '$BomRef' already exists. Skipping."
        return $existing
    }

    # Create component element
    $component = $Sbom.CreateElement("component", $ns)
    $component.SetAttribute("type", $Type)
    $component.SetAttribute("bom-ref", $BomRef)

    # Add name
    $nameElement = $Sbom.CreateElement("name", $ns)
    $nameElement.InnerText = $Name
    $component.AppendChild($nameElement) | Out-Null

    # Add purl if provided
    if ($Purl) {
        $purlElement = $Sbom.CreateElement("purl", $ns)
        $purlElement.InnerText = $Purl
        $component.AppendChild($purlElement) | Out-Null
    }

    # Add external reference for distribution URL
    if ($DistributionUrl) {
        $extRefs = $Sbom.CreateElement("externalReferences", $ns)
        $ref = $Sbom.CreateElement("reference", $ns)
        $ref.SetAttribute("type", "distribution")
        
        $urlElement = $Sbom.CreateElement("url", $ns)
        $urlElement.InnerText = $DistributionUrl
        $ref.AppendChild($urlElement) | Out-Null
        
        # Add hash inside reference if provided
        if ($DistributionHash) {
            $hashesElement = $Sbom.CreateElement("hashes", $ns)
            $hashElement = $Sbom.CreateElement("hash", $ns)
            $hashElement.SetAttribute("alg", "SHA-256")
            $hashElement.InnerText = $DistributionHash
            $hashesElement.AppendChild($hashElement) | Out-Null
            $ref.AppendChild($hashesElement) | Out-Null
        }
        
        $extRefs.AppendChild($ref) | Out-Null
        $component.AppendChild($extRefs) | Out-Null
    }

    # Add component-level hash if provided
    if ($Hash) {
        $hashesElement = $Sbom.CreateElement("hashes", $ns)
        $hashElement = $Sbom.CreateElement("hash", $ns)
        $hashElement.SetAttribute("alg", "SHA-256")
        $hashElement.InnerText = $Hash
        $hashesElement.AppendChild($hashElement) | Out-Null
        $component.AppendChild($hashesElement) | Out-Null
    }

    $components.AppendChild($component) | Out-Null
    return $component
}

<#
.SYNOPSIS
    Adds a composition to a CycloneDX SBOM.
.PARAMETER Sbom
    The SBOM XmlDocument.
.PARAMETER BomRef
    Unique identifier for the composition.
.PARAMETER Dependencies
    Array of component bom-ref strings to include in the composition.
#>
function Add-SBOMComposition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [xml]$Sbom,
        [Parameter(Mandatory = $true)]
        [string]$BomRef,
        [Parameter(Mandatory = $true)]
        [string[]]$Dependencies
    )

    $ns = $Sbom.CdxNamespace
    if (-not $ns) {
        $ns = $Sbom.DocumentElement.NamespaceURI
    }

    # Ensure compositions container exists
    $compositions = $Sbom.DocumentElement.SelectSingleNode("cdx:compositions", $Sbom.NamespaceManager)
    if (-not $compositions) {
        $compositions = $Sbom.CreateElement("compositions", $ns)
        $Sbom.DocumentElement.AppendChild($compositions) | Out-Null
    }

    # Check for duplicate bom-ref
    $existing = $compositions.SelectSingleNode("cdx:composition[@bom-ref='$BomRef']", $Sbom.NamespaceManager)
    if ($existing) {
        Write-Warning "Composition with bom-ref '$BomRef' already exists. Skipping."
        return $existing
    }

    # Create composition element
    $composition = $Sbom.CreateElement("composition", $ns)
    $composition.SetAttribute("bom-ref", $BomRef)

    # Add aggregate (always "complete")
    $aggregateElement = $Sbom.CreateElement("aggregate", $ns)
    $aggregateElement.InnerText = "complete"
    $composition.AppendChild($aggregateElement) | Out-Null

    # Add dependencies
    $depsContainer = $Sbom.CreateElement("dependencies", $ns)
    foreach ($depRef in $Dependencies) {
        $dep = $Sbom.CreateElement("dependency", $ns)
        $dep.SetAttribute("ref", $depRef)
        $depsContainer.AppendChild($dep) | Out-Null
    }
    $composition.AppendChild($depsContainer) | Out-Null

    $compositions.AppendChild($composition) | Out-Null
    return $composition
}

<#
.SYNOPSIS
    Adds a dependency to an existing composition.
#>
function Add-SBOMCompositionDependency {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [xml]$Sbom,
        [Parameter(Mandatory = $true)]
        [string]$CompositionRef,
        [Parameter(Mandatory = $true)]
        [string]$DependencyRef
    )

    $ns = $Sbom.CdxNamespace
    if (-not $ns) {
        $ns = $Sbom.DocumentElement.NamespaceURI
    }

    $composition = $Sbom.DocumentElement.SelectSingleNode(
        "cdx:compositions/cdx:composition[@bom-ref='$CompositionRef']", 
        $Sbom.NamespaceManager
    )
    
    if (-not $composition) {
        throw "Composition '$CompositionRef' not found."
    }

    $depsContainer = $composition.SelectSingleNode("cdx:dependencies", $Sbom.NamespaceManager)
    if (-not $depsContainer) {
        $depsContainer = $Sbom.CreateElement("dependencies", $ns)
        $composition.AppendChild($depsContainer) | Out-Null
    }

    # Check if dependency already exists
    $existing = $depsContainer.SelectSingleNode("cdx:dependency[@ref='$DependencyRef']", $Sbom.NamespaceManager)
    if ($existing) {
        Write-Warning "Dependency '$DependencyRef' already exists in composition '$CompositionRef'."
        return $existing
    }

    $dep = $Sbom.CreateElement("dependency", $ns)
    $dep.SetAttribute("ref", $DependencyRef)
    $depsContainer.AppendChild($dep) | Out-Null
    return $dep
}
