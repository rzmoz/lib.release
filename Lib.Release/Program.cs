using DotNet.Basics.Cli;
using DotNet.Basics.Pipelines;

namespace Lib.Release
{
    internal class Program
    {
        static async Task<int> Main(string[] args)
        {
            var app = new LoogConsoleBuilder(args)
                .Services(services => services.AddPipelines())

                .Build();

            return await app.RunPipelineAsync<ReleasePipeline>();
        }
    }
}
