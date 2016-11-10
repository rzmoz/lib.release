Function New-Lib.Release
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$solutionName,
        [switch]$nonugets = $false,        
        [switch]$notests = $false,
        [string]$testAssembliesFilter = "*.tests.dll",
        [string]$msbuildConfiguration = "release"
    )

    ##*********** Init ***********##

    $currentDir =  (Get-Item -Path ".\" -Verbose).FullName
    Write-Host "dir.current: $currentDir" -ForegroundColor Cyan

    $buildScriptDir = Get-ProjectDir "lib.release"
    Write-Host "lib.release.dir: $buildScriptDir" -ForegroundColor Cyan       
    Write-Host "msbuild.configuration: $msbuildConfiguration" -ForegroundColor Cyan
    Write-Host "nugets.enabled: $nugets" -ForegroundColor Cyan
    $outputDir = "$slnDir\Output"
    Write-Host "nugets.output.dir: $outputDir" -ForegroundColor Cyan
    
    Write-Host "##*********** sln ***********##" -ForegroundColor Cyan

    $slnDir = Get-ProjectDir $solutionName
    Write-Host "sln.dir: $slnDir" -ForegroundColor Cyan
        
    $slnPath = "$slnDir\$solutionName.sln"
    Write-Host "sln.path: $slnPath" -ForegroundColor Cyan

    $releaseParams = (Get-Content -Raw -Path $slnDir\lib.release.json | ConvertFrom-Json).projects
    Write-Host "sln.release.params:"$releaseParams -ForegroundColor Cyan    

    Write-Host "##*********** test ***********##" -ForegroundColor Cyan

    Write-Host "test.disabled: $notests" -ForegroundColor Cyan
    Write-Host "test.assemblies.filter: $testAssembliesFilter" -ForegroundColor Cyan    
       
    $consoleRunnerPath = Get-ChildItem -Path "$slnDir\packages" -Filter xunit.console.exe -Recurse -ErrorAction SilentlyContinue -Force| Sort-Object FullName | Select-Object -Last 1
    Write-Host "test.runner.console.path:"$consoleRunnerPath.FullName -ForegroundColor Cyan    
    
    
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

    $assemblyInfos = $projects | % { $_."project.assemblyInfo" }
    
    try
    {                        
        ##*********** Build ***********##
  
        #clean repo for release - this will mess things up if everything is not committed!!
        #https://git-scm.com/docs/git-clean
        Write-Host "Cleaning repo for $msbuildConfiguration build"
        Reset-GitDir $slnDir | Write-Host -ForegroundColor DarkGray
        
        #patch assembly infos
        foreach($project in $projects){            
            Update-AssemblyInfoVersions $project."project.assemblyInfo" $project."project.semVer10" $project."project.semVer20"
        } 
                
        #restore nugets
        #https://docs.nuget.org/consume/command-line-reference
        Write-Host "Restoring nuget packages"
        & "$buildScriptDir\nuget.exe" restore $slnPath | Write-Host -ForegroundColor DarkGray
        
        #build sln
        Write-Host "Building $slnPath"
        & "C:\Program Files (x86)\MSBuild\14.0\Bin\amd64\MSBuild.exe" $slnPath /t:rebuild /p:Configuration=$msbuildConfiguration /verbosity:minimal | Write-Host -ForegroundColor DarkGray
        
        #clean output dir if exists
        if(Test-Path $outputDir) { Remove-Item "$outputDir\*" -Force | Write-Host -ForegroundColor DarkGray }
        #create aritfacts dir
        New-Item $outputDir -ItemType Directory -Force | Write-Host -ForegroundColor DarkGray
        
        $testsPassed = $notests;
        
        if(-NOT ($notests)){            
            if($consoleRunnerPath -eq $null) {
                Write-Host "Unit test console runner not found! Unit tests will NOT be run" -ForegroundColor Red
                $testsPassed=$false;
            }
            else {
                #run unit tests
                $testAssemblies = Get-ChildItem -Path "$slnDir" -Filter "$testAssembliesFilter" -Recurse | Where-Object { $_.FullName -like "*`\bin`\$msbuildConfiguration`\$testAssembliesFilter" -and $_.Attributes -ne "Directory" }

                & $consoleRunnerPath.FullName "C:\Projects\DotNet.Basics\DotNet.Basics.Tests\bin\Release\DotNet.Basics.Tests.dll"

                $testsPassed = ($lastexitcode -eq 0)

                if($testsPassed){
                    Write-Host "All tests passed" -ForegroundColor Green
                } else {
                    Write-Host "One ore more tests failed!" -ForegroundColor Red
                }
            }
        }        
        
        #create nugets if all tests passed
        if($testsPassed) {
            #create nugets and place in output Dir dir
            foreach($project in $projects) {
                $nugetTarget = $project."nuget.target"
                $nugetVersion = $project."project.semVer10"
                #https://docs.nuget.org/consume/command-line-reference
                Write-Host "Packing $nugetTarget -v $nugetVersion"
                & "$buildScriptDir\nuget.exe" pack $nugetTarget -Properties "Configuration=$msbuildConfiguration;Platform=AnyCPU" -version $nugetVersion  -OutputDirectory $outputDir  | Write-Host -ForegroundColor DarkGray
            }            

            if(-NOT ($nonugets)) {
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

        
        #revert assembly info
        $assemblyInfos | Undo-AssemblyInfoVersions

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

    $projectDir = "$slnDir\$projectName"
    $projectInfo.Add("project.dir",$projectDir);

    $projectVersion = $projectParams.version
    $projectInfo.Add("project.version",$projectVersion);
            
    $semver10 = $projectVersion
    $projectInfo.Add("project.semVer10",$semver10);
            
    $semver20 = "$semver10+$commitsSinceInit.$commitHash"
    $projectInfo.Add("project.semVer20",$semver20);

    $assemblyInfo = (Get-AssemblyInfos $projectDir).FullName
    $projectInfo.Add("project.assemblyInfo",$assemblyInfo);

    $nugetTarget = "$slnDir\$projectName\$projectName.csproj"
    $projectInfo.Add("nuget.target",$nugetTarget);    

    return $projectInfo    
}

Function Get-AssemblyInfos{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$Rootdir
    )
    
    return Get-ChildItem $Rootdir -Filter "AssemblyInfo.cs" -recurse | Where-Object { $_.Attributes -ne "Directory"}
}


Function Update-AssemblyInfoVersions
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$assemblyInfoFullName,
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [Parameter(Mandatory=$true)]
        [string]$SemVer20
    )
  
    Write-Host "Updating AssemblyInfos"

        $fullName=$assemblyInfoFullName
        Write-host "Updating $fullName" -ForegroundColor DarkGray
        $TmpFile = $assemblyInfoFullName + ".tmp"   
        Write-host "Backup: $TmpFile"  -ForegroundColor DarkGray

        #backup file for reverting later
        Copy-Item $fullName $TmpFile

        [regex]$patternAssemblyVersion = "(AssemblyVersion\("")(\d+\.\d+\.\d+\.\d+)(""\))"
        $replacePatternAssemblyVersion = "`${1}$($Version)`$3"
        [regex]$patternAssemblyFileVersion = "(AssemblyFileVersion\("")(\d+\.\d+\.\d+\.\d+)(""\))"
        $replacePatternAssemblyFileVersion = "`${1}$($Version)`$3"
        [regex]$patternAssemblyInformationalVersion = "(AssemblyInformationalVersion\("")(\d+\.\d+\.\d+\.\d+)(""\))"
        $replacePatternAssemblyInformationalVersion = "`${1}$($SemVer20)`$3"

        # run the regex replace        
        $updated = Get-Content -Path $fullName |
            % { $_ -replace $patternAssemblyVersion, $replacePatternAssemblyVersion } |
            % { $_ -replace $patternAssemblyFileVersion, $replacePatternAssemblyFileVersion } |
            % { $_ -replace $patternAssemblyInformationalVersion, $replacePatternAssemblyInformationalVersion }
        Set-Content $fullName -Value $updated -Force
    
}
Function Undo-AssemblyInfoVersions
{
    Write-host "Reverting assemblyInfos"
    foreach ($o in $input)
    {
        $TmpFile = $o + ".tmp"
        Write-host "Reverting $TmpFile" -ForegroundColor DarkGray
        if(Test-Path($TmpFile)){            
            Move-Item  $TmpFile $o -Force
        }        
    }
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
