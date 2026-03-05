<#
.SYNOPSIS
Transforms XML using .NET's XslCompiledTransform.
.PARAMETER Stylesheet
The path to the XSLT stylesheet file.
.PARAMETER InputXml
The path to the input XML file, or an XML object/string.
.PARAMETER OutputFile
Optional path to write the output. If not specified, returns output as string.
.PARAMETER Parameters
Optional hashtable of XSLT parameters.
#>
function Invoke-DotNetXslt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stylesheet,
        [Parameter(Mandatory = $true)]
        [string]$InputXml,
        [string]$OutputFile,
        [hashtable]$Parameters
    )
    
    $xslt = New-Object System.Xml.Xsl.XslCompiledTransform
    $xsltSettings = New-Object System.Xml.Xsl.XsltSettings($true, $true)
    $resolver = New-Object System.Xml.XmlUrlResolver
    
    try {
        $xslt.Load($Stylesheet, $xsltSettings, $resolver)
    }
    catch {
        throw "Failed to load XSLT stylesheet: $_"
    }
    
    $argList = New-Object System.Xml.Xsl.XsltArgumentList
    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $null = $argList.AddParam($key, "", $Parameters[$key])
        }
    }
    
    $xmlReader = [System.Xml.XmlReader]::Create($InputXml)
    
    try {
        if ($OutputFile) {
            $writerSettings = New-Object System.Xml.XmlWriterSettings
            $writerSettings.Indent = $true
            $writerSettings.Encoding = [System.Text.Encoding]::UTF8
            $xmlWriter = [System.Xml.XmlWriter]::Create($OutputFile, $writerSettings)
            try {
                $xslt.Transform($xmlReader, $argList, $xmlWriter)
            }
            finally {
                $xmlWriter.Close()
            }
            return $null
        }
        else {
            $stringWriter = New-Object System.IO.StringWriter
            $writerSettings = New-Object System.Xml.XmlWriterSettings
            $writerSettings.Indent = $true
            $writerSettings.OmitXmlDeclaration = $false
            $xmlWriter = [System.Xml.XmlWriter]::Create($stringWriter, $writerSettings)
            try {
                $xslt.Transform($xmlReader, $argList, $xmlWriter)
            }
            finally {
                $xmlWriter.Close()
            }
            return $stringWriter.ToString()
        }
    }
    finally {
        $xmlReader.Close()
    }
}

<#
.SYNOPSIS
Transforms XML using MSXML (Windows only, COM-based).
.PARAMETER Stylesheet
The path to the XSLT stylesheet file.
.PARAMETER InputXml
The path to the input XML file.
.PARAMETER OutputFile
Optional path to write the output. If not specified, returns output as string.
.PARAMETER Parameters
Optional hashtable of XSLT parameters.
.NOTES
Requires Windows with MSXML installed. May not work in PowerShell Core on non-Windows platforms.
#>
function Invoke-MsxmlXslt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stylesheet,
        [Parameter(Mandatory = $true)]
        [string]$InputXml,
        [string]$OutputFile,
        [hashtable]$Parameters
    )
    
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        throw "MSXML processor is only available on Windows."
    }
    
    try {
        $xmlDoc = New-Object -ComObject Msxml2.DOMDocument.6.0
        $xslDoc = New-Object -ComObject Msxml2.DOMDocument.6.0
        $xslTemplate = New-Object -ComObject Msxml2.XSLTemplate.6.0
    }
    catch {
        throw "Failed to create MSXML COM objects. MSXML 6.0 may not be installed: $_"
    }
    
    $xmlDoc.async = $false
    $xmlDoc.resolveExternals = $true
    $xslDoc.async = $false
    $xslDoc.resolveExternals = $true
    $null = $xslDoc.setProperty("AllowXsltScript", $true)
    
    if (-not $xmlDoc.load($InputXml)) {
        $err = $xmlDoc.parseError
        throw "Failed to load input XML: $($err.reason) at line $($err.line)"
    }
    
    if (-not $xslDoc.load($Stylesheet)) {
        $err = $xslDoc.parseError
        throw "Failed to load XSLT stylesheet: $($err.reason) at line $($err.line)"
    }
    
    $xslTemplate.stylesheet = $xslDoc
    $xslProc = $xslTemplate.createProcessor()
    $xslProc.input = $xmlDoc
    
    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $null = $xslProc.addParameter($key, $Parameters[$key], "")
        }
    }
    
    $null = $xslProc.transform()
    $result = $xslProc.output
    
    if ($OutputFile) {
        [System.IO.File]::WriteAllText($OutputFile, $result, [System.Text.Encoding]::UTF8)
        return $null
    }
    else {
        return $result
    }
}

<#
.SYNOPSIS
Transforms XML using AltovaXML (Windows only, COM-based, XSLT 2.0 support).
.PARAMETER Stylesheet
The path to the XSLT stylesheet file.
.PARAMETER InputXml
The path to the input XML file.
.PARAMETER OutputFile
Optional path to write the output. If not specified, returns output as string.
.PARAMETER Parameters
Optional hashtable of XSLT parameters.
.NOTES
Requires AltovaXML to be installed and registered. Only available on Windows.
#>
function Invoke-AltovaXslt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stylesheet,
        [Parameter(Mandatory = $true)]
        [string]$InputXml,
        [string]$OutputFile,
        [hashtable]$Parameters,
        [switch]$NoPrompt
    )
    function Install-AltovaXml {
        $downloadUrl = "http://cdn.sw.altova.com/v2013r2/en/AltovaXMLCmu2013.exe"
        try {
            $tempInstaller = [System.IO.Path]::GetTempFileName() + ".exe"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempInstaller -UseBasicParsing
            Start-Process -FilePath $tempInstaller -Wait
            Remove-Item $tempInstaller -Force
            # check if COM object is now available                
            $altova = New-Object -ComObject AltovaXML.Application
            if (-not $altova) {
                throw "AltovaXML COM object still not available after installation."
            }
            else {
                Write-Host "AltovaXML installed successfully. Retry command."
            }
        }
        catch {
            throw "Failed to install or create AltovaXML COM object: $_"
        }
    } 
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        throw "AltovaXML processor is only available on Windows."
    }
    
    try {
        $altova = New-Object -ComObject AltovaXML.Application
    }
    catch {
        Write-Warning "Failed to create AltovaXML COM object. AltovaXML may not be installed or registered."
        if ($NoPrompt) {
            throw "AltovaXML COM object not found: $_"
        }
        $install = Read-Host "Do you want to download and install it now? (Y/N)"
        if ($install.ToLowerInvariant() -eq "y") {
            Install-AltovaXml
        }
        else {
            throw "AltovaXML COM object not found: $_"
        }
    }
    $xslt2 = $altova.XSLT2
    
    # Load input XML from file
    try {
        $inputContent = [System.IO.File]::ReadAllText($InputXml)
        $xslt2.InputXMLFromText = $inputContent
    }
    catch {
        throw "Failed to load input XML from '$InputXml': $_"
    }
    
    # Set stylesheet file path
    $xslt2.XSLFileName = $Stylesheet
    
    # Add parameters if provided
    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            # AltovaXML expects string values to be quoted for literal strings
            # Check if value is already quoted or is an XPath expression (starts with /)
            $isQuoted = $value -match '^[''"]{1}.*[''"]{1}$'
            $isXPath = $value -match '^/'
            if ($value -is [string] -and -not $isQuoted -and -not $isXPath) {
                $value = "'$value'"
            }
            $null = $xslt2.AddExternalParameter($key, $value)
        }
    }
    
    try {
        if ($OutputFile) {
            $null = $xslt2.Execute($OutputFile)
            $xslt2.ClearExternalParameterList() 
            return $null
        }
        else {
            $result = $xslt2.ExecuteAndGetResultAsString()
            $xslt2.ClearExternalParameterList()
            return $result
        }
    }
    catch {
        $altovaError = $xslt2.LastErrorMessage
        throw "XSLT transformation failed: $altovaError"
    }
}

<#
.SYNOPSIS
Transforms XML using xsltproc (libxslt command-line tool).
.PARAMETER Stylesheet
The path to the XSLT stylesheet file.
.PARAMETER InputXml
The path to the input XML file.
.PARAMETER OutputFile
Optional path to write the output. If not specified, returns output as string.
.PARAMETER Parameters
Optional hashtable of XSLT parameters (passed as --stringparam).
.NOTES
Requires xsltproc to be installed and available on PATH.
Supports XSLT 1.0 with EXSLT extensions.
#>
function Invoke-XsltprocXslt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stylesheet,
        [Parameter(Mandatory = $true)]
        [string]$InputXml,
        [string]$OutputFile,
        [hashtable]$Parameters
    )
    
    $xsltprocCmd = Get-Command 'xsltproc' -ErrorAction SilentlyContinue
    if (-not $xsltprocCmd) {
        throw "xsltproc is not installed or not found on PATH."
    }
    
    $xsltprocArgs = @()

    # xsltproc (libxslt) is a Unix tool; on Windows its I/O layer rejects mixed-separator
    # paths (e.g. D:\foo/bar.xml). Resolve to an absolute path and use forward slashes.
    $resolvedInput    = [System.IO.Path]::GetFullPath($InputXml)
    $resolvedStylesheet = [System.IO.Path]::GetFullPath($Stylesheet)
    if ($IsWindows) {
        $resolvedInput      = $resolvedInput.Replace('\', '/')
        $resolvedStylesheet = $resolvedStylesheet.Replace('\', '/')
    }

    if ($OutputFile) {
        $resolvedOutput = [System.IO.Path]::GetFullPath($OutputFile)
        if ($IsWindows) {
            $resolvedOutput = $resolvedOutput.Replace('\', '/')
        }
        $xsltprocArgs += '--output'
        $xsltprocArgs += $resolvedOutput
    }
    
    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $xsltprocArgs += '--stringparam'
            $xsltprocArgs += $key
            $xsltprocArgs += [string]$Parameters[$key]
        }
    }
    
    $xsltprocArgs += $resolvedStylesheet
    $xsltprocArgs += $resolvedInput
    
    $procResult = & xsltproc @xsltprocArgs 2>&1
    
    $stderr = @($procResult | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $stdout = @($procResult | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    
    if ($LASTEXITCODE -ne 0) {
        $errorMsg = ($stderr | ForEach-Object { $_.ToString() }) -join "`n"
        throw "xsltproc transformation failed (exit code $LASTEXITCODE): $errorMsg"
    }
    
    if ($OutputFile) {
        return $null
    }
    else {
        return ($stdout -join "`n")
    }
}
