using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using Lib.Release.Steps;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        public ReleasePipeline(ILoog log, IServiceProvider services) : base(services)
        {
            AddStep<AssertLibRootDirStep>();
            AddStep<InitForReleaseStep>();
            AddStep<InitVersionsStep>();
            AddStep<ApplyVersionStep>();
        }
    }
}
