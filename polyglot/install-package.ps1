<#
.SYNOPSIS
    Installs a downloaded package artifact into the local repository.
.DESCRIPTION
    Handles post-download concerns: hash verification, zip extraction,
    rootZip directory renaming, and cleanup. Idempotent — skips if the
    target directory already exists.
.PARAMETER DownloadedPath
    Path to the downloaded artifact file (e.g. a .zip or .jar).
.PARAMETER Name
    Canonical package name used for the installed directory.
.PARAMETER Version
    Package version used for the installed directory.
.PARAMETER ZipRoot
    The directory name inside the zip archive, if it differs from "$Name-$Version".
    When set, the extracted directory is renamed to "$Name-$Version".
.PARAMETER Hashes
    Array of hash objects (each with Algorithm and Hash properties) to verify against
    the downloaded file. Each entry is checked via Test-FileHash.
.PARAMETER LocalRepository
    Target directory where packages are installed. Defaults to Get-LocalRepositoryPath.
.OUTPUTS
    The full path to the installed package directory.
#>
function Install-Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $DownloadedPath,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Version,
        [string] $ZipRoot,
        [PSCustomObject[]] $Hashes = @(),
        [string] $LocalRepository = (Get-LocalRepositoryPath)
    )

    $targetDir = Join-Path $LocalRepository "$Name-$Version"

    # Idempotent: already installed
    if (Test-Path $targetDir -PathType Container) {
        Write-Verbose "Package $Name-$Version already installed at $targetDir"
        return $targetDir
    }

    if (-not (Test-Path $DownloadedPath)) {
        throw "Downloaded artifact not found: $DownloadedPath"
    }

    # Hash verification
    foreach ($h in $Hashes) {
        $null = Test-FileHash -Path $DownloadedPath -ExpectedHash $h.Hash -Algorithm $h.Algorithm
    }

    # Extract if zip (nupkg files are also ZIP archives)
    $extension = [System.IO.Path]::GetExtension($DownloadedPath)
    if ($extension -in @(".zip", ".nupkg")) {
        Expand-Archive -Path $DownloadedPath -DestinationPath $LocalRepository -Force

        # Handle rootZip rename: the directory inside the zip may not match the canonical name
        if ($ZipRoot -and $ZipRoot -cne "$Name-$Version") {
            $extractedDir = Join-Path $LocalRepository $ZipRoot
            if (Test-Path $extractedDir -PathType Container) {
                Write-Host "Renaming extracted directory '$ZipRoot' to '$Name-$Version'"
                Rename-Item -Path $extractedDir -NewName "$Name-$Version" -Force
            }
            else {
                Write-Warning "Expected zip root directory '$ZipRoot' not found after extraction."
            }
        }
        else {
            Write-Host "No rootZip specified or matches canonical name; no renaming needed."
        }

    }
    else {
        # Non-zip: ensure target directory exists and move the file into it
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        $destFile = Join-Path $targetDir (Split-Path $DownloadedPath -Leaf)
        if ($DownloadedPath -ne $destFile) {
            Move-Item -Path $DownloadedPath -Destination $destFile -Force
        }
    }

    return $targetDir
}
