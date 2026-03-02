
function Get-MultiXmlDocuments {
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]$StdOut
    )
    
    # Detect multipart MIME: first non-empty line starts with "--"
    $firstLine = ($StdOut -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($firstLine -match '^--(.+)') {
        $boundary = $matches[1] -replace '--$', ''
        $parts = Parse-MimeMultipart -MimeString $StdOut -Boundary $boundary
        $results = foreach ($part in $parts) {
            ConvertTo-NativeType -MimePart $part
        }
        return $results
    }

    # XmlCalabash standard out format
    $headerPattern = '^=== result :: \d+ :: .+?={10,}\r?\n'
    $trailerPattern = '^={72,}\r?\n?'
    
    # If no headers, treat as single document
    if (-not [regex]::IsMatch($StdOut, $headerPattern, 'Multiline')) {
        return , ($StdOut)
    }
    
    # Split on headers, ignore empty entries
    $docs = [regex]::Split($StdOut, $headerPattern, 'Multiline') | Where-Object { $_.Trim() }
    
    # Remove trailers and convert each doc via ConvertTo-NativeType
    $xmlDocs = foreach ($doc in $docs) {
        $clean = [regex]::Replace($doc, $trailerPattern, '', 'Multiline')
        $mimePart = @{ Headers = @{ 'Content-Type' = 'application/xml' }; Content = $clean.Trim() }
        ConvertTo-NativeType -MimePart $mimePart
    }
    return $xmlDocs
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
        [bool]$PipeInput,
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
        [hashtable]$Namespace
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

    if ($catalog) {
        $xcArgs += @("--catalog:`"$catalog`"")
    }

    #handle STDIN
    if ($PipeInput) {
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

    $stdinString = $null
    if ($PipeInput -and $null -ne $InputObject) {
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
        if ($MergeOutput) {
            $output = & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
        }
        else {
            $output = & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs
        }
    }
    if ($output -is [array]) {
        return $output -join "`n" | Get-MultiXmlDocuments
    }
    else {
        return $output | Get-MultiXmlDocuments
    }
} 


function Invoke-MorganaXProc {
    [CmdletBinding()]
    param(
        [array]$paths,        
        [bool]$PipeInput,
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
        [hashtable]$Namespace
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
        $xcArgs += @("--catalog:`"$catalog`"")
    }

    #handle STDIN
    if ($PipeInput) {
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
    $stdinString = $null
    if ($PipeInput -and $null -ne $InputObject) {
        $stdinString = if ($InputObject -is [string]) { $InputObject } else { $InputObject.OuterXml }
    }

    if ($null -ne $stdinString) {
        if ($MergeOutput) {
            $output = $stdinString | & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs 2>&1
        }
        else {
            $output = $stdinString | & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs
        }
    }
    else {
        if ($MergeOutput) {
            $output = & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs 2>&1
        }
        else {
            $output = & java -cp "$cp" @passthroughJava com.xml_project.morganaxproc3.XProcEngine @xcArgs
        }
    }
    if ($output -is [array]) {
        $output = $output -join "`n"
    }
    #Write-Host $output
    return $output
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