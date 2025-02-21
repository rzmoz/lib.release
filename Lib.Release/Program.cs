using DotNet.Basics.Cli;
using DotNet.Basics.Pipelines;
using Microsoft.Extensions.DependencyInjection;

namespace Lib.Release
{
    internal class Program
    {
        static async Task<int> Main(string[] args)
        {
            await using var app = new CliHostBuilder(args)
                .WithServices(services =>
                {
                    services.AddPipelines();
                    services.AddScoped<Nuget>();
                })
                .Build();

            return await app.RunPipelineAsync<ReleasePipeline>();
        }
    }
}
