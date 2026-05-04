using DotNet.Basics.Cli;
using DotNet.Basics.IO;
using DotNet.Basics.Sys;
using Spectre.Console;
using Spectre.Console.Cli;
using System.ComponentModel;

namespace Lib.Release
{
    public class ReleaseCliSettings : CliCommandSettings
    {
        private const string _fallbackProjectsDirName = @"c:\projects";
        private const string NUGET_API_KEY_Name = "NUGET_API_KEY";


        [CommandArgument(0, $"<{nameof(Lib)}>")]
        [Description("Lib to release. Can be either name in default location or fully rooted path")]
        public required string Lib { get; set; }

        [CommandOption($"--{nameof(ApiKey)}")]
        [Description($"nuget.org api key for pushing packages to nuget.org. Can also be set as environment variable: {NUGET_API_KEY_Name}. Explicit {nameof(ApiKey)} set overrules Environment variable")]
        public string? ApiKey { get; set; }

        [CommandOption($"--{nameof(SkipTests)}")]
        [Description("Skip running tests")]
        [DefaultValue(false)]
        public required bool SkipTests { get; init; }

        public LibReleaseInfo ReleaseInfo { get; set; } = new();

        public override ValidationResult Validate()
        {
            if (!Path.IsPathRooted(Lib))
                Lib = _fallbackProjectsDirName.ToDir(Lib);
            if (!Lib.ToDir().Exists())
                return ValidationResult.Error($"Lib '{Lib}' not found at {Lib}");

            if (string.IsNullOrEmpty(ApiKey))
                ApiKey = Environment.GetEnvironmentVariable(NUGET_API_KEY_Name);
            if (string.IsNullOrEmpty(ApiKey))
                return ValidationResult.Error($"{nameof(ApiKey)} not set");
            return base.Validate();
        }
    }
}
