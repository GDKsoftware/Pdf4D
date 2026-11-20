# Builds the resource files in src/Resources from the PDFBox 3.0.8 sources in tools/pdfbox-src (tools/fetch-pdfbox-src.ps1).
# Every source file becomes one zlib-compressed RCDATA resource; each group (glyph lists, AFM metrics, CMaps, fonts, ICC profiles) is
# one .res file that its linker unit Pdf4D.Resources.<Group>.pas includes with {$R}. The script also writes
# src/Resources/resources.csv (name;source;sha256;license) with the SHA-256 of the uncompressed bytes and copies the
# MustRead.html of the AFM files next to the resources, because the AFM licence requires that it stays with the AFM files.
# The output is byte-identical for identical sources.
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..\pdfbox-src'),
    [string]$OutputFolder = (Join-Path $PSScriptRoot '..\..\src\Resources'),
    [string]$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
    # Rebuilds only the .res file of this group (GLYPHLIST, AFM, CMAP, FONT, UNICODE or ICC); resources.csv always lists all groups.
    [string]$OnlyGroup = ''
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;

public static class Pdf4DZlib
{
    // zlib stream (RFC 1950): header 78 9C, raw deflate data, big-endian Adler-32 of the uncompressed data.
    public static byte[] Compress(byte[] data)
    {
        using (var output = new MemoryStream())
        {
            output.WriteByte(0x78);
            output.WriteByte(0x9C);
            using (var deflate = new DeflateStream(output, CompressionLevel.Optimal, true))
            {
                deflate.Write(data, 0, data.Length);
            }
            uint a = 1, b = 0;
            foreach (byte value in data)
            {
                a = (a + value) % 65521;
                b = (b + a) % 65521;
            }
            uint adler = (b << 16) | a;
            output.WriteByte((byte)(adler >> 24));
            output.WriteByte((byte)(adler >> 16));
            output.WriteByte((byte)(adler >> 8));
            output.WriteByte((byte)adler);
            return output.ToArray();
        }
    }
}
'@

$SourceRoot = (Resolve-Path $SourceRoot).Path
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}
$OutputFolder = (Resolve-Path $OutputFolder).Path

$pdfboxResources = Join-Path $SourceRoot 'pdfbox\src\main\resources\org\apache\pdfbox\resources'
$cmapFolder = Join-Path $SourceRoot 'fontbox\src\main\resources\org\apache\fontbox\cmap'

function Get-ResourceName([string]$Group, [string]$Item) {
    # Must match TPdfResourceData.NameOf
    return ('PDF4D_' + $Group + '_' + $Item).ToUpperInvariant() -replace '[^A-Z0-9]', '_'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Get-SourcePath([string]$FullPath) {
    # Files outside the PDFBox sources (the generated Unicode tables) are named relative to the repository root
    if ($FullPath.StartsWith($SourceRoot)) {
        return $FullPath.Substring($SourceRoot.Length).TrimStart('\').Replace('\', '/')
    }
    return $FullPath.Substring($repoRoot.Length).TrimStart('\').Replace('\', '/')
}

# Each group: output name, resource group token, and the list of (item name, file, license)
$groups = @()

$glyphItems = @()
foreach ($name in 'glyphlist', 'zapfdingbats', 'additional') {
    $license = if ($name -eq 'additional') { 'Apache-2.0' } else { 'Adobe-GlyphList-BSD' }
    $glyphItems += , @($name, (Join-Path $pdfboxResources "glyphlist\$name.txt"), $license)
}
$groups += , @('GlyphList', 'GLYPHLIST', $glyphItems)

$afmItems = @()
foreach ($file in Get-ChildItem (Join-Path $pdfboxResources 'afm') -Filter '*.afm' | Sort-Object Name) {
    $afmItems += , @([IO.Path]::GetFileNameWithoutExtension($file.Name), $file.FullName, 'Adobe-AFM')
}
$mustRead = Join-Path $pdfboxResources 'afm\MustRead.html'
$afmItems += , @('MustRead', $mustRead, 'Adobe-AFM')
$groups += , @('Afm', 'AFM', $afmItems)

$cmapItems = @()
foreach ($file in Get-ChildItem $cmapFolder -File | Sort-Object Name) {
    $cmapItems += , @($file.Name, $file.FullName, 'Adobe-CMap-BSD')
}
$groups += , @('CMap', 'CMAP', $cmapItems)

$fontItems = @()
$fontItems += , @('LiberationSans', (Join-Path $pdfboxResources 'ttf\LiberationSans-Regular.ttf'), 'OFL-1.1')
$groups += , @('Fonts', 'FONT', $fontItems)

$unicodeItems = @()
$textTables = Join-Path $repoRoot 'tools\unicode\text-tables.txt'
$unicodeItems += , @('TextTables', $textTables, 'Unicode-3.0')
$groups += , @('Unicode', 'UNICODE', $unicodeItems)

$iccItems = @()
# The profile that PDDeviceCMYK loads; its copyright tag says CC0
$iccItems += , @('CMYK', (Join-Path $pdfboxResources 'icc\CGATS001Compat-v2-micro.icc'), 'CC0-1.0')
$groups += , @('Icc', 'ICC', $iccItems)

$work = Join-Path ([IO.Path]::GetTempPath()) ('pdf4d-resources-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$csv = New-Object System.Collections.Generic.List[string]
$csv.Add('name;source;sha256;license')
$seen = @{}
$sha = [Security.Cryptography.SHA256]::Create()

try {
    foreach ($group in $groups) {
        $groupName = $group[0]
        $groupToken = $group[1]
        $rcLines = New-Object System.Collections.Generic.List[string]
        $groupFolder = Join-Path $work $groupName
        New-Item -ItemType Directory -Path $groupFolder | Out-Null

        foreach ($item in $group[2]) {
            $resourceName = Get-ResourceName $groupToken $item[0]
            if ($seen.ContainsKey($resourceName)) {
                throw "Duplicate resource name $resourceName ($($item[1]) and $($seen[$resourceName]))"
            }
            $seen[$resourceName] = $item[1]
            if (-not (Test-Path $item[1])) {
                throw "Missing source file $($item[1]); run tools/fetch-pdfbox-src.ps1"
            }

            $bytes = [IO.File]::ReadAllBytes($item[1])
            $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
            [IO.File]::WriteAllBytes((Join-Path $groupFolder "$resourceName.z"), [Pdf4DZlib]::Compress($bytes))
            $rcLines.Add("$resourceName RCDATA `"$resourceName.z`"")
            $csv.Add(('{0};{1};{2};{3}' -f $resourceName, (Get-SourcePath $item[1]), $hash, $item[2]))
        }

        $rcPath = Join-Path $groupFolder "Pdf4D.Resources.$groupName.rc"
        [IO.File]::WriteAllLines($rcPath, $rcLines, (New-Object Text.UTF8Encoding($false)))

        if ($OnlyGroup -ne '' -and $OnlyGroup -ne $groupToken) {
            continue
        }
        $resPath = Join-Path $OutputFolder "Pdf4D.Resources.$groupName.res"
        $command = "call `"$RsVars`" && cd /d `"$groupFolder`" && brcc32 -fo`"$resPath`" `"$rcPath`""
        $output = & cmd /c $command 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) {
            $output | ForEach-Object { Write-Host $_ }
            throw "brcc32 failed for group $groupName"
        }
        Write-Host ("{0}: {1} resources, {2:N0} bytes" -f $groupName, $group[2].Count, (Get-Item $resPath).Length)
    }
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

# The AFM licence requires MustRead.html to stay with the AFM files
Copy-Item $mustRead (Join-Path $OutputFolder 'afm-MustRead.html') -Force

# LF line endings, no BOM
[IO.File]::WriteAllText((Join-Path $OutputFolder 'resources.csv'), (($csv -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "Wrote $($csv.Count - 1) resources to $OutputFolder"
