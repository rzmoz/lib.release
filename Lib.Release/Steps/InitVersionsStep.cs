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
            var packages = (await args.ReleaseInfo.Releases
                .ForEachParallelAsync(async r => await nuget.SearchAsync(r.Name)))
                .Select(p => p)
                .Distinct()
                .ToDictionary(p => p.Name);

            var candidates = args.ReleaseInfo.Releases.ToList();

            log.Verbose($"Resolving packages for release from:\r\n{candidates.ToJson(true)}");

            foreach (var candidate in candidates)
            {
                if (packages.TryGetValue(candidate.Name, out var latestPkg))
                {
                    var comparisonVersion = new SemVersion(candidate.Version, candidate.PreRelease);

                    if (comparisonVersion.Equals(latestPkg.SemVersion))
                    {
                        args.ReleaseInfo.Releases.RemoveAt(args.ReleaseInfo.Releases.IndexOf(candidate.Name));
                        log.Warning($"{candidate} {"already exists".Highlight()}. Ignoring in release.");
                        continue;
                    }
                }
                log.Info($"{candidate.ToString().Highlight()} approved for release.");
            }

            if (args.ReleaseInfo.Releases.Any())
                return 0;
            
            log.Error($"No release candidates. Aborting release");
            return 400;
        }
    }
}
