Function Get-Lib.Release.Configuration
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$solutionName,        
        [string]$buildConfiguration = "release",
        [string]$testsSuffix = ".tests",
        [string]$projectsRootdir = "c:\projects"
    )
	PROCESS {

        [hashtable]$conf = @{}
        
        #----- system ------#
        $conf.CurrentDir = (Get-Item -Path ".\" -Verbose).FullName
        
        #----- sln -----#
        [hashtable]$conf.Solution = @{}

        $conf.Solution.Name = $solutionName.Trim('.','\')
        $conf.Solution.Dir = [System.IO.Path]::Combine($projectsRootdir,$conf.Solution.Name).TrimEnd('\')
        $conf.Solution.Path = "$($conf.Solution.Dir)\$($conf.Solution.Name).sln"        
        
        #----- msbuild -----#
        [hashtable]$conf.Build = @{}
        $conf.Build.Configuration = $buildConfiguration        

        #----- test -----#
        [hashtable]$conf.Test = @{}
        $conf.Test.ProjectsFilter = $testProjectsFilter
        $conf.Test.Disabled = $false        

        #----- nuget -----#
        [hashtable]$conf.Nuget = @{}
        $conf.Nuget.OutputDir = "$($conf.Solution.Dir)\Lib.Release.Output"
        $conf.Nuget.Disabled = $false        

        ####----- Expanding Configurations -----####
        if(Test-Path $conf.Solution.Dir){        
            sl $conf.Solution.Dir  #moving location             
        } else {
            Write-Error "$($conf.Solution.Dir) not found. Aborting..."
            return
        }
        
        #----- release -----#
        [hashtable]$conf.Release = @{}                
        $conf.Release.Params = Get-Content -Raw -Path "$($conf.Solution.Dir)\lib.release.json"  | ConvertFrom-Json
        
        #----- git -----#
        [hashtable]$conf.Git = @{}
        $conf.Git.Branch = git rev-parse --abbrev-ref HEAD
        $conf.Git.Hash = git rev-parse --verify HEAD
        $conf.Git.ShortHash = git log --pretty=format:'%h' -n 1
        $conf.Git.Commits = git rev-list --all --count $conf.Git.Branch
        
        #----- projects -----#
        
        [hashtable]$conf.Projects = @{}        
        foreach($releaseParams in $conf.Release.Params) {
            $pInfo = New-ProjectInfo $conf $releaseParams
            $conf.Projects.Add($pInfo.Name,$pInfo)
        }

        #$conf.ProjectFiles = $conf.Projects | % { $_."project.file" }
        
        Write-Lib.Release.Configuration $conf

        return $conf
    }
}

Function New-ProjectInfo
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

        [hashtable]$pInfo = @{}
        $pInfo.Name = "$($releaseParams.name)"
        $pInfo.TestName = "$($pInfo.Name).tests"
        $pInfo.Dir = "$($conf.Solution.Dir)\$($pInfo.Name)"
        $pInfo.Path = "$($pInfo.Dir)\$($pInfo.Name).csproj"
        $pInfo.Major = $releaseParams.major
        $pInfo.Minor = $releaseParams.minor
        $pInfo.Version = "$($pInfo.Major).$($pInfo.Minor).$($conf.Commits)"
        $pInfo.SemVer10 = $pInfo.Version    
            
	    if(-NOT ([string]::IsNullOrEmpty($releaseParams.prerelease))){
		    $releaseParams.prerelease= "-$($releaseParams.prerelease)"
	    }
    
        $pInfo.SemVer20 = "$($pInfo.semver10)$($releaseParams.prerelease)+$($conf.Git.ShortHash)"

        return $pInfo
	}
}

Function New-Lib.Release
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$solutionName,
        [switch]$nonugets = $false,        
        [switch]$notests = $false,
        [string]$testProjectFilter = "*.tests.csproj",
        [string]$buildConfiguration = "release"
    )
	PROCESS {

    ##*********** Init ***********##
    $conf = Get-Lib.Release.Configuration     

	##*********** Generate lib release package(s) ***********##
    try
	{	
		#git clean pre-conditions: git status is ready for deployment
		#verify all changes are committed before proceeding	
	    if(Get-GitStatus $slnDir){
    		Write-Host "Git status is clean. good to go"
	    } else {
    		Write-Host "Git status not ready to release. Are all changes committed?"  -ForegroundColor Red
		    return -1
	    }

        #clean repo for release - this will mess things up if everything is not committed!		
        #https://git-scm.com/docs/git-clean
        Write-Host "Cleaning repo for $buildConfiguration build"
        Reset-GitDir $slnDir | Write-Host -ForegroundColor DarkGray
  
        #restore projects
		$projectFiles | % { Restore-Project $_ }
		
		#patch project version
        $projects| %{ Update-ProjectVersion $_."project.file" $_."project.semVer10" $_."project.semVer20"}
				
        #build sln
        Write-Host "Building $slnPath"
        dotnet build $slnPath --configuration $buildConfiguration --no-incremental --verbosity minimal | Write-Host -ForegroundColor DarkGray
        		
        #clean output dir if exists
        if(Test-Path $outputDir) { Remove-Item "$outputDir\*" -Force | Write-Host -ForegroundColor DarkGray }
        #create aritfacts dir
        New-Item $outputDir -ItemType Directory -Force | Write-Host -ForegroundColor DarkGray
        
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
		
    } finally {        
        #clean output Dir if exists
        if(Test-Path $outputDir) { Remove-Item "$outputDir\*" -Force | Write-Host -ForegroundColor DarkGray }
		if(Test-Path $outputDir) { Remove-Item "$outputDir" -Force | Write-Host -ForegroundColor DarkGray }

		#revert project version
        $projectFiles | Undo-ProjectVersion
		
        Write-Host "Setting location $currentDir" | Write-Host -ForegroundColor DarkGray
        sl $currentDir        
    }	
	}
	
}

Function Restore-Project
{
Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath
    )

	PROCESS {
	Write-Host "Restoring $ProjectPath"
	dotnet restore $ProjectPath | Write-Host -ForegroundColor DarkGray
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
	PROCESS {
    $projectDir = [System.IO.Path]::Combine($ProjectsRootDir,$ProjectName).TrimEnd('\')
    if(-NOT (Test-Path($projectDir))) {
        throw "Project dir not found: $projectDir"
    }
    else {
        return $projectDir
    }
	}
}

Function Get-GitStatus
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName
    )
	PROCESS {
    $projectDir = Get-ProjectDir $ProjectName

    $currentDir = (Get-Location).Path

    try{
        sl $projectDir
		Write-Host "Asserting Git status is ready for release" -ForegroundColor DarkGray
        $gitStatus = git status | Out-String 
		Write-Host $gitStatus -ForegroundColor DarkGray
		
		if($gitStatus -imatch 'nothing to commit, working tree clean'){
			return $true
		} else {			
			return $false
		}
	} finally {
        sl $currentDir
    }  
	}
}

Function Reset-GitDir
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName
    )

	PROCESS {
    $projectDir = Get-ProjectDir $ProjectName

    $currentDir = (Get-Location).Path

    try{
        sl $projectDir
        git clean -d -x -f
    } finally {
        sl $currentDir
    }

    Write-Verbose "Git dir: $projectDir"
	}
}

Function Update-ProjectVersion
{
	[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectFullName,
        [Parameter(Mandatory=$true)]
        [string]$SemVer10,
        [Parameter(Mandatory=$true)]
        [string]$SemVer20
    )
  
	PROCESS {
    Write-Host "Updating project version for $ProjectFullName"

    $fullName = $ProjectFullName
    Write-host "Updating $fullName" -ForegroundColor DarkGray
    $TmpFile = $ProjectFullName + ".tmp"   
    Write-host "Backup: $TmpFile"  -ForegroundColor DarkGray

    #backup file for reverting later
    Copy-Item $fullName $TmpFile

	#load project xml
	[xml]$xml = Get-Content -Path $fullName 

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
    $xml.Save($fullName)	
	}
}

Function Undo-ProjectVersion
{
	[CmdletBinding()]
	Param (
    )

    Write-host "Reverting project version"
    foreach ($o in $input)
    {
        $TmpFile = $o + ".tmp"
        Write-host "Reverting $TmpFile" -ForegroundColor DarkGray
        if(Test-Path($TmpFile)){            
            Move-Item $TmpFile $o -Force
        }        
    }
}


Function Write-Lib.Release.Configuration
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]        
        [HashTable]$configuration
    )
    PROCESS {
        foreach ($conf in $configuration.GetEnumerator()) {
      
            $confType = $conf.Value.GetType().fullname            
            
            if($confType -eq "System.Collections.HashTable"){
                
                $conf.Value.GetEnumerator() | foreach { Write-Verbose "$($conf.Key).$($_.Key) : $($_.Value)"}
            }
            elseif($confType -eq "System.Collections.ArrayList"){
                
                $conf.GetEnumerator()| foreach{ Write-Verbose "$($_)" }
                
            } else{
                Write-Verbose "$($conf.Key) : $($conf.Value)"    
            }            
        }
    }
}