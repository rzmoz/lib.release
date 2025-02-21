using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class LibReleasePipelineArgs
    {
        public DirPath? LibRootDir { get; set; }
        public string? ApiKey { get; set; }
        public LibReleaseInfo ReleaseInfo { get; set; } = new();
        public bool SkipTests { get; set; }
    }
}
