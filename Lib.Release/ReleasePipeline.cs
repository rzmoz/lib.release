using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        private readonly ILoog _log;
        private static readonly DirPath _fallbackProjectsDirName = @"c:\projects";

        public ReleasePipeline(ILoog log, IServiceProvider services) : base(services)
        {
            _log = log;
            AddStep(nameof(AssertLibRootDir), AssertLibRootDir);
            AddStep<InitForReleaseStep>();
        }

        public Task<int> AssertLibRootDir(LibReleasePipelineArgs args)
        {
            if (args.LibRootDir == null)
                throw new ArgumentNullException(nameof(args.LibRootDir));

            if (Path.IsPathRooted(args.LibRootDir.RawPath) && args.LibRootDir.Exists())
                return Task.FromResult(0);
            _log.Debug($"Lib root dir is not rooted. Setting root to: {_fallbackProjectsDirName.RawPath}");
            args.LibRootDir = _fallbackProjectsDirName.ToDir(args.LibRootDir);
            if (args.LibRootDir.Exists())
            {
                _log.Debug($"Lib root dir found at {args.LibRootDir.FullName}");
                return Task.FromResult(0);
            }

            _log.Fatal($"Lib root dir NOT found! {args.LibRootDir.FullName}");
            return Task.FromResult(400);
        }
    }
}
