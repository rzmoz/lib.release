using DotNet.Basics.IO;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys;

namespace Lib.Release.Steps
{
    public class RunTestsStep(ILoog log) : CmdPromptStep<LibReleasePipelineArgs>(log)
    {
        private readonly ILoog _log = log;

        protected override Task<int> RunImpAsync(LibReleasePipelineArgs args)
        {
            if (args.SkipTests)
            {
                _log.Info("Skipping tests");
                return Task.FromResult(0);
            }

            foreach (var testProjectName in args.ReleaseInfo.Tests)
            {
                var csprojFile = args.LibRootDir!.ToDir(testProjectName).GetFiles("*.csproj").Single();
                var testCmd = @$"dotnet test ""{csprojFile.FullName}"" -c release";
                _log.Info($"Testing {csprojFile.FullName.Highlight()}");

                var logger = CmdRun(testCmd, out var exitCode);
                if (exitCode != 0 || logger.HasErrors)
                    throw new ApplicationException($"Tests failed in {csprojFile.Name}. See log for details.");
            }

            return Task.FromResult(0);
        }
    }
}
