param(
    $processing = "xproc",
    $processor = "xmlcalabash",
    $targetComposition = "oscal"
)
$localRepository = "$HOME/.polyglotpm"
#process bundle
Import-Module ./polyglot -Force
[System.Collections.ArrayList]$paths = Copy-SoftwareComposition `
    -sbomPath .\sbom.xml `
    -targetComposition $targetComposition `
    -localRepository  $localRepository
    
$cp = $paths.ToArray() -join ";"
#convert paths to ClassPath format

if ($processing -eq "xproc") {
    if ($processor -eq "xmlcalabash") {

        $processorPath = "$localRepository\xmlcalabash-3.0.0-beta7"
        #construct classpath
        $cp = "$cp;$processorPath/*"

        if (![System.IO.File]::Exists("$processorPath")) {
            Write-Host "XML Calabash script did not find the 3.0.0-beta7 distribution jar"
            #     Exit 1
        }

        Get-ChildItem "$processorPath\extra" -Filter *.jar |
        ForEach-Object {
            $cp = "$cp;$_"
        }

        Get-ChildItem "$processorPath\lib" -Filter *.jar |
        ForEach-Object {
            $cp = "$cp;$_"
        }
        Write-Host "ClassPath: $cp"
        # FIXME: should there be some attempt to look for $Env:JAVA_HOME here?

        java -cp "$cp" com.xmlcalabash.app.Main $args

    }
}