using DotNet.Basics.Pipelines;
using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Win;

namespace Lib.Release.Steps
{
    public abstract class CmdPromptStep<T>(ILoog log) : PipelineStep<T>
    {
        protected ILoog Log { get; } = log;

        protected CmdPromptLogger CmdRun(string cmd, out int exitCode)
        {
            var cmdLogger = new CmdPromptLogger();
            cmdLogger.DebugLogged += Log.Debug;
            cmdLogger.InfoLogged += Log.Debug;
            cmdLogger.ErrorLogged += Log.Error;


            exitCode = CmdPrompt.Run(cmd, cmdLogger);

            return cmdLogger;
        }
    }
}
