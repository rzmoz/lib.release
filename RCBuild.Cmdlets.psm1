Function New-RCBuild
{
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,
        [string]$msbuildConfiguration = "release",
        [Alias("nuget")]
        [switch]$pushToNugetOrg,
        [switch]$disableTests
    )

    ##*********** Init ***********##

    $currentDir =  (Get-Item -Path ".\" -Verbose).FullName
    Write-Host "Current dir: $buildScriptDir"

    $buildScriptDir = Get-ProjectDir "rcbuild"
    Write-Host "Build Script dir: $buildScriptDir"

    $projectDir = Get-ProjectDir $ProjectName
    Write-Host "Project dir: $projectDir"
    
    Write-Host "msbuild.configuration: $msbuildConfiguration" -ForegroundColor Cyan

    if(Test-Path $projectDir){
        Write-Host "Setting location $projectDir" | Write-Host -ForegroundColor DarkGray
        sl $projectDir #moving location 
    } else {
        Write-Host "$projectDir not found. Aborting.." -ForegroundColor Red
        return
    }

    try
    {
        $parameters = Get-Content -Raw -Path .\RC.Params.json | ConvertFrom-Json

        $artifactsDir = "$projectDir\Artifacts"
        Write-Host "aritfacts dir: $artifactsDir" -ForegroundColor Cyan
        $testResultsPath = "$artifactsDir\testresults.xml"
        Write-Host "test results path: $testResultsPath" -ForegroundColor Cyan
        $branch = git rev-parse --abbrev-ref HEAD
        Write-Host "branch: $branch" -ForegroundColor Cyan
        $commitHash = git rev-parse --verify HEAD
        Write-Host "hash: $commitHash" -ForegroundColor Cyan
        $shortHash = git log --pretty=format:'%h' -n 1
        Write-Host "hash.short: $shortHash" -ForegroundColor Cyan
        $versionAssembly = $parameters."version.assembly"
        Write-Host "version.assembly: $versionAssembly" -ForegroundColor Cyan
        $versionPrerelase= $parameters."version.prerelease"
        Write-Host "version.prerelease: $versionPrerelase" -ForegroundColor Cyan
        $commitsSinceInit = git rev-list --first-parent --count HEAD
        Write-Host "# of commits: $commitsSinceInit" -ForegroundColor Cyan
        $semver10 = $versionAssembly
        if(-Not [string]::IsNullOrWhiteSpace($versionPrerelase)) {
            $semver10 +="-$versionPrerelase"
        }
        Write-Host "semVer10: $semver10" -ForegroundColor Cyan
        $semver20 = "$semver10+$commitsSinceInit.$commitHash"
        Write-Host "semVer20: $semver20" -ForegroundColor Cyan
        $slnPath = $parameters."sln.path"
        Write-Host "sln.path: $slnPath" -ForegroundColor Cyan        
        $testAssembliesFilter = $parameters."test.assemblies"
        Write-Host "test.assemblies filter: $testAssembliesFilter" -ForegroundColor Cyan
        $nugetTargets = $parameters."nuget.targets"
        foreach($nugetTarget in $nugetTargets.path) {
            Write-Host "nuget.target: $nugetTarget" -ForegroundColor Cyan
        }

        ##*********** Build ***********##
        
        #clean repo for release - this will fail if everything is not committed
        #https://git-scm.com/docs/git-clean
        Write-Host "Cleaning repo for relase build"
        Reset-GitDir $projectDir | Write-Host -ForegroundColor DarkGray

        #patch assembly infos
        $assemblyInfos = Get-ChildItem $projectDir -Filter "AssemblyInfo.cs" -recurse | Where-Object { $_.Attributes -ne "Directory"} 
        $assemblyInfos | Update-AssemblyInfoVersions $versionAssembly $semver20

        #restore nugets
        #https://docs.nuget.org/consume/command-line-reference
        Write-Host "Restoring nuget packages"
        & "$buildScriptDir\nuget.exe" restore $slnPath | Write-Host -ForegroundColor DarkGray

        #build sln
        Write-Host "Building $slnPath"
        & "C:\Program Files (x86)\MSBuild\14.0\Bin\amd64\MSBuild.exe" $slnPath /t:rebuild /p:Configuration=$msbuildConfiguration /verbosity:minimal | Write-Host -ForegroundColor DarkGray
        
        #clean artifacts dir if exists
        if(Test-Path $artifactsDir) { Remove-Item "$artifactsDir\*" -Force | Write-Host -ForegroundColor DarkGray }
        #create aritfacts dir
        New-Item $artifactsDir -ItemType Directory -Force | Write-Host -ForegroundColor DarkGray

        if(-NOT ($disableTests)){
            #run unit tests
            $testAssemblies = Get-ChildItem -Path $projectDir -Filter "$testAssembliesFilter" -Recurse | Where-Object { $_.FullName -like "*`\bin`\$msbuildConfiguration`\$testAssembliesFilter" -and $_.Attributes -ne "Directory" }
            Write-Host $testAssemblies.FullName
            #https://github.com/nunit/docs/wiki/Console-Command-Line
            & "$buildScriptDir\nunit\nunit3-console.exe" $testAssemblies.FullName --framework:net-4.5 --result:$testResultsPath | Write-Host -ForegroundColor DarkGray

            #get test result
            [xml]$testResults = Get-Content -Path $testResultsPath
            $result = $testResults."test-run".result
            if($result -eq "Passed") {
            Write-Host "Unit tests: $result" -ForegroundColor Green
            } else {
                Write-Host "Unit tests: $result!" -ForegroundColor Red
            }
        }        

        #create nugets and place in artifacts dir
        foreach($nugetTarget in $nugetTargets.path) {
        #https://docs.nuget.org/consume/command-line-reference
        Write-Host "Packing $nugetTarget"
        & "$buildScriptDir\nuget.exe" pack $nugetTarget -Properties "Configuration=$msbuildConfiguration;Platform=AnyCPU" -version $semver10 -OutputDirectory $artifactsDir  | Write-Host -ForegroundColor DarkGray
        }

        if($pushToNugetOrg) {
            $apiKey = Read-Host "Please enter nuget API key"
            #https://docs.nuget.org/consume/command-line-reference
            Get-ChildItem $artifactsDir -Filter "*.nupkg" | % { 
                Write-Host $_.FullName
                & "$buildScriptDir\nuget.exe" push $_.FullName -ApiKey $apiKey -Source "https://api.nuget.org/v3/index.json" -NonInteractive | Write-Host -ForegroundColor DarkGray
            }
        }        

        Write-host "Build $semver20 completed!" -ForegroundColor Green

    } finally {        
        #revert assembly info
        $assemblyInfos | Undo-AssemblyInfoVersions

        Write-Host "Setting location $currentDir" | Write-Host -ForegroundColor DarkGray
        sl $currentDir
    }
}


Function Update-AssemblyInfoVersions
{
    Param (
        [string]$Version,
        [string]$SemVer20
    )
  
    Write-Host "Updating AssemblyInfos"

    foreach ($o in $input)
    {
        $fullName=$o.FullName
        Write-host "Updating $fullName" -ForegroundColor DarkGray
        $TmpFile = $o.FullName + ".tmp"   
        Write-host "Backup: $TmpFile"  -ForegroundColor DarkGray

        #backup file for reverting later
        Copy-Item $o.FullName $TmpFile

        [regex]$patternAssemblyVersion = "(AssemblyVersion\("")(\d+\.\d+\.\d+\.\d+)(""\))"
        $replacePatternAssemblyVersion = "`${1}$($Version)`$3"
        [regex]$patternAssemblyFileVersion = "(AssemblyFileVersion\("")(\d+\.\d+\.\d+\.\d+)(""\))"
        $replacePatternAssemblyFileVersion = "`${1}$($Version)`$3"
        [regex]$patternAssemblyInformationalVersion = "(AssemblyInformationalVersion\("")(\d+\.\d+\.\d+\.\d+)(""\))"
        $replacePatternAssemblyInformationalVersion = "`${1}$($SemVer20)`$3"

        # run the regex replace        
        $updated = Get-Content -Path $o.FullName |
            % { $_ -replace $patternAssemblyVersion, $replacePatternAssemblyVersion } |
            % { $_ -replace $patternAssemblyFileVersion, $replacePatternAssemblyFileVersion } |
            % { $_ -replace $patternAssemblyInformationalVersion, $replacePatternAssemblyInformationalVersion }
        Set-Content $o.FullName -Value $updated -Force
    }
}
Function Undo-AssemblyInfoVersions
{
    Write-host "Reverting assemblyInfos"
    foreach ($o in $input)
    {
        $TmpFile = $o.FullName + ".tmp"   
        Write-host "Reverting $TmpFile" -ForegroundColor DarkGray
        Move-Item  $TmpFile $o.FullName -Force
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
