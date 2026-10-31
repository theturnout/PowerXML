
<#
.SYNOPSIS
Transforms inputs using XML technologies
.PARAMETER Processing
The kind of processing to run. Default xproc.
.PARAMETER Processor
The specific processor to use.
.PARAMETER TargetComposition
The target composition in the SBOM to use to determine which packages are required to run the code.
.PARAMETER inPipe
Whether to use the STDIN to pass data to the pipeline's default port.
.PARAMETER inPort
A hashtable of ports bound to inputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER inPort
A hashtable of ports bound to outputs, e.g. @{input1='file1.xml', input2='file2.xml}
.PARAMETER Passthrough
An array of parameters passed directly to the processor.
.PARAMETER PassthroughJava
An array of parameters passed directly to the Java JVM.
#>
function Transform-IXml {
    [CmdletBinding()]
    param(
        $Processing = "ixml",
        $Processor = "nineml",
        $TargetComposition = "oscal",        
        [Parameter(Mandatory = $true)] 
        $Grammar,
        $input,
        [array]$Passthrough,
        [array]$PassthroughJava
    )
    #process bundle
    Import-Module "$PSScriptRoot/polyglot" -Force
    $localRepository = Get-LocalRepositoryPath
    [array]$paths = Copy-SoftwareComposition `
        -SbomPath "$PSScriptRoot\sbom.xml" `
        -TargetComposition $TargetComposition `
        -LocalRepository  $localRepository | Select-Object -Unique    
    
    #$cp = $paths -join ";"
    #convert paths to ClassPath format

    if ($Processing -eq "xproc") {
        if ($Processor -eq "nineml") {
            $processorPath = (Join-Path $localRepository "coffeepot-3.2.9")
            
            #construct classpath
            $cp = "$processorPath/coffeepot-3.2.9.jar"
            
            $cp += Get-PXClassPath -Paths $paths
            
            $cpDelimiter = if ($IsLinux -or $IsMacOS) { ":" } else { ";" }
            Get-ChildItem "$processorPath\lib" -Filter *.jar |
            ForEach-Object {
                $cp = "$cp$cpDelimiter$_"
            }

            Write-Host "ClassPath: $cp"
            $xcArgs = @()

            $xcArgs += @("-g,$Grammar")

            $xcArgs += @("-i,$input")

            java -jar

        }
    }
}
