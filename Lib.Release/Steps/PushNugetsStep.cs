using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Serilog.Looging;

namespace Lib.Release.Steps
{
    public class PushNugetsStep(ILoog log) : CmdPromptStep<LibReleasePipelineArgs>(log)
    {
        private readonly ILoog _log = log;

        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            return Task.FromResult(args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                var nugetFile = r.PackDir!.GetFiles("*.nupkg").Single();

                var pushCmd = @$"dotnet nuget push ""{nugetFile.FullName}"" --api-key ""{args.PublishKey}"" --source ""{args.ReleaseInfo.Source}"" --skip-duplicate";

                var logger = CmdRun(pushCmd, out var exitCode);
                if (exitCode != 0 || logger.HasErrors)
                    throw new ApplicationException($"Failed to push {nugetFile.FullName} to {args.ReleaseInfo.Source}. See log for details.");

                if (logger.Info.ToString().Contains("Conflict", StringComparison.OrdinalIgnoreCase))
                {
                    _log.Warning($"Conflict detected for {r.Name.Highlight()}. See log for details");
                    return 400;
                }
                
                _log.Success($"{r.Name.Highlight()} was successfully released to {args.ReleaseInfo.Source}");
                return 0;

            }).Sum());
        }
    }
}
