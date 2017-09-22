Function New-Lib.Release
{
    [CmdletBinding()]
    Param (
        [string]$solutionName = "netcore.basics",
        [switch]$nonugets = $false,
        [switch]$notests = $false,
        [string]$testProjectFilter = "*.tests.csproj",
        [string]$buildConfiguration = "release"
    )

    Begin{
    }

    Process {
        $conf = Initialize-Lib.Release.Configuration $solutionName | Expand-Lib.Release.Configuration

        if(
            ((Test-PathVerbose $conf.Solution.Dir) -eq $false)
        ){
            Write-Host "Aborting...!" -ForegroundColor Red -BackgroundColor Black
            return;
        }
        
        Write-Lib.Release.Configuration $conf

        #assert project paths
        Write-HostIfVerbose "Asserting project paths" -ForegroundColor Gray
        $allPathsOk = $true

        $conf.Projects.Values | % {
                        if (-NOT (Test-Path $_.Path )){ 
                            Write-Host "$($_.Path) not found!" -ForegroundColor Red
                            $allPathsOk = $false
                        }
                        if (-NOT (Test-Path $_.TestPath )){ 
                            Write-Host "$($_.TestPath) not found!" -ForegroundColor Red
                            $allPathsOk = $false
                        }
                    }
        if(-not ($allPathsOk)){
            Write-Error "Project paths are corrupt! See log for details. Aborting..."
            return
        }
        
        Invoke-InDir $conf.Solution.Dir {
            try{
                ######### Initialize Git Dir #########    
                $gitGoodToGoNeedle = 'nothing to commit, working tree clean'
                $gitStatus = git status | Out-String
		        if($gitStatus -imatch $gitGoodToGoNeedle){                
                    Write-HostIfVerbose "Cleaning $((Get-Location).Path)" -ForegroundColor Gray 
    		        #clean
                    git clean -d -x -f | Out-String | Write-HostIfVerbose
                
    		    } else {
                    Write-Host "Git dir contains uncommitted changes and is not ready for release! Expected '$($gitGoodToGoNeedle)'. Aborting..." -ForegroundColor Red -BackgroundColor Black
                    Write-Host "$($gitStatus)" -ForegroundColor White
                    return
                }

                #restore projects
                $conf.Projects.Values | % { $_.Path } | % { 
                    Write-HostIfVerbose "Restoring $($_)" -ForegroundColor Gray
                    dotnet restore $_ | Write-HostIfVerbose 
                }
                #TODO: Write to error if error
                
                #patch project version
                $conf.Projects.Values | % { Update-ProjectVersion $_.Path $_.SemVer10 $_.SemVer20 }

                #build sln
                Write-HostIfVerbose "Building $($conf.Solution.Path)" -ForegroundColor Gray
                dotnet build $conf.Solution.Path --configuration $conf.Build.Configuration --no-incremental --verbosity minimal | Write-HostIfVerbose
                
                #nugets
                #clean output dir if exists
                if(Test-Path $conf.Nuget.OutputDir) { Remove-Item "$($conf.Nuget.OutputDir)\*" -Force | Write-Host -ForegroundColor DarkGray }
                #create aritfacts dir
                New-Item $conf.Nuget.OutputDir -ItemType Directory -Force | Write-Host -ForegroundColor DarkGray


            } finally {
                #clean output Dir if exists
                if(Test-Path $conf.Nuget.OutputDir) { Remove-Item "$($conf.Nuget.OutputDir)\*" -Force | Write-Host -ForegroundColor DarkGray }
		        if(Test-Path $conf.Nuget.OutputDir) { Remove-Item "$($conf.Nuget.OutputDir)" -Force | Write-Host -ForegroundColor DarkGray }

		        #revert project version
                $conf.Projects.Values | % { $_.Path } | Undo-ProjectVersion
            }
        }
    }

    End{        
    }
}

########################################################################
#                             Configuration                            #
########################################################################


Function Initialize-Lib.Release.Configuration
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$solutionName,        
        [string]$buildConfiguration = "release",
        [string]$testProjectsSuffix = ".tests",
        [string]$projectsRootdir = "c:\projects"
    )
	PROCESS {

        [HashTable]$conf = @{}
        
        #----- sln -----#
        [HashTable]$conf.Solution = @{}
        $conf.Solution.Name = $solutionName.Trim('.','\')
        $conf.Solution.Dir = [System.IO.Path]::Combine($projectsRootdir,$conf.Solution.Name).TrimEnd('\')
        $conf.Solution.Path = "$($conf.Solution.Dir)\$($conf.Solution.Name).sln"        
        
        #----- msbuild -----#
        [HashTable]$conf.Build = @{}
        $conf.Build.Configuration = $buildConfiguration        

        #----- test -----#
        [HashTable]$conf.Test = @{}
        $conf.Test.ProjectsSuffix = $testProjectsSuffix
        $conf.Test.Disabled = $false        

        #----- nuget -----#
        [hashtable]$conf.Nuget = @{}
        $conf.Nuget.OutputDir = "$($conf.Solution.Dir)\Lib.Release.Output"
        $conf.Nuget.Disabled = $false

        return $conf
    }
}

Function Expand-Lib.Release.Configuration
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
        [Alias('Configuration')]
        [HashTable]$conf
    )
    PROCESS {        

        #----- msbuild -----#
        [HashTable]$conf.System = @{}
        $conf.System.CurrentDir = (Get-Location).Path
        $conf.System.ScriptDir = $PSScriptRoot

        #----- release -----#
        [HashTable]$conf.Release = @{}
        $conf.Release.Params = Get-Content -Raw -Path "$($conf.Solution.Dir)\lib.release.json"  | ConvertFrom-Json
        
        #----- git -----#
        [HashTable]$conf.Git = @{}

        Invoke-InDir $conf.Solution.Dir {
            $conf.Git.Branch = git rev-parse --abbrev-ref HEAD
            $conf.Git.Hash = git rev-parse --verify HEAD
            $conf.Git.ShortHash = git log --pretty=format:'%h' -n 1
            $conf.Git.Commits = git rev-list --all --count $conf.Git.Branch
        }        
        
        #----- projects -----#
        
        [HashTable]$conf.Projects = @{}        
        foreach($releaseParams in $conf.Release.Params) {
            $pInfo = Get-ProjectInfo $conf $releaseParams
            $conf.Projects.Add($pInfo.Name,$pInfo)
        }

        return $conf
    }
}

Function Write-Lib.Release.Configuration
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [HashTable]$configuration,
        [Parameter(Position=1)]
        [Int]$level = 0
    )
    Process {
        if ((Test-Verbose) -ne $true){
            return
        }

        $level++

        $spacer = ""
        for($i=0; $i -lt $level; $i++){
            $spacer += "  "
        }

        foreach ($conf in $configuration.GetEnumerator()) {
      
            $confType = $conf.Value.GetType().fullname            
            
            if($confType -eq "System.Collections.HashTable"){
                Write-Host "$($spacer)[$($conf.Key)]" -ForegroundColor Gray
                Write-Lib.Release.Configuration $conf.Value $level
            }
            else {
                Write-Host "$($spacer)$($conf.Key) : $($conf.Value)" -ForegroundColor DarkGray
            }            
        }
    }
}

Function Get-ProjectInfo
{
	[CmdletBinding()]
    Param (
        [Parameter(Position=0, 
        Mandatory=$true )]
        [HashTable]$conf,
        [Parameter(Position=1, 
        Mandatory=$true )]
        [PSCustomObject]$releaseParams       
    )

	PROCESS {
        [HashTable]$pInfo = @{}
        $pInfo.Name = "$($releaseParams.name)"
        $pInfo.TestName = "$($pInfo.Name).tests"
        $pInfo.Dir = "$($conf.Solution.Dir)\$($pInfo.Name)"
        $pInfo.Path = "$($pInfo.Dir)\$($pInfo.Name).csproj"
        $pInfo.TestPath = "$($conf.Solution.Dir)\$($pInfo.TestName)\$($pInfo.TestName).csproj"
        $pInfo.Major = $releaseParams.major
        $pInfo.Minor = $releaseParams.minor
        $pInfo.Version = "$($pInfo.Major).$($pInfo.Minor).$($conf.Git.Commits)"
        $pInfo.SemVer10 = $pInfo.Version    
            
	    if(-NOT ([String]::IsNullOrEmpty($releaseParams.prerelease))){
		    $releaseParams.prerelease= "-$($releaseParams.prerelease)"
	    }
    
        $pInfo.SemVer20 = "$($pInfo.semver10)$($releaseParams.prerelease)+$($conf.Git.ShortHash)"

        return $pInfo
	}
}

Function New-Lib.Release.Arkiv
{
	PROCESS {

		$testsPassed = $true;
        
        if(-NOT ($notests)){            
				
				$testProjects = Get-ChildItem -Path "$slnDir" -Filter "$testProjectFilter" -Recurse | Select-Object 
				
				Write-Host "Test projects found: $testProjects" -ForegroundColor DarkGray

				$testProjects | % {			
						Write-Host "Testing $_"

						$testResult = dotnet test $_.Directory.FullName --configuration $buildConfiguration --no-build
						
						Write-Host $testResult -ForegroundColor DarkGray

						if(-NOT ($testResult -imatch 'Test Run Successful.')){
							Write-Host "$_.Name tests failed" -ForegroundColor Red
							$testsPassed = $false
						} else {
							Write-Host "$_.Name tests passed" -ForegroundColor DarkGray
						}
				}

                if($testsPassed){
                    Write-Host "All tests passed" -ForegroundColor Green
                }            
        } 
		        
        #create nugets if all tests passed
        if($testsPassed) {
            
            if(-NOT ($nonugets)) {

				#create nugets and place in output Dir dir
				foreach($project in $projects) {					
	                $projectFile = $project."project.file"
					$packageVersion = $project."project.semVer10"
                
					Write-Host "Packing $projectFile -v $packageVersion"
					dotnet pack $projectFile --configuration $buildConfiguration --no-build --output $outputDir  | Write-Host -ForegroundColor DarkGray
				}

                $apiKey = Read-Host "Please enter nuget API key"
                #https://docs.nuget.org/consume/command-line-reference
                Get-ChildItem $outputDir -Filter "*.nupkg" | % { 
                    Write-Host $_.FullName
                    & "$buildScriptDir\nuget.exe" push $_.FullName -ApiKey $apiKey -Source "https://api.nuget.org/v3/index.json" -NonInteractive | Write-Host -ForegroundColor DarkGray
                }                
            }            
            Write-host "Build completed!" -ForegroundColor Green
        }
        else {
            Write-host "Build failed!" -ForegroundColor Red
        }
	}
	
}

Function Get-ProjectDir
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,
        [string]$ProjectsRootDir = "c:\projects"
    )
	Process {
        $projectDir = [System.IO.Path]::Combine($ProjectsRootDir,$ProjectName).TrimEnd('\')
        if(-NOT (Test-Path($projectDir))) {
            throw "Project dir not found: $projectDir"
        }
        else {
            return $projectDir
        }
	}
}

########################################################################
#                            Project Version                           #
########################################################################


Function Update-ProjectVersion
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$SemVer10,
        [Parameter(Mandatory=$true)]
        [string]$SemVer20
    )
  
	Process {
        Write-HostIfVerbose "Updating $Path" -ForegroundColor DarkGray
        $TmpFile = $Path + ".tmp"   
        Write-HostIfVerbose "Backup: $TmpFile"  -ForegroundColor DarkGray

        #backup file for reverting later
        Copy-Item $Path $TmpFile

	    #load project xml
	    [xml]$xml = Get-Content -Path $Path

	    #ensure version nodes exist
	    $propertyGroupNode = $xml.SelectSingleNode("//Project/PropertyGroup")
	    if ($propertyGroupNode -eq $null) {
    		Write-Host "csproj format not recognized. Is this a valid VS 17 project file?" |-ForegroundColor Red
		    return
	    }
		
	    if ($propertyGroupNode.Version -eq $null) {
    		$propertyGroupNode.AppendChild($xml.CreateElement("Version")) | Write-Host -ForegroundColor DarkGray
    	}

	    if ($propertyGroupNode.AssemblyVersion -eq $null) {
    		$propertyGroupNode.AppendChild($xml.CreateElement("AssemblyVersion"))| Write-Host -ForegroundColor DarkGray
    	}
	
	    if ($propertyGroupNode.FileVersion -eq $null) {
    		$propertyGroupNode.AppendChild($xml.CreateElement("FileVersion"))| Write-Host -ForegroundColor DarkGray
    	}

	    #update versions
	    $propertyGroupNode.SelectSingleNode("//Version").InnerText = $SemVer20
	    $propertyGroupNode.SelectSingleNode("//AssemblyVersion").InnerText = $SemVer10
	    $propertyGroupNode.SelectSingleNode("//FileVersion").InnerText = $SemVer10
		
    	#write to project file
        $xml.Save($Path)	
	}
}

Function Undo-ProjectVersion
{
	[CmdletBinding()]
	Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [String]$Path
        )

    Process{
        $Path | % { 
            $TmpFile = $_ + ".tmp"
            Write-HostIfVerbose "Reverting $TmpFile"
            if(Test-Path($TmpFile)){
                Move-Item $TmpFile $_ -Force
            }        
        }
    }    
}

########################################################################
#                             PS Foundation                            #
########################################################################
Function Invoke-InDir
{
    [CmdletBinding()]
    Param (                
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [String]$Path,
        [Parameter(Position=1, Mandatory=$true)]
        [Scriptblock]$Script,
        [Parameter(Position=2)]
        [String]$ExitPath = (Get-Location).Path
    )
    PROCESS {

        $pathEntered = $false

        try{
            if( Test-Path $Path){
                sl $Path
                $pathEntered = $true
                Write-HostIfVerbose "Entered: $($Path) From $ExitPath"               

                $Script.InvokeReturnAsIs()
            }
            else {
                Write-HostIfVerbose "Not Entered: $($Path)"
                return 
            }
        } finally {
            if($pathEntered){
                sl $ExitPath
                Write-HostIfVerbose "Exited: $($Path) To $ExitPath"
            }            
        }        
    }
}


Function Write-HostIfVerbose
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [String]$message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::DarkGray,
        [ConsoleColor]$BackgroundColor
    )
    Process {
        if(Test-Verbose) {
            if($BackgroundColor) {
                Write-Host $message -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
            } else {
                Write-Host $message -ForegroundColor $ForegroundColor
             
            }
        }
    }
}

Function Test-PathVerbose
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [String]$path
    )
    PROCESS {

        if(Test-Path $path){
            return $true
        } else {
            Write-Error "$($path) not found!"
            return $false
        }
    }
}

Function Test-Verbose {
    [CmdletBinding()]
    param()
    [System.Management.Automation.ActionPreference]::SilentlyContinue -ne $VerbosePreference
}