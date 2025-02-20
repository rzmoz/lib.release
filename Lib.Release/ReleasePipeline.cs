using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys.Text;
using Lib.Release.Steps;

namespace Lib.Release
{
    public class ReleasePipeline : Pipeline<LibReleasePipelineArgs>
    {
        private readonly ILoog _log;

        public ReleasePipeline(ILoog log, IServiceProvider services) : base(services)
        {
            _log = log;
            AddStep<AssertLibRootDirStep>();
            AddStep<InitForReleaseStep>();
            AddStep<InitVersionsStep>();
            AddStep<ApplyVersionStep>();
            AddStep<BuildSolutionStep>();
        }

        protected override async Task<int> InnerRunAsync(LibReleasePipelineArgs args)
        {
            try
            {
                return await base.InnerRunAsync(args);
            }
            finally
            {
                _log.Info($"Finally: {args.ToJson(true)}");

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
