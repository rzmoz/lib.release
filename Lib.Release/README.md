# Lib.Release

Dotnet tool for packing and pushing to nuget.org

## Install
```bash
dotnet tool install --global "Lib.Release"
```

## Usage with manadtory arguments
```bash
Lib.Release --LibRootDir "<path to sln dir>" --ApiKey "<nuget.org api key with write permissions>"
```

## Optional flags
```bash
--verbose "Outputs extended loggin information"
--ado "Logger outputs Azure DevOps friendly format"
--debug "Stop execution to add compiler"
```

## Example
```bash
lib.release --LibRootDir "c:\projects\myProject" --ApiKey "340943908435" --verbose
```

## View on nuget.org: https://www.nuget.org/packages/lib.release