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
        $targetComposition = "oscal",
        [switch]$inPipe,
        [Parameter(Mandatory = $true)] 
        $pipeline,
        [hashtable]$options,
        [hashtable]$inPort,
        [hashtable]$outPort,
        [string]$catalog,
        [array]$passthrough,
        [array]$passthroughJava
    )
    $localRepository = "$HOME/.polyglotpm"
    #process bundle
    Import-Module "$PSScriptRoot/polyglot" -Force
    [array]$paths = Copy-SoftwareComposition `
        -sbomPath "$PSScriptRoot\sbom.xml" `
        -targetComposition $targetComposition `
        -localRepository  $localRepository | Select-Object -Unique    
    
    #$cp = $paths -join ";"
    #convert paths to ClassPath format

    if ($processing -eq "xproc") {
        if ($processor -eq "xmlcalabash") {

            $processorPath = (Join-Path $localRepository "xmlcalabash-3.0.0-beta7")
        
            #construct classpath
            $cp = "$processorPath/xmlcalabash-app-3.0.0-beta7.jar"
     
            $cp += Get-PXClassPath -paths $paths

            $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
            Get-ChildItem "$processorPath\lib" -Filter *.jar |
            ForEach-Object {
                $cp = "$cp$cpDelimiter$_"
            }


            Write-Host "ClassPath: $cp"
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
        
            if($options) {
                $xcOptions = @()
                foreach ($enum in $options.GetEnumerator()) {
                        $xcOptions += ("$($enum.Key)=$($enum.Value)")
                }
                $xcArgs += $xcOptions
            }

            # Handle CmdLet params
            # Calabash has trace, warn, error, if you want to use them, use passthrough
            if($Verbose){
                $xcArgs += @("--verbosity:info")
                $xcArgs += @("--explain")
            } elseif($Debug) {
                $xcArgs += @("--verbosity:debug")
                $xcArgs += @("--explain")
            }

            $xcArgs += @($pipeline)
            # see https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5#passing-arguments-that-contain-quote-characters
            $PSNativeCommandArgumentPassing = 'Legacy'
            Write-Host "args to processor is $xcArgs"
            $output = & java -cp "$cp" @passthroughJava com.xmlcalabash.app.Main @xcArgs 2>&1
return $output
        } 
    }
}

function Get-PXClassPath {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [array]$paths
    ) 
    $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }

    $cp = @()
    $paths | ForEach-Object {
        Get-ChildItem "$_" -Filter *.jar |
        ForEach-Object {
            Write-Host "Adding $($_.FullName) to classpath"
            $cp = "$cp$cpDelimiter$_"
        }
    }
    return $cp
}
function New-Bundle {
    [CmdletBinding()]
    param(        
        $targetComposition = "oscal",
        $bundleName
    )
    
    $localRepository = "$HOME/.polyglotpm"
    #process bundle
    Import-Module "$PSScriptRoot/polyglot" -Force
    [array]$paths = Copy-SoftwareComposition `
        -sbomPath "$PSScriptRoot\sbom.xml" `
        -targetComposition $targetComposition `
        -localRepository  $localRepository | Select-Object -Unique    

    $bundlePath = Join-Path $localRepository "bundles"        
    New-Item -Path $bundlePath -Name $bundleName -ItemType Directory -Force | Out-Null

    $paths | ForEach-Object {      
        Write-Host "Copying software composition from $($_) to $bundlePath"                  
        Copy-Item -Path "$($_)\*.jar" -Destination $bundlePath -Force -Recurse
    }
}
