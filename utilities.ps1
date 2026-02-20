#region MIME Multipart Parser
<#
.SYNOPSIS
    Parses a MIME multipart message and returns an array of hashtables representing each part.
.DESCRIPTION
    Accepts a string containing a MIME multipart message and a boundary string.
    Returns an array of hashtables with keys: Headers, Content.
#>
function Parse-MimeMultipart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $MimeString,
        [Parameter(Mandatory)]
        [string] $Boundary
    )
    $parts = [System.Collections.ArrayList]::new()
    $startBoundary = "--$Boundary"
    $endBoundary = "--$Boundary--"
    
    # Normalize line endings to LF for consistent processing
    $normalized = $MimeString -replace "`r`n", "`n"
    
    # Split into lines
    $lines = $normalized -split "`n"
    
    $currentPart = $null
    $inHeaders = $false
    $headerLines = [System.Collections.ArrayList]::new()
    $contentLines = [System.Collections.ArrayList]::new()
    $foundEndBoundary = $false
    
    foreach ($line in $lines) {
        if ($line -eq $endBoundary -or $line.Trim() -eq $endBoundary) {
            # End of multipart - save current part if exists
            if ($null -ne $currentPart) {
                $currentPart.Content = ($contentLines -join "`n").Trim()
                [void]$parts.Add($currentPart)
            }
            $foundEndBoundary = $true
            break
        }
        elseif ($line -eq $startBoundary -or $line.Trim() -eq $startBoundary) {
            # Save previous part if exists
            if ($null -ne $currentPart) {
                $currentPart.Content = ($contentLines -join "`n").Trim()
                [void]$parts.Add($currentPart)
            }
            # Start new part
            $currentPart = @{ Headers = @{}; Content = "" }
            $inHeaders = $true
            $headerLines = [System.Collections.ArrayList]::new()
            $contentLines = [System.Collections.ArrayList]::new()
        }
        elseif ($null -ne $currentPart) {
            if ($inHeaders) {
                if ($line -eq "" -or $line -match "^\s*$") {
                    # Empty line marks end of headers
                    $inHeaders = $false
                    # Parse accumulated headers (already unfolded)
                    foreach ($headerLine in $headerLines) {
                        if ($headerLine -match "^([^:]+):\s*(.*)$") {
                            $currentPart.Headers[$matches[1].Trim()] = $matches[2].Trim()
                        }
                    }
                }
                elseif ($line -match "^[\s\t]+" -and $headerLines.Count -gt 0) {
                    # Folded header continuation - append to previous header line
                    # Replace leading whitespace with a single space per RFC 2822
                    $continuation = $line -replace "^[\s\t]+", " "
                    $lastIndex = $headerLines.Count - 1
                    $headerLines[$lastIndex] = $headerLines[$lastIndex] + $continuation
                }
                else {
                    [void]$headerLines.Add($line)
                }
            }
            else {
                [void]$contentLines.Add($line)
            }
        }
    }
    
    # Handle case where message doesn't end with end boundary
    if (-not $foundEndBoundary -and $null -ne $currentPart) {
        $currentPart.Content = ($contentLines -join "`n").Trim()
        [void]$parts.Add($currentPart)
    }
    
    # Output each part individually for proper pipeline support
    # This allows: Parse-MimeMultipart | ConvertTo-NativeType | ForEach-Object {...}
    foreach ($part in $parts) {
        Write-Output $part
    }
}
#region MimeContent Wrapper Class
# Define a .NET class to wrap content when MIME type doesn't map to native types
if (-not ('PowerXML.MimeContent' -as [type])) {
    Add-Type -TypeDefinition @'
namespace PowerXML
{
    public class MimeContent
    {
        public string ContentType { get; set; }
        public string Charset { get; set; }
        public string ContentDisposition { get; set; }
        public string ContentDescription { get; set; }
        public string RawContent { get; set; }
        public byte[] BinaryContent { get; set; }
        public System.Collections.Generic.Dictionary<string, string> Headers { get; set; }

        public MimeContent()
        {
            Headers = new System.Collections.Generic.Dictionary<string, string>();
        }

        public override string ToString()
        {
            return string.Format("MimeContent[{0}]: {1} bytes", 
                ContentType ?? "unknown", 
                BinaryContent != null ? BinaryContent.Length : (RawContent != null ? RawContent.Length : 0));
        }
    }
}
'@
}
#endregion

#region ConvertTo-NativeType
<#
.SYNOPSIS
    Attempts to convert MIME multipart content to native PowerShell/.NET types based on Content-Type.
.DESCRIPTION
    Given a MIME part (hashtable with Headers and Content), this function attempts to convert
    the content to an appropriate native type:
    - application/xml, text/xml -> [System.Xml.XmlDocument]
    - application/json -> PSCustomObject (via ConvertFrom-Json)
    - text/plain, text/html, text/* -> [string]
    - Unknown types are wrapped in a PowerXML.MimeContent object
.PARAMETER MimePart
    A hashtable containing Headers and Content keys, as returned by Parse-MimeMultipart.
.OUTPUTS
    The converted native type, or a PowerXML.MimeContent wrapper for unknown types.
#>
function ConvertTo-NativeType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable] $MimePart
    )
    
    process {
        $headers = $MimePart.Headers
        $content = $MimePart.Content
        
        # Parse Content-Type header
        $contentTypeHeader = $headers['Content-Type']
        $mimeType = $null
        $charset = 'UTF-8'  # Default charset
        
        if ($contentTypeHeader) {
            # Parse "application/json; charset=UTF-8" format
            $parts = $contentTypeHeader -split ';'
            $mimeType = $parts[0].Trim().ToLowerInvariant()
            
            foreach ($part in $parts[1..($parts.Count - 1)]) {
                if ($part -match 'charset\s*=\s*([^\s;]+)') {
                    $charset = $matches[1].Trim('"', "'")
                }
            }
        }
        
        # Attempt conversion based on MIME type
        switch -Regex ($mimeType) {
            '^application/xml$|^text/xml$|^application/.*\+xml$' {
                try {
                    $xmlDoc = [System.Xml.XmlDocument]::new()
                    $xmlDoc.LoadXml($content)
                    return $xmlDoc
                }
                catch {
                    Write-Warning "Failed to parse XML content: $_"
                    # Fall through to wrapper
                }
            }
            
            '^application/json$|^application/.*\+json$' {
                try {
                    return ($content | ConvertFrom-Json)
                }
                catch {
                    Write-Warning "Failed to parse JSON content: $_"
                    # Fall through to wrapper
                }
            }
            
            '^text/' {
                # Return text types as strings directly
                return $content
            }
            
            '^image/|^audio/|^video/|^application/octet-stream$' {
                # Binary types - decode if base64 encoded, otherwise wrap
                $wrapper = [PowerXML.MimeContent]::new()
                $wrapper.ContentType = $mimeType
                $wrapper.Charset = $charset
                $wrapper.ContentDisposition = $headers['Content-Disposition']
                $wrapper.ContentDescription = $headers['Content-Description']
                $wrapper.RawContent = $content
                foreach ($key in $headers.Keys) {
                    $wrapper.Headers[$key] = $headers[$key]
                }
                
                # Try to decode as base64
                try {
                    $wrapper.BinaryContent = [Convert]::FromBase64String($content)
                }
                catch {
                    # Not base64, store raw bytes
                    $encoding = [System.Text.Encoding]::GetEncoding($charset)
                    $wrapper.BinaryContent = $encoding.GetBytes($content)
                }
                
                return $wrapper
            }
        }
        
        # Unknown or unhandled type - wrap in MimeContent
        $wrapper = [PowerXML.MimeContent]::new()
        $wrapper.ContentType = $mimeType
        $wrapper.Charset = $charset
        $wrapper.ContentDisposition = $headers['Content-Disposition']
        $wrapper.ContentDescription = $headers['Content-Description']
        $wrapper.RawContent = $content
        foreach ($key in $headers.Keys) {
            $wrapper.Headers[$key] = $headers[$key]
        }
        
        # Store as bytes using the specified charset
        try {
            $encoding = [System.Text.Encoding]::GetEncoding($charset)
            $wrapper.BinaryContent = $encoding.GetBytes($content)
        }
        catch {
            $wrapper.BinaryContent = [System.Text.Encoding]::UTF8.GetBytes($content)
        }
        
        return $wrapper
    }
}
#endregion

<#
.SYNOPSIS
Ensures PowerShell and required modules are installed.
#>
function Confirm-Prerequisites {
    [CmdletBinding()]
    param(
        [string]$RequirementsPath = (Join-Path -Path $PSScriptRoot -ChildPath '../requirements.psd1')
    )

    # Ensure PowerShell Core 7.4+
    # $psv = $PSVersionTable.PSVersion
    # if ($psv.Major -lt 7 -or ($psv.Major -eq 7 -and $psv.Minor -lt 4)) {
    #     throw "PowerShell Core 7.4 or later is required. Current version: $psv"
    # }

    Write-Host "PowerShell version $psv detected."

    # Read requirements.psd1
    if (-not (Test-Path $RequirementsPath)) {
        throw "Could not find requirements file at $RequirementsPath"
    }
    $ModuleRequirements = Import-PowerShellDataFile -Path $RequirementsPath

    foreach ($module in $ModuleRequirements.Keys) {
        $requiredVersion = $ModuleRequirements[$module]
        $installed = Get-Module -ListAvailable -Name $module | Where-Object {
            $_.Version -like $requiredVersion -or ($requiredVersion -eq '*' -or $_.Version.ToString() -like $requiredVersion)
        }
        if (-not $installed) {      
            #use native pwsh prompting confirm Y/N/A
            $confirm = Read-Host "Module $module ($requiredVersion) is not installed. Would you like to install it now? (yes/no)"        
            if ($confirm -notmatch '^[Yy]') {
                Write-Host "Installing module $module ($requiredVersion) from PowerShell Gallery..."
                $installParams = @{
                    Name            = $module
                    RequiredVersion = if ($requiredVersion -ne '*') { $requiredVersion } else { $null }
                    Force           = $true
                    AllowClobber    = $true
                    Scope           = 'CurrentUser'
                    AllowPrerelease = $true
                }
                if (-not $installParams.RequiredVersion) { $installParams.Remove('RequiredVersion') }
                Install-Module @installParams
            }
            else {
                $prerequisitesMet = $false
            }
        }    
        else {
            Write-Host "Module $module ($requiredVersion) is already installed."
        }
    }
    if (-not $prerequisitesMet) {
        throw "Not all prerequisites are satisfied. Please install the required modules and try again."
    }
    Write-Host "All prerequisites are satisfied."
}
function Import-EnvironmentVariables {
    [CmdletBinding()]
    param(
        [string]$path
    )
    $envData = Import-PowerShellDataFile $path
    $envData.GetEnumerator() | ForEach-Object {
        [Environment]::SetEnvironmentVariable($_.Key, $_.Value, "Process")
    }
}


function Start-SleepWithProgress {
    [Alias('s')]
    [CmdletBinding()]
    param(
        [int]$seconds
    )
    $cps = Get-CommonParameterSubset -Bound $PSBoundParameters
    # Loop Number of seconds you want to sleep
    for ($i = 0; $i -le $seconds; $i++) {
        $timeleft = ($seconds - $i);

        # Progress bar showing progress of the sleep
        Write-Progress -Activity "Sleeping" -CurrentOperation "$Timeleft More Seconds" -PercentComplete (($i / $seconds) * 100);

        # Sleep 1 second
        Start-Sleep -s 1
    }

    Write-Progress -Completed -Activity "Sleeping"
}

<#
.SYNOPSIS
    Retries a script block upon failure, with configurable delay and backoff strategies.
.PARAMETER ScriptBlock
    The script block to execute.
.PARAMETER MaxRetries
    The maximum number of retry attempts. Default is 10.
.PARAMETER DelaySeconds
    The initial delay in seconds before retrying. Default is 2 seconds. Will increase by 1 second on each retry.
.PARAMETER ExponentialBackoff
    If specified, the delay will double after each retry.
.PARAMETER IsTransientError
    A script block that checks if an error is transient. It receives the error
     record as a parameter and should return $true for transient errors. Only 
     transient errors will be retried.
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock] $ScriptBlock,
        [int] $MaxRetries = 20,
        [int] $DelaySeconds = 2,
        [switch] $ExponentialBackoff,
        [ScriptBlock] $IsTransientError = {
            param($errorRecord)
            # Default transient error check: network timeout or 5xx HTTP status      
            return ($errorRecord -match 'MsGraph|MS Graph|Specified HTTP method is not allowed|No such host is known|not found|does not exist|not iterable|timeout|temporarily|503|502|504|404|Retrying|invalid usage location')
        }
    )
    $cps = Get-CommonParameterSubset -Bound $PSBoundParameters
    $attempt = 0
    $success = $false
    $lastError = $null

    while (-not $success -and $attempt -lt $MaxRetries) {
        try {
            $attempt++
            Write-Verbose "Attempt $attempt of $MaxRetries..."
            return & $ScriptBlock
            $success = $true
        }
        catch {
            $lastError = $_
            if (& $IsTransientError $lastError) {
                Write-Verbose "Transient error encountered: $($lastError). Retrying..."
                if ($ExponentialBackoff) {
                    $DelaySeconds *= 2
                }
                else {
                    $DelaySeconds += $attempt
                }
                Start-SleepWithProgress -Seconds $DelaySeconds @cps
            }
            else {
                Write-Error "NON-transient error encountered. Not retrying."
                throw $lastError
            }
        }
    }

    throw "Operation failed after $MaxRetries attempts. Last error: $($lastError)"
}

function Get-CommonParameterSubset {
    param([hashtable]$Bound)

    $allowed = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'Confirm', 'WhatIf')
    $subset = @{}
    foreach ($key in $allowed) {
        if ($Bound.ContainsKey($key)) {
            $subset[$key] = $Bound[$key]
        }
    }
    return $subset
}

function Expect-NotNullOrEmpty {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Value,
        #404 is there to force a retry when used with Invoke-WithRetry
        [string] $Message = "Expected value to be not null. Retrying..."
    )
    if ($null -eq $Value -or $Value -is [array] -and $Value.Count -eq 0) {
        throw $Message
    }
    return $Value
}

<#
.SYNOPSIS
Loads a certificate from a PFX file.
.PARAMETER pfxPath
The path to the PFX file. Required.
.PARAMETER pfxPassword
The password for the PFX file. Required.
#>
function Get-Certificate {
    param(
        [string]$pfxPath,
        [securestring]$pfxPassword 
    )
    # Check file extension for .p12 or .pfx
    $ext = [System.IO.Path]::GetExtension($pfxPath)
    if ($ext -eq ".p12" -or $ext -eq ".pfx") {
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $pfxPath,
            $pfxPassword, 
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }
    else {
        throw "Unsupported certificate file extension: $ext. Only .pfx and .p12 are supported."
    }
}
function ConvertTo-HashString {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InputString
    )
    $stringAsStream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.StreamWriter]::new($stringAsStream)
    $writer.Write($InputString)
    $writer.Flush()
    $stringAsStream.Position = 0
    return (Get-FileHash -InputStream $stringAsStream).Hash
}

