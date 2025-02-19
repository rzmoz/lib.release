﻿using DotNet.Basics.Sys;

namespace Lib.Release
{
    public class LibReleasePipelineArgs
    {
        public DirPath? LibRootDir { get; set; }
        public string? PublishKey { get; set; }
        public List<LibReleaseInfo> ReleaseInfos { get; } = new();
    }
}
