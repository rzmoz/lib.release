using DotNet.Basics.Cli;
using DotNet.Basics.Pipelines;
using Microsoft.Extensions.DependencyInjection;

namespace Lib.Release
{
    internal class Program
    {
        static async Task<int> Main(string[] args)
        {
            var app = new CliHostBuilder()
                .WithServices(services =>
                {
                    services.AddPipelines();
                    services.AddScoped<Nuget>();
                })
                .WithCommand<ReleaseCliCommand>(true)
                .Build();

            return await app.RunAsync(args);
        }
    }
}
