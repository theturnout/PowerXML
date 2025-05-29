
# Hashtable to track resolved POMs
# May not work well now that it's global.
$resolvedPOMs = @{}

function Get-MavenArtifact {
    param (
        [string]$groupId,
        [string]$artifactId,
        [string]$version,
        [string]$repoUrl,
        [string]$downloadPath
    )

    $groupPath = $groupId -replace '\.', '/'
    $artifactBaseUrl = "$repoUrl/$groupPath/$artifactId/$version"
    
    $jarUrl = "$artifactBaseUrl/$artifactId-$version.jar"
    $pomUrl = "$artifactBaseUrl/$artifactId-$version.pom"

    $artifactFolder = "$downloadPath\$artifactId-$version"
    if (!(Test-Path $artifactFolder)) {
        New-Item -ItemType Directory -Path $artifactFolder -Force | Out-Null
    }

    $jarFile = "$artifactFolder\$artifactId-$version.jar"
    $pomFile = "$artifactFolder\pom.xml"

    if (!(Test-Path $jarFile)) {
        Write-Host "Downloading JAR: $jarUrl"
        Invoke-WebRequest -Uri $jarUrl -OutFile $jarFile
    }
    else {
        Write-Verbose "JAR already exists: $jarFile"
    }

    if (!(Test-Path $pomFile)) {
        Write-Host "Downloading POM: $pomUrl"
        Invoke-WebRequest -Uri $pomUrl -OutFile $pomFile
    }
    else {
        Write-Verbose "POM already exists: $pomFile"
    }

    return $pomFile
}

function Resolve-Dependencies {
    param (
        [string]$pomFile,
        [string]$repoUrl,
        [string]$downloadPath
    )

    [xml]$pomXml = Get-Content -Path $pomFile
    $dependencies = $pomXml.project.dependencies.dependency
    	
    foreach ($dep in $dependencies) {
        $depGroupId = $dep.groupId
        $depArtifactId = $dep.artifactId
        $depVersion = $dep.version
        $depScope = $dep.scope

        # If no scope is specified, it defaults to "compile"
        if (-not $depScope) {
            $depScope = "compile"
        }

        # Skip dependencies that are not needed at runtime
        if ($depScope -eq "test" -or $depScope -eq "system" -or ($dep.optional -eq "true")) {
            Write-Verbose "Skipping non-runtime or optional dependency: ${depGroupId}:${depArtifactId}:${depVersion} (scope: $depScope)"
            continue
        }

        if (-not $depVersion) {
            Write-Warning "Skipping dependency without version: ${depGroupId}:${depArtifactId}. Dependency Management is not currently supported"
            continue
        }
        
        $depKey = "${depGroupId}:${depArtifactId}:${depVersion}"

        if ($resolvedPOMs.ContainsKey($depKey)) {
            Write-Verbose "Skipping already resolved dependency: $depKey"
            continue
        }

        $resolvedPOMs[$depKey] = $true  # Mark this dependency as resolved

        Write-Verbose "Resolving Dependency: ${depGroupId}:${depArtifactId}:${depVersion}"
        $depPomFile = Get-MavenArtifact -groupId $depGroupId -artifactId $depArtifactId -version $depVersion -repoUrl $repoUrl -downloadPath $downloadPath
        $paths = @("$downloadPath\$depArtifactId-$depVersion")
        
        if ($depPomFile) {
            $currentPaths = Resolve-Dependencies -pomFile $depPomFile -repoUrl $repoUrl -downloadPath $downloadPath
            if ($currentPaths) {
                $paths += $currentPaths
            }
        }
        
    }
    return $paths
}

# function Resolve-Package-Version
