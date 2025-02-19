using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;
using LibGit2Sharp;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        private readonly ILoog _log;

        public ReleasePipeline(ILoog log)
        {
            _log = log;
            AddStep(nameof(AssertLibRootDir), AssertLibRootDir);
            AddStep(nameof(InitGitDirForRelease), InitGitDirForRelease);
        }

        public Task<int> AssertLibRootDir(LibReleasePipelineArgs args)
        {
            if (args.LibRootDir == null)
                throw new ArgumentNullException(nameof(args.LibRootDir));
            if (!args.LibRootDir.ToDir().Exists())
                throw new DirectoryNotFoundException(args.LibRootDir.ToDir().FullName);

            return Task.FromResult(0);
        }
        public Task<int> InitGitDirForRelease(LibReleasePipelineArgs args)
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
                    _log.Error($"There are {status.Count()} pending changes. Commit before release!");
                    foreach (var item in status)
                    {
                        _log.Debug($"{item.FilePath}:{item.State.ToName()}");
                    }
                    return Task.FromResult(400);
                }

                var binDirs = args.LibRootDir.ToDir().GetDirectories("bin", SearchOption.AllDirectories);


                _log.Debug("Cleaning bin dirs");
                binDirs.ForEach(d => _log.Verbose(d.FullName));
                binDirs.ForEach(d => d.DeleteIfExists());
            }
            return Task.FromResult(0);
        }
    }
}
