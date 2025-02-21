using DotNet.Basics.Cli;
using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Win;

namespace Lib.Release.Steps
{
    public class PackNugetsStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                r.PackDir!.CreateIfNotExists();
                r.PackDir!.CleanIfExists();

                var packCmd = @$"dotnet pack ""{r.ProjectFile!.FullName}"" -c release --force -o ""{r.PackDir!.FullName}""";

                if (CmdPrompt.Run(packCmd, log.WithPromptLogger()) != 0)
                    throw new ApplicationException($"Failed to pack {r.Name}. See log for details.");
            });
            return Task.FromResult(0);
        }
    }
}
