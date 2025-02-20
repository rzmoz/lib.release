using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Serilog.Looging;

namespace Lib.Release.Steps
{
    public class PackNugetsStep(ILoog log) : CmdPromptStep<LibReleasePipelineArgs>(log)
    {
        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                r.PackDir!.CreateIfNotExists();
                r.PackDir!.CleanIfExists();

                var packCmd = @$"dotnet pack ""{r.ProjectFile!.FullName}"" -c release --force -o ""{r.PackDir!.FullName}""";

                var logger = CmdRun(packCmd, out var exitCode);
                if (exitCode != 0 || logger.HasErrors)
                    throw new ApplicationException($"Failed to pack {r.Name}. See log for details.");
            });
            return Task.FromResult(0);
        }
    }
}
