using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        private readonly ILoog _log;

        public ReleasePipeline(ILoog log)
        {
            _log = log;
            AddStep(nameof(AssertLibRootDir), AssertLibRootDir);
            AddStep<InitGitDirStep>();
        }

        public Task<int> AssertLibRootDir(LibReleasePipelineArgs args)
        {
            if (args.LibRootDir == null)
                throw new ArgumentNullException(nameof(args.LibRootDir));
            if (!args.LibRootDir.ToDir().Exists())
                throw new DirectoryNotFoundException(args.LibRootDir.ToDir().FullName);

            return Task.FromResult(0);
        }
    }
}
