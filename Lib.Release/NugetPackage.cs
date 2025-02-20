using DotNet.Basics.Sys;
using DotNet.Basics.Serilog.Looging;

namespace Lib.Release
{
    public class NugetPackage
    {
        public string Name { get; set; } = string.Empty;
        public SemVersion Version { get; set; } = new();
        public long Downloads { get; set; }


        protected bool Equals(NugetPackage other)
        {
            return Name.Equals(other.Name, StringComparison.OrdinalIgnoreCase);
        }

        public override bool Equals(object? obj)
        {
            if (obj is null) return false;
            if (ReferenceEquals(this, obj)) return true;
            if (obj.GetType() != GetType()) return false;
            return Equals((NugetPackage)obj);
        }

        public override int GetHashCode()
        {
            return Name.ToLowerInvariant().GetHashCode();
        }

        public override string ToString()
        {
            return $"{Name.Highlight()} | {Version.SemVer20String.Highlight()} | {Downloads.ToString().Highlight()}";
        }
    }
}
