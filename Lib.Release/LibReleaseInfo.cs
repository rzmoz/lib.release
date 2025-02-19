namespace Lib.Release
{
    public class LibReleaseInfo
    {
        public string Source { get; set; } = "https://api.nuget.org/v3/index.json";
        public List<ReleaseInfo> Releases { get; set; } = new();
        public IReadOnlyList<string> Tests { get; set; } = [];
    }
}
