<#
.PARAMETER StdOut
The standard output from the processor, which may contain one or more XML documents, either as a single document, a sequence of documents separated by XmlCalabash-style headers and trailers, or as multipart MIME output.
.NOTES
If multiple documents are encountered without mime/type, they are assumed to be XML.
.OUTPUTS
One or more documents in their native type as possible. See `ConvertTo-NativeType` for details on how MIME parts are converted to native types.
#>
function Get-MultiXmlDocuments {
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
        $parts = Parse-MimeMultipart -MimeString $StdOut -Boundary $boundary
        foreach ($part in $parts) {
            ConvertTo-NativeType -MimePart $part
        }
    }
    elseif ([regex]::IsMatch($StdOut, $headerPattern, 'Multiline')) {
        # XmlCalabash standard out
        $docs = [regex]::Split($StdOut, $headerPattern, 'Multiline') | Where-Object { $_.Trim() }
        foreach ($doc in $docs) {
            $clean = [regex]::Replace($doc, $trailerPattern, '', 'Multiline')
            $mimePart = @{ Headers = @{ 'Content-Type' = 'application/xml' }; Content = $clean.Trim() }
            ConvertTo-NativeType -MimePart $mimePart
        }
    }
    elseif (([regex]::Matches($StdOut, '<\?xml')).Count -gt 1) {
        # Multiple concatenated XML documents (e.g. MorganaXProc stdout for sequences)
        $parts = [regex]::Split($StdOut.Trim(), '(?=<\?xml)') | Where-Object { $_.Trim() }
        foreach ($part in $parts) {
            $mimePart = @{ Headers = @{ 'Content-Type' = 'application/xml' }; Content = $part.Trim() }
            ConvertTo-NativeType -MimePart $mimePart
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
Invokes the XmlCalabash processor with the specified parameters.
.PARAMETER paths
An array of paths to search for the XmlCalabash processor and its dependencies.
#> 
function Invoke-XmlCalabash {
    [CmdletBinding()]
    param(
        [array]$paths,        
        $InputObject,
        [Parameter(Mandatory = $true)] 
        $pipeline,        
        [hashtable]$options,
        [hashtable]$inPort,
        [hashtable]$outPort,
        [string]$catalog,
        [array]$passthrough,
        [array]$passthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace,
        [switch]$CollectOutput
    )
    # look for the xmlcalabash path
    $processorPath = $paths | Where-Object {
        $_ -like "*xmlcalabash*"        
    } | Select-Object -First 1
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
    if ($outPort) {
        $xcOutput = @()
        foreach ($enum in $outPort.GetEnumerator()) {
            $xcOutput += ("--output:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcOutput
    }
    # else {
    #     $mimeOut = New-TemporaryFile
    #     $xcArgs += ("--output-multiplex:$($mimeOut.FullName)")
    # }

    if ($catalog) {
        $xcArgs += @("--catalog:`"$catalog`"")
    }

    #handle STDIN
    if ($InputObject) {
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
    Write-Debug "args to processor is $xcArgs"
    Write-Debug "Classpath: $cp"
    [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

    $stdinString = $null
    if ($null -ne $InputObject) {
        $stdinString = if ($InputObject -is [string]) { $InputObject } else { $InputObject.OuterXml }
    }

    if ($null -ne $stdinString) {
        if ($MergeOutput) {
            $output = $stdinString | & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
        }
        else {
            $output = $stdinString | & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs
        }
    }
    else {
        # this will break if someone is missing an inport and the processor 
        # tried to bind it to stdin
        if ($MergeOutput) {
            $output = $null | & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
        }
        else {
            $output = $null | & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs
        }
    }
    $stdoutResult = if ($output -is [array]) {
        $output -join "`n" | Get-MultiXmlDocuments
    }
    else {
        $output | Get-MultiXmlDocuments
    }

    if ($CollectOutput -and $outPort -and $outPort.Count -gt 0) {
        $collectedFromFiles = @()
        foreach ($enum in $outPort.GetEnumerator()) {
            $filePath = $enum.Value
            if (Test-Path $filePath) {
                $fileContent = Get-Content -Path $filePath -Raw
                $collectedFromFiles += @($fileContent | Get-MultiXmlDocuments)
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
        [array]$paths,                
        $InputObject,
        [Parameter(Mandatory = $true)] 
        $pipeline,        
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
    #$processorPath = (Join-Path $localRepository "MorganaXProc-IIIse-1.8.2")
        
    # look for the xmlcalabash path
    $processorPath = $paths | Where-Object {
        $_ -like "*MorganaXProc-IIIse*"
    } | Select-Object -First 1
    if ( -not $processorPath) {
        throw "Could not find MorganaXProc processor in software composition paths"
    }    
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
    if ($Configuration) {
        $xcArgs += @("-config=`"$Configuration`"")
    }
    $xcArgs += @($pipeline)
    # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
    if ($inPort) {
        $xcInput = @()
        foreach ($enum in $inPort.GetEnumerator()) {
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
    if ($outPort) {
        $xcOutput = @()
        foreach ($enum in $outPort.GetEnumerator()) {
            $xcOutput += ("-output:$($enum.Key)=`"$($enum.Value)`"")                        
        }
        $xcArgs += $xcOutput
    }

    if ($catalog) {
        $xcArgs += @("-catalogs=`"$catalog`"")
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
    Write-Host "args to processor is $xcArgs"

    # try to force UTF-8
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

    # Morgana does not support --pipe; write pipeline input to a temp file and pass via -input:source
    if ($null -ne $InputObject) {
        $stdinContent = if ($InputObject -is [string]) { $InputObject } else { $InputObject.OuterXml }
        $stdinTempFile = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".xml")
        [System.IO.File]::WriteAllText($stdinTempFile, $stdinContent, [System.Text.UTF8Encoding]::new())
        $xcArgs += @("-input:source=`"$stdinTempFile`"")
    }

    if ($MergeOutput) {
        $output = & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs 2>&1
    }
    else {
        $output = & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs
    }
    $stdoutResult = if ($output -is [array]) {
        $output -join "`n" | Get-MultiXmlDocuments
    }
    else {
        $output | Get-MultiXmlDocuments
    }

    if ($CollectOutput -and $outPort -and $outPort.Count -gt 0) {
        $collectedFromFiles = @()
        foreach ($enum in $outPort.GetEnumerator()) {
            $filePath = $enum.Value
            if (Test-Path $filePath) {
                $fileContent = Get-Content -Path $filePath -Raw
                $collectedFromFiles += @($fileContent | Get-MultiXmlDocuments)
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
        [array]$paths,
        [switch]$shortenClassPath
    ) 
    $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
    #Write-Host $paths
    $cp = @()
    if ($shortenClassPath) {
        $cp = "$($paths -join $cpDelimiter)"
        return $cp
    }
    else {
        $paths | ForEach-Object {
            Get-ChildItem "$_" -Filter *.jar |
                ForEach-Object {
                    Write-Verbose "Adding $($_.FullName) to classpath"
                    $cp = "$cp$cpDelimiter$_"
                }
            }
            return $cp
        }
    }