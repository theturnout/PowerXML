. "$PSScriptRoot\xproc.ps1"
. "$PSScriptRoot\xslt.ps1"

<#
.PARAMETER InputObject
The input to resolve, which can be an XML object or a string containing XML content.
.PARAMETER Extension
The file extension to use for the temporary file if the input is XML content. Default is "xml". Only matters if the processor handles files of certain extensions differently.
.PARAMETER targetEncoding
The target encoding to use when writing the XML content to a temporary file. Default is "UTF8". Supported encodings include "UTF8", "UTF16", "UTF16LE", "UTF16BE", "ISO-8859-1", and "US-ASCII".
.NOTES
Any XML input will be rewritten to a temporary file with the given extension and encoding, and the path to that file will be returned. Non-XML input (e.g. a file path) will be returned as-is.
#>
function Resolve-XmlInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [string]$Extension = "xml",        
        [string]$targetEncoding = "UTF8"
    )
    $xmlTypes = @(
        'System.Xml.XmlDocument',
        'System.Xml.Linq.XDocument',
        'System.Xml.Linq.XElement',
        'System.Xml.XmlElement',
        'System.Xml.XmlNode'
    )
    $isXml = $false
    if ($null -ne $InputObject) {
        if ($InputObject -is [array]) {
            $resolvedArray = @()
            foreach ($item in $InputObject) {
                $resolvedArray += Resolve-XmlInput -InputObject $item `
                    -Extension $Extension `
                    -targetEncoding $targetEncoding
            }
            return $resolvedArray
        }
        if ($xmlTypes -contains $InputObject.GetType().FullName) {
            $isXml = $true
        }
        elseif ($InputObject -is [string]) {
            # try to parse the string as XML
            try {
                [xml]$tryXml = $InputObject
                if ($tryXml.DocumentElement -or $tryXml.Root) {
                    $isXml = $true
                }
            }
            catch {
                $isXml = $false
            }
        }
    }
    if ($isXml) {
        $tempFile = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".$Extension")
        $encoding = $targetEncoding.ToUpperInvariant()
        if ($InputObject -is [string]) {
            $xmlContent = $tryXml.OuterXml
        }
        elseif ($InputObject -is [System.Xml.Linq.XNode]) {
            # System.Xml.Linq types (XDocument, XElement) use ToString(),
            # and the declaration must be prepended for XDocument.
            if ($InputObject -is [System.Xml.Linq.XDocument] -and $InputObject.Declaration) {
                $xmlContent = $InputObject.Declaration.ToString() + "`n" + $InputObject.ToString()
            }
            else {
                $xmlContent = $InputObject.ToString()
            }
        }
        else {
            $xmlContent = $InputObject.OuterXml
        }
        Set-Content `
            -Path $tempFile `
            -Value $xmlContent `
            -Encoding $encoding
        return $tempFile
    }
    else {
        return $InputObject
    }
}
<#
.SYNOPSIS
Transforms inputs using XML technologies
.PARAMETER processing
The kind of processing to run. Default xproc.
.PARAMETER processor
The specific processor to use.
.PARAMETER PackageResolution
A hashtable that groups polyglot package manager settings for XProc processing:
  sbomPath            - Path to a CycloneDX SBOM XML file. Defaults to the bundled sbom.xml.
  targetComposition   - The composition in the SBOM to resolve. Defaults to the first composition.
  GetLatest           - When $true, resolves the latest version for supported package types
                        (codeberg, github) via their release API, replacing the SBOM-pinned version.
  AdditionalPackages  - A single purl string or array of purls to merge into the SBOM.
                        Matching components (same type/namespace/name) have their version replaced
                        and hashes removed. Non-matching purls are added as new components.
                        When no sbomPath is available, an interstitial SBOM is created from these.
  ValidateSbom        - When $true, runs XSD schema validation against the CycloneDX bom-1.5.xsd
                        schema when loading the SBOM. Throws on validation errors.
.PARAMETER inPort
A hashtable of ports bound to inputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER outPort
A hashtable of ports bound to outputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER catalog
The path to an XML catalog file to use for resolving XML resources.
.PARAMETER passthrough
An array of parameters passed directly to the processor.
.PARAMETER passthroughJava
An array of parameters passed directly to the Java JVM.
.PARAMETER MergeOutput
Merges the STDOUT and STDERR of the processor into a single stream. Default is true.
.PARAMETER Namespace
A hashtable of namespace prefixes and URIs to use when processing the pipeline, e.g.
#>
function Transform-Xml {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,        
        [ValidateSet("xproc", "xslt")]
        $processing = "xproc",
        [ValidateSet("xmlcalabash", "morganaxproc", "dotnet", "msxml", "altova", "xsltproc")]
        $processor = "xmlcalabash",
        [hashtable]$PackageResolution,
        [Parameter(Mandatory = $true)] 
        $pipeline,        
        [Alias("parameters")]
        [hashtable]$options,
        [hashtable]$inPort,
        [hashtable]$outPort,
        [string]$catalog,
        [array]$passthrough,
        [array]$passthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace,
        [string]$Configuration,
        [switch]$CollectOutput
    )
    
    $pipelinePath = Resolve-XmlInput -InputObject $pipeline -Extension "xpl"
    
    $inPortProcessed = $null
    if ($inPort) {
        $inPortProcessed = @{}
        foreach ($key in $inPort.Keys) {
            $val = $inPort[$key]
            $inPortProcessed[$key] = Resolve-XmlInput -InputObject $val -Extension "xml"
        }
    }
    if ($processing -eq "xproc") {
        $localRepository = Get-LocalRepositoryPath
        # Unpack PackageResolution settings with defaults
        $sbomPath = if ($PackageResolution -and $PackageResolution.sbomPath) { $PackageResolution.sbomPath } else { "$PSScriptRoot\sbom.xml" }
        $targetComposition = if ($PackageResolution) { $PackageResolution.targetComposition } else { $null }
        $getLatest = if ($PackageResolution) { [bool]$PackageResolution.GetLatest } else { $false }
        $additionalPackages = if ($PackageResolution -and $PackageResolution.AdditionalPackages) {
            @($PackageResolution.AdditionalPackages)
        }
        else { $null }
        $validateSbom = if ($PackageResolution) { [bool]$PackageResolution.ValidateSbom } else { $false }

        $compositionParams = @{
            sbomPath        = $sbomPath
            localRepository = $localRepository
        }
        if ($targetComposition) {
            $compositionParams.targetComposition = $targetComposition
        }
        if ($getLatest) {
            $compositionParams.GetLatest = $true
        }
        if ($additionalPackages) {
            $compositionParams.AdditionalPackages = $additionalPackages
        }
        if ($validateSbom) {
            $compositionParams.ValidateSbom = $true
        }
        [array]$paths = Copy-SoftwareComposition @compositionParams | Select-Object -Unique    
        if ($processor -eq "xmlcalabash") {
            return Invoke-XmlCalabash `
                -paths $paths `
                -InputObject $InputObject `
                -pipeline $pipelinePath `
                -options $options `
                -inPort $inPortProcessed `
                -outPort $outPort `
                -catalog $catalog `
                -passthrough $passthrough `
                -passthroughJava $passthroughJava `
                -MergeOutput $MergeOutput `
                -Namespace $Namespace `
                -CollectOutput:$CollectOutput
        }
        elseif ($processor -eq "morganaxproc") {
            return Invoke-MorganaXProc `
                -paths $paths `
                -InputObject $InputObject `
                -pipeline $pipelinePath `
                -options $options `
                -inPort $inPortProcessed `
                -outPort $outPort `
                -catalog $catalog `
                -passthrough $passthrough `
                -passthroughJava $passthroughJava `
                -MergeOutput $MergeOutput `
                -Namespace $Namespace `
                -Configuration $Configuration `
                -CollectOutput:$CollectOutput
        }
        else {
            throw "Unsupported processor $processor for processing type $processing"
        }
    }
    elseif ($processing -eq "xslt") {
        # For XSLT processing:
        # - pipeline parameter is the stylesheet
        # - inPort with 'source' key is the input XML
        # - outPort with 'result' key is the output file (optional)
        # - options are XSLT parameters
        
        $stylesheetPath = Resolve-XmlInput -InputObject $pipeline -Extension "xsl"
        
        # Get input XML from inPort 'source' key, or use first value
        $inputXmlPath = $null
        if ($inPortProcessed -and $inPortProcessed.Count -gt 0) {
            if ($inPortProcessed.ContainsKey('source')) {
                $inputXmlPath = $inPortProcessed['source']
            }
            else {
                $inputXmlPath = $inPortProcessed.Values | Select-Object -First 1
            }
        }
        
        if (-not $inputXmlPath) {
            throw "XSLT processing requires input XML. Use -inPort @{source = 'input.xml'}"
        }
        
        # Get output file from outPort 'result' key, or use first value
        $outputFilePath = $null
        if ($outPort -and $outPort.Count -gt 0) {
            if ($outPort.ContainsKey('result')) {
                $outputFilePath = $outPort['result']
            }
            else {
                $outputFilePath = $outPort.Values | Select-Object -First 1
            }
        }
        
        if ($processor -eq "dotnet") {
            return Invoke-DotNetXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $options
        }
        elseif ($processor -eq "msxml") {
            return Invoke-MsxmlXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $options
        }
        elseif ($processor -eq "xsltproc") {
            return Invoke-XsltprocXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $options
        }
        elseif ($processor -eq "altova") {
            return Invoke-AltovaXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $options
        }
        else {
            throw "Unsupported processor '$processor' for processing type 'xslt'. Supported processors: dotnet, msxml, xsltproc, altova"
        }
    }
    else {
        throw "Unsupported processing type '$processing'. Supported types: xproc, xslt"
    }
    # Clean up temp file if created
    #  if ($null -ne $tempPipelineFile -and (Test-Path $tempPipelineFile)) {
    #      Remove-Item -Path $tempPipelineFile -Force -ErrorAction SilentlyContinue
    #  }
}
