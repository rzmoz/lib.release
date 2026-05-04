using DotNet.Basics.Cli;
using Spectre.Console.Cli;

namespace Lib.Release
{
    public class ReleaseCliCommand(ReleasePipeline pipeline) : CliCommand<ReleaseCliSettings>
    {
        protected override async Task<int> ExecuteAsync(CommandContext context, ReleaseCliSettings settings, CancellationToken cancellationToken)
        {   
            return await pipeline.RunAsync(settings);
        }
    }
}
