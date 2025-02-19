using DotNet.Basics.Cli;
using DotNet.Basics.Pipelines;

namespace Lib.Release
{
    internal class Program
    {
        static async Task<int> Main(string[] args)
        {
            await using var app = new CliHostBuilder(args)
                .WithServices(services => services.AddPipelines().AddPipelineSteps())
                .Build();

            return await app.RunPipelineAsync<ReleasePipeline>();
        }
    }
}
