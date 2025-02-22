﻿using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;
using DotNet.Basics.Sys.Text;
using LibGit2Sharp;

namespace Lib.Release.Steps
{
    public class InitForReleaseStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        private const string _libReleaseInfoFileName = "lib.release.json";
        private const string _outputDirName = ".nupkg";

        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {   //assert git status
            var gitStatus = AssertGitStatus(args);
            if (gitStatus != 0)
                return Task.FromResult(gitStatus);

            CleanBinDirs(args);

            var releaseInfo = InitReleaseInfo(args);

            return Task.FromResult(releaseInfo);
        }

        private int AssertGitStatus(LibReleasePipelineArgs args)
        {
            using var repo = new Repository(args.LibRootDir!);
            var status = repo.RetrieveStatus(new StatusOptions
            {
                ExcludeSubmodules = true,
                IncludeIgnored = false
            });

            if (status.Any())//pending changes => no good to release
            {
                log.Error($"There are {status.Count()} pending changes. Commit before release!");
                status.GroupBy(s => s.State)
                    .ForEach(g =>
                    {
                        log.Verbose($"{g.Key.ToName().Highlight()}:");
                        g.ForEach(s =>
                            log.Verbose($"- {s.FilePath}".WithIndent(1)));
                    });
                return 400;
            }

            return 0;
        }

        private void CleanBinDirs(LibReleasePipelineArgs args)
        {
            var binDirs = args.LibRootDir!.GetDirectories(_outputDirName, SearchOption.AllDirectories);
            log.Debug($"Cleaning {_outputDirName} dirs");
            binDirs.ForEach(d => log.Verbose(d.FullName));
            binDirs.ForEach(d => d.DeleteIfExists());
        }

        private int InitReleaseInfo(LibReleasePipelineArgs args)
        {
            var libInfoFile = args.LibRootDir!.GetFiles(_libReleaseInfoFileName, SearchOption.AllDirectories).FirstOrDefault();
            if (libInfoFile == null)
                throw new FileNotFoundException(_libReleaseInfoFileName);

            args.ReleaseInfo = libInfoFile.ReadAllText()!.FromJson<LibReleaseInfo>()!;
            log.Debug($"{nameof(args.ReleaseInfo)}:{args.ReleaseInfo.ToJson(true)}");
            return 0;
        }
    }
}
