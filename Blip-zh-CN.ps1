param(
    [ValidateSet('Apply', 'Restore', 'Status')]
    [string]$Mode = 'Apply',
    [switch]$Launch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$bundleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$translationsPath = Join-Path $bundleDir 'translations.zh-CN.json'
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Blip-zh-CN'
$versionsRoot = Join-Path $installRoot 'versions'
$backupRoot = Join-Path $installRoot 'backup'
$statePath = Join-Path $installRoot 'state.json'
$shortcutName = 'Blip（简体中文）.lnk'
$shortcutPaths = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName),
    (Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\$shortcutName")
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not ('BlipZhCn.ClassPatcher' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace BlipZhCn {
    public sealed class PatchResult {
        public byte[] Bytes { get; set; }
        public int ReplacementCount { get; set; }
    }

    public static class ClassPatcher {
        private static int U2(byte[] bytes, int offset) {
            return (bytes[offset] << 8) | bytes[offset + 1];
        }

        private static void WriteU2(Stream stream, int value) {
            stream.WriteByte((byte)((value >> 8) & 0xff));
            stream.WriteByte((byte)(value & 0xff));
        }

        public static PatchResult Patch(byte[] bytes, IDictionary translations) {
            if (bytes.Length < 10 || bytes[0] != 0xca || bytes[1] != 0xfe ||
                bytes[2] != 0xba || bytes[3] != 0xbe) {
                return new PatchResult { Bytes = bytes, ReplacementCount = 0 };
            }

            int constantCount = U2(bytes, 8);
            int[] starts = new int[constantCount];
            int[] ends = new int[constantCount];
            int[] tags = new int[constantCount];
            var utf8 = new Dictionary<int, string>();
            int[] stringReferenceIndexes = new int[constantCount];
            int position = 10;

            for (int i = 1; i < constantCount; i++) {
                int start = position;
                int tag = bytes[position++];
                starts[i] = start;
                tags[i] = tag;
                switch (tag) {
                    case 1:
                        int length = U2(bytes, position);
                        position += 2;
                        utf8[i] = Encoding.UTF8.GetString(bytes, position, length);
                        position += length;
                        break;
                    case 3:
                    case 4:
                        position += 4;
                        break;
                    case 5:
                    case 6:
                        position += 8;
                        ends[i] = position;
                        i++;
                        continue;
                    case 7:
                    case 16:
                    case 19:
                    case 20:
                        position += 2;
                        break;
                    case 8:
                        stringReferenceIndexes[i] = U2(bytes, position);
                        position += 2;
                        break;
                    case 9:
                    case 10:
                    case 11:
                    case 12:
                    case 17:
                    case 18:
                        position += 4;
                        break;
                    case 15:
                        position += 3;
                        break;
                    default:
                        throw new InvalidDataException("Unknown class constant tag " + tag + ".");
                }
                ends[i] = position;
            }

            int constantPoolEnd = position;
            int replacements = 0;
            var translatedReferenceIndexes = new Dictionary<int, int>();
            var appendedUtf8 = new List<byte[]>();
            var appendedIndexByText = new Dictionary<string, int>();

            // Never rewrite an existing Utf8 constant in place. The JVM may share the
            // same Utf8 entry between a visible string and a field/method name (for
            // example the SegoeIcon.Cancel enum). Append a new Utf8 entry and point
            // only the CONSTANT_String entry at it.
            for (int i = 1; i < constantCount; i++) {
                if (tags[i] != 8) continue;
                string source;
                if (!utf8.TryGetValue(stringReferenceIndexes[i], out source) || !translations.Contains(source))
                    continue;
                string target = Convert.ToString(translations[source]);
                byte[] encoded = Encoding.UTF8.GetBytes(target);
                if (encoded.Length > UInt16.MaxValue)
                    throw new InvalidDataException("Translated string is too long: " + source);
                int translatedIndex;
                if (!appendedIndexByText.TryGetValue(target, out translatedIndex)) {
                    translatedIndex = constantCount + appendedUtf8.Count;
                    appendedIndexByText[target] = translatedIndex;
                    appendedUtf8.Add(encoded);
                }
                translatedReferenceIndexes[i] = translatedIndex;
                replacements++;
            }

            int newConstantCount = constantCount + appendedUtf8.Count;
            if (newConstantCount > UInt16.MaxValue)
                throw new InvalidDataException("Class constant pool is too large after translation.");
            using (var output = new MemoryStream(bytes.Length + 4096)) {
                output.Write(bytes, 0, 8);
                WriteU2(output, newConstantCount);
                for (int i = 1; i < constantCount; i++) {
                    if (starts[i] == 0) continue;
                    int translatedIndex;
                    if (tags[i] == 8 && translatedReferenceIndexes.TryGetValue(i, out translatedIndex)) {
                        output.WriteByte(8);
                        WriteU2(output, translatedIndex);
                        continue;
                    }
                    output.Write(bytes, starts[i], ends[i] - starts[i]);
                }
                foreach (byte[] encoded in appendedUtf8) {
                    output.WriteByte(1);
                    WriteU2(output, encoded.Length);
                    output.Write(encoded, 0, encoded.Length);
                }
                output.Write(bytes, constantPoolEnd, bytes.Length - constantPoolEnd);
                return new PatchResult { Bytes = output.ToArray(), ReplacementCount = replacements };
            }
        }
    }
}
'@
}

function Get-BlipPackage {
    $package = Get-AppxPackage -Name 'BlipStudioInc.BlipApp' | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) { throw '未找到 Microsoft Store 版 Blip。请先安装 Blip。' }
    if (-not (Test-Path -LiteralPath $package.InstallLocation)) { throw 'Blip 安装目录不存在。' }
    return $package
}

function Get-Translations {
    if (-not (Test-Path -LiteralPath $translationsPath)) { throw "缺少翻译文件：$translationsPath" }
    # Windows PowerShell 5.1 lacks ConvertFrom-Json -AsHashtable and its JSON
    # object conversion rejects keys that differ only by case. The translation
    # table legitimately contains such labels, so use the case-sensitive .NET
    # JSON deserializer available on supported Windows systems.
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $table = $serializer.DeserializeObject((Get-Content -LiteralPath $translationsPath -Raw -Encoding UTF8))
    foreach ($source in $table.Keys) {
        $sourceSlots = ([regex]::Matches([string]$source, [char]1)).Count
        $targetSlots = ([regex]::Matches([string]$table[$source], [char]1)).Count
        if ($sourceSlots -ne $targetSlots) { throw "占位符数量不一致：$source" }
    }
    return $table
}

function Copy-Stream([System.IO.Stream]$Source, [System.IO.Stream]$Destination) {
    $buffer = New-Object byte[] 131072
    while (($read = $Source.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $Destination.Write($buffer, 0, $read)
    }
}

function Patch-Jar([string]$JarPath, [System.Collections.IDictionary]$Translations) {
    $tempPath = "$JarPath.zhcn-new"
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    $sourceArchive = [IO.Compression.ZipFile]::OpenRead($JarPath)
    $targetStream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $targetArchive = [IO.Compression.ZipArchive]::new($targetStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    $replacementCount = 0
    try {
        foreach ($entry in $sourceArchive.Entries) {
            $newEntry = $targetArchive.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)
            $newEntry.LastWriteTime = $entry.LastWriteTime
            $newEntry.ExternalAttributes = $entry.ExternalAttributes
            if ($entry.FullName.EndsWith('/')) { continue }
            $input = $entry.Open()
            $output = $newEntry.Open()
            try {
                if ($entry.FullName.EndsWith('.class', [StringComparison]::OrdinalIgnoreCase)) {
                    $memory = [IO.MemoryStream]::new()
                    try {
                        Copy-Stream $input $memory
                        $result = [BlipZhCn.ClassPatcher]::Patch($memory.ToArray(), $Translations)
                        $output.Write($result.Bytes, 0, $result.Bytes.Length)
                        $replacementCount += $result.ReplacementCount
                    }
                    finally { $memory.Dispose() }
                }
                else {
                    Copy-Stream $input $output
                }
            }
            finally {
                $output.Dispose()
                $input.Dispose()
            }
        }
    }
    finally {
        $targetArchive.Dispose()
        $targetStream.Dispose()
        $sourceArchive.Dispose()
    }
    Move-Item -LiteralPath $tempPath -Destination $JarPath -Force
    return $replacementCount
}

function New-BlipShortcut([string]$TargetPath) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in $shortcutPaths) {
        $parent = Split-Path -Parent $shortcutPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
        $shortcut.IconLocation = "$TargetPath,0"
        $shortcut.Description = 'Blip 简体中文（社区汉化，原版 Store 安装保持不变）'
        $shortcut.Save()
    }
}

function Remove-BlipShortcuts {
    foreach ($shortcutPath in $shortcutPaths) {
        if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    }
}

function Stop-BlipProcesses {
    $running = Get-Process -Name 'Blip' -ErrorAction SilentlyContinue
    if (-not $running) { return }
    Write-Host '正在关闭当前运行的 Blip，以安全切换程序文件…'
    $running | Stop-Process -Force
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $running = Get-Process -Name 'Blip' -ErrorAction SilentlyContinue
    } while ($running -and (Get-Date) -lt $deadline)
    if ($running) { throw 'Blip 未能在 10 秒内退出，请手动关闭后重试。' }
}

if ($Mode -eq 'Status') {
    $package = Get-BlipPackage
    Write-Host "Store 版：$($package.Version)"
    Write-Host "原版目录：$($package.InstallLocation)"
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        Write-Host "汉化副本：$($state.localizedRoot)"
        Write-Host "汉化版本：$($state.version)"
        Write-Host "替换文案：$($state.replacementCount) 处"
    }
    else { Write-Host '汉化状态：尚未应用' }
    exit 0
}

$package = Get-BlipPackage
$version = $package.Version.ToString()
$sourceRoot = $package.InstallLocation
$localizedRoot = Join-Path $versionsRoot $version
$localizedApp = Join-Path $localizedRoot 'app'
$localizedExe = Join-Path $localizedRoot 'bin\Blip.exe'
$versionBackup = Join-Path $backupRoot $version
$sourceMainJar = Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'app') -Filter 'desktopApp-desktop-*.jar' | Select-Object -First 1
$sourceSharedJar = Get-Item -LiteralPath (Join-Path $sourceRoot 'app\shared-jvm.jar')
if (-not $sourceMainJar) { throw '未找到 Blip 主界面 JAR。' }

Stop-BlipProcesses

if ($Mode -eq 'Restore') {
    if (Test-Path -LiteralPath $localizedRoot) {
        $backupMain = Join-Path $versionBackup $sourceMainJar.Name
        $backupShared = Join-Path $versionBackup $sourceSharedJar.Name
        if (Test-Path -LiteralPath $backupMain) { Copy-Item -LiteralPath $backupMain -Destination (Join-Path $localizedApp $sourceMainJar.Name) -Force }
        if (Test-Path -LiteralPath $backupShared) { Copy-Item -LiteralPath $backupShared -Destination (Join-Path $localizedApp $sourceSharedJar.Name) -Force }
    }
    Remove-BlipShortcuts
    Write-Host '已恢复：汉化快捷方式已移除，汉化副本中的两个 JAR 已还原。'
    Write-Host 'Microsoft Store 安装的原版 Blip 从未被修改，可直接从开始菜单启动。'
    exit 0
}

$translations = Get-Translations
New-Item -ItemType Directory -Path $versionsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $versionBackup -Force | Out-Null

if (-not (Test-Path -LiteralPath $localizedRoot)) {
    Write-Host "正在复制 Blip $version 到独立汉化目录…"
    Copy-Item -LiteralPath $sourceRoot -Destination $localizedRoot -Recurse -Force
}

Copy-Item -LiteralPath $sourceMainJar.FullName -Destination (Join-Path $versionBackup $sourceMainJar.Name) -Force
Copy-Item -LiteralPath $sourceSharedJar.FullName -Destination (Join-Path $versionBackup $sourceSharedJar.Name) -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'AppxManifest.xml') -Destination (Join-Path $versionBackup 'AppxManifest.xml') -Force

# 每次应用前均从 Store 原版刷新两个目标 JAR，确保脚本可重复运行。
Copy-Item -LiteralPath $sourceMainJar.FullName -Destination (Join-Path $localizedApp $sourceMainJar.Name) -Force
Copy-Item -LiteralPath $sourceSharedJar.FullName -Destination (Join-Path $localizedApp $sourceSharedJar.Name) -Force

$mainCount = Patch-Jar (Join-Path $localizedApp $sourceMainJar.Name) $translations
$sharedCount = Patch-Jar (Join-Path $localizedApp $sourceSharedJar.Name) $translations
$replacementCount = $mainCount + $sharedCount
if ($replacementCount -lt 100) { throw "实际替换数量异常偏少：$replacementCount" }

New-BlipShortcut $localizedExe
$state = [ordered]@{
    version = $version
    packageFullName = $package.PackageFullName
    originalRoot = $sourceRoot
    localizedRoot = $localizedRoot
    executable = $localizedExe
    replacementCount = $replacementCount
    appliedAt = (Get-Date).ToString('o')
    mainJarSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $localizedApp $sourceMainJar.Name)).Hash
    sharedJarSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $localizedApp $sourceSharedJar.Name)).Hash
}
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "汉化已应用：Blip $version，共替换 $replacementCount 处界面文案。"
Write-Host "汉化目录：$localizedRoot"
Write-Host '原版 Store 包保持不变。桌面和开始菜单已创建“Blip（简体中文）”。'

if ($Launch) {
    Start-Process -FilePath $localizedExe -WorkingDirectory (Split-Path -Parent $localizedExe)
}
