using DotNet.Basics.Diagnostics;
using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Win;
using Microsoft.Extensions.Logging;
using System.Text;

namespace Lib.Release.Steps
{
    public class PushNugetsStep(ILogger log) : PipelineStep<ReleaseCliSettings>
    {
        public const string NugetSource = "https://api.nuget.org/v3/index.json";

        protected override Task<int> RunImpAsync(ReleaseCliSettings args)
        {
            return Task.FromResult(args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                var pushLogger = new EventLogger();
                var infos = new StringBuilder();
                var errors = new StringBuilder();
                pushLogger.MessageLogged += (LogLevel level, string message, Exception? e) =>
                {
                    if (level >= LogLevel.Error)
                        errors.Append(message);
                    else
                        infos.Append(message);
                };
                var exitCode = 0;

                r.PackDir!.GetFiles("*.nupkg")
                .OrderByDescending(f => f.Name)
                .ForEach(nugetFile =>
                {
                    var pushCmd = @$"dotnet nuget push ""{nugetFile.FullName}"" --api-key ""{args.ApiKey}"" --source ""{NugetSource}"" --skip-duplicate";

                    var exitCode = CmdPrompt.Run(pushCmd, pushLogger);
                    if (exitCode != 0 || errors.Length > 0)
                        throw new ApplicationException($"Failed to push {nugetFile.FullName.Highlight()} to {NugetSource}. See log for details");

                    var info = infos.ToString();

                    if (info.Contains("Your package was pushed.", StringComparison.OrdinalIgnoreCase))
                    {
                        log.Success($"{r.ToString().Highlight()} successfully released");
                    }
                    else if (info.Contains("Conflict", StringComparison.OrdinalIgnoreCase))
                    {
                        log.Warn($"Conflict detected for {r.ToString().Highlight()}");
                        exitCode += 400;
                    }
                    else
                    {
                        log.Error($"Error detected for {r.ToString().Highlight()}");
                        exitCode += 400;
                    }
                });
                return exitCode;
            }).Sum());
        }
    }
}
