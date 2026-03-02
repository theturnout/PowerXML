#Remove-Item -Path $libPath -Recurse -Force -ErrorAction SilentlyContinue
#if (-not (Test-Path $libPath)) {
#    New-Item -ItemType Directory -Path $libPath | Out-Null
#}


$hashAlgorithm = "SHA256"

<#
.SYNOPSIS
    Validates a file's hash against an expected value.
.PARAMETER Path
    Path to the file to validate.
.PARAMETER ExpectedHash
    The expected hash value (hex string).
.PARAMETER Algorithm
    Hash algorithm to use. Defaults to SHA256.
.OUTPUTS
    Returns the computed hash string on success.
.NOTES
    Throws if the computed hash does not match the expected hash.
#>
function Test-FileHash {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedHash,
        [string]$Algorithm = "SHA256"
    )

    $computed = Get-FileHash -Path $Path -Algorithm $Algorithm
    if ($computed.Hash -ne $ExpectedHash) {
        throw "Hash mismatch for '$(Split-Path $Path -Leaf)'. Expected: $ExpectedHash, Actual: $($computed.Hash)"
    }
    return $computed.Hash
}

# Function to list GitHub releases
function Get-GitHubReleases {
    [CmdletBinding()]
    param (
        [string]$RepoOwner,
        [string]$RepoName
    )

    # Define the API URL
    $url = "https://api.github.com/repos/$RepoOwner/$RepoName/releases"

    try {
        # Make the API request
        $response = Invoke-RestMethod -Uri $url -UseBasicParsing

        # Check if releases are available
        if ($response -and $response.Count -gt 0) {
            Write-Host "Available releases for $RepoOwner/$RepoName :`n"
            foreach ($release in $response) {
                # Display release information
                Write-Host "Tag: $($release.tag_name)"
                Write-Host "Name: $($release.name)"
                Write-Host "Published at: $($release.published_at)"
                Write-Host "URL: $($release.html_url)"
                Write-Host "-----"
            }
        }
        else {
            Write-Host "No releases found for $RepoOwner/$RepoName."
        }
    }
    catch {
        Write-Host "An error occurred while fetching releases. Please check the repository name and owner."
        Write-Host "Error details: $($_.Exception.Message)"
    }
}

# Function to download a specific or latest release
function Copy-GitHubRelease {
    [CmdletBinding()]
    param (
        [string]$RepoOwner,
        [string]$RepoName,
        [string]$Version = "latest",
        [string[]]$Assets = @(), # Array of specific asset names to download
        [string]$libPath,
        [string]$ApiPath = "https://api.github.com",
        [hashtable]$ExpectedHashes = @{}
    )
    Write-Verbose $Assets.ToString()

    # Local-first: skip API call if all requested assets are already cached
    if ($Assets.Count -gt 0 -and $libPath) {
        $allCached = $true
        $cachedPaths = @()
        foreach ($assetName in $Assets) {
            $fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($assetName)
            $directoryPath = Join-Path $libPath $fileNameWithoutExtension
            if (Test-Path $directoryPath -PathType Container) {
                $cachedPaths += $directoryPath
            }
            else {
                $allCached = $false
                break
            }
        }
        if ($allCached) {
            Write-Verbose "All requested assets already cached in $libPath. Skipping API call."
            return $cachedPaths
        }
    }

    # Define the API URL
    if ($Version -eq "latest") {
        $url = "$apiPath/repos/$RepoOwner/$RepoName/releases/latest"        
    }
    else {
        $url = "$apiPath/repos/$RepoOwner/$RepoName/releases/tags/$Version"
    }

    try {
        # Make the API request
        $response = Invoke-RestMethod -Uri $url -UseBasicParsing
        # Verify assets are available
        if ($response.assets -and $response.assets.Count -gt 0) {
            $tag = $response.tag_name
            
            # Filter assets to download
            $assetsToDownload = if ($Assets.Count -eq 0) {
                $response.assets
            }
            else {
                # Filter assets to only include those specified in the Assets array
                $response.assets | Where-Object { $Assets -contains $_.name }
            }
            
            if ($assetsToDownload.Count -eq 0) {
                Write-Warning "No matching assets found to download."
                return
            }
            else {
                Write-Verbose "Available releases for $RepoOwner/$RepoName :`n"
            }
            $paths = @() 
            foreach ($asset in $assetsToDownload) {
                Write-Host $asset.name | Out-Host
                $isDownloaded = $false                
                $fileName = $asset.name
                
                if (Test-Path (Join-Path $libPath $fileName)) {
                    $isDownloaded = $true
                }                
                
                $outFile = (Join-Path $libPath $fileName)

                if ($isDownloaded) {
                    Write-Verbose "$fileName (Already downloaded)"
                }
                else {
                    $downloadUrl = $asset.browser_download_url
                    Write-Host "Downloading $fileName from $downloadUrl..."
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile -UseBasicParsing
                    Write-Host "$fileName downloaded successfully.`n"
                }
                # Validate hash if expected
                if ($ExpectedHashes.ContainsKey($fileName)) {
                    Test-FileHash -Path $outFile -ExpectedHash $ExpectedHashes[$fileName]
                }

                # Don't assume ZIP
                #check if extension is anything Expand-Archive can handle                
                $extension = [System.IO.Path]::GetExtension($fileName)
                $extract = $true
                if ($extension -ne ".zip") {
                    Write-Verbose "The file $fileName is not a ZIP archive. Skipping extraction."
                    $extract = $false
                }
                $fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                $directoryPath = (Join-Path $libPath $fileNameWithoutExtension)
                if (Test-Path $directoryPath -PathType Container) {
                    Write-Verbose "Directory $directoryPath already exists, skipping extraction."
                    $extract = $false
                }
                if ($extract) {
                    Expand-Archive -Path $outFile -DestinationPath $libPath -Force
                    #TODO get actual version if "latest"                    
                    # Check if the ZIP file was already extracted
                    # Pwsh does not generate a wrapper, so this will be specific to the artifact,
                    # thankfully, MorganaXProc and xmlcalbash both have a directory with the same name as the ZIP file.
                    # can have existing directory with same name as ZIP file
                    $fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                }
                $directoryExists = Test-Path $directoryPath -PathType Container
                if ($directoryExists) {
                    $paths += @($directoryPath)
                }
                else {
                    Write-Error "Logic error"
                }
            }
            #Write-Host $paths
            return $paths

        }
        else {
            Write-Host "No releases found for $RepoOwner/$RepoName."
        }
        #   if ($response.assets -and $response.assets.Count -gt 0) {
        #       foreach ($asset in $response.assets) {
        #           $fileName = $asset.name
        #       }
        #   } else {
        #       Write-Host "No downloadable assets found for the specified release."
        #   }
    }
    catch {
        Write-Host "An error occurred while downloading the release. Please check the inputs."
        Write-Host "Error details: $($_.Exception.Message)"
    }
}

