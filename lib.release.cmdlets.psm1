Function New-Lib.Release
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$solutionName,
        [switch]$nonugets = $false,        
        [switch]$notests = $false,
        [string]$testProjectFilter = "*.tests.csproj",
        [string]$buildConfiguration = "release"
    )

    ##*********** Init ***********##

	#trim solution name
	$solutionName = $solutionName.Trim('.','\')

    $currentDir =  (Get-Item -Path ".\" -Verbose).FullName
    Write-Host "dir.current: $currentDir" -ForegroundColor Cyan

	Write-Host "##*********** sln ***********##" -ForegroundColor Cyan

    $slnDir = Get-ProjectDir $solutionName
    Write-Host "sln.dir: $slnDir" -ForegroundColor Cyan
        
    $slnPath = "$slnDir\$solutionName.sln"
    Write-Host "sln.path: $slnPath" -ForegroundColor Cyan

    $releaseParams = (Get-Content -Raw -Path $slnDir\lib.release.json | ConvertFrom-Json).projects
    Write-Host "sln.release.params:"$releaseParams -ForegroundColor Cyan    

    $buildScriptDir = Get-ProjectDir "lib.release"
    Write-Host "lib.release.dir: $buildScriptDir" -ForegroundColor Cyan       
    Write-Host "build.configuration: $buildConfiguration" -ForegroundColor Cyan
    Write-Host "nugets.disabled: $nonugets" -ForegroundColor Cyan
    $outputDir = "$slnDir\Output"
    Write-Host "nugets.output.dir: $outputDir" -ForegroundColor Cyan    

    Write-Host "##*********** tests ***********##" -ForegroundColor Cyan

    Write-Host "tests.disabled: $notests" -ForegroundColor Cyan
    Write-Host "tests.filter: $testProjectFilter" -ForegroundColor Cyan    
    
    
    if(Test-Path $slnDir ){        
        sl $slnDir  #moving location 
        Write-Host "location: $slnDir " -ForegroundColor Cyan
    } else {
        Write-Host "$slnDir not found. Aborting.." -ForegroundColor Red
        return
    }

    Write-Host "##*********** git ***********##" -ForegroundColor Cyan

    $branch = git rev-parse --abbrev-ref HEAD
    Write-Host "git.branch: $branch" -ForegroundColor Cyan
        
    $commitHash = git rev-parse --verify HEAD
    Write-Host "git.hash: $commitHash" -ForegroundColor Cyan
        
    $shortHash = git log --pretty=format:'%h' -n 1
    Write-Host "git.hash.short: $shortHash" -ForegroundColor Cyan

    $commitsSinceInit = git rev-list --first-parent --count HEAD
    Write-Host "git.commits: $commitsSinceInit" -ForegroundColor Cyan

    Write-Host "##*********** projects ***********##" -ForegroundColor Cyan

    $projects = New-Object System.Collections.ArrayList

    foreach($projectParams in $releaseParams) {
        $projectInfo = New-ProjectInfo -slnDir $slnDir -slnName $slnName -projectParams $projectParams        
        $projects.Add($projectInfo)
    }

    Write-Host ($projects | Out-String) -ForegroundColor DarkGray

	#verify all changes are committed before proceeding	
	if(Get-GitStatus $slnDir){
		Write-Host "Git status is clean. good to go"
	} else {
		Write-Host "Git status not ready to release. Are all changes committed?"  -ForegroundColor Red
		return -1
	}
	
	$projectFiles = $projects | % { $_."project.file" }

	##*********** Generate lib release package(s) ***********##
    try
	{
	
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

Function New-ProjectInfo
{
    Param (
        [string]$slnDir,
        [string]$slnName,
        [PSCustomObject]$projectParams
    )

    Write-host "Processing project:"($projectParams) -ForegroundColor DarkGray
                
    $projectInfo = New-Object System.Collections.Hashtable
            
    $projectName = $solutionName+$projectParams.extension
    $projectInfo.Add("project.name",$projectName);

	$projectFile = "$slnDir\$projectName\$projectName.csproj"
    $projectInfo.Add("project.file",$projectFile);

    $projectDir = "$slnDir\$projectName"
    $projectInfo.Add("project.dir",$projectDir);

    $projectVersion = $projectParams.version
    $projectInfo.Add("project.version",$projectVersion);
            
    $semver10 = $projectVersion
    $projectInfo.Add("project.semVer10",$semver10);
            
    $semver20 = "$semver10+$commitsSinceInit.$commitHash"
    $projectInfo.Add("project.semVer20",$semver20);
	
    return $projectInfo    
}

Function Restore-Project
{
Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath
    )

	Write-Host "Restoring $ProjectPath"
	dotnet restore $ProjectPath | Write-Host -ForegroundColor DarkGray
}

Function Get-ProjectDir
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,
        [string]$ProjectsRootDir = "c:\projects"
    )

    $projectDir = [System.IO.Path]::Combine($ProjectsRootDir,$ProjectName).TrimEnd('\')
    if(-NOT (Test-Path($projectDir))) {
        throw "Project dir not found: $projectDir"
    }
    else {
        return $projectDir
    }
}

Function Get-GitStatus
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName
    )

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

Function Reset-GitDir
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName
    )

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

Function Update-ProjectVersion
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectFullName,
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [Parameter(Mandatory=$true)]
        [string]$SemVer20
    )
  
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
	$propertyGroupNode.SelectSingleNode("//AssemblyVersion").InnerText = $Version
	$propertyGroupNode.SelectSingleNode("//FileVersion").InnerText = $Version
		
	#write to project file
    $xml.Save($fullName)	
}

Function Undo-ProjectVersion
{
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
