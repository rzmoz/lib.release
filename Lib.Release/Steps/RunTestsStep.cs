using DotNet.Basics.Diagnostics;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Sys;
using DotNet.Basics.Win;
using Microsoft.Extensions.Logging;

namespace Lib.Release.Steps
{
    public class RunTestsStep(ILogger log) : PipelineStep<ReleaseCliSettings>
    {
        protected override Task<int> RunImpAsync(ReleaseCliSettings args)
        {
            if (args.SkipTests)
            {
                log.Info("Skipping tests");
                return Task.FromResult(0);
            }

            if (args.ReleaseInfo.Tests.Any())
            {
                foreach (var testProjectName in args.ReleaseInfo.Tests)
                {
                    var csprojFile = args.Lib.ToDir(testProjectName)!.GetFiles("*.csproj").Single();
                    var testCmd = @$"dotnet test ""{csprojFile.FullName}"" -c release";
                    log.Debug($"Testing {csprojFile.FullName.Highlight()}");

                    if (CmdPrompt.Run(testCmd, log) != 0)
                        throw new ApplicationException($"Tests failed in {csprojFile.Name}. See log for details");
                }
            }
            else
                log.Warn("No tests configured. Skipping tests...");
            
            return Task.FromResult(0);
        }
    }
}
