<#
.PARAMETER InputObject
The input to resolve, which can be an XML object or a string containing XML content.
.PARAMETER Extension
The file extension to use for the temporary file if the input is XML content. Default is "xml".
.PARAMETER targetEncoding
The target encoding to use when writing the XML content to a temporary file. Default is "utf-8". Supported encodings include "utf-8", "utf-16", "utf-16LE", "utf-16BE", "iso-8859-1", and "us-ascii".
.NOTES
Any XML input will be rewritten to a temporary file with the given extension and encoding, and the path to that file will be returned. Non-XML input (e.g. a file path) will be returned as-is.
#>
function Resolve-XmlInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [string]$Extension = "xml",
        [ValidationSet("utf-8", "utf-16", "utf-16LE", "utf-16BE", "iso-8859-1", "us-ascii")]        
        [string]$targetEncoding = "utf-8"
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
        if ($xmlTypes -contains $InputObject.GetType().FullName) {
            $isXml = $true
        }
        elseif ($InputObject -is [string]) {
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
        if ($InputObject -is [string]) {            
            if ($targetEncoding) {
                [System.IO.File]::WriteAllText($tempFile, $tryXml.OuterXml, [System.Text.Encoding]::GetEncoding($targetEncoding))
            }
            else {
                # Default to UTF-8 without BOM                 
                [System.IO.File]::WriteAllText($tempFile, $tryXml.OuterXml)
            }            
        }
        else {
            $InputObject.OuterXml | Set-Content -Path $tempFile -Encoding UTF8
        }
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
.PARAMETER inPipe
Whether to use the STDIN to pass data to the pipeline's default port.
.PARAMETER inPort
A hashtable of ports bound to inputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER inPort
A hashtable of ports bound to outputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER passthrough
An array of parameters passed directly to the processor.
.PARAMETER passthroughJava
An array of parameters passed directly to the Java JVM.
#>
function Transform-Xml {
    [CmdletBinding()]
    param(
        $processing = "xproc",
        $processor = "xmlcalabash",
        $targetComposition = "pester-tests",
        [switch]$inPipe,
        [Parameter(Mandatory = $true)] 
        $pipeline,        
        [hashtable]$options,
        [hashtable]$inPort,
        [hashtable]$outPort,
        [string]$catalog,
        [array]$passthrough,
        [array]$passthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace
    )
    Import-Module "$PSScriptRoot/polyglot" -Force
    $localRepository = Get-LocalRepositoryPath
    #process bundle
    [array]$paths = Copy-SoftwareComposition `
        -sbomPath "$PSScriptRoot\sbom.xml" `
        -targetComposition $targetComposition `
        -localRepository $localRepository | Select-Object -Unique    

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
        if ($processor -eq "xmlcalabash") {
            return Invoke-XmlCalabash `
                -paths $paths `
                -inPipe:$inPipe `
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
                -inPipe:$inPipe `
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
    # Clean up temp file if created
    #  if ($null -ne $tempPipelineFile -and (Test-Path $tempPipelineFile)) {
    #      Remove-Item -Path $tempPipelineFile -Force -ErrorAction SilentlyContinue
    #  }
}
function Invoke-XmlCalabash {
    [CmdletBinding()]
    param(
        [array]$paths,        
        [switch]$inPipe,
        [Parameter(Mandatory = $true)] 
        $pipeline,        
        [hashtable]$options,
        [hashtable]$inPort,
        [hashtable]$outPort,
        [string]$catalog,
        [array]$passthrough,
        [array]$passthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace
    )
    # look for the xmlcalabash path
    $processorPath = $paths | Where-Object {
        $_ -like "*xmlcalabash*"
    }
    if ( -not $processorPath) {
        throw "Could not find xmlcalabash processor in software composition paths"
    }    

    #construct classpath
    $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
    $cp = "$processorPath/*$cpDelimiter"

    $cp += Get-PXClassPath -paths $paths -shortenClassPath

    #    Get-ChildItem "$processorPath\lib" -Filter *.jar |
    #        ForEach-Object {
    #            $cp = "$cp$cpDelimiter$_"
    #        }
    #
    #    Get-ChildItem "$processorPath\extra" -Filter *.jar |
    #        ForEach-Object {
    #            $cp = "$cp$cpDelimiter$_"
    #        }
    $cp = "$cp$cpDelimiter$processorPath/lib/*$cpDelimiter$processorPath/extra/*"
    Write-Verbose "ClassPath: $cp"
    $xcArgs = @()
    # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
    if ($inPort) {
        $xcInput = @()
        foreach ($enum in $inPort.GetEnumerator()) {
            $xcInput += ("--input:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcInput
    }
    if ($outPort) {
        $xcOutput = @()
        foreach ($enum in $outPort.GetEnumerator()) {
            $xcOutput += ("--output:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcOutput
    }

    if ($catalog) {
        $xcArgs += @("--catalog:`"$catalog`"")
    }

    #handle STDIN
    if ($inPipe) {
        $xcArgs += @("--pipe")
    }

    if ($passthrough) {
        $xcArgs += $passthrough
    }
        
    if ($options) {
        $xcOptions = @()
        foreach ($enum in $options.GetEnumerator()) {
            $xcOptions += ("$($enum.Key)=$($enum.Value)")
        }
        $xcArgs += $xcOptions
    }
    if ($Namespace) {
        $nsArgs = @()
        foreach ($enum in $Namespace.GetEnumerator()) {
            $nsArgs += ("--namespace:$($enum.Key)=$($enum.Value)")
        }
        $xcArgs += $nsArgs
    }

    # Handle CmdLet params
    # Calabash has trace, warn, error, if you want to use them, use passthrough
    if ($Verbose) {
        $xcArgs += @("--verbosity:info")
        $xcArgs += @("--explain")
    }
    elseif ($Debug) {
        $xcArgs += @("--verbosity:debug")
        $xcArgs += @("--explain")
    }

    
    # create configuration file
    # Define the XML content as a here-string
    $xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<cc:xml-calabash xmlns:cc="https://xmlcalabash.com/ns/configuration" version="1.0">
    <cc:mimetype content-type="text/plain" extensions="ixml pdf inp" />
</cc:xml-calabash>
"@
    
    # Create a temporary file with .xml extension
    $tempFile = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".xml")
    
    # Write the XML content to the temporary file using UTF-8 encoding
    $null = [System.IO.File]::WriteAllText($tempFile, $xmlContent, [System.Text.Encoding]::UTF8)
    
    if ($tempFile) {
        $xcArgs += @("--configuration:`"$tempFile`"")
    }
        
    $xcArgs += @($pipeline)
    # see https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5#passing-arguments-that-contain-quote-characters
    $PSNativeCommandArgumentPassing = 'Legacy'
    #Write-Verbose "args to processor is $xcArgs"

    [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

    if ($MergeOutput) {
        $output = & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
    }
    else {
        $output = & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs
    }
    return $output
} 


function Invoke-MorganaXProc {
    [CmdletBinding()]
    param(
        [array]$paths,        
        [switch]$inPipe,
        [Parameter(Mandatory = $true)] 
        $pipeline,        
        [hashtable]$options,
        [hashtable]$inPort,
        [hashtable]$outPort,
        [string]$catalog,
        [array]$passthrough,
        [array]$passthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace
    )
    $processorPath = (Join-Path $localRepository "MorganaXProc-IIIse-1.8")
        
    #construct classpath
    $cp = "$processorPath/MorganaXProc-IIIse.jar"

    $cp += Get-PXClassPath -paths $paths

    $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
    Get-ChildItem "$processorPath\MorganaXProc-IIIse_lib" -Filter *.jar |
        ForEach-Object {
            $cp = "$cp$cpDelimiter$_"
        }
        
    # Write-Verbose "ClassPath: $cp"
    $xcArgs = @()
    $xcArgs += @($pipeline)
    # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
    if ($inPort) {
        $xcInput = @()
        foreach ($enum in $inPort.GetEnumerator()) {
            $xcInput += ("-input:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcInput
    }
    if ($outPort) {
        $xcOutput = @()
        foreach ($enum in $outPort.GetEnumerator()) {
            $xcOutput += ("-output:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcOutput
    }

    if ($catalog) {
        $xcArgs += @("--catalog:`"$catalog`"")
    }

    #handle STDIN
    if ($inPipe) {
        $xcArgs += @("--pipe")
    }

    if ($passthrough) {
        $xcArgs += $passthrough
    }
        
    if ($options) {
        $xcOptions = @()
        foreach ($enum in $options.GetEnumerator()) {
            $xcOptions += ("-option:$($enum.Key)=$($enum.Value)")
        }
        $xcArgs += $xcOptions
    }
    if ($Namespace) {
        $nsArgs = @()
        foreach ($enum in $Namespace.GetEnumerator()) {
            $nsArgs += ("-namespace:$($enum.Key)=$($enum.Value)")
        }
        $xcArgs += $nsArgs
    }

    # Handle CmdLet params
    # Calabash has trace, warn, error, if you want to use them, use passthrough
    if ($Verbose) {
        $xcArgs += @("-debug")        
    }
    elseif ($Debug) {
        $xcArgs += @("-debug")
    }

    #TODO parameterize
    $xcArgs += @("-silent")

    # see https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5#passing-arguments-that-contain-quote-characters
    $PSNativeCommandArgumentPassing = 'Legacy'
    #Write-Verbose "args to processor is $xcArgs"

    # try to force UTF-8
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    #Write-Host "Invoking java -cp $cp com.xml_project.morganaxproc3.XProcEngine $xcArgs"
    if ($MergeOutput) {
        $output = & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs 2>&1
    }
    else {
        $output = & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs
    }
    Write-Host $output
    return $output
} 

function Get-PXClassPath {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [array]$paths,
        [switch]$shortenClassPath
    ) 
    $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
    Write-Host $paths
    $cp = @()
    if ($shortenClassPath) {
        $cp = "$($paths -join $cpDelimiter)"
        return $cp
    }
    else {
        $paths | ForEach-Object {
            Get-ChildItem "$_" -Filter *.jar |
                ForEach-Object {
                    Write-Host "Adding $($_.FullName) to classpath"
                    $cp = "$cp$cpDelimiter$_"
                }
            }
            return $cp
        }
    }

    function New-Bundle {
        [CmdletBinding()]
        param(        
            $targetComposition = "oscal",
            $bundleName
        )
    
        $localRepository = Get-LocalRepositoryPath
        #process bundle
        Import-Module "$PSScriptRoot/polyglot" -Force
        [array]$paths = Copy-SoftwareComposition `
            -sbomPath "$PSScriptRoot\sbom.xml" `
            -targetComposition $targetComposition `
            -localRepository $localRepository | Select-Object -Unique    

        $bundlePath = Join-Path $localRepository "bundles"        
        New-Item -Path $bundlePath -Name $bundleName -ItemType Directory -Force | Out-Null

        $paths | ForEach-Object {      
            Write-Host "Copying software composition from $($_) to $bundlePath"                  
            Copy-Item -Path "$($_)\*.jar" -Destination $bundlePath -Force -Recurse
        }
    }
