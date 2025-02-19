using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class ReleaseInfo
    {
        public string Name { get; set; } = string.Empty;
        public SemVersion Version { get; set; } = new();
        public string PreRelease { get; set; } = string.Empty;
    }
}
