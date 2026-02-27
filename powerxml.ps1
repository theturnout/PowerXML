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
# Probably should all be starting UpperCase
<#
.SYNOPSIS
Transforms inputs using XML technologies
.PARAMETER processing
The kind of processing to run. Default xproc.
.PARAMETER processor
The specific processor to use.
.PARAMETER targetComposition
The target composition in the SBOM to use to determine which packages are required to run the code.
.PARAMETER inPort
A hashtable of ports bound to inputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER inPort
A hashtable of ports bound to outputs, e.g. @{input1='file1.xml', input2='file2.xml}
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
        [ValidateSet("xmlcalabash", "morganaxproc", "dotnet", "msxml", "altova")]
        $processor = "xmlcalabash",
        $targetComposition = "pester-tests",
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
        [hashtable]$Namespace
    )
    
    $isPipelineInput = $MyInvocation.ExpectingInput
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
        #process bundle
        [array]$paths = Copy-SoftwareComposition `
            -sbomPath "$PSScriptRoot\sbom.xml" `
            -targetComposition $targetComposition `
            -localRepository $localRepository | Select-Object -Unique    
        if ($processor -eq "xmlcalabash") {
            return Invoke-XmlCalabash `
                -paths $paths `
                -PipeInput $isPipelineInput `
                -InputObject $InputObject `
                -pipeline $pipelinePath `
                -options $options `
                -inPort $inPortProcessed `
                -outPort $outPort `
                -catalog $catalog `
                -passthrough $passthrough `
                -passthroughJava $passthroughJava `
                -MergeOutput $MergeOutput `
                -Namespace $Namespace
        }
        elseif ($processor -eq "morganaxproc") {
            return Invoke-MorganaXProc `
                -paths $paths `
                -PipeInput $isPipelineInput `
                -InputObject $InputObject `
                -pipeline $pipelinePath `
                -options $options `
                -inPort $inPortProcessed `
                -outPort $outPort `
                -catalog $catalog `
                -passthrough $passthrough `
                -passthroughJava $passthroughJava `
                -MergeOutput $MergeOutput `
                -Namespace $Namespace
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
