using DotNet.Basics.IO;
using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class ReleaseInfo
    {
        public string Name { get; set; } = string.Empty;
        public string Version { get; set; } = string.Empty;
        public string PreRelease { get; set; } = string.Empty;
        public FilePath? ProjectFile { get; set; }
        public FilePath? TempProjectFile => ProjectFile?.Directory.ToFile($"{ProjectFile.Name}.tmp");
        public DirPath? PackDir => ProjectFile?.Directory.Add("bin/.nuget");

        public SemVersion GetSemVer() => $"{Version}{(PreRelease.Any() ? $"+{PreRelease}" : "")}";

        public static implicit operator ReleaseInfo(string name)
        {
            return new ReleaseInfo
            {
                Name = name
            };
        }

        protected bool Equals(ReleaseInfo other)
        {
            return Name.Equals(other.Name, StringComparison.OrdinalIgnoreCase);
        }

        public override bool Equals(object? obj)
        {
            if (obj is null) return false;
            if (ReferenceEquals(this, obj)) return true;
            if (obj.GetType() != GetType()) return false;
            return Equals((ReleaseInfo)obj);
        }

        public override int GetHashCode()
        {
            return Name.GetHashCode();
        }

        public override string ToString()
        {
            return $"{Name}: {Version}{(PreRelease.Any() ? $"+{PreRelease}" : "")}";
        }
    }
}
