#Remove-Item -Path $libPath -Recurse -Force -ErrorAction SilentlyContinue
#if (-not (Test-Path $libPath)) {
#    New-Item -ItemType Directory -Path $libPath | Out-Null
#}


$hashAlgorithm = "SHA256"

# Function to list GitHub releases
function Get-GitHubReleases {
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
        [string]$ApiPath = "https://api.github.com"
    )
    Write-Verbose $Assets.ToString()
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
                # todo check file size, if not equal to asset size, delete and re-download

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
            Write-Host $paths
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

# Prepare artifact for storage
function Build-Artifact {
    param (
        [string]$name,
        [string]$version,
        [string]$urlTemplate,
        [string]$zipRoot = "$name-$version",
        #[string]$destFolderName = $name,
        [string]$extendedPath,
        [string]$expectedHash,
        [string]$libPath
    )

    $zipHash = Get-FileHash -Path $zipPath -Algorithm $hashAlgorithm
    # Print the calculated hash
    if ($expectedHash -and $zipHash.Hash -ne $expectedHash) {
        Write-Warning "The file hash does NOT match the known hash."            
    }
    # if (-not (Test-Path $unzipPath)) {
    #     New-Item -ItemType Directory -Path $unzipPath | Out-Null
    # }
    #Saxon doesn't come in a nested directory and will need to append the libPath
    Expand-Archive -Path $zipPath -DestinationPath (Join-Path $libPath $extendedPath) -Force
    if (-not $extendedPath) {            
        Rename-Item -Path (Join-Path $libPath $zipRoot) -NewName "$name-$version" -Force
    }

}

function DownloadArtifactNew {

    param (
        [string]$name,
        [string]$version,
        [string]$urlTemplate,
        [string]$zipRoot = "$name-$version",
        #[string]$destFolderName = $name,
        [string]$extendedPath,
        [string]$expectedHash
    )
    if (-not $version) {
        # attempt to find version
        #    GetLatestVersion()
    }

    DownloadArtifact -name $name -version $version -urlTemplate $asset.RepoUri
    #see if this artifact is in our data list
    #  if($Data.assets[$name]){
    #      $asset = $Data.assets[$name]
    #      if($asset.RepoType -eq "GitHub"){
    #          Copy-GitHubRelease -RepoOwner $asset.RepoOwner `
    #          -RepoName $asset.RepoName `
    #          -Version $version `
    #          -Assets @($asset.AssetString)
    #      } else {
    #          DownloadArtifact -name $name -version $version -urlTemplate $asset.RepoUri
    #      }
    #  }

}

function DownloadArtifact {
    param (
        [string]$name,
        [string]$version,
        [string]$urlTemplate,
        [string]$zipRoot = "$name-$version",
        #[string]$destFolderName = $name,
        [string]$extendedPath,
        [string]$expectedHash,
        [string]$libPath
    )
    if (-not $version) {
        # attempt to find version
        #    GetLatestVersion()
    }

    #$destPath = Join-Path $libPath $destFolderName
    $zipPath = Join-Path $libPath "$name-$version.zip"
    $unzipPath = Join-Path $libPath "$name-$version"
    if (-not (Test-Path $unzipPath)) {
        Write-Host "Downloading $name-$version ..."

        # Add version to urlTemplate
        $downloadUrl = $urlTemplate -f $version
        Write-Host "Remote site is $downloadUrl"
        Invoke-WebRequest -UserAgent "Wget" -Uri $downloadUrl -OutFile $zipPath
        $zipHash = Get-FileHash -Path $zipPath -Algorithm $hashAlgorithm
        # Print the calculated hash
        if ($expectedHash -and $zipHash.Hash -ne $expectedHash) {
            Write-Warning "The file hash does NOT match the known hash."            
        }
        # if (-not (Test-Path $unzipPath)) {
        #     New-Item -ItemType Directory -Path $unzipPath | Out-Null
        # }
        #Saxon doesn't come in a nested directory and will need to append the libPath
        Expand-Archive -Path $zipPath -DestinationPath (Join-Path $libPath $extendedPath) -Force
        if (-not $extendedPath) {            
            Rename-Item -Path (Join-Path $libPath $zipRoot) -NewName "$name-$version" -Force
        }
        # Remove-Item -Path $zipPath -Force
    }
    else {
        Write-Host "$name $version already downloaded."
    }
}

function DownloadSaxon {
    param (
        [string]$version = "11-5J",
        [string]$edition = "HE"
    )
    $edition = $edition.ToUpper()
    if ($edition -notin @("HE", "PE", "EE")) {
        throw "Invalid Saxon edition specified. Valid options are: HE, PE, EE."
    }

    $saxonJar = "saxon-${edition.ToLower()}-$version.jar"
    if (-not (Test-Path (Join-Path $libPath $saxonJar))) {
        DownloadArtifact -name "Saxon $edition" -version $version `
            -urlTemplate "https://www.saxonica.com/download/Saxon$edition$version.zip" `
            -extendedPath "saxon-$edition-$version" 
        #-destFolderName "Saxon$edition$version"

        # Clean up extraneous JARs
        #    Get-ChildItem -Path $libPath -Filter "saxon-$edition-*.jar" | Where-Object {
        #        $_.Name -ne $saxonJar
        #    } | Remove-Item -Force
    }
    else {
        Write-Host "Saxon $edition $version already downloaded."
    }
}

# CLI logic
## if ($args.Count -eq 0) {
##     Write-Host "Usage:"
##     Write-Host "  ls <RepoOwner> <RepoName>         # List available versions"
##     Write-Host "  use <RepoOwner> <RepoName> <Tag> # Download a specific or latest version"
## }
## else {
##     switch ($args[0]) {
##         "ls" {
##             if ($args.Count -ne 3) {
##                 Write-Host "Usage: ls <RepoOwner> <RepoName>"
##             }
##             else {
##                 Get-GitHubReleases -RepoOwner $args[1] -RepoName $args[2]
##             }
##         }
##         "use" {
##               if ($args.Count -lt 3) {
##                 Write-Host "Usage: use <RepoOwner> <RepoName> <Tag> [<Asset1> <Asset2> ...]"
##                 Write-Host "  Omit <Tag> to download the latest version. Omit assets to download all."
##             } else {
##                 $version = if ($args.Count -ge 4) { $args[3] } else { "latest" }
##                 $assets = if ($args.Count -gt 4) { $args[4..($args.Count - 1)] } else { @() }
##                 Copy-GitHubRelease -RepoOwner $args[1] -RepoName $args[2] -Version $version -Assets $assets
##             }
##         }
##         default {
##             Write-Host "Unknown command: $($args[0])"
##             Write-Host "Use 'ls' to list versions or 'use' to download."
##         }
##     }
## }