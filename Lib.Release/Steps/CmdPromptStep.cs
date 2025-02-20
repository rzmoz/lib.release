using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Win;

namespace Lib.Release.Steps
{
    public abstract class CmdPromptStep<T>(ILoog log) : PipelineStep<T>
    {
        protected CmdPromptLogger CmdRun(string cmd, out int exitCode)
        {
            var cmdLogger = new CmdPromptLogger();
            cmdLogger.DebugLogged += log.Debug;
            cmdLogger.InfoLogged += log.Debug;
            cmdLogger.ErrorLogged += log.Error;


            exitCode = CmdPrompt.Run(cmd, cmdLogger);

            return cmdLogger;
        }
    }
}
