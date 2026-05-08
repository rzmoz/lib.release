using DotNet.Basics.Cli;
using DotNet.Basics.Cli.Logging;
using Microsoft.Extensions.Logging;
using Spectre.Console.Cli;

namespace Lib.Release
{
    public class ReleaseCliCommand(ReleasePipeline pipeline, ILogger log) : CliCommand<ReleaseCliSettings>
    {
        protected override async Task<int> ExecuteAsync(CommandContext context, ReleaseCliSettings settings, CancellationToken cancellationToken)
        {
            var exitCode = -1;
            await log.StatusRandomMessagesAsync(async ctx => exitCode = await pipeline.RunAsync(settings));
            return exitCode;
        }
    }
}
