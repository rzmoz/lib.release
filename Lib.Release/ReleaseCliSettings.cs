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

        [CommandArgument(0, $"<{nameof(Lib)}>")]
        [Description("Lib to release. Can be either name in default location or fully rooted path")]
        public required string Lib { get; set; }

        [CommandOption($"--{nameof(ApiKey)}", isRequired: true)]
        [Description("nuget.org api key for pushing packages to nuget.org")]
        public required string ApiKey { get; init; }

        [CommandOption($"--{nameof(SkipTests)}")]
        [Description("Skip running tests")]
        [DefaultValue(false)]
        public required bool SkipTests { get; init; }

        public LibReleaseInfo ReleaseInfo { get; set; } = new();

        public override ValidationResult Validate()
        {
            if (Path.IsPathRooted(Lib) && Lib.ToDir().Exists())
                return ValidationResult.Success();

            Lib = _fallbackProjectsDirName.ToDir(Lib);
            if (Lib.ToDir().Exists())
                return ValidationResult.Success();

            return ValidationResult.Error($"Lib '{Lib}' not found at {Lib}");
        }
    }
}
