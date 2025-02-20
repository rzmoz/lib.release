﻿using System.Text;
using DotNet.Basics.IO;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;
using DotNet.Basics.Sys.Text;
using DotNet.Basics.Win;

namespace Lib.Release
{
    //https://learn.microsoft.com/en-us/nuget/reference/nuget-exe-cli-reference?tabs=windows
    public class Nuget(ILoog log)
    {
        private static readonly SysRegex _nugetPackageRegex = @"^> (?<name>.+?) \| (?<version>.+?) \| Downloads: (?<downloads>[0-9\.]+)";

        private readonly FileApplication _nugetExe = new(".nuget");
        private const string _fileName = "nuget.exe";
        private FilePath _nugetFilePath => _nugetExe.InstallDir.ToFile(_fileName);
        private const string _publicNugetSource = "https://api.nuget.org/v3/index.json";
        private const string _nugetExeDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe";

        public async Task InitAsync()
        {
            _nugetExe.Install();
            using var httpClient = new HttpClient();
            await using var fileStream = await httpClient.GetStreamAsync(_nugetExeDownloadUrl);
            await using var writer = _nugetFilePath.OpenWrite(FileMode.Create);
            await fileStream.CopyToAsync(writer.BaseStream);
            await writer.FlushAsync();
            await fileStream.FlushAsync();
            log.Verbose($"{_fileName.Highlight()} initialized");
        }

        public IReadOnlyList<NugetPackage> Search(string packageName, bool preRelease = true, params string[] sources)
        {
            if (sources.Length == 0)
                sources = [_publicNugetSource];

            var sourcesString = sources.Select(s => $@"-Source ""{s}""").JoinString(" ");
            var searchCmd = @$"{_nugetFilePath.FullName} search ""{packageName}"" -NonInteractive {(preRelease ? "-PreRelease " : "")}{sourcesString}";
            log.Verbose(searchCmd);
            var info = new StringBuilder();
            var error = new StringBuilder();
            var debug = new StringBuilder();
            CmdPrompt.Run(searchCmd, i => info.AppendLine(i), e => error.AppendLine(e), d => debug.AppendLine(d));

            var infoStr = info.ToString();

            if (debug.Length > 0)
                log.Debug(debug.ToString());
            if (infoStr.Any())
                log.Debug(infoStr);
            if (error.Length > 0)
                log.Error(error.ToString());

            var pkgMatches = _nugetPackageRegex.Matches(infoStr);

            return pkgMatches.Select(m =>
            {
                var pkg = new NugetPackage
                {
                    Name = m.Groups["name"].Value,
                    Version = m.Groups["version"].Value,
                    Downloads = long.Parse(m.Groups["downloads"].Value.Remove(@"\."))
                };

                log.Debug($"Package info: {pkg}");
                return pkg;
            }).ToList();
        }
    }
}
