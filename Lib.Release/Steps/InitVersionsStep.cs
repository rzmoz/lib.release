using DotNet.Basics.Collections;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;
using DotNet.Basics.Sys.Text;

namespace Lib.Release.Steps
{
    public class InitVersionsStep(ILoog log, Nuget nuget) : PipelineStep<LibReleasePipelineArgs>
    {
        protected override async Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            var pkgs = (await args.ReleaseInfo.Releases.ForEachParallelAsync(async r => await nuget.SearchAsync(r.Name))).Select(p => p).Distinct().ToDictionary(p => p.Name);

            var candidates = args.ReleaseInfo.Releases.ToList();

            log.Debug($"{"Resolving packages for release from:".Highlight()}\r\n{candidates.ToJson(true)}");

            foreach (var candidate in candidates)
            {
                if (pkgs.TryGetValue(candidate.Name, out var latestPkg))
                {
                    var comparisonVersion = SemVersion.Parse($"{candidate.Version}{(candidate.PreRelease.Any() ? $"+{candidate.PreRelease}" : "")}");

                    if (comparisonVersion.Equals(latestPkg.SemVersion))
                    {
                        args.ReleaseInfo.Releases.RemoveAt(args.ReleaseInfo.Releases.IndexOf(candidate.Name));
                        log.Info($"{candidate} {"already exists".Highlight()}. Removing from release.");
                        continue;
                    }
                }
                log.Success($"{candidate} approved for release.");

            }

            if (args.ReleaseInfo.Releases.Any())
            {
                return 0;
            }
            log.Warning($"No release candidates. Aborting release");
            return 400;
        }
    }
}
