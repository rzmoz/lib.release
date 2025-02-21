using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;

namespace Lib.Release.Steps
{
    public class AssertLibRootDirStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        private static readonly DirPath _fallbackProjectsDirName = @"C:\Projects";

        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            if (args.LibRootDir == null)
                throw new ArgumentNullException(nameof(args.LibRootDir));

            if (Path.IsPathRooted(args.LibRootDir.RawPath) && args.LibRootDir.Exists())
                return Task.FromResult(0);
            log.Debug($"Lib root dir is not rooted. Setting root to: {_fallbackProjectsDirName.RawPath}");
            args.LibRootDir = _fallbackProjectsDirName.ToDir(args.LibRootDir);
            if (args.LibRootDir.Exists())
            {
                log.Debug($"Lib root dir found at {args.LibRootDir!.FullName.Highlight()}");
                return Task.FromResult(0);
            }

            log.Fatal($"Lib root dir NOT found! {args.LibRootDir!.FullName.Highlight()}");
            return Task.FromResult(400);
        }
    }
}
