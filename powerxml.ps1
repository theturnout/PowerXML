# WinPS 5.1 compatibility: define platform variables that only exist in PS Core 6+
if (-not (Get-Variable IsWindows -Scope Global -ErrorAction SilentlyContinue)) {
    $global:IsWindows = $true
    $global:IsLinux = $false
    $global:IsMacOS = $false
}

# WinPS 5.1 compatibility: System.Xml.Linq is auto-loaded in .NET Core but not .NET Framework
Add-Type -AssemblyName System.Xml.Linq -ErrorAction SilentlyContinue

. "$PSScriptRoot\xproc.ps1"
. "$PSScriptRoot\xslt.ps1"

<#
.PARAMETER InputObject
The input to resolve, which can be an XML object or a string containing XML content.
.PARAMETER Extension
The file extension to use for the temporary file if the input is XML content. Default is "xml". Only matters if the processor handles files of certain extensions differently.
.PARAMETER TargetEncoding
The target encoding to use when writing the XML content to a temporary file. Default is "UTF8". Supported encodings include "UTF8", "UTF16", "UTF16LE", "UTF16BE", "ISO-8859-1", and "US-ASCII".
.NOTES
Any XML input will be rewritten to a temporary file with the given extension and encoding, and the path to that file will be returned. Non-XML input (e.g. a file path) will be returned as-is.
#>
function Resolve-PXXmlInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [string]$Extension = "xml",        
        [string]$TargetEncoding = "UTF8"
    )
    $xmlTypes = @(
        'System.Xml.XmlDocument',
        'System.Xml.Linq.XDocument',
        'System.Xml.Linq.XElement',
        'System.Xml.XmlElement',
        'System.Xml.XmlNode'
    )
    $isXml = $false
    if ($null -ne $InputObject) {
        if ($InputObject -is [array]) {
            $resolvedArray = @()
            foreach ($item in $InputObject) {
                $resolvedArray += Resolve-PXXmlInput -InputObject $item `
                    -Extension $Extension `
                    -TargetEncoding $TargetEncoding
            }
            return $resolvedArray
        }
        if ($xmlTypes -contains $InputObject.GetType().FullName) {
            $isXml = $true
        }
        elseif ($InputObject -is [string] -and $InputObject -like "pkg:*") {
            # Package URLs resolve through PolyglotPM to a local file (#31)
            return Resolve-PXPurlInput -PurlString $InputObject
        }
        elseif ($InputObject -is [string]) {
            # try to parse the string as XML
            try {
                [xml]$tryXml = $InputObject
                if ($tryXml.DocumentElement -or $tryXml.Root) {
                    $isXml = $true
                }
            }
            catch {
                $isXml = $false
            }
        }
    }
    if ($isXml) {
        $tempFile = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, ".$Extension")
        $encoding = $TargetEncoding.ToUpperInvariant()
        if ($InputObject -is [string]) {
            $xmlContent = $tryXml.OuterXml
        }
        elseif ($InputObject -is [System.Xml.Linq.XNode]) {
            # System.Xml.Linq types (XDocument, XElement) use ToString(),
            # and the declaration must be prepended for XDocument.
            if ($InputObject -is [System.Xml.Linq.XDocument] -and $InputObject.Declaration) {
                $xmlContent = $InputObject.Declaration.ToString() + "`n" + $InputObject.ToString()
            }
            else {
                $xmlContent = $InputObject.ToString()
            }
        }
        else {
            $xmlContent = $InputObject.OuterXml
        }
        Set-Content `
            -Path $tempFile `
            -Value $xmlContent `
            -Encoding $encoding
        return $tempFile
    }
    else {
        return $InputObject
    }
}
<#
.SYNOPSIS
Resolves a Package URL input to a local file path.
.DESCRIPTION
Resolves the purl through PolyglotPM (fetching it into the local repository if not
already cached) and locates the requested file within the installed package: via
the purl #subpath (relative to the package directory), via the filename qualifier
for package types where it has no download meaning (maven, nuget — searched
recursively within the package directory), or the artifact itself when the purl
resolves to a single file. For github, codeberg, and sourceforge purls the filename
qualifier names the downloadable asset; use #subpath to select a file within those
packages.
.PARAMETER PurlString
The Package URL, e.g. "pkg:maven/org.example/lib@1.0?filename=convert.xpl".
.OUTPUTS
The local file path.
#>
function Resolve-PXPurlInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PurlString
    )
    $purl = ConvertFrom-PkgUri $PurlString
    $paths = Get-PackageFromPurl -Purl $purl
    $packagePath = if ($paths -is [array]) { $paths[0] } else { $paths }

    if (-not $packagePath -or -not (Test-Path $packagePath)) {
        throw "The purl did not resolve to an installed package (purl: $PurlString). For github, codeberg, and sourceforge purls the filename qualifier names the downloadable asset; use #subpath to select a file inside the package."
    }

    $subpath = if ($purl.Subpath) { $purl.Subpath.TrimStart("#") } else { $null }
    $fileName = if ($null -ne $purl.QualifiersParsed) { $purl.QualifiersParsed["filename"] } else { $null }

    if ($subpath) {
        $candidate = Join-Path $packagePath $subpath
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
        throw "File '$subpath' not found within package at '$packagePath' (purl: $PurlString)."
    }

    # For types where the filename qualifier has no download meaning (maven, nuget),
    # it selects the file inside the installed package
    $downloadTypes = @("github", "codeberg", "sourceforge")
    if ($fileName -and $purl.Type -notin $downloadTypes) {
        $matches = @(Get-ChildItem -Path $packagePath -Filter $fileName -Recurse -File -ErrorAction SilentlyContinue)
        if ($matches.Count -eq 0) {
            throw "File '$fileName' not found within package at '$packagePath' (purl: $PurlString)."
        }
        if ($matches.Count -gt 1) {
            $found = ($matches | ForEach-Object { $_.FullName }) -join "', '"
            throw "File '$fileName' is ambiguous within package at '$packagePath': '$found'. Use a #subpath instead."
        }
        return $matches[0].FullName
    }

    if (Test-Path $packagePath -PathType Leaf) {
        return $packagePath
    }
    throw "The purl resolves to a directory at '$packagePath'; specify ?filename= or a #subpath to select a file within it (purl: $PurlString)."
}
<#
.SYNOPSIS
Detects the primary port of an XProc pipeline.
.DESCRIPTION
Returns the name of the pipeline's primary input or output port by inspecting the top-level p:declare-step declaration. Preference order: the port marked primary="true", the only declared port when there is exactly one, and finally the conventional fallback ("source" for inputs, "result" for outputs). Unparseable or non-XProc documents also fall back to the convention.
.PARAMETER PipelinePath
Path to the XProc pipeline document.
.PARAMETER Direction
Whether to inspect input or output ports.
.OUTPUTS
The port name as a string.
#>
function Get-PXPrimaryPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PipelinePath,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Input", "Output")]
        [string]$Direction
    )
    $fallback = if ($Direction -eq "Input") { "source" } else { "result" }
    try {
        [xml]$pipelineXml = Get-Content -Path $PipelinePath -Raw -ErrorAction Stop
    }
    catch {
        return $fallback
    }
    $namespace = @{ p = "http://www.w3.org/ns/xproc" }
    $ports = @(Select-Xml -Xml $pipelineXml -XPath "/p:declare-step/p:$($Direction.ToLower())" -Namespace $namespace)
    if ($ports.Count -eq 0) {
        return $fallback
    }
    foreach ($port in $ports) {
        if ($port.Node.GetAttribute("primary") -in @("true", "1")) {
            return $port.Node.GetAttribute("port")
        }
    }
    if ($ports.Count -eq 1) {
        return $ports[0].Node.GetAttribute("port")
    }
    return $fallback
}
# Session-scoped namespace registry, populated by Register-PXNamespace and merged
# into Transform-PXXml invocations (explicit -Namespace entries take precedence)
$script:NamespaceRegistry = @{}

# Session-scoped composition registry, populated by Register-PXComposition (#12).
# Transform-PXXml uses the selected default composition when no -PackageResolution
# is given, and caches resolved paths so the PolyglotPM engine runs once per
# composition instead of on every call
$script:PXCompositionRegistry = @{}
$script:PXPDefaultComposition = $null

<#
.SYNOPSIS
Registers a named software composition for the session.
.DESCRIPTION
Stores the composition's resolution settings under a session-scoped name for use
by Transform-PXXml (via Select-PXComposition). The composition is resolved
through PolyglotPM on first use and the resolved paths are cached for subsequent
calls. Re-register to refresh a cached composition (relevant with -GetLatest).
.PARAMETER Name
The session-scoped composition name.
.PARAMETER TargetComposition
The composition in the SBOM to resolve. Defaults to the first composition.
.PARAMETER SbomPath
Path to a CycloneDX SBOM XML file. Defaults to the bundled sbom.xml.
.PARAMETER GetLatest
Resolves the latest version for supported package types.
.PARAMETER AdditionalPackages
Purl strings merged into the SBOM before resolution.
.PARAMETER ValidateSbom
Runs XSD schema validation when loading the SBOM.
#>
function Register-PXComposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z_][\w.-]*$")]
        [string]$Name,
        [string]$TargetComposition,
        [string]$SbomPath,
        [switch]$GetLatest,
        [string[]]$AdditionalPackages,
        [switch]$ValidateSbom
    )
    if ($script:PXCompositionRegistry.ContainsKey($Name)) {
        Write-Warning "Composition '$Name' is already registered; overwriting."
    }
    $resolution = @{}
    if ($SbomPath) { $resolution.SbomPath = $SbomPath }
    if ($TargetComposition) { $resolution.TargetComposition = $TargetComposition }
    if ($GetLatest) { $resolution.GetLatest = $true }
    if ($AdditionalPackages) { $resolution.AdditionalPackages = @($AdditionalPackages) }
    if ($ValidateSbom) { $resolution.ValidateSbom = $true }
    $script:PXCompositionRegistry[$Name] = @{
        Resolution = $resolution
        Paths      = $null
    }
}

<#
.SYNOPSIS
Removes registered software compositions from the session.
.DESCRIPTION
Unregisters one or more named compositions. Unknown names are ignored (a verbose
message is written). Removing the selected default clears that selection.
#>
function Unregister-PXComposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Name
    )
    process {
        foreach ($compositionName in $Name) {
            if ($script:PXCompositionRegistry.ContainsKey($compositionName)) {
                $script:PXCompositionRegistry.Remove($compositionName)
                if ($script:PXPDefaultComposition -eq $compositionName) {
                    $script:PXPDefaultComposition = $null
                }
            }
            else {
                Write-Verbose "Composition '$compositionName' was not registered."
            }
        }
    }
}

<#
.SYNOPSIS
Gets the software compositions registered for the session.
.PARAMETER Name
Optional name filter. When omitted, all registered compositions are returned.
.OUTPUTS
One object per registered composition with Name, TargetComposition, SbomPath,
GetLatest, AdditionalPackages, ValidateSbom, Resolved, and Paths properties.
#>
function Get-PXComposition {
    [CmdletBinding()]
    param(
        [string]$Name
    )
    $keys = if ($Name) {
        @($script:PXCompositionRegistry.Keys | Where-Object { $_ -eq $Name })
    }
    else {
        @($script:PXCompositionRegistry.Keys)
    }
    foreach ($key in ($keys | Sort-Object)) {
        $entry = $script:PXCompositionRegistry[$key]
        [PSCustomObject]@{
            Name               = $key
            TargetComposition  = $entry.Resolution.TargetComposition
            SbomPath           = $entry.Resolution.SbomPath
            GetLatest          = [bool]$entry.Resolution.GetLatest
            AdditionalPackages = $entry.Resolution.AdditionalPackages
            ValidateSbom       = [bool]$entry.Resolution.ValidateSbom
            Resolved           = ($null -ne $entry.Paths)
            Paths              = $entry.Paths
            IsDefault          = ($script:PXPDefaultComposition -eq $key)
        }
    }
}

<#
.SYNOPSIS
Selects the default software composition for the session.
.DESCRIPTION
Sets the registered composition used by Transform-PXXml when no -PackageResolution
is given. Explicit -PackageResolution entries always take precedence.
.PARAMETER Name
The registered composition to select.
#>
function Select-PXComposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    if (-not $script:PXCompositionRegistry.ContainsKey($Name)) {
        throw "Composition '$Name' is not registered. Register it with Register-PXComposition first."
    }
    $script:PXPDefaultComposition = $Name
}

<#
.SYNOPSIS
Registers a namespace prefix for the session.
.DESCRIPTION
Adds a prefix-to-URI mapping to the session-scoped registry. Transform-PXXml merges the registry with its -Namespace parameter (explicit parameter entries take precedence) when invoking XProc processors.
.PARAMETER Prefix
The namespace prefix, e.g. "pre" for use with namespaced options like "pre:opt".
.PARAMETER Uri
The namespace URI the prefix maps to.
#>
function Register-PXNamespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z_][\w.-]*$")]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )
    if ($script:NamespaceRegistry.ContainsKey($Prefix) -and $script:NamespaceRegistry[$Prefix] -ne $Uri) {
        Write-Warning "Prefix '$Prefix' was registered to '$($script:NamespaceRegistry[$Prefix])'; overwriting with '$Uri'."
    }
    $script:NamespaceRegistry[$Prefix] = $Uri
}

<#
.SYNOPSIS
Removes namespace prefixes from the session registry.
.DESCRIPTION
Unregisters one or more prefixes. Unknown prefixes are ignored (a verbose message is written). Accepts pipeline input from Get-PXNamespace.
.PARAMETER Prefix
The namespace prefix(es) to remove.
#>
function Unregister-PXNamespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Prefix
    )
    process {
        # NOTE: the loop variable must not differ from $Prefix by case alone —
        # PowerShell variables are case-insensitive, so a [string[]]-typed
        # parameter would coerce each element back into an array on assignment
        foreach ($prefixName in $Prefix) {
            if ($script:NamespaceRegistry.ContainsKey($prefixName)) {
                $script:NamespaceRegistry.Remove($prefixName)
            }
            else {
                Write-Verbose "Prefix '$prefixName' was not registered."
            }
        }
    }
}

<#
.SYNOPSIS
Gets the namespace prefixes registered for the session.
.PARAMETER Prefix
Optional prefix filter. When omitted, all registered prefixes are returned.
.OUTPUTS
One object per registered prefix with Prefix and Uri properties.
#>
function Get-PXNamespace {
    [CmdletBinding()]
    param(
        [string]$Prefix
    )
    $keys = if ($Prefix) {
        @($script:NamespaceRegistry.Keys | Where-Object { $_ -eq $Prefix })
    }
    else {
        @($script:NamespaceRegistry.Keys)
    }
    foreach ($key in ($keys | Sort-Object)) {
        [PSCustomObject]@{
            Prefix = $key
            Uri    = $script:NamespaceRegistry[$key]
        }
    }
}
<#
.SYNOPSIS
Transforms inputs using XML technologies
.PARAMETER Processing
The kind of processing to run. Default xproc.
.PARAMETER Processor
The specific processor to use.
.PARAMETER PackageResolution
A hashtable that groups polyglot package manager settings for XProc processing:
  SbomPath            - Path to a CycloneDX SBOM XML file. Defaults to the bundled sbom.xml.
  TargetComposition   - The composition in the SBOM to resolve. Defaults to the first composition.
  GetLatest           - When $true, resolves the latest version for supported package types
                        (codeberg, github) via their release API, replacing the SBOM-pinned version.
  AdditionalPackages  - A single purl string or array of purls to merge into the SBOM.
                        Matching components (same type/namespace/name) have their version replaced
                        and hashes removed. Non-matching purls are added as new components.
                        When no sbomPath is available, an interstitial SBOM is created from these.
  ValidateSbom        - When $true, runs XSD schema validation against the CycloneDX bom-1.5.xsd
                        schema when loading the SBOM. Throws on validation errors.
.PARAMETER InPort
A hashtable of ports bound to inputs, e.g. @{input1='file1.xml', input2='file2.xml}. A single value (a path, XML string or object, or an array of documents for sequences) binds to the pipeline's primary input port.
.PARAMETER OutPort
A hashtable of ports bound to outputs, e.g. @{result='output.xml'}. A single value (a path) binds to the pipeline's primary output port.
.PARAMETER Catalog
The path to an XML catalog file to use for resolving XML resources.
.PARAMETER Passthrough
An array of parameters passed directly to the processor.
.PARAMETER PassthroughJava
An array of parameters passed directly to the Java JVM.
.PARAMETER MergeOutput
Merges the STDOUT and STDERR of the processor into a single stream. Default is true.
.PARAMETER Namespace
A hashtable of namespace prefixes and URIs to use when processing the pipeline, e.g. @{ pre = "http://example.com/pre" }. Merged with the session-scoped registry (see Register-PXNamespace); explicit entries here take precedence.
.PARAMETER Configuration
Either a path to a processor configuration file, or a hashtable of configuration settings (1-1 with the engine's XML/JSON shape). Hashtables are merged over MorganaXProc's auto-detected defaults; when omitted, the defaults are injected automatically.
.PARAMETER MultiplexOutput
XProc only. When set, all outputs (STDOUT documents plus any bound output ports) are additionally written to this file as a multipart/mixed message with an X-Port header per part, suitable for feeding back as input. STDOUT documents are labeled with the conventional "result" port.
.PARAMETER ClassPath
XProc only. A ready-made Java classpath used verbatim (order preserved), bypassing PolyglotPM dependency resolution and processor discovery entirely — for tools that manage their own jars. Use -PassthroughJava for JVM options such as javaagents and -Configuration to supply a processor config file. When -ClassPath is given without -Configuration, no config is generated.
#>
function Transform-PXXml {
    [CmdletBinding(DefaultParameterSetName = "Pipeline")]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,        
        [ValidateSet("xproc", "xslt")]
        $Processing = "xproc",
        [ValidateSet("xmlcalabash", "morganaxproc", "dotnet", "msxml", "altova", "xsltproc", "phoenixml")]
        $Processor = "xmlcalabash",
        [hashtable]$PackageResolution,
        [Parameter(Mandatory = $true, ParameterSetName = "Pipeline")]
        $Pipeline,
        [Parameter(Mandatory = $true, ParameterSetName = "Step")]
        [string]$Step,
        [Alias("parameters")]
        [hashtable]$Options,
        $InPort,
        $OutPort,
        [string]$Catalog,
        [array]$Passthrough,
        [array]$PassthroughJava,
        [bool]$MergeOutput = $true,
        [hashtable]$Namespace,
        $Configuration,
        [switch]$CollectOutput,
        [string]$MultiplexOutput,
        [string]$ClassPath
    )
    
    if ($PSCmdlet.ParameterSetName -eq "Step" -and $Processing -ne "xproc") {
        throw "-Step is only supported for XProc processing. Use -Pipeline to run XSLT stylesheets."
    }
    if ($MultiplexOutput -and $Processing -ne "xproc") {
        throw "-MultiplexOutput is only supported for XProc processing."
    }
    if ($ClassPath -and $Processing -ne "xproc") {
        throw "-ClassPath is only supported for XProc processing."
    }

    $pipelinePath = $null
    if ($PSCmdlet.ParameterSetName -eq "Pipeline") {
        $pipelinePath = Resolve-PXXmlInput -InputObject $Pipeline -Extension "xpl"
    }

    # Merge the session-scoped namespace registry (Register-PXNamespace) with the
    # -Namespace parameter; explicit parameter entries take precedence
    $registeredNamespaces = @(Get-PXNamespace)
    $effectiveNamespace = $null
    if ($Namespace -or $registeredNamespaces.Count -gt 0) {
        $effectiveNamespace = @{}
        foreach ($registered in $registeredNamespaces) {
            $effectiveNamespace[$registered.Prefix] = $registered.Uri
        }
        if ($Namespace) {
            foreach ($key in $Namespace.Keys) {
                $effectiveNamespace[$key] = $Namespace[$key]
            }
        }
    }

    # Resolve the step QName for direct step execution; unprefixed names get "p:"
    # and prefixes resolve through the effective namespace map ("p" is built in)
    $stepQName = $null
    if ($PSCmdlet.ParameterSetName -eq "Step") {
        $stepPrefix, $stepLocal = $Step -split ":", 2
        if (-not $stepLocal) {
            $stepQName = "p:$Step"
        }
        else {
            $xprocNamespace = "http://www.w3.org/ns/xproc"
            $prefixUri = if ($stepPrefix -eq "p") {
                $xprocNamespace
            }
            elseif ($effectiveNamespace -and $effectiveNamespace.ContainsKey($stepPrefix)) {
                $effectiveNamespace[$stepPrefix]
            }
            else {
                $null
            }
            if (-not $prefixUri) {
                throw "Step namespace prefix '$stepPrefix' is not bound. Register it with Register-PXNamespace or pass -Namespace."
            }
            $stepQName = $Step
        }
    }

    # Normalize single values (or arrays of documents) into default-port bindings.
    # Named hashtables are passed through unchanged. Direct step execution binds
    # to the conventional ports since there is no pipeline to introspect.
    if ($null -ne $InPort -and $InPort -isnot [hashtable] -and $InPort -isnot [System.Collections.Specialized.OrderedDictionary] -and @($InPort).Count -gt 0) {
        $portName = if ($Processing -eq "xproc") {
            if ($stepQName) { "source" } else { Get-PXPrimaryPort -PipelinePath $pipelinePath -Direction Input }
        }
        else {
            "source"
        }
        $InPort = @{ $portName = $InPort }
    }
    if ($null -ne $OutPort -and $OutPort -isnot [hashtable] -and $OutPort -isnot [System.Collections.Specialized.OrderedDictionary] -and @($OutPort).Count -gt 0) {
        $portName = if ($Processing -eq "xproc") {
            if ($stepQName) { "result" } else { Get-PXPrimaryPort -PipelinePath $pipelinePath -Direction Output }
        }
        else {
            "result"
        }
        $OutPort = @{ $portName = $OutPort }
    }
    # Multipart/mixed input files are parsed and their parts routed to ports by
    # their X-Port headers; parts without an X-Port go to the port the file was
    # bound to (#35)
    if ($InPort) {
        $expandedInPort = @{}
        foreach ($key in @($InPort.Keys)) {
            $val = $InPort[$key]
            $candidate = if ($val -is [string]) { $val } else { $null }
            $isMime = $false
            $boundary = $null
            if ($candidate -and (Test-Path $candidate -PathType Leaf)) {
                $firstLine = (Get-Content -Path $candidate -TotalCount 1 -ErrorAction SilentlyContinue)
                if ($firstLine -and $firstLine.Trim().StartsWith("--")) {
                    # Strip exactly the leading "--" delimiter; the boundary itself
                    # may legitimately begin with dashes
                    $boundary = $firstLine.Trim().Substring(2)
                    $mimeString = Get-Content -Path $candidate -Raw
                    # Confirm it is really a multipart message via the end marker
                    $isMime = $mimeString.Contains("--$boundary--")
                }
            }
            if ($isMime) {
                foreach ($mimePart in @(Parse-PXMimeMultipart -MimeString $mimeString -Boundary $boundary)) {
                    $partPort = if ($mimePart.Headers["X-Port"]) { $mimePart.Headers["X-Port"] } else { $key }
                    $contentType = $mimePart.Headers["Content-Type"]
                    $mediaType = if ($contentType) { ($contentType -split ';', 2)[0].Trim() } else { '' }
                    $extension = if ($mediaType -in @('application/xml', 'text/xml') -or $mediaType -like '*+xml') { '.xml' } else { '.txt' }
                    $partFile = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, $extension)
                    Set-Content -Path $partFile -Value $mimePart.Content -Encoding UTF8
                    if ($expandedInPort.ContainsKey($partPort)) {
                        $existing = $expandedInPort[$partPort]
                        $expandedInPort[$partPort] = if ($existing -is [array]) { $existing + $partFile } else { @($existing, $partFile) }
                    }
                    else {
                        $expandedInPort[$partPort] = $partFile
                    }
                }
            }
            else {
                $expandedInPort[$key] = $val
            }
        }
        $InPort = $expandedInPort
    }
    
    $inPortProcessed = $null
    if ($InPort) {
        $inPortProcessed = @{}
        foreach ($key in $InPort.Keys) {
            $val = $InPort[$key]
            $inPortProcessed[$key] = Resolve-PXXmlInput -InputObject $val -Extension "xml"
        }
    }
    if ($Processing -eq "xproc") {
        $localRepository = Get-LocalRepositoryPath

        # A ready-made classpath bypasses dependency resolution and processor
        # discovery entirely — the caller owns the jars (#8)
        if ($ClassPath) {
            [array]$Paths = @()
        }
        else {
            # Effective resolution (#12): explicit -PackageResolution wins, then the
            # session default composition (Select-PXComposition), then bundled defaults.
            # Registered compositions resolve once and cache their paths.
            $effectiveResolution = $PackageResolution
            $registryEntry = $null
            if (-not $effectiveResolution -and $script:PXPDefaultComposition) {
                $registryEntry = $script:PXCompositionRegistry[$script:PXPDefaultComposition]
                if ($registryEntry) {
                    $effectiveResolution = $registryEntry.Resolution
                }
            }

            if ($registryEntry -and $registryEntry.Paths) {
                [array]$Paths = $registryEntry.Paths
            }
            else {
                $sbomPath = if ($effectiveResolution -and $effectiveResolution.SbomPath) { $effectiveResolution.SbomPath } else { "$PSScriptRoot\sbom.xml" }
                $targetComposition = if ($effectiveResolution) { $effectiveResolution.TargetComposition } else { $null }
                $getLatest = if ($effectiveResolution) { [bool]$effectiveResolution.GetLatest } else { $false }
                $additionalPackages = if ($effectiveResolution -and $effectiveResolution.AdditionalPackages) {
                    @($effectiveResolution.AdditionalPackages)
                }
                else { $null }
                $validateSbom = if ($effectiveResolution) { [bool]$effectiveResolution.ValidateSbom } else { $false }

                $compositionParams = @{
                    SbomPath        = $sbomPath
                    LocalRepository = $localRepository
                }
                if ($targetComposition) {
                    $compositionParams.TargetComposition = $targetComposition
                }
                if ($getLatest) {
                    $compositionParams.GetLatest = $true
                }
                if ($additionalPackages) {
                    $compositionParams.AdditionalPackages = $additionalPackages
                }
                if ($validateSbom) {
                    $compositionParams.ValidateSbom = $true
                }

                [array]$Paths = Copy-SoftwareComposition @compositionParams | Select-Object -Unique
                if ($registryEntry) {
                    $registryEntry.Paths = $Paths
                }
            }
        }

        $result = $null
        if ($Processor -eq "xmlcalabash") {
            $result = Invoke-XmlCalabash `
                -Paths $Paths `
                -ClassPath $ClassPath `
                -Configuration $Configuration `
                -InputObject $InputObject `
                -Step $stepQName `
                -Pipeline $pipelinePath `
                -Options $Options `
                -InPort $inPortProcessed `
                -OutPort $OutPort `
                -Catalog $Catalog `
                -Passthrough $Passthrough `
                -PassthroughJava $PassthroughJava `
                -MergeOutput $MergeOutput `
                -Namespace $effectiveNamespace `
                -CollectOutput:($CollectOutput -and -not $MultiplexOutput)
        }
        elseif ($Processor -eq "morganaxproc") {
            # MorganaXProc has no step-run CLI: synthesize a wrapper pipeline (#9)
            $morganaPipelinePath = $pipelinePath
            if ($stepQName) {
                $morganaPipelinePath = New-PXStepShell -Step $stepQName `
                    -Namespaces $effectiveNamespace `
                    -InPort $inPortProcessed `
                    -OutPort $OutPort `
                    -Options $Options
            }
            try {
                $result = Invoke-MorganaXProc `
                    -Paths $Paths `
                    -ClassPath $ClassPath `
                    -InputObject $InputObject `
                    -Pipeline $morganaPipelinePath `
                    -Options $Options `
                    -InPort $inPortProcessed `
                    -OutPort $OutPort `
                    -Catalog $Catalog `
                    -Passthrough $Passthrough `
                    -PassthroughJava $PassthroughJava `
                    -MergeOutput $MergeOutput `
                    -Namespace $effectiveNamespace `
                    -Configuration $Configuration `
                    -CollectOutput:($CollectOutput -and -not $MultiplexOutput)
            }
            finally {
                if ($stepQName -and $morganaPipelinePath -and (Test-Path $morganaPipelinePath -PathType Leaf)) {
                    Remove-Item -Path $morganaPipelinePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            throw "Unsupported processor $Processor for processing type $Processing"
        }

        # Collect all outputs (STDOUT plus bound output ports) into one
        # multipart/mixed file with X-Port headers per part (#35)
        if ($MultiplexOutput) {
            $parts = @()
            $collectedFromFiles = @()
            foreach ($doc in @($result)) {
                $parts += @{ Port = "result"; Content = $doc }
            }
            if ($OutPort) {
                foreach ($key in @($OutPort.Keys)) {
                    $filePath = $OutPort[$key]
                    if ($filePath -is [string] -and (Test-Path $filePath -PathType Leaf)) {
                        $fileContent = Get-Content -Path $filePath -Raw
                        foreach ($doc in @($fileContent | Get-PXMultiXmlDocuments)) {
                            $parts += @{ Port = $key; Content = $doc }
                            if ($CollectOutput) {
                                $collectedFromFiles += $doc
                            }
                        }
                    }
                }
            }
            ConvertTo-PXMimeMultipart -Parts $parts -Path $MultiplexOutput | Out-Null
            if ($CollectOutput) {
                $result = @($result | Where-Object { $null -ne $_ }) + $collectedFromFiles
            }
        }
        return $result
    }
    elseif ($Processing -eq "xslt") {
        # For XSLT processing:
        # - pipeline parameter is the stylesheet
        # - inPort with 'source' key is the input XML
        # - outPort with 'result' key is the output file (optional)
        # - options are XSLT parameters
        
        $stylesheetPath = Resolve-PXXmlInput -InputObject $Pipeline -Extension "xsl"
        
        # Get input XML from inPort 'source' key, or use first value
        $inputXmlPath = $null
        if ($inPortProcessed -and $inPortProcessed.Count -gt 0) {
            if ($inPortProcessed.ContainsKey('source')) {
                $inputXmlPath = $inPortProcessed['source']
            }
            else {
                $inputXmlPath = $inPortProcessed.Values | Select-Object -First 1
            }
        }
        
        if (-not $inputXmlPath) {
            throw "XSLT processing requires input XML. Use -InPort @{source = 'input.xml'}"
        }
        
        # Get output file from outPort 'result' key, or use first value
        $outputFilePath = $null
        if ($OutPort -and $OutPort.Count -gt 0) {
            if ($OutPort.ContainsKey('result')) {
                $outputFilePath = $OutPort['result']
            }
            else {
                $outputFilePath = $OutPort.Values | Select-Object -First 1
            }
        }
        
        if ($Processor -eq "dotnet") {
            return Invoke-DotNetXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $Options
        }
        elseif ($Processor -eq "msxml") {
            return Invoke-MsxmlXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $Options
        }
        elseif ($Processor -eq "xsltproc") {
            return Invoke-XsltprocXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $Options
        }
        elseif ($Processor -eq "altova") {
            return Invoke-AltovaXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $Options
        }
        elseif ($Processor -eq "phoenixml") {
            # Phoenixml requires NuGet package resolution
            $localRepository = Get-LocalRepositoryPath
            $sbomPath = if ($PackageResolution -and $PackageResolution.SbomPath) { $PackageResolution.SbomPath } else { $null }
            $targetComposition = if ($PackageResolution) { $PackageResolution.TargetComposition } else { $null }
            $getLatest = if ($PackageResolution) { [bool]$PackageResolution.GetLatest } else { $false }
            $additionalPackages = if ($PackageResolution -and $PackageResolution.AdditionalPackages) {
                @($PackageResolution.AdditionalPackages)
            }
            else { $null }
            $validateSbom = if ($PackageResolution) { [bool]$PackageResolution.ValidateSbom } else { $false }

            $compositionParams = @{
                LocalRepository = $localRepository
            }
            if ($sbomPath) {
                $compositionParams.SbomPath = $sbomPath
            }
            if ($targetComposition) {
                $compositionParams.TargetComposition = $targetComposition
            }
            if ($getLatest) {
                $compositionParams.GetLatest = $true
            }
            if ($validateSbom) {
                $compositionParams.ValidateSbom = $true
            }

            # Default AdditionalPackages for phoenixml when no SBOM or packages specified
            if (-not $sbomPath -and -not $additionalPackages) {
                $additionalPackages = @(
                    'pkg:nuget/PhoenixmlDb.Core@1.0.13',
                    'pkg:nuget/PhoenixmlDb.XQuery@1.0.5',
                    'pkg:nuget/PhoenixmlDb.Xslt@1.0.0'
                )
            }
            if ($additionalPackages) {
                $compositionParams.AdditionalPackages = $additionalPackages
            }

            [array]$Paths = Copy-SoftwareComposition @compositionParams | Select-Object -Unique

            return Invoke-PhoenixmlXslt `
                -Stylesheet $stylesheetPath `
                -InputXml $inputXmlPath `
                -OutputFile $outputFilePath `
                -Parameters $Options `
                -AssemblyPaths $Paths
        }
        else {
            throw "Unsupported processor '$Processor' for processing type 'xslt'. Supported processors: dotnet, msxml, xsltproc, altova, phoenixml"
        }
    }
    else {
        throw "Unsupported processing type '$Processing'. Supported types: xproc, xslt"
    }
    # Clean up temp file if created
    #  if ($null -ne $tempPipelineFile -and (Test-Path $tempPipelineFile)) {
    #      Remove-Item -Path $tempPipelineFile -Force -ErrorAction SilentlyContinue
    #  }
}
