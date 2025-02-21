# Lib.Release

Dotnet tool for packing and pushing to nuget.org

## Install
```bash
dotnet tool install --global Lib.Release
```

## Usage with manadtory arguments
```bash
Lib.Release --LibRootDir "<path to sln dir>" --PublishKey "<nuget write token>"
```

## Optional flags
```bash
--verbose => Outputs extended log information
--ado => Logger outputs in Azur DevOps friendly format
--debug => Stop execution to add compiler
```
## View on nuget.org: https://www.nuget.org/packages/lib.release