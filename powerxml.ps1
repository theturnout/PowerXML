param(
    $processing = "xproc",
    $processor = "xmlcalabash",
    $targetComposition = "oscal",
    $pipeline,
    [hashtable]$inPort,
    [hashtable]$outPort
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

        $processorPath = "$localRepository\xmlcalabash-3.0.0-beta7"              
        
        #construct classpath
        $cp = "$cp;$processorPath/*"
       
        $paths | ForEach-Object {
            Get-ChildItem "$_" -Filter *.jar |
            ForEach-Object {
                $cp = "$cp;$_"
            }
        }

        Get-ChildItem "$processorPath\lib" -Filter *.jar |
        ForEach-Object {
            $cp = "$cp;$_"
        }
        #Write-Host "ClassPath: $cp"
        # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?
        if($inPort){
            $xcInput = @()
            foreach($enum in $inPort.GetEnumerator()) {
                $xcInput += ("--input:$($enum.Key)=`"$($enum.Value)`"")                        
            }
        }
        Write-Host $xcInput[0]
        $xcArgs = $xcInput + @($pipeline)
        Write-Host "args to processor is $xcArgs"
        & java -cp "$cp" com.xmlcalabash.app.Main @xcArgs

    }
}