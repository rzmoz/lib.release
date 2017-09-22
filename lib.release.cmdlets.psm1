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
        $currentDir = (Get-Location).Path
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
                        if (-NOT (Test-Path $_.Path)){ 
                            Write-Host "$($_.Path) not found!" -ForegroundColor Red
                            $allPathsOk = $false
                        }
                        if (-NOT (Test-Path $_.TestPath )){ 
                            Write-Host "$($_.TestPath) not found!" -ForegroundColor Red
                            $allPathsOk = $false
                        }
                    }
        if(-NOT ($allPathsOk)){
            Write-Error "Project paths are corrupt! See log for details. Aborting..."
            return
        }

        if((Enter-Dir $conf.Solution.Dir)) {
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
                    dotnet restore $_ | Out-String | Write-HostIfVerbose 
                }
                #TODO: Write to error if error
                
                #patch project version
                $conf.Projects.Values | % { Update-ProjectVersion $_.Path $_.SemVer10 $_.SemVer20 }

                #build sln
                Write-HostIfVerbose "Building $($conf.Solution.Path)" -ForegroundColor Gray
                dotnet build $conf.Solution.Path --configuration $conf.Build.Configuration --no-incremental --verbosity minimal | Out-String | Write-HostIfVerbose
                
                #nugets
                #clean output dir if exists
                if(Test-Path $conf.Nuget.OutputDir) { Remove-Item "$($conf.Nuget.OutputDir)\*" -Force | Write-HostIfVerbose }
                #create aritfacts dir
                New-Item $conf.Nuget.OutputDir -ItemType Directory -Force | Write-HostIfVerbose

                
                #tests
                $testsPassed = $true;
        
                if(-NOT ($notests)){            
				    $conf.Projects.Values | % { $_.TestPath } | % {
                        Write-HostIfVerbose "Testing $($_)" -ForegroundColor Gray
                        
                        $testResult = dotnet test $_ --configuration $conf.Build.Configuration --no-build | Out-String
						
						Write-HostIfVerbose $testResult

						if(-NOT ($testResult -imatch 'Test Run Successful.')){
							Write-Host "$($_) tests failed" -ForegroundColor Red
							$testsPassed = $false
						}
                    }						
				}

                if(-NOT ($testsPassed)){                    
                    return
                }

                #nugets
                if($testsPassed) {
                    if(-NOT ($nonugets)) {
                        #create nugets and place in output Dir dir
                        $projects | % {
							Write-HostIfVerbose "Packing $($_.Path) -v $($_.SemVer10)"
					        dotnet pack $_.Path --configuration $conf.Build.Configuration --no-build --output $conf.Nuget.OutputDir | Out-String | Write-HostIfVerbose
						}
				        
                        $apiKey = Read-Host "Please enter nuget API key"
                        #https://docs.nuget.org/consume/command-line-reference
                        Get-ChildItem $conf.Nuget.OutputDir -Filter "*.nupkg" | % { 
                            Write-HostIfVerbose $_.FullName -ForegroundColor Gray
                            & "$($PSScriptRoot)\nuget.exe" push $_.FullName -ApiKey $apiKey -Source "https://api.nuget.org/v3/index.json" -NonInteractive | Write-HostIfVerbose
                        }                        
                    }            
                } else {
                    Write-Error "Release failed!"
                }

            } finally {
                #clean output Dir if exists
                if(Test-Path $conf.Nuget.OutputDir) { Remove-Item "$($conf.Nuget.OutputDir)\*" -Force | Write-Host -ForegroundColor DarkGray }
		        if(Test-Path $conf.Nuget.OutputDir) { Remove-Item "$($conf.Nuget.OutputDir)" -Force | Write-Host -ForegroundColor DarkGray }

		        #revert project version
                $conf.Projects.Values | % { $_.Path } | Undo-ProjectVersion

                #bugging out!
                sl $currentDir
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

        if((Enter-Dir $conf.Solution.Dir)) {
            $conf.Git.Branch = git rev-parse --abbrev-ref HEAD
            $conf.Git.Hash = git rev-parse --verify HEAD
            $conf.Git.ShortHash = git log --pretty=format:'%h' -n 1
            $conf.Git.Commits = git rev-list --all --count $conf.Git.Branch
        } else {
            return
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
    		Write-Error "csproj format not recognized. Is this a valid VS 17 project file?" |-ForegroundColor Red
		    return
	    }
		
	    if ($propertyGroupNode.Version -eq $null) {
    		$propertyGroupNode.AppendChild($xml.CreateElement("Version")) | Write-HostIfVerbose
    	}

	    if ($propertyGroupNode.AssemblyVersion -eq $null) {
    		$propertyGroupNode.AppendChild($xml.CreateElement("AssemblyVersion")) | Write-HostIfVerbose
    	}
	
	    if ($propertyGroupNode.FileVersion -eq $null) {
    		$propertyGroupNode.AppendChild($xml.CreateElement("FileVersion")) | Write-HostIfVerbose
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
Function Enter-Dir
{
    [CmdletBinding()]
    Param (                
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [String]$Path
    )
    PROCESS {
        
        if( Test-Path $Path){
            sl $Path
            Write-HostIfVerbose "Entered: $($Path) From $ExitPath"               
            return $true
        } else {
            Write-Error "Failed to enter: $($Path)"
            return $false
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