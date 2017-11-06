remove-module AU -ea ignore
import-module $PSScriptRoot\..\AU

Describe 'Update-AUPackages using streams' -Tag updateallstreams {
    $saved_pwd = $pwd

    function global:nuspec_file() { [xml](gc $PSScriptRoot/test_package_with_streams/test_package_with_streams.nuspec) }
    $pkg_no = 2
    $streams_no = $pkg_no * 3

    BeforeEach {
        $global:au_Root      = "TestDrive:\packages"
        $global:au_NoPlugins = $true

        rm -Recurse $global:au_root -ea ignore
        foreach ( $i in 1..$pkg_no ) {
            $name = "test_package_with_streams_$i"
            $path = "$au_root\$name"

            cp -Recurse -Force $PSScriptRoot\test_package_with_streams $path
            $nu = nuspec_file
            $nu.package.metadata.id = $name
            rm "$path\*.nuspec"
            $nu.OuterXml | sc "$path\$name.nuspec"
            mv "$path\test_package_with_streams.json" "$path\$name.json"

            $module_path = Resolve-Path $PSScriptRoot\..\AU
            "import-module '$module_path' -Force", (gc $path\update.ps1 -ea ignore) | sc $path\update.ps1
        }

        $Options = [ordered]@{}
    }

    Context 'Plugins' {

        It 'should execute GitReleases plugin when there are updates' {
            gc $global:au_Root\test_package_with_streams_1\update.ps1 | set content
            $content -replace '@\{.+1\.3.+\}', "@{ Version = '1.3.2' }" | set content
            $content -replace '@\{.+1\.2.+\}', "@{ Version = '1.2.4' }" | set content
            $content | sc $global:au_Root\test_package_with_streams_1\update.ps1
    
            $Options.GitReleases = @{
                ApiToken    = 'apiToken'
                ReleaseType = 'package'
                Force       = $true
            }

            Mock Invoke-RestMethod {
                return @{
                    tag_name = 'test_package_with_streams_1-1.2.4'
                    assets = @(
                        @{
                            url = 'https://api.github.com/test_package_with_streams_1.1.2.4.nupkg'
                            name = 'test_package_with_streams_1.1.2.4.nupkg'
                        }
                    )
                }
            } -ModuleName AU

            updateall -NoPlugins:$false -Options $Options 6> $null

            Assert-MockCalled Invoke-RestMethod -Exactly 6 -ModuleName AU
        }
    }

    It 'should update package with checksum verification mode' {

        $choco_path = gcm choco.exe | % Source
        $choco_hash = Get-FileHash $choco_path -Algorithm SHA256 | % Hash
        gc $global:au_Root\test_package_with_streams_1\update.ps1 | set content
        $content -replace '@\{.+1\.3.+\}', "@{ Version = '1.3.2'; ChecksumType32 = 'sha256'; Checksum32 = '$choco_hash'}" | set content
        $content -replace 'update', "update -ChecksumFor 32" | set content
        $content | sc $global:au_Root\test_package_with_streams_1\update.ps1

        $res = updateall -Options $Options 6> $null
        $res.Count | Should Be $pkg_no
        $res[0].Updated | Should Be $true
    }

    It 'should limit update time' {
        gc $global:au_Root\test_package_with_streams_1\update.ps1 | set content
        $content -replace 'update', "sleep 10; update" | set content
        $content | sc $global:au_Root\test_package_with_streams_1\update.ps1
        $Options.UpdateTimeout = 5

        $res = updateall -Options $Options 3>$null 6> $null
        $res[0].Error -eq "Job termintated due to the 5s UpdateTimeout" | Should Be $true
    }

    It 'should update all packages when forced' {
        $Options.Force = $true

        $res = updateall -Options $Options 6> $null

        lsau | measure | % Count | Should Be $pkg_no
        $res.Count | Should Be $pkg_no
        ($res.Result -match 'update is forced').Count | Should Be $pkg_no
        ($res | ? Updated).Count | Should Be $pkg_no
    }

    It 'should update no packages when none is newer' {
        $res = updateall 6> $null

        lsau | measure | % Count | Should Be $pkg_no
        $res.Count | Should Be $pkg_no
        ($res.Result -match 'No new version found').Count | Should Be $streams_no
        ($res | ? Updated).Count | Should Be 0
    }

    $saved_pwd = $pwd
}

