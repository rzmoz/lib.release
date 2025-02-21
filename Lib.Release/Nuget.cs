using System.Text.Json.Nodes;
using DotNet.Basics.Serilog.Looging;
using static System.Net.WebRequestMethods;

namespace Lib.Release
{
    //https://learn.microsoft.com/en-us/nuget/reference/nuget-exe-cli-reference?tabs=windows
    public class Nuget(ILoog log) : IDisposable
    {
        private static readonly HttpClient _client = new();

        private const string _nugetDotOrgSource = "https://api.nuget.org/v3/index.json";

        public async Task<NugetPackage> SearchAsync(string packageName, bool preRelease = true, string? source = null)
        {
            var latest = await GetLatestPackageInfoAsync(packageName, preRelease, source) ?? new NugetPackage
            {
                Name = packageName,
                Version = "0.0.0"
            };

            log.Debug($"{latest.Name.Highlight()} version resolved to: {latest.Version.Highlight()}");
            return latest;
        }

        private async Task<NugetPackage?> GetLatestPackageInfoAsync(string packageName, bool preRelease = true, string? source = null)
        {
            var searchUrl = await GetSearchQueryUrlAsync(source);
            var query = $"{searchUrl}?take=1&q={packageName}&prerelease={preRelease}";
            log.Debug($"Searching for package: {packageName} at {searchUrl}");
            var response = await _client.GetAsync(query);
            var json = await JsonNode.ParseAsync(await response.Content.ReadAsStreamAsync())!;
            var data = json!["data"]!.AsArray()!;
            return !data.Any()
                ? null
                : new NugetPackage
                {
                    Name = packageName,
                    Version = data!.First()!["version"]!.GetValue<string>()
                };
        }

        private async Task<string> GetSearchQueryUrlAsync(string? source)
        {
            source ??= _nugetDotOrgSource;
            var response = await _client.GetAsync(source);
            var json = await JsonNode.ParseAsync(await response.Content.ReadAsStreamAsync())!;
            var resources = json!["resources"]!.AsArray();
            foreach (var resource in resources)
            {
                if (resource!["@type"]!.GetValue<string>().Equals("SearchQueryService"))
                    return resource["@id"]!.GetValue<string>();
            }
            throw new ArgumentException($"Failed to find SearchQueryService in {source}");
        }


        public void Dispose()
        {
            _client.Dispose();
        }
    }
}
