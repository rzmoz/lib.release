using DotNet.Basics.Collections;
using DotNet.Basics.IO;
using DotNet.Basics.Pipelines;
using DotNet.Basics.Diagnostics;
using DotNet.Basics.Sys;
using Microsoft.Extensions.Logging;
using System.Xml;

namespace Lib.Release.Steps
{
    public class ApplyVersionStep(ILogger log) : PipelineStep<ReleaseCliSettings>
    {
        private const string _versionNodeName = "Version";
        private static readonly string[] _versionNodeNames = [_versionNodeName, "AssemblyVersion", "FileVersion"];

        protected override Task<int> RunImpAsync(ReleaseCliSettings args)
        {
            var result = args.ReleaseInfo.Releases.ForEachParallel(r =>
            {
                var projFile = args.Lib.ToFile(r.Name, $"{r.Name}.csproj");

                if (projFile.Exists())
                {
                    log.Debug($"Project file {projFile} found");
                    r.ProjectFile = projFile;//set for final cleanup
                    return PatchVersions(r);
                }
                log.Critical($"Project file {projFile} not found!");
                return 400;
            }).Sum();
            return Task.FromResult(result);
        }

        private int PatchVersions(ReleaseInfo r)
        {
            r.ProjectFile!.CopyTo(r.TempProjectFile!, true);
            var xml = new XmlDocument();
            xml.Load(r.ProjectFile!.FullName);

            var propertyGroupNode = xml.SelectSingleNode("//Project/PropertyGroup");
            if (propertyGroupNode == null)
            {
                log.Error($"Xml format in {r.ProjectFile.FullName.Highlight()} not recognized");
                return 400;
            }

            foreach (var name in _versionNodeNames)
            {
                var vNode = propertyGroupNode.SelectSingleNode($"//{name}");

                if (propertyGroupNode.SelectSingleNode($"//{name}") == null)
                {
                    propertyGroupNode.AppendChild(xml.CreateElement(name));
                    vNode = propertyGroupNode.SelectSingleNode($"//{name}");
                }

                vNode!.InnerText = name == _versionNodeName
                    ? r.GetSemVer().SemVer20String
                    : $"{r.GetSemVer().FileVerString}";

                log.Debug($"{name} set to {vNode.InnerText} in {r.ProjectFile.Name}");
            }

            xml.Save(r.ProjectFile.FullName);
            return 0;
        }
    }
}
