using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys.Text;

namespace Lib.Release.Steps
{
    public class BuildSolutionStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            
            return Task.FromResult(0);
        }
    }
}
