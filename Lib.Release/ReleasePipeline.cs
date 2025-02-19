using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        public ReleasePipeline(IServiceProvider services) : base(services)
        {
            AddStep(nameof(AssertLibRootDir), AssertLibRootDir);
            AddStep<InitForReleaseStep>();
        }

        public Task<int> AssertLibRootDir(LibReleasePipelineArgs args)
        {
            if (args.LibRootDir == null)
                throw new ArgumentNullException(nameof(args.LibRootDir));
            if (!args.LibRootDir.Exists())
                throw new DirectoryNotFoundException(args.LibRootDir.FullName);

            return Task.FromResult(0);
        }
    }
}
