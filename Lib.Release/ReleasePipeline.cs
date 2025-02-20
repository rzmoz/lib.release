using DotNet.Basics.Pipelines;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        public ReleasePipeline(IServiceProvider services) : base(services)
        {
            AddStep<AssertLibRootDirStep>();
            AddStep<InitForReleaseStep>();
            AddStep<InitVersionsStep>();
        }
    }
}
