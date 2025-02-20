using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;

namespace Lib.Release.Steps
{
    public class ApplyVersionStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            var result = args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                var projFile = args.LibRootDir!.ToFile(r.Name, $"{r.Name}.csproj");

                if (projFile.Exists())
                {
                    log.Debug($"Project file {projFile} found");
                    r.ProjectFile = projFile;//set for final cleanup
                    return 0;
                }
                log.Fatal($"Project file {projFile} not found!");
                return 400;
            }).Sum();
            return Task.FromResult(result);
        }
    }
}
