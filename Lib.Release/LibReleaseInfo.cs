namespace Lib.Release
{
    public class LibReleaseInfo
    {
        public List<ReleaseInfo> Releases { get; set; } = new();
        public IReadOnlyList<string> Tests { get; set; } = [];
    }
}
