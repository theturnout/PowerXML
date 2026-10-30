<#
.SYNOPSIS
    Installs a downloaded package artifact into the local repository.
.DESCRIPTION
    Handles post-download concerns: hash verification, zip extraction,
    wrapper directory renaming, and cleanup. The archive's wrapper directory
    is auto-detected from its structure; archives without one are extracted
    directly into the canonical "$Name-$Version" directory. Idempotent — skips
    if the target directory already exists.
.PARAMETER DownloadedPath
    Path to the downloaded artifact file (e.g. a .zip or .jar).
.PARAMETER Name
    Canonical package name used for the installed directory.
.PARAMETER Version
    Package version used for the installed directory.
.PARAMETER ZipRoot
    Legacy metadata for the directory name inside the zip archive when it differs
    from "$Name-$Version". The wrapper directory is auto-detected from the archive
    structure; when ZipRoot disagrees with the detected root (or the archive has
    no wrapper), a warning is emitted and the detected structure wins.
.PARAMETER Hashes
    Array of hash objects (each with Algorithm and Hash properties) to verify against
    the downloaded file. Each entry is checked via Test-FileHash.
.PARAMETER LocalRepository
    Target directory where packages are installed. Defaults to Get-LocalRepositoryPath.
.OUTPUTS
    The full path to the installed package directory.
#>
# WinPS 5.1 compatibility: the zip API is auto-loaded in .NET Core but not .NET Framework
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

<#
.SYNOPSIS
    Detects the wrapper directory of a zip-format archive.
.DESCRIPTION
    Returns the single top-level directory name when every archive entry lives
    underneath it, and $null when the archive has no wrapper (entries at the
    archive root). Unreadable archives also return $null.
.PARAMETER Path
    Path to the archive file.
.OUTPUTS
    The wrapper directory name, or $null when there is none.
#>
function Get-ArchiveRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )
    try {
        # Resolve PSDrive paths (e.g. TestDrive:\) to real filesystem paths
        # so the .NET zip API can open them
        $resolvedPath = Convert-Path -Path $Path -ErrorAction Stop
        $archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath)
    }
    catch {
        return $null
    }
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName } | Where-Object { $_ })
        if ($entryNames.Count -eq 0) {
            return $null
        }
        $roots = @($entryNames | ForEach-Object { ($_ -split "/")[0] } | Sort-Object -Unique)
        if ($roots.Count -ne 1) {
            return $null
        }
        $root = $roots[0]
        # A single top-level entry name is only a wrapper directory when
        # entries actually live underneath it
        $nested = @($entryNames | Where-Object { $_.Length -gt $root.Length -and $_.StartsWith("$root/") })
        if ($nested.Count -eq 0) {
            return $null
        }
        return $root
    }
    finally {
        $archive.Dispose()
    }
}
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
        $canonicalName = "$Name-$Version"
        # Determine the archive's wrapper directory: auto-detected from the
        # archive structure, with the -ZipRoot parameter kept for compatibility.
        $archiveRoot = Get-ArchiveRoot -Path $DownloadedPath
        if ($ZipRoot -and $archiveRoot -and ($ZipRoot -cne $archiveRoot)) {
            Write-Warning "ZipRoot '$ZipRoot' does not match the archive's actual root directory '$archiveRoot'; using the detected root."
        }
        if (-not $archiveRoot -and $ZipRoot) {
            Write-Warning "ZipRoot '$ZipRoot' was specified, but the archive has no wrapper directory; extracting directly into '$canonicalName'."
        }

        if ($archiveRoot) {
            $stagingDir = Join-Path $LocalRepository "install-$(New-Guid)"
            $null = New-Item -ItemType Directory -Path $stagingDir -ErrorAction Stop
            try {
                Expand-Archive -Path $DownloadedPath -DestinationPath $stagingDir -Force -ErrorAction Stop
                $extractedDir = Join-Path $stagingDir $archiveRoot
                Move-Item -LiteralPath $extractedDir -Destination $targetDir -ErrorAction Stop
            }
            finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force
            }
        }
        else {
            # No wrapper directory in the archive: extract its contents directly
            # into the canonical directory instead of spraying them into the
            # repository root
            Expand-Archive -Path $DownloadedPath -DestinationPath $targetDir -Force
            Write-Host "Archive has no wrapper directory; extracted contents into '$canonicalName'."
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
