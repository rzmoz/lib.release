Function New-Lib.Release {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$SolutionName,
        [Parameter(Position = 1)]
        [string]$nugetApiKey,
        [switch]$NoNugets = $false,
        [switch]$NoTests = $false,        
        [string]$LibRootDir = "/Users/rr/Projects"
    )

    Begin {
        $currentDir = (Get-Location).Path
        Write-H1 "Initializing $($SolutionName) for release"
        $solutionDir = [System.IO.Path]::Combine($LibRootDir, $SolutionName).TrimEnd('\')
    }

    Process {
        if ((Enter-Dir $solutionDir)) {
            $SolutionName = $SolutionName.TrimStart(".").TrimStart("\\").TrimEnd("\\")
            $conf = Initialize-Lib.Release.Configuration $SolutionName -LibRootDir $LibRootDir

            $conf | Write-Lib.Release.Configuration

            if ($conf.InitSuccess -ne $true) {
                Write-Error "Aborting..."
                return
            }     
            
            try {
                #get nuget api key
                if (-NOT($nugetApiKey)) {
                    $nugetApiKey = Read-Host "Please enter nuget API key"
                }
                

                ######### Initialize Git Dir #########
                
                Write-H1 "Cleaning $((Get-Location).Path)"
                $gitGoodToGoNeedle = 'nothing to commit, working tree clean'
                $gitStatus = git status | Out-String
                Write-Line $gitStatus
                if ($gitStatus -imatch $gitGoodToGoNeedle) {
                    Write-Host "Cleaning bin dirs:"
                    Get-ChildItem "$solutionDir" -Filter "bin" -recurse | ForEach-Object {
                        Write-Host "Cleaning: $($_.FullName)" -ForegroundColor DarkGray
                        Remove-Item "$($_.FullName)/*" -Recurse -Force
                    }
                }
                else {
                    Write-Problem "Git dir contains uncommitted changes and is not ready for release! Expected '$($gitGoodToGoNeedle)'. Aborting..."
                    return
                }     
                
                #patch project version
                Write-H1 "Patching project versions"
                $conf.Releases.Values | ForEach-Object { Update-ProjectVersion $_.Path $_.Version $_.SemVer20 }
                                                
                #build sln
                Write-H1 "Building $($conf.Solution.Path)"
                $buildOutput = dotnet build $conf.Solution.Path --configuration $conf.Build.Configuration --no-incremental --verbosity quiet | Out-String
                Write-Line $buildOutput
                if (-NOT($buildOutput -imatch "Build succeeded")) {
                    Write-Problem "Build failed"
                    return
                }
                
                #tests
                if ($NoTests) {
                    Write-Warning "Skipping tests. -NoTests flag set"
                }
                else {
                    Write-H1 "Testing $($conf.Build.Configuration)"
                    if (-NOT($conf.Tests | Test-Projects -BuildConfiguration $conf.Build.Configuration)) {
                        return
                    }
                }
                
                #nugets
                #clean output dir if exists
                Write-H1  "Cleaning OutPut dir: $($conf.Nugets.ArtifactsDir)"
                if (Test-Path $conf.Nugets.ArtifactsDir) { Remove-Item "$($conf.Nugets.ArtifactsDir)\*" -Force | Out-String | Write-Line }
                
                #create aritfacts dir
                New-Item $conf.Nugets.ArtifactsDir -ItemType Directory -Force | Out-String | Write-Line

                if ($NoNugets) {
                    Write-Warning "Skipping nugets. -NoNugets flag set"
                }
                else {
                    Write-H1 "Packaging Nugets"
                    $conf.Releases | Publish-Nugets -NugetsOutputDir $conf.Nugets.ArtifactsDir -NugetsSource $conf.Nugets.Source -Buildconfiguration $conf.Build.Configuration -ApiKey $nugetApiKey
                }

            }
            finally {
                Write-H1 "Cleaning up..."

                #clean output Dir if exists
                if (Test-Path $conf.Nugets.ArtifactsDir) { Remove-Item "$($conf.Nugets.ArtifactsDir)\*" -Force | Write-Line }
                if (Test-Path $conf.Nugets.ArtifactsDir) { Remove-Item "$($conf.Nugets.ArtifactsDir)" -Force | Write-Line }

                #revert project version
                $conf.Releases.Values | ForEach-Object { $_.Path } | Undo-ProjectVersion
            }

        }
        else {
            Write-Problem "Solution dir not found. Aborting..."
            return
        }
    }
    End {
        #bugging out!
        if ($currentDir -ne (Get-Location).Path) {
            Enter-Dir $currentDir | Out-Null
        }        
    }
}

########################################################################
#                             Configuration                            #
########################################################################
Function Initialize-Lib.Release.Configuration {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$SolutionName,      
        [Parameter(Mandatory = $false)]
        [string]$BuildConfiguration = 'release',
        [Parameter(Mandatory = $true)]
        [string]$LibRootDir
    )
    PROCESS {
        [HashTable]$conf = @{}
        $conf.InitSuccess = $true

        #----- sln -----#
        [HashTable]$conf.Solution = @{}
        $conf.Solution.Path = (Get-Item "$SolutionName.sln").FullName
        
        #----- git -----#
        [HashTable]$conf.Git = @{}
        $conf.Git.Branch = git rev-parse --abbrev-ref HEAD
        $conf.Git.Hash = git rev-parse --verify HEAD
        $conf.Git.ShortHash = git log --pretty=format:'%h' -n 1
        $conf.Git.Commits = git rev-list --all --count $conf.Git.Branch

        #----- msbuild -----#
        [HashTable]$conf.Build = @{}
        $conf.Build.Configuration = $BuildConfiguration        

        #----- Release -----#
        [HashTable]$conf.Releases = @{}
        $libReleaseParams = Get-Content -Raw -Path "$($(Get-Location).Path)\lib.release.json" | ConvertFrom-Json
        
        $libReleaseParams.releases.GetEnumerator() | ForEach-Object {
            $release = @{}
            $release.Name = $_.name
            $release.Version = $_.version
            $release.PreRelease = $_.prerelease
            $release.Path = $(Get-ChildItem -Path "." -Recurse -Depth 1 -Filter "*$($_.name).csproj").FullName

            if (-NOT ([String]::IsNullOrEmpty($release.PreRelease))) {
                $release.PreRelease = "-$($release.PreRelease )"
            }
            $release.SemVer20 = "$($release.Version)$($release.PreRelease)+$($conf.Git.ShortHash)"
            $conf.Releases.Add($_.Name.ToLower(), $release)
        }
        #----- tests -----#
        [HashTable]$conf.Tests = @{}

        $libReleaseParams.tests.GetEnumerator() | ForEach-Object {
            $testInfo = @{}
            $testInfo.Name = $_
            $testInfo.Path = $(Get-ChildItem -Path "." -Recurse -Depth 1 -Filter "*$($_).csproj").FullName
            $conf.Tests.Add($testInfo.Name, $testInfo)
        }

        #----- nuget -----#
        [hashtable]$conf.Nugets = @{}
        $conf.Nugets.Source = $libReleaseParams.nuget.source
        $conf.Nugets.ArtifactsDir = "$($(Get-Location).Path)\.lib.release.artifacts"
        
        return $conf
    }
}
Function Write-Lib.Release.Configuration {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [HashTable]$conf,
        [Parameter(Position = 1)]
        [Int]$level = 0
    )

    Begin {
        if ($level -eq 0) {
            Write-H2 "[Configuration]"
        }

        $level++
    }

    Process {
        $spacer = ""
        for ($i = 0; $i -lt $level; $i++) {
            $spacer += "  "
        }
        
        $conf.GetEnumerator() | ForEach-Object {
            if ($_.Value -eq $null) {
                Write-Line "$($spacer)$($_.Key) : null"
                
            }
            elseif (($_.Value.GetType().fullname) -eq "System.Collections.HashTable") {
                Write-H2 "$($spacer)[$($_.Key)]"
                Write-Lib.Release.Configuration $_.Value $level
            }
            else {
                Write-Line "$($spacer)$($_.Key) : $($_.Value)"
            }            
        }    
    }
}

########################################################################
#                            Project Version                           #
########################################################################
Function Update-ProjectVersion {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$SemVer10,
        [Parameter(Mandatory = $true)]
        [string]$SemVer20
    )
  
    Process {
        Write-H2 "Patching $Path"
        $TmpFile = $Path + ".tmp"

        #backup file for reverting later
        Copy-Item $Path $TmpFile

        #load project xml
        [xml]$xml = Get-Content -Path $Path

        #ensure version nodes exist
        $propertyGroupNode = $xml.SelectSingleNode("//Project/PropertyGroup")
        if ($propertyGroupNode -eq $null) {
            Write-Problem "csproj format not recognized. Is this a valid VS 17 project file?"
            return
        }

        #assert node exists
        @( "Version", "AssemblyVersion", "FileVersion") | % {
            if ($propertyGroupNode.SelectSingleNode("//$($_)") -eq $null) {
                $propertyGroupNode.AppendChild($xml.CreateElement($_)) | Out-Null
            }
            
            $propertyGroupNode.SelectSingleNode("//$($_)").InnerText = $SemVer10
            
            if ($_ -eq "Version") {
                $propertyGroupNode.SelectSingleNode("//$($_)").InnerText = $SemVer20
            }

            Write-Line "  $($_): $($propertyGroupNode.SelectSingleNode("//$($_)").InnerText)"
        }
                
        #write to project file
        $xml.Save($Path)	
    }
}
Function Undo-ProjectVersion {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [String]$Path
    )

    Process {
        $Path | % { 
            $TmpFile = $_ + ".tmp"
            Write-Line "Reverting $TmpFile"
            if (Test-Path($TmpFile)) {
                Move-Item $TmpFile $_ -Force
            }        
        }
    }    
}

########################################################################
#                                Tests                                 #
########################################################################
Function Test-Projects {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [HashTable]$TestProjects,
        [Parameter(Mandatory = $true)]
        [String]$Buildconfiguration
    )

    Begin {
        $testsPassed = $true
    }

    Process {
        $TestProjects.GetEnumerator() | ForEach-Object {

            Write-H2 "Testing $($_.key)"

            if (-NOT(Test-Path($_.value.Path))) {
                Write-Error  "$($_.value.Name) not found!"
            }
            else {
                Write-Line "Testing $($_.value.Path)"
                $testResult = dotnet test $_.value.Path --configuration $Buildconfiguration --no-build | Out-String
						
                $testResult | Write-Line

                if (-NOT ($testResult -imatch 'Passed!')) {							
                    $testsPassed = $false
                }                
            }            
        }        
    }

    End {
        if (-NOT($testsPassed)) {
            Write-Host "Tests failed!" -ForegroundColor Red -BackgroundColor Black
        }
        return $testsPassed
    }
}


########################################################################
#                                Nugets                                #
########################################################################
Function Publish-Nugets {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [HashTable]$Projects,
        [Parameter(Mandatory = $true)]
        [String]$NugetsOutputDir,
        [Parameter(Mandatory = $true)]
        [String]$NugetsSource,
        [Parameter(Mandatory = $true)]
        [String]$Buildconfiguration,
        [Parameter(Mandatory = $true)]
        [String]$ApiKey
    )

    Begin {        
    }
    
    Process {

        #create nugets and place in output Dir dir
        
        $Projects.Values | % {
            $packageId = $_["name"]
            Write-H2 "Packing $($packageId) -v $($_.SemVer20)"
            Write-Line "From $($_.Path)"
            dotnet pack $_.Path -p:PackageID=$packageId --configuration $BuildConfiguration --no-build --output $NugetsOutputDir | Out-String | Write-Line
        }        
                
        Get-ChildItem $NugetsOutputDir -Filter "*.nupkg" | % { 
            Write-H2 $_.FullName
            $result = dotnet nuget push $_.FullName --source $NugetsSource --api-key $ApiKey --no-symbols --force-english-output --skip-duplicate | out-string
            
            if (-NOT($result -imatch 'Your package was pushed.')) {                
                Write-Problem $result
            }
        }         
    }

    End {        
    }
}

########################################################################
#                             PS Foundation                            #
########################################################################
Function Test-PathVerbose {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [String]$Path
    )
    PROCESS {
        Write-Line "Asserting path: $($Path) -> " -NoNewLine

        if (Test-Path $Path) {
            Write-Line "Found!"
            return $true
        }
        else {
            Write-Problem "Not Found!"
            return $false
        }
    }
}
Function Enter-Dir {
    [CmdletBinding()]
    Param (                
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [String]$Path
    )
    PROCESS {
        
        if (Test-Path $Path) {
            Write-Line "Entered: $($Path) From $((Get-Location).Path)"
            Set-Location $Path            
            return $true
        }
        else {
            Write-Warning "Dir not found: $($Path)"
            return $false
        }
    }
}

########################################################################
#                                 Write                                #
########################################################################
Function Write-H1 {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$message
    )
    Process {        
        Write-Host $message -ForegroundColor Cyan
    }
}
Function Write-H2 {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$message
    )
    Process {        
        Write-Host $message -ForegroundColor Gray
    }
}
Function Write-Warning {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$message
    )
    Process {        
        Write-Host $message -ForegroundColor Yellow -BackgroundColor Black
    }
}
Function Write-Problem {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$message
    )
    Process {        
        Write-Host $message -ForegroundColor Red -BackgroundColor Black
    }
}
Function Write-Line {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$message,
        [Switch]$NoNewLine
    )
    Process {        
        Write-Host $message -ForegroundColor DarkGray -NoNewline:$NoNewLine
    }
}