Function New-Lib.Release
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$SolutionName,
        [switch]$NoNugets = $false,
        [switch]$NoTests = $false,
        [string]$TestsProjectSuffix = ".tests",
        [string]$BuildConfiguration = "release",
        [string]$ScanRootDir = "c:\projects"
    )

    Begin{
        $currentDir = (Get-Location).Path

        Write-HostIfVerbose "Initializing $($SolutionName) for release" -ForegroundColor Cyan        
        
    }

    Process {

        Write-Progress -Activity "Initializing $($SolutionName) for release" -Status "Initializing configuration"
        
        $conf = Initialize-Lib.Release.Configuration $SolutionName -buildConfiguration $BuildConfiguration -testsProjectSuffix $TestsProjectSuffix -ScanRootDir $ScanRootDir -NoTests:$NoTests -NoNugets:$NoNugets
        
        $conf | Write-Lib.Release.Configuration

        if(-NOT($conf.InitSuccess)){ 
            Write-Host "Initialization failed. Verify target solution exists." -ForegroundColor Red -BackgroundColor Black
            return
        }
        
        #assert project paths        
        if(-NOT($conf.Projects.Values | % { (Test-PathVerbose $_.Path) -and (Test-PathVerbose $_.TestPath) } )){
            Write-Error "Aborting..."
            return
        }        
        
        if((Enter-Dir $conf.Solution.Dir)) {
            try{                
                ######### Initialize Git Dir #########    
                Write-Progress -Activity "Initializing $($SolutionName) for release" -Status "Initializing git dir"
                
                Write-HostIfVerbose "Cleaning $((Get-Location).Path)" -ForegroundColor Cyan
                $gitGoodToGoNeedle = 'nothing to commit, working tree clean'
                $gitStatus = git status | Out-String
                Write-HostIfVerbose $gitStatus 
		        if($gitStatus -imatch $gitGoodToGoNeedle){
                    $gitClean = git clean -d -x -f | Out-String
                    if(-NOT([string]::IsNullOrEmpty($gitClean))){ Write-HostIfVerbose $gitClean } #clean output is empty if nothing to clean so we need to check if string is empty
    		    } else {
                    Write-Host "Git dir contains uncommitted changes and is not ready for release! Expected '$($gitGoodToGoNeedle)'. Aborting..." -ForegroundColor Red -BackgroundColor Black
                    Write-Host "$($gitStatus)" -ForegroundColor Red -BackgroundColor Black
                    return
                }     
                
                #patch project version
                Write-Progress -Activity "dotnet" -Status "Patching versions"
                Write-HostIfVerbose "Patching project versions" -ForegroundColor Cyan
                $conf.Projects.Values | % { Update-ProjectVersion $_.Path $_.SemVer10 $_.SemVer20 }

                #restore projects
                Write-Progress -Activity "dotnet" -Status "Restoring"
                Write-HostIfVerbose "Restoring Nugets" -ForegroundColor Cyan
                $conf.Projects.Values | % { $_.Path } | % { 
                    Write-HostIfVerbose "Restoring $($_)" -ForegroundColor Gray
                    $restore = dotnet restore $_ | Out-String | Write-HostIfVerbose
                    #TODO: Write in red if error
                }
                                
                #build sln
                Write-Progress -Activity "dotnet" -Status "Building"
                Write-HostIfVerbose "Building $($conf.Solution.Path)" -ForegroundColor Cyan
                dotnet build $conf.Solution.Path --configuration $conf.Build.Configuration --no-incremental --verbosity minimal | Out-String | Write-HostIfVerbose
                #TODO: Write in red if error
                
                #tests
                if($conf.Tests.Disabled) {
                    Write-HostIfVerbose "Skipping tests. -NoTests flag set" -ForegroundColor Yellow
                } else {
                    Write-Progress -Activity "dotnet" -Status "Testing"
                    Write-HostIfVerbose "Testing release" -ForegroundColor Cyan
                    if(-NOT($conf.Projects | Test-Projects -BuildConfiguration $conf.Build.Configuration)){
                        return
                    }
                }
                
                #nugets
                #clean output dir if exists
                Write-Progress -Activity "Nugets" -Status "Cleaning output dir"
                Write-HostIfVerbose "Cleaning OutPut dir: $($conf.Nugets.OutputDir)" -ForegroundColor Cyan
                if(Test-Path $conf.Nugets.OutputDir) { Remove-Item "$($conf.Nugets.OutputDir)\*" -Force | Out-String | Write-HostIfVerbose }
                
                #create aritfacts dir
                New-Item $conf.Nugets.OutputDir -ItemType Directory -Force | Out-String | Write-HostIfVerbose

                if($conf.Nugets.Disabled){
                    Write-HostIfVerbose "Skipping nugets. -NoNugets flag set" -ForegroundColor Yellow -BackgroundColor Black                    
                } else {
                    Write-Progress -Activity "Nugets" -Status "Packaging"
                    Write-HostIfVerbose "Packaging Nugets" -ForegroundColor Cyan
                    $conf.Projects | Publish-Nugets -NugetsOutputDir $conf.Nugets.OutputDir -Buildconfiguration $conf.Build.Configuration | Out-Null #nuget.exe writes its own error messages
                }

            } finally {
                Write-Progress -Activity "Post build" -Status "Cleaning up garbage"
                Write-HostIfVerbose "Cleaning up..." -ForegroundColor Cyan

                #clean output Dir if exists
                if(Test-Path $conf.Nugets.OutputDir) { Remove-Item "$($conf.Nugets.OutputDir)\*" -Force | Write-Host -ForegroundColor DarkGray }
		        if(Test-Path $conf.Nugets.OutputDir) { Remove-Item "$($conf.Nugets.OutputDir)" -Force | Write-Host -ForegroundColor DarkGray }

		        #revert project version
                $conf.Projects.Values | % { $_.Path } | Undo-ProjectVersion                
                
                Write-Progress -Activity "Post build" -Completed
            }            
        }
        
    }
    End{        
        #bugging out!
        Enter-Dir $currentDir | Out-Null
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
        [string]$SolutionName,      
        [Parameter(Mandatory=$true)]  
        [string]$BuildConfiguration,
        [Parameter(Mandatory=$true)]
        [string]$TestsProjectSuffix,
        [Parameter(Mandatory=$true)]
        [string]$ScanRootDir,        
        [Parameter(Mandatory=$true)]
        [switch]$NoTests = $false,
        [Parameter(Mandatory=$true)]
        [switch]$NoNugets = $false
    )
	PROCESS {

        [HashTable]$conf = @{}
        $conf.InitSuccess = $false

        #----- sln -----#
        [HashTable]$conf.Solution = @{}
        $conf.Solution.Name = $SolutionName.Trim('.','\')
        $conf.Solution.Dir = [System.IO.Path]::Combine($ScanRootDir,$SolutionName).TrimEnd('\')
        $conf.Solution.Path = "$($conf.Solution.Dir)\$($conf.Solution.Name).sln"        

        if(-NOT(Test-PathVerbose $conf.Solution.Dir)){
            return $conf
        }
        
        #----- msbuild -----#
        [HashTable]$conf.Build = @{}
        $conf.Build.Configuration = $BuildConfiguration        

        #----- test -----#
        [HashTable]$conf.Tests = @{}
        $conf.Tests.ProjectSuffix = $TestsProjectSuffix
        $conf.Tests.Disabled = $NoTests    

        #----- nuget -----#
        [hashtable]$conf.Nugets = @{}
        $conf.Nugets.OutputDir = "$($conf.Solution.Dir)\Lib.Release.Output"
        $conf.Nugets.Disabled = $NoNugets
        
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
            $conf.Projects.Add($pInfo.Name, $pInfo)
        }

        $conf.InitSuccess = $true

        return $conf
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
        $pInfo.Dir = "$($conf.Solution.Dir)\$($pInfo.Name)"
        $pInfo.Path = "$($pInfo.Dir)\$($pInfo.Name).csproj"
        $pInfo.TestName = "$($pInfo.Name)$($conf.Tests.ProjectSuffix)"        
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

Function Write-Lib.Release.Configuration
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [HashTable]$configuration,
        [Parameter(Position=1)]
        [Int]$level = 0
    )

    Begin {
        if($level -eq 0){
            Write-HostIfVerbose "[Configuration]" -ForegroundColor Gray
        }
    }

    Process {
        $level++

        $spacer = ""
        for($i=0; $i -lt $level; $i++){
            $spacer += "  "
        }

        $configuration.GetEnumerator() | % {
                                
            if(($_.Value.GetType().fullname) -eq "System.Collections.HashTable"){
                Write-HostIfVerbose "$($spacer)[$($_.Key)]" -ForegroundColor Gray
                Write-Lib.Release.Configuration $_.Value $level
            }
            else {
                Write-HostIfVerbose "$($spacer)$($_.Key) : $($_.Value)" -ForegroundColor DarkGray
            }            
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
        Write-HostIfVerbose "Patching $Path" -ForegroundColor Gray
        $TmpFile = $Path + ".tmp"

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

        #assert node exists
        @( "Version", "AssemblyVersion", "FileVersion") | % {
            if ($propertyGroupNode.SelectSingleNode("//$($_)") -eq $null) {
    		    $propertyGroupNode.AppendChild($xml.CreateElement($_)) | Out-Null
            }
            
            $propertyGroupNode.SelectSingleNode("//$($_)").InnerText = $SemVer10
            
            if($_ -eq "Version"){
                $propertyGroupNode.SelectSingleNode("//$($_)").InnerText = $SemVer20
            }

            Write-HostIfVerbose "  $($_): $($propertyGroupNode.SelectSingleNode("//$($_)").InnerText)"
        }
                
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
#                                Tests                                 #
########################################################################
Function Test-Projects
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [HashTable]$Projects,
        [Parameter(Mandatory=$true)]
        [String]$Buildconfiguration
    )

    Begin {
        $testsPassed = $true
    }

    Process {
        $Projects.Values | % {         
            Write-HostIfVerbose "Testing $($_.TestPath)" -ForegroundColor Gray
            $testResult = dotnet test $_.TestPath --configuration $Buildconfiguration --no-build | Out-String
						
			$testResult | Write-HostIfVerbose 

			if(-NOT ($testResult -imatch 'Test Run Successful.')){							
			    $testsPassed = $false
			}        
        }        
    }

    End {
        if(-NOT($testsPassed)){
            Write-Host "Tests failed!" -ForegroundColor Red -BackgroundColor Black
        }
        return $testsPassed
    }
}


########################################################################
#                                Nugets                                #
########################################################################
Function Publish-Nugets
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [HashTable]$Projects,
        [Parameter(Mandatory=$true)]
        [String]$NugetsOutputDir,
        [Parameter(Mandatory=$true)]
        [String]$Buildconfiguration
    )

    Begin {
        $allNugetsPushed = $true
    }
    
    Process {        

        #create nugets and place in output Dir dir
        $Projects.Values | % {
		    Write-HostIfVerbose "Packing $($_.Path) -v $($_.SemVer10)"
			dotnet pack $_.Path --configuration $BuildConfiguration --no-build --output $NugetsOutputDir | Out-String | Write-HostIfVerbose
			}
                				        
        $apiKey = Read-Host "Please enter nuget API key"
        
        Write-Progress -Activity "Nugets" -Status "Publishing"

        #https://docs.nuget.org/consume/command-line-reference
        Get-ChildItem $NugetsOutputDir -Filter "*.nupkg" | % { 
            Write-HostIfVerbose $_.FullName -ForegroundColor Gray
            $result = & "$($PSScriptRoot)\nuget.exe" push $_.FullName -ApiKey $apiKey -Source "https://api.nuget.org/v3/index.json" -NonInteractive | Out-String

            if(-NOT($result -imatch 'Your package was pushed.')){
                $allNugetsPushed = $false
                Write-HostIfVerbose $result -ForegroundColor Red -BackgroundColor Black
            }
        }
        
    }

    End {
        return $allNugetsPushed
    }
}

########################################################################
#                             PS Foundation                            #
########################################################################
Function Test-PathVerbose
{
    [CmdletBinding()]
    Param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [String]$Path
    )
    PROCESS {
        Write-HostIfVerbose "Asserting path: $($Path) -> " -NoNewline

        if(Test-Path $Path){
            Write-HostIfVerbose "Found!"
            return $true
        } else {
            Write-HostIfVerbose "Not Found!" -ForegroundColor Red -BackgroundColor Black
            return $false
        }
    }
}

Function Enter-Dir
{
    [CmdletBinding()]
    Param (                
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [String]$Path
    )
    PROCESS {
        
        if(Test-Path $Path){
            Write-HostIfVerbose "Entered: $($Path) From $((Get-Location).Path)"
            sl $Path            
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
        [ConsoleColor]$BackgroundColor,
        [Switch]$NoNewline = $false
    )
    Process {
        if(Test-Verbose) {
            if($BackgroundColor) {
                Write-Host $message -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewline:$NoNewline
            } else {
                Write-Host $message -ForegroundColor $ForegroundColor -NoNewline:$NoNewline
             
            }
        }
    }
}

Function Test-Verbose {
    [CmdletBinding()]
    param()
    [System.Management.Automation.ActionPreference]::SilentlyContinue -ne $VerbosePreference
}