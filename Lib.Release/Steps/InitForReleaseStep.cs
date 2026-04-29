using DotNet.Basics.Cli.Logging;
using DotNet.Basics.Collections;
using DotNet.Basics.Diagnostics;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Sys;
using DotNet.Basics.Sys.Text;
using LibGit2Sharp;
using Microsoft.Extensions.Logging;
using Spectre.Console;

namespace Lib.Release.Steps
{
    public class InitForReleaseStep(ILogger log) : PipelineStep<ReleaseCliSettings>
    {
        private const string _libReleaseInfoFileName = "lib.release.json";
        private const string _outputDirName = ".nupkg";

        protected override Task<int> RunImpAsync(ReleaseCliSettings args)
        {   //assert git status
            var gitStatus = AssertGitStatus(args);
            if (gitStatus != 0)
                return Task.FromResult(gitStatus);

            CleanBinDirs(args);

            var releaseInfo = InitReleaseInfo(args);

            return Task.FromResult(releaseInfo);
        }

        private int AssertGitStatus(ReleaseCliSettings args)
        {
            using var repo = new Repository(args.Lib);
            var status = repo.RetrieveStatus(new StatusOptions
            {
                ExcludeSubmodules = true,
                IncludeIgnored = false
            });

            if (status.Any())//pending changes => no good to release
            {
                log.Error($"There are {status.Count().ToString().Highlight()} pending changes. Commit before release!");
                status.GroupBy(s => s.State)
                    .ForEach(g =>
                    {
                        log.Info($"{g.Key.ToName().ToTitleCase().Highlight()}:");
                        g.ForEach(s => log.Info(s.FilePath));
                    });
                return 400;
            }

            return 0;
        }

        private void CleanBinDirs(ReleaseCliSettings args)
        {
            var binDirs = args.Lib.ToDir().GetDirectories(_outputDirName, SearchOption.AllDirectories);
            log.Debug($"Cleaning {_outputDirName} dirs");
            binDirs.ForEach(d => log.Debug(d.FullName));
            binDirs.ForEach(d => d.DeleteIfExists());
        }

        private int InitReleaseInfo(ReleaseCliSettings args)
        {
            var libInfoFile = args.Lib.ToDir().GetFiles(_libReleaseInfoFileName, SearchOption.AllDirectories).FirstOrDefault();
            if (libInfoFile == null)
                throw new FileNotFoundException(_libReleaseInfoFileName);

            args.ReleaseInfo = libInfoFile.ReadAllText()!.FromJson<LibReleaseInfo>()!;
            return 0;
        }
    }
}
