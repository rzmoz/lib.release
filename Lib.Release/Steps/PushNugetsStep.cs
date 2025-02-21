using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Serilog.Looging;

namespace Lib.Release.Steps
{
    public class PushNugetsStep(ILoog log) : CmdPromptStep<LibReleasePipelineArgs>(log)
    {
        private readonly ILoog _log = log;
        public const string NugetSource = "https://api.nuget.org/v3/index.json";

        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            return Task.FromResult(args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                var nugetFile = r.PackDir!.GetFiles("*.nupkg").Single();

                var pushCmd = @$"dotnet nuget push ""{nugetFile.FullName}"" --api-key ""{args.ApiKey}"" --source ""{NugetSource}"" --skip-duplicate";

                var logger = CmdRun(pushCmd, out var exitCode);
                if (exitCode != 0 || logger.HasErrors)
                    throw new ApplicationException($"Failed to push {nugetFile.FullName.Highlight()} to {NugetSource}. See log for details.");

                var info = logger.Info.ToString();

                if (info.Contains("Your package was pushed.", StringComparison.OrdinalIgnoreCase))
                {
                    _log.Success($"{r.ToString().Highlight()} was successfully released. See log for details.");
                    return 0;
                }
                if (info.Contains("Conflict", StringComparison.OrdinalIgnoreCase))
                {
                    _log.Warning($"Conflict detected for {r.ToString().Highlight()}. See log for details.");
                    return 400;
                }
                _log.Warning($"Error detected for {r.ToString().Highlight()}. See log for details.");
                return 400;


            }).Sum());
        }
    }
}
