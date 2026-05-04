using DotNet.Basics.Cli.Logging;
using DotNet.Basics.Collections;
using DotNet.Basics.Diagnostics;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Sys;
using DotNet.Basics.Sys.Text;
using Spectre.Console;
using Spectre.Console.Json;

namespace Lib.Release.Steps
{
    public class InitVersionsStep(DevConsole log, Nuget nuget) : PipelineStep<ReleaseCliSettings>
    {
        protected override async Task<int> RunImpAsync(ReleaseCliSettings args)
        {
            var packages = (await args.ReleaseInfo.Releases
                .ForEachParallelAsync(async r => await nuget.SearchAsync(r.Name)))
                .Select(p => p)
                .Distinct()
                .ToDictionary(p => p.Name);

            var candidates = args.ReleaseInfo.Releases.ToList();
            log.Debug("Resolving packages for release from:");
            if (log.MinimumLogLevel <= Microsoft.Extensions.Logging.LogLevel.Debug)
            {
                log.Write(new JsonText(candidates.ToJson()));
                log.Write(Text.NewLine);
            }
            foreach (var candidate in candidates)
            {
                if (packages.TryGetValue(candidate.Name, out var latestPkg))
                {
                    var comparisonVersion = new SemVersion(candidate.Version, candidate.PreRelease);

                    if (comparisonVersion.Equals(latestPkg.SemVersion))
                    {
                        args.ReleaseInfo.Releases.RemoveAt(args.ReleaseInfo.Releases.IndexOf(candidate.Name));
                        log.Info($"{candidate} already exists. Ignoring in release");
                        continue;
                    }
                }
                log.Info($"{candidate.ToString().Highlight()} approved for release!");
            }

            if (args.ReleaseInfo.Releases.Any())
                return 0;

            log.Warn($"No release candidates. Aborting release");
            return 409;
        }
    }
}
