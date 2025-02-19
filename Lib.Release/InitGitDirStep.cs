using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;
using LibGit2Sharp;

namespace Lib.Release
{
    public class InitGitDirStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            using (var repo = new Repository(args.LibRootDir))
            {
                var status = repo.RetrieveStatus(new StatusOptions
                {
                    ExcludeSubmodules = true,
                    IncludeIgnored = false
                });

                if (status.Any())//pending changes => no good to release
                {
                    log.Error($"There are {status.Count()} pending changes. Commit before release!");
                    foreach (var item in status)
                    {
                        log.Debug($"{item.FilePath}:{item.State.ToName()}");
                    }
                    return Task.FromResult(400);
                }

                var binDirs = args.LibRootDir.ToDir().GetDirectories("bin", SearchOption.AllDirectories);


                log.Debug("Cleaning bin dirs");
                binDirs.ForEach(d => log.Verbose(d.FullName));
                binDirs.ForEach(d => d.DeleteIfExists());
            }
            return Task.FromResult(0);
        }
    }
}
