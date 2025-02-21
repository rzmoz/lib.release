using DotNet.Basics.Cli;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;
using DotNet.Basics.Win;

namespace Lib.Release.Steps
{
    public class RunTestsStep(ILoog log) : PipelineStep<LibReleasePipelineArgs>
    {
        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
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
                    var csprojFile = args.LibRootDir!.ToDir(testProjectName)!.GetFiles("*.csproj").Single();
                    var testCmd = @$"dotnet test ""{csprojFile.FullName}"" -c release";
                    log.Debug($"Testing {csprojFile.FullName.Highlight()}");

                    if (CmdPrompt.Run(testCmd, log.WithPromptLogger()) != 0)
                        throw new ApplicationException($"Tests failed in {csprojFile.Name}. See log for details.");
                }
            }
            else
                log.Warning("No tests configured. Skipping tests...");
            
            return Task.FromResult(0);
        }
    }
}
