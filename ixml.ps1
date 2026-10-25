
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
function Transform-IXml {
    [CmdletBinding()]
    param(
        $processing = "ixml",
        $processor = "nineml",
        $targetComposition = "oscal",        
        [Parameter(Mandatory = $true)] 
        $grammar,
        $input,
        [array]$passthrough,
        [array]$passthroughJava
    )
    #process bundle
    Import-Module "$PSScriptRoot/polyglot" -Force
    $localRepository = Get-LocalRepositoryPath
    [array]$paths = Copy-SoftwareComposition `
        -sbomPath "$PSScriptRoot\sbom.xml" `
        -targetComposition $targetComposition `
        -localRepository  $localRepository | Select-Object -Unique    
    
    #$cp = $paths -join ";"
    #convert paths to ClassPath format

    if ($processing -eq "xproc") {
        if ($processor -eq "nineml") {
            $processorPath = (Join-Path $localRepository "coffeepot-3.2.9")
            
            #construct classpath
            $cp = "$processorPath/coffeepot-3.2.9.jar"
            
            $cp += Get-PXClassPath -paths $paths
            
            $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
            Get-ChildItem "$processorPath\lib" -Filter *.jar |
            ForEach-Object {
                $cp = "$cp$cpDelimiter$_"
            }

            Write-Host "ClassPath: $cp"
            $xcArgs = @()

            $xcArgs += @("-g,$grammar")

            $xcArgs += @("-i,$input")

            java -jar

        }
    }
}
