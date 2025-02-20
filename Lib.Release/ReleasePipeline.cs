using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using Lib.Release.Steps;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        public ReleasePipeline(IServiceProvider services) : base(services)
        {
            AddStep<AssertLibRootDirStep>();
            AddStep<InitForReleaseStep>();
            AddStep<InitVersionsStep>();
            AddStep<ApplyVersionStep>();
            AddStep<RunTestsStep>();
            AddStep<PackNugetsStep>();
            AddStep<PushNugetsStep>();
        }

        protected override async Task<int> InnerRunAsync(LibReleasePipelineArgs args)
        {
            try
            {
                return await base.InnerRunAsync(args);
            }
            finally
            {
                args.ReleaseInfo.Releases.ForEachParallel(r =>
                {
                    r.TempProjectFile!.CopyTo(r.ProjectFile!, true);
                    r.TempProjectFile!.DeleteIfExists();
                    return 0;
                });

            }

        }
    }
}
