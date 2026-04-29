using DotNet.Basics.Cli;
using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Win;
using Microsoft.Extensions.Logging;

namespace Lib.Release.Steps
{
    public class PackNugetsStep(ILogger log) : PipelineStep<ReleaseCliSettings>
    {
        protected override Task<int> RunImpAsync(ReleaseCliSettings args)
        {
            args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                r.PackDir!.CreateIfNotExists();
                r.PackDir!.CleanIfExists();

                var packCmd = @$"dotnet pack ""{r.ProjectFile!.FullName}"" -c release --force -o ""{r.PackDir!.FullName}""";

                if (CmdPrompt.Run(packCmd, log) != 0)
                    throw new ApplicationException($"Failed to pack {r.Name}. See log for details");
            });
            return Task.FromResult(0);
        }
    }
}
