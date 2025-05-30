# Probably should all be starting UpperCase
param(
    $processing = "xproc",
    $processor = "xmlcalabash",
    $targetComposition = "oscal",
    [switch]$inPipe, 
    $pipeline,
    [hashtable]$inPort,
    [hashtable]$outPort,
    [array]$passthrough
)
$localRepository = "$HOME/.polyglotpm"
#process bundle
Import-Module ./polyglot -Force
[array]$paths = Copy-SoftwareComposition `
    -sbomPath .\sbom.xml `
    -targetComposition $targetComposition `
    -localRepository  $localRepository | Select-Object -Unique    
    
#$cp = $paths -join ";"
#convert paths to ClassPath format

if ($processing -eq "xproc") {
    if ($processor -eq "xmlcalabash") {

        $processorPath = (Join-Path $localRepository "xmlcalabash-3.0.0-beta7")
        
        #construct classpath
        $cp = "$processorPath/xmlcalabash-app-3.0.0-beta7.jar"
      
        $cpDelimiter = if($IsLinux -or $IsMacOS) {":"} else {";"}

        $paths | ForEach-Object {
            Get-ChildItem "$_" -Filter *.jar |
            ForEach-Object {
                $cp = "$cp$cpDelimiter$_"
            }
        }

        Get-ChildItem "$processorPath\lib" -Filter *.jar |
        ForEach-Object {
            $cp = "$cp$cpDelimiter$_"
        }
        # Write-Host "ClassPath: $cp"
        $xcArgs = @()
        # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
        if($inPort){
            $xcInput = @()
            foreach($enum in $inPort.GetEnumerator()) {
                $xcInput += ("--input:$($enum.Key)=`"$($enum.Value)`"")                        
            }
            $xcArgs += $xcInput
        }
        if($outPort){
            $xcOutput = @()
            foreach($enum in $outPort.GetEnumerator()) {
                $xcOutput += ("--output:$($enum.Key)=`"$($enum.Value)`"")                        
            }
            $xcArgs += $xcOutput
        }

        #handle STDIN
        if($inPipe){
            $xcArgs += @("--pipe")
        }

        if($passthrough){
            $xcArgs += $passthrough
        }
        
        $xcArgs += @($pipeline)
        # see https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5#passing-arguments-that-contain-quote-characters
        $PSNativeCommandArgumentPassing = 'Legacy'
        Write-Host "args to processor is $xcArgs"
        & java -cp "$cp" com.xmlcalabash.app.Main @xcArgs

    }
}