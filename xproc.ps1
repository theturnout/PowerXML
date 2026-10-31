<#
.PARAMETER StdOut
The standard output from the processor, which may contain one or more XML documents, either as a single document, a sequence of documents separated by XmlCalabash-style headers and trailers, or as multipart MIME output.
.NOTES
If multiple documents are encountered without mime/type, they are assumed to be XML.
.OUTPUTS
One or more documents in their native type as possible. See `ConvertTo-PXNativeType` for details on how MIME parts are converted to native types.
#>
function Get-PXMultiXmlDocuments {
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]$StdOut
    )
    
    $headerPattern = '^=== result :: \d+ :: .+?={10,}\r?\n'
    $trailerPattern = '^={72,}\r?\n?'
    $firstLine = ($StdOut -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 1)

    $output = if ($firstLine -match '^--(.+)') {
        # Multipart MIME output
        $boundary = $matches[1] -replace '--$', ''
        $parts = Parse-PXMimeMultipart -MimeString $StdOut -Boundary $boundary
        foreach ($part in $parts) {
            ConvertTo-PXNativeType -MimePart $part
        }
    }
    elseif ([regex]::IsMatch($StdOut, $headerPattern, 'Multiline')) {
        # XmlCalabash standard out
        $docs = [regex]::Split($StdOut, $headerPattern, 'Multiline') | Where-Object { $_.Trim() }
        foreach ($doc in $docs) {
            $clean = [regex]::Replace($doc, $trailerPattern, '', 'Multiline')
            $mimePart = @{ Headers = @{ 'Content-Type' = 'application/xml' }; Content = $clean.Trim() }
            ConvertTo-PXNativeType -MimePart $mimePart
        }
    }
    elseif (([regex]::Matches($StdOut, '<\?xml')).Count -gt 1) {
        # Multiple concatenated XML documents (e.g. MorganaXProc stdout for sequences)
        $parts = [regex]::Split($StdOut.Trim(), '(?=<\?xml)') | Where-Object { $_.Trim() }
        foreach ($part in $parts) {
            $mimePart = @{ Headers = @{ 'Content-Type' = 'application/xml' }; Content = $part.Trim() }
            ConvertTo-PXNativeType -MimePart $mimePart
        }
    }
    else {
        # Single document
        , ($StdOut)
    }

    return $output
}
<#
.SYNOPSIS
Converts a configuration hashtable to an engine XML configuration file.
.DESCRIPTION
Builds an XML configuration (1-1 with the JSON shape of the hashtable) and writes it
to a temporary file: hashtable keys become element names, string values become
element text, arrays repeat the element, nested hashtables nest elements, and
'@'-prefixed keys become attributes. Returns the path to the generated file; the
caller is responsible for removing it after use.
.PARAMETER Config
The configuration hashtable.
.PARAMETER Root
The root element name.
.PARAMETER Namespace
The default namespace of the root element.
.OUTPUTS
The path to the generated configuration file.
#>
function ConvertTo-PXXmlConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )

    function Escape-XmlText {
        param($Value)
        if ($null -eq $Value) { return "" }
        return [System.Security.SecurityElement]::Escape([string]$Value)
    }

    function Convert-ConfigNode {
        param($Name, $Value, $Depth)
        $indent = "    " * $Depth
        if ($Value -is [array]) {
            foreach ($item in $Value) {
                Convert-ConfigNode -Name $Name -Value $item -Depth $Depth
            }
            return
        }
        if ($Value -is [hashtable]) {
            $attributes = ""
            $childLines = @()
            foreach ($key in ($Value.Keys | Sort-Object)) {
                if ($key -like "@*") {
                    $attrName = $key.TrimStart("@")
                    $attributes += " $attrName=`"$(Escape-XmlText $Value[$key])`""
                }
                else {
                    $childLines += Convert-ConfigNode -Name $key -Value $Value[$key] -Depth ($Depth + 1)
                }
            }
            if ($childLines.Count -eq 0) {
                return "$indent<$Name$attributes/>"
            }
            return (@("$indent<$Name$attributes>") + $childLines + "$indent</$Name>") -join "`n"
        }
        return "$indent<$Name>$(Escape-XmlText $Value)</$Name>"
    }

    $lines = @(
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<$Root xmlns=`"$Namespace`">"
    )
    foreach ($key in ($Config.Keys | Sort-Object)) {
        if ($key -like '@*') {
            $attrName = $key.TrimStart('@')
            $lines[1] = $lines[1].Substring(0, $lines[1].Length - 1) + " $attrName=`"$(Escape-XmlText $Config[$key])`">"
        }
        else {
            $lines += Convert-ConfigNode -Name $key -Value $Config[$key] -Depth 1
        }
    }
    $lines += "</$Root>"

    $configPath = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".xml")
    Set-Content -Path $configPath -Value ($lines -join "`n") -Encoding UTF8
    return $configPath
}

<#
.SYNOPSIS
Builds the auto-detected MorganaXProc configuration defaults.
.DESCRIPTION
Scans the composition paths for the Saxon jar and maps its version to the matching
XSLT/XQuery connector (Saxon 12.3+ needs Saxon12-3; earlier 12.x uses Saxon12, and
so on). The NineML and MarkupBlitz invisible-XML connectors are registered as well;
Morgana initializes connectors lazily, so entries are harmless when the jars are
not on the classpath.
.PARAMETER Paths
The software composition paths (directories scanned recursively for Saxon jars).
.OUTPUTS
A configuration hashtable suitable for ConvertTo-PXXmlConfig.
#>
function Get-PXMorganaAutoConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Paths
    )
    $config = @{}

    $saxonJar = $Paths | ForEach-Object {
        Get-ChildItem -Path $_ -Filter "Saxon*.jar" -File -Recurse -ErrorAction SilentlyContinue
    } | Select-Object -First 1
    if ($saxonJar -and $saxonJar.Name -match "Saxon[^\d]*(\d+)\.(\d+)") {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $connector = if ($major -gt 12 -or ($major -eq 12 -and $minor -ge 3)) { "Saxon12-3" }
        elseif ($major -eq 12) { "Saxon12" }
        elseif ($major -eq 11) { "Saxon11" }
        elseif ($major -eq 10) { "Saxon10" }
        else { $null }
        if ($connector) {
            $config["xslt-connector"] = $connector
            $config["xquery-connector"] = $connector
        }
    }

    # Morgana initializes connectors lazily; harmless when the jars are absent
    $config["ixml-connector"] = @(
        "com.xml_project.morganaxproc3.ninemlConnector.NineMLConnector",
        "com.xml_project.morganaxproc3.markupblitzConnector.MarkupBlitzConnector"
    )

    return $config
}
<#
.SYNOPSIS
Synthesizes an XProc wrapper pipeline that runs a single step.
.DESCRIPTION
Generates a p:declare-step shell for processors without a direct step-run CLI
(e.g. MorganaXProc). One input/output port is declared per bound port,
non-primary inputs are wired explicitly with p:pipe, and primary connections
flow implicitly. Returns the path to a temporary .xpl file; the caller is
responsible for removing it after use.
.PARAMETER Step
The step QName, e.g. "p:xslt". The prefix must be "p" or resolve through Namespaces.
.PARAMETER Namespaces
Effective prefix-to-URI namespace map (registry merged with the -Namespace parameter).
.PARAMETER InPort
Resolved input port bindings (port name to value).
.PARAMETER OutPort
Output port bindings (port name to path). When empty, a conventional primary result port is declared.
.PARAMETER Options
Option bindings declared on the wrapper and forwarded to the wrapped step.
.OUTPUTS
The path to the generated temporary pipeline file.
#>
function New-PXStepShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [hashtable]$Namespaces,
        [hashtable]$InPort,
        [hashtable]$OutPort,
        [hashtable]$Options
    )
    $xprocNamespace = "http://www.w3.org/ns/xproc"
    $stepPrefix, $stepLocal = $Step -split ":", 2
    if (-not $stepLocal) {
        $stepPrefix = "p"
        $stepLocal = $Step
    }
    if ($stepPrefix -eq "p") {
        $prefixUri = $xprocNamespace
    }
    elseif ($Namespaces -and $Namespaces.ContainsKey($stepPrefix)) {
        $prefixUri = $Namespaces[$stepPrefix]
    }
    else {
      throw "Step namespace prefix '$stepPrefix' is not bound. Register it with Register-PXNamespace or pass -Namespace."
    }

    # One declared input port per bound input; "source" becomes the primary port
    $inputLines = @()
    $pipedInputNames = @()
    if ($InPort -and $InPort.Count -gt 0) {
        foreach ($portName in @($InPort.Keys)) {
            if ($portName -eq "source") {
                $inputLines += "    <p:input port=`"source`" primary=`"true`" sequence=`"true`"/>"
            }
            else {
                $inputLines += "    <p:input port=`"$portName`" sequence=`"true`"/>"
                $pipedInputNames += $portName
            }
        }
    }

    # One declared output port per bound output (conventional "result" when none); "result" is primary.
    # Non-primary outputs connect explicitly to the same-named port on the wrapped step.
    $outputKeys = if ($OutPort -and $OutPort.Count -gt 0) { @($OutPort.Keys) } else { @("result") }
    $outputLines = @()
    foreach ($portName in $outputKeys) {
        if ($portName -eq "result") {
            $outputLines += "    <p:output port=`"result`" primary=`"true`" sequence=`"true`"/>"
        }
        else {
            $outputLines += "    <p:output port=`"$portName`" sequence=`"true`">"
            $outputLines += "        <p:pipe step=`"wrapped-step`" port=`"$portName`"/>"
            $outputLines += "    </p:output>"
        }
    }

    $optionLines = @()
    $withOptionLines = @()
    if ($Options) {
        foreach ($optionName in $Options.Keys) {
            $escapedName = [System.Security.SecurityElement]::Escape([string]$optionName)
            $optionLines += "    <p:option name=`"$escapedName`" required=`"true`"/>"
            $withOptionLines += "        <p:with-option name=`"$escapedName`" select=`"`$$escapedName`"/>"
        }
    }

    # Explicit wiring for the non-primary inputs; the primary input and output connect implicitly
    $stepLines = @("    <$stepPrefix`:$stepLocal name=`"wrapped-step`">")
    foreach ($portName in $pipedInputNames) {
        $stepLines += "        <p:with-input port=`"$portName`">"
        $stepLines += "            <p:pipe step=`"pipeline`" port=`"$portName`"/>"
        $stepLines += "        </p:with-input>"
    }
    $stepLines += $withOptionLines
    $stepLines += "    </$stepPrefix`:$stepLocal>"

    $namespaceDecl = if ($stepPrefix -eq "p") { "" } else { " xmlns:$stepPrefix=`"$prefixUri`"" }
    if ($Options -and $Namespaces) {
        foreach ($prefix in $Namespaces.Keys) {
            if ($prefix -ne "p" -and $prefix -ne $stepPrefix) {
                $uri = [System.Security.SecurityElement]::Escape([string]$Namespaces[$prefix])
                $namespaceDecl += " xmlns:$prefix=`"$uri`""
            }
        }
    }
    $shellLines = @(
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<p:declare-step xmlns:p=`"$xprocNamespace`"$namespaceDecl name=`"pipeline`" version=`"3.0`">"
    )
    $shellLines += $inputLines
    $shellLines += $outputLines
    $shellLines += $optionLines
    $shellLines += $stepLines
    $shellLines += "</p:declare-step>"

    $shellPath = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".xpl")
    Set-Content -Path $shellPath -Value ($shellLines -join "`n") -Encoding UTF8
    return $shellPath
}
<#
.SYNOPSIS
Invokes the XmlCalabash processor with the specified parameters.
.PARAMETER Paths
An array of paths to search for the XmlCalabash processor and its dependencies.
.PARAMETER Step
When specified, runs this step directly (run --step:QName) instead of the pipeline.
#> 
function Invoke-XmlCalabash {
    [CmdletBinding()]
    param(
        [array]$Paths,        
        $InputObject,
        [string]$Step,
        $Pipeline,        
        [string]$ClassPath,
        [hashtable]$Options,
        [hashtable]$InPort,
        [hashtable]$OutPort,
        [string]$Catalog,
        [array]$Passthrough,
        [array]$PassthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace,
        [switch]$CollectOutput,
        $Configuration
    )
    if ($ClassPath) {
        # The caller owns the classpath entirely; no processor discovery (#8)
        $cp = $ClassPath
    }
    else {
        # look for the xmlcalabash path
        $processorPath = $Paths | Where-Object {
            $_ -like "*xmlcalabash*"        
        } | Select-Object -First 1
        if ( -not $processorPath) {
            throw "Could not find xmlcalabash processor in software composition paths"
        }
        if (-not (Test-Path $processorPath -PathType Container)) {
            throw "XmlCalabash processor directory not found at '$processorPath'. The package cache may be corrupt - delete it and re-run."
        }

        #construct classpath
        $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
        $cp = "$processorPath/*$cpDelimiter"

        $cp += Get-PXClassPath -Paths $Paths -ShortenClassPath
        $cp = "$cp$cpDelimiter$processorPath/lib/*$cpDelimiter$processorPath/extra/*"
    }

    #    Get-ChildItem "$processorPath\lib" -Filter *.jar |
    #        ForEach-Object {
    #            $cp = "$cp$cpDelimiter$_"
    #        }
    #
    #    Get-ChildItem "$processorPath\extra" -Filter *.jar |
    #        ForEach-Object {
    #            $cp = "$cp$cpDelimiter$_"
    #        }
    Write-Verbose "ClassPath: $cp"
    $xcArgs = @()
    # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
    if ($InPort) {
        $xcInput = @()
        foreach ($enum in $InPort.GetEnumerator()) {
            $portName = $enum.Key
            $portVal = $enum.Value
            if ($portVal -is [array]) {
                foreach ($uri in $portVal) {
                    $xcInput += ("--input:$portName=`"$uri`"")
                }
            }
            else {
                $xcInput += ("--input:$portName=`"$portVal`"")
            }
        }
        $xcArgs += $xcInput
    }
    if ($OutPort) {
        $xcOutput = @()
        foreach ($enum in $OutPort.GetEnumerator()) {
            $xcOutput += ("--output:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcOutput
    }
    # else {
    #     $mimeOut = New-TemporaryFile
    #     $xcArgs += ("--output-multiplex:$($mimeOut.FullName)")
    # }

    if ($Catalog) {
        $xcArgs += @("--catalog:`"$Catalog`"")
    }

    #handle STDIN
    if ($InputObject) {
        $xcArgs += @("--pipe")
    }

    if ($Passthrough) {
        $xcArgs += $Passthrough
    }
        
    if ($Options) {
        $xcOptions = @()
        foreach ($enum in $Options.GetEnumerator()) {
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

    
    $configArg = $null
    if ($Configuration -is [string] -and $Configuration) {
        $configArg = $Configuration
    }
    elseif ($Configuration -is [hashtable] -or -not $ClassPath) {
        $effectiveConfig = @{ '@version' = '1.0' }
        if (-not $ClassPath) {
            $effectiveConfig.mimetype = @{ '@content-type' = 'text/plain'; '@extensions' = 'ixml pdf inp' }
        }
        if ($Configuration -is [hashtable]) {
            foreach ($key in $Configuration.Keys) {
                $effectiveConfig[$key] = $Configuration[$key]
            }
        }
        $configArg = ConvertTo-PXXmlConfig -Config $effectiveConfig `
            -Root "xml-calabash" `
            -Namespace "https://xmlcalabash.com/ns/configuration"
    }
    if ($configArg) {
        $xcArgs += @("--configuration:`"$configArg`"")
    }

    if ($Step) {
        # Direct step execution: the run command prefix is required for --step
        $xcArgs += @("run")
        $xcArgs += @("--step:$Step")
    }
    elseif ($Pipeline) {
        $xcArgs += @($Pipeline)
    }
    else {
        throw "Invoke-XmlCalabash requires either -Pipeline or -Step."
    }
    # see https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5#passing-arguments-that-contain-quote-characters
    $PSNativeCommandArgumentPassing = 'Legacy'
    Write-Debug "args to processor is $xcArgs"
    Write-Debug "Classpath: $cp"
    [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

    $stdinString = $null
    if ($null -ne $InputObject) {
        $stdinString = if ($InputObject -is [string]) { $InputObject } else { $InputObject.OuterXml }
    }

    if ($null -ne $stdinString) {
        if ($MergeOutput) {
            $output = $stdinString | & java -cp "$cp" @PassthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
        }
        else {
            $output = $stdinString | & java -cp "$cp" @PassthroughJava com.xmlcalabash.app.Main @xcArgs
        }
    }
    else {
        # this will break if someone is missing an inport and the processor 
        # tried to bind it to stdin
        if ($MergeOutput) {
            $output = $null | & java -cp "$cp" @PassthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
        }
        else {
            $output = $null | & java -cp "$cp" @PassthroughJava com.xmlcalabash.app.Main @xcArgs
        }
    }

    # Surface processor failures: a non-zero exit code means the run failed (#29)
    if ($LASTEXITCODE -ne 0) {
        $failureText = if ($output -is [array]) { $output -join "`n" } else { [string]$output }
        throw "XML Calabash failed with exit code $LASTEXITCODE`:$failureText"
    }

    $stdoutResult = if ($output -is [array]) {
        $output -join "`n" | Get-PXMultiXmlDocuments
    }
    else {
        $output | Get-PXMultiXmlDocuments
    }

    if ($CollectOutput -and $OutPort -and $OutPort.Count -gt 0) {
        $collectedFromFiles = @()
        foreach ($enum in $OutPort.GetEnumerator()) {
            $filePath = $enum.Value
            if (Test-Path $filePath) {
                $fileContent = Get-Content -Path $filePath -Raw
                $collectedFromFiles += @($fileContent | Get-PXMultiXmlDocuments)
            }
        }
        $combined = @()
        if ($stdoutResult) { $combined += @($stdoutResult) }
        if ($collectedFromFiles) { $combined += @($collectedFromFiles) }
        return $combined
    }

    return $stdoutResult
} 


function Invoke-MorganaXProc {
    [CmdletBinding()]
    param(
        [array]$Paths,                
        $InputObject,
        [Parameter(Mandatory = $true)] 
        $Pipeline,        
        [hashtable]$Options,
        [hashtable]$InPort,
        [hashtable]$OutPort,
        [string]$Catalog,
        [array]$Passthrough,
        [array]$PassthroughJava,
        [bool]$MergeOutput = $true,
    [hashtable]$Namespace,
    $Configuration,
    [string]$ClassPath,
    [switch]$CollectOutput
    )
    #$processorPath = (Join-Path $localRepository "MorganaXProc-IIIse-1.8.2")
        
    if ($ClassPath) {
        # The caller owns the classpath entirely; no processor discovery (#8)
        $cp = $ClassPath
    }
    else {
        # look for the MorganaXProc path
        $processorPath = $Paths | Where-Object {
            $_ -like "*MorganaXProc-IIIse*"
        } | Select-Object -First 1
        if ( -not $processorPath) {
            throw "Could not find MorganaXProc processor in software composition paths"
        }
        #construct classpath
        $morganaJar = Join-Path $processorPath "MorganaXProc-IIIse.jar"
        if (-not (Test-Path $morganaJar -PathType Leaf)) {
            throw "MorganaXProc-IIIse.jar not found at '$processorPath'. The package cache may be corrupt - delete '$processorPath' and re-run."
        }
        $cp = $morganaJar

        $cp += Get-PXClassPath -Paths $Paths
        
        $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
        Get-ChildItem "$processorPath\MorganaXProc-IIIse_lib" -Filter *.jar |
            ForEach-Object {
                $cp = "$cp$cpDelimiter$_"
            }
    }
        
    # Write-Verbose "ClassPath: $cp"

    # Configuration (#22): a file path is used as-is; a hashtable is merged over
    # the auto-detected defaults (explicit entries win); when omitted, the
    # auto-detected defaults are injected (connector auto-detection + ixml)
    $generatedConfigPath = $null
    if ($Configuration -is [string] -and $Configuration) {
        $configArg = $Configuration
    }
    elseif ($ClassPath) {
        # Manual mode: the caller owns the classpath, no config is generated (#8)
        $configArg = $null
        $generatedConfigPath = $null
    }
    else {
        $effectiveConfig = Get-PXMorganaAutoConfig -Paths $Paths
        if ($Configuration -is [hashtable]) {
            foreach ($key in $Configuration.Keys) {
                $effectiveConfig[$key] = $Configuration[$key]
            }
        }
        $generatedConfigPath = ConvertTo-PXXmlConfig -Config $effectiveConfig `
            -Root "morgana-config" `
            -Namespace "http://www.xml-project.com/morganaxproc"
        $configArg = $generatedConfigPath
    }

    $xcArgs = @()
    if ($configArg) {
        $xcArgs += @("-config=`"$configArg`"")
    }
    $xcArgs += @($Pipeline)
    # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
    if ($InPort) {
        $xcInput = @()
        foreach ($enum in $InPort.GetEnumerator()) {
            $portName = $enum.Key
            $portVal = $enum.Value
            if ($portVal -is [array]) {
                foreach ($uri in $portVal) {
                    $xcInput += ("-input:$portName=`"$uri`"")
                }
            }
            else {
                $xcInput += ("-input:$portName=`"$portVal`"")
            }
        }
        $xcArgs += $xcInput
    }
    if ($OutPort) {
        $xcOutput = @()
        foreach ($enum in $OutPort.GetEnumerator()) {
            $xcOutput += ("-output:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcOutput
    }

    if ($Catalog) {
        $xcArgs += @("-catalogs=`"$Catalog`"")
    }


    if ($Passthrough) {
        $xcArgs += $Passthrough
    }
        
    if ($Options) {
        $xcOptions = @()
        foreach ($enum in $Options.GetEnumerator()) {
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
    Write-Debug "args to processor is $xcArgs"

    # try to force UTF-8
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

    # Morgana does not support --pipe; write pipeline input to a temp file and pass via -input:source
    if ($null -ne $InputObject) {
        $stdinContent = if ($InputObject -is [string]) { $InputObject } else { $InputObject.OuterXml }
        $stdinTempFile = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".xml")
        [System.IO.File]::WriteAllText($stdinTempFile, $stdinContent, [System.Text.UTF8Encoding]::new())
        $xcArgs += @("-input:source=`"$stdinTempFile`"")
    }

    try {
        if ($MergeOutput) {
            $output = & java -cp "$cp" @PassthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs 2>&1
        }
        else {
            $output = & java -cp "$cp" @PassthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs
        }

        # Surface processor failures: a non-zero exit code means the run failed (#29)
        if ($LASTEXITCODE -ne 0) {
            $failureText = if ($output -is [array]) { $output -join "`n" } else { [string]$output }
            throw "MorganaXProc failed with exit code $LASTEXITCODE`:$failureText"
        }
    }
    finally {
        if ($generatedConfigPath -and (Test-Path $generatedConfigPath -PathType Leaf)) {
            Remove-Item -Path $generatedConfigPath -Force -ErrorAction SilentlyContinue
        }
    }

    $stdoutResult = if ($output -is [array]) {
        $output -join "`n" | Get-PXMultiXmlDocuments
    }
    else {
        $output | Get-PXMultiXmlDocuments
    }

    if ($CollectOutput -and $OutPort -and $OutPort.Count -gt 0) {
        $collectedFromFiles = @()
        foreach ($enum in $OutPort.GetEnumerator()) {
            $filePath = $enum.Value
            if (Test-Path $filePath) {
                $fileContent = Get-Content -Path $filePath -Raw
                $collectedFromFiles += @($fileContent | Get-PXMultiXmlDocuments)
            }
        }
        $combined = @()
        if ($stdoutResult) { $combined += @($stdoutResult) }
        if ($collectedFromFiles) { $combined += @($collectedFromFiles) }
        return $combined
    }

    return $stdoutResult
}

function Get-PXClassPath {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [array]$Paths,
        [switch]$ShortenClassPath
    ) 
    $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
    #Write-Host $Paths
    $cp = @()
    if ($ShortenClassPath) {
        $cp = "$($Paths -join $cpDelimiter)"
        return $cp
    }
    else {
        $Paths | ForEach-Object {
            Get-ChildItem "$_" -Filter *.jar |
                ForEach-Object {
                    Write-Verbose "Adding $($_.FullName) to classpath"
                    $cp = "$cp$cpDelimiter$_"
                }
            }
            return $cp
        }
    }