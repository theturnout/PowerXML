BeforeAll {
    # TODO: clear .polyglotpm cache
    #$global:TestDir = Join-Path $env:TEMP "pester-test-$(New-Guid)"
    #New-Item -ItemType Directory -Path $TestDir | Out-Null
    $global:TestDir = "TestDrive:\"
    Import-Module "$PSScriptRoot/../polyglot"

    $env:polyglotpm = (Join-Path $global:TestDir "polyglotpm")
    New-Item -ItemType Directory -Path $env:polyglotpm | Out-Null
}

AfterAll {
    #  Remove-Item -Path $global:TestDir -Recurse -Force
}

Describe 'File downloading' {
    It 'Should have Download a GitHub Release' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        Download-GitHubRelease -repoOwner "HiltonRoscoe" -repoName "exchangerxml" `
            -Version "v4-beta2" `
            -assets @("xngr-editor.zip") `
            -libPath $global:TestDir
        
        Test-Path "$global:TestDir\xngr-editor.zip" | Should -Be $true
    }

    It 'Should have Download a Specific file from codeberg' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $purl = ConvertFrom-PkgUri "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24?filename=xmlcalabash-3.0.24.zip"        
        $paths = Get-PackageFromPurl -purl $purl
        Test-Path "$env:polyglotpm\xmlcalabash-3.0.24.zip" | Should -Be $true
    }
    It 'Produces a path when file is already downloaded from codeberg' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $purl = ConvertFrom-PkgUri "pkg:codeberg/xmlcalabash/xmlcalabash3@3.0.24?filename=xmlcalabash-3.0.24.zip"        
        $paths = Get-PackageFromPurl -purl $purl
        $paths | Should -Not -Be $null
    }
    
    It 'Should have Download a Specific file from Maven' {
        #https://github.com/Election-Tech-Initiative/electionguard/releases/tag/v2.1
        $purl = ConvertFrom-PkgUri "pkg:maven/org.xmlresolver/xmlresolver@6.0.12"        
        $paths = Get-PackageFromPurl -purl $purl
        Test-Path "$env:polyglotpm\xmlresolver-6.0.12" | Should -Be $true
    }
    # Add more specific tests for Download-GitHubRelease here
}

