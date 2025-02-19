using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class LibReleaseInfo
    {
        public string Name { get; set; } = string.Empty;
        public SemVersion Version { get; set; } = "0.0.1";
    }
}
