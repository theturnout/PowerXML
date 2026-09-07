BeforeAll {
    $global:TestDir = "TestDrive:/"
    Import-Module "$PSScriptRoot/../polyglot"

    # Dependency cache: use POWERXML_TEST_CACHE env var, or fall back to a persistent temp directory.
    # Set POWERXML_TEST_CACHE=TestDrive:/ for ephemeral (clean) runs.
    if ($env:POWERXML_TEST_CACHE) {
        $env:polyglotpm = $env:POWERXML_TEST_CACHE
    }
    else {
        $tempBase = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
        $env:polyglotpm = Join-Path $tempBase "powerxml-test-deps"
    }
    if (-not (Test-Path $env:polyglotpm)) {
        New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
    }
}

AfterAll {
    $env:polyglotpm = $null
}

Describe 'File downloading' {
    It 'Should have Download a GitHub Release' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $paths = Copy-GitHubRelease -repoOwner "nineml" -repoName "coffeefilter" `
            -Version "3.3.4" `
            -assets @("coffeefilter-3.3.4.zip") `
            -libPath $global:TestDir
           
        Test-Path "$global:TestDir/coffeefilter-3.3.4" | Should -Be $true
    }

    It 'Should have Download a Specific file from codeberg' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $purl = ConvertFrom-PkgUri "pkg:codeberg/NineML/nineml@3.3.8?filename=coffeefilter-3.3.8.zip"        
        $paths = Get-PackageFromPurl -purl $purl
        Test-Path "$env:polyglotpm/coffeefilter-3.3.8" | Should -Be $true
        $paths | Should -Not -Be $null
    }
    It 'Produces a path when file is already downloaded from codeberg' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $purl = ConvertFrom-PkgUri "pkg:codeberg/NineML/nineml@3.3.8?filename=coffeefilter-3.3.8.zip"        
        $paths = Get-PackageFromPurl -purl $purl
        $paths | Should -Not -Be $null
    }
       
    It 'Should have Download a Specific file from Maven' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $purl = ConvertFrom-PkgUri "pkg:maven/org.xmlresolver/xmlresolver@6.0.12"        
        $paths = Get-PackageFromPurl -purl $purl
        Test-Path "$env:polyglotpm/xmlresolver-6.0.12" | Should -Be $true
        $paths | Should -Not -Be $null
    }
    It 'Should download a specific file from SourceForge' {
        $purl = ConvertFrom-PkgUri "pkg:sourceforge/morganaxproc-IIIse@1.6?filename=MorganaXProc-IIIse-1.6.7/MorganaXProc-IIIse-1.6.7.zip"
        $downloadedPath = Get-PackageFromPurl -purl $purl
        # Post-process: rootZip is SBOM-level metadata, handled by Install-Package
        $installedPath = Install-Package -DownloadedPath $downloadedPath `
            -Name $purl.Name -Version $purl.Version `
            -ZipRoot "MorganaXProc-IIIse-1.6.7" `
            -LocalRepository $env:polyglotpm
        #path matches the package name, not the file name nor zip root
        Test-Path "$env:polyglotpm/morganaxproc-IIIse-1.6" | Should -Be $true
        $installedPath | Should -Not -Be $null
    }
    # Add more specific tests for Copy-GitHubRelease here
}

