using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class LibReleasePipelineArgs
    {
        public string? LibRootDir { get; set; }
        public string? PublishKey { get; set; }
        public List<LibReleaseInfo> Releases { get; } = new();
    }
}
