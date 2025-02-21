using DotNet.Basics.Serilog.Looging;
using DotNet.Basics.Sys.Text;

namespace Lib.Release
{
    //https://learn.microsoft.com/en-us/nuget/reference/nuget-exe-cli-reference?tabs=windows
    public class Nuget(ILoog log) : IDisposable
    {
        private static readonly SysRegex _pkgVersionRegex = @"<span class=""install-command-row"">dotnet add package .+? --version (?<version>.+?)</span>";
        private static readonly HttpClient _client = new();

        private const string _nugetSearchBaseurl = "https://www.nuget.org/packages/";

        public async Task<NugetPackage> SearchAsync(string packageName, bool preRelease = true)
        {
            var searchQueryUrl = $"{_nugetSearchBaseurl}{packageName}";

            log.Debug($"Searching for package: {searchQueryUrl}");
            var response = await _client.GetAsync(searchQueryUrl);
            if (!response.IsSuccessStatusCode)
                return new NugetPackage
                {
                    Name = packageName,
                    Version = "0.0.0"
                };

            var html = await response.Content.ReadAsStringAsync();
            log.Verbose(html);
            var version = _pkgVersionRegex.Match(html);

            log.Verbose($"{packageName.Highlight()} version resolved to: {version.Highlight()}");

            return new NugetPackage
            {
                Name = packageName,
                Version = version
            };
        }
        public void Dispose()
        {
            _client.Dispose();
        }
    }
}
