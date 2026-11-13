# Builds tests/fonts: the test fonts for text extraction and font metrics, and tests/fonts/manifest.csv.
# Fonts from the PDFBox source are copied from tools/pdfbox-src/ (fetched when missing); the others are
# downloaded from the URLs in fontbox/pom.xml (PDFBox 3.0.8) and checked against the SHA-512 listed there.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
& (Join-Path $root 'tools\fetch-pdfbox-src.ps1') | Out-Null
$src = Join-Path $root 'tools\pdfbox-src'
$dest = Join-Path $root 'tests\fonts'
New-Item -ItemType Directory -Force $dest | Out-Null

$ofl = 'SIL OFL 1.1'
$fromSource = @(
    @{ file = 'LiberationSans-Regular.ttf'; path = 'fontbox\src\test\resources\ttf\LiberationSans-Regular.ttf'; license = $ofl; notes = 'Liberation Fonts, copy from the PDFBox 3.0.8 source' },
    @{ file = 'JosefinSans-Italic.ttf'; path = 'fontbox\src\test\resources\ttf\JosefinSans-Italic.ttf'; license = $ofl; notes = 'Josefin Sans, copy from the PDFBox 3.0.8 source' },
    @{ file = 'FoglihtenNo07.otf'; path = 'fontbox\src\test\resources\otf\FoglihtenNo07.otf'; license = $ofl; notes = 'FoglihtenNo07 by Grzegorz Luk, CFF, copy from the PDFBox 3.0.8 source' }
)
$downloads = @(
    @{ file = 'SourceSansProBold.otf'; url = 'https://issues.apache.org/jira/secure/attachment/12684264/SourceSansProBold.otf'; sha512 = '28a044a2685fbc8da7810d9ac7b6b93a95542d504d7d8e671f009b8ebb2f5b70c974be7ea78974b188d8e6ab17d65b08f276c054927857315d5aad26f6fe36fc'; license = $ofl; notes = 'Source Sans Pro Bold by Adobe, CFF' },
    @{ file = 'OpenSans-Regular.pfb'; url = 'https://mirror.math.princeton.edu/pub/CTAN/fonts/opensans/type1/OpenSans-Regular.pfb'; sha512 = '2787fcecc0feb1c9e6ff0d8de6193658413863e44eaab572751ca7e6c3b369c0a9731f4952cb0821f307760f0422f77c5f0d3fe7df6b054643fb39423e8d70ee'; license = 'Apache-2.0'; notes = 'Open Sans, Type 1 conversion' },
    @{ file = 'DejaVuSerifCondensed.pfb'; url = 'https://issues.apache.org/jira/secure/attachment/13064282/DejaVuSerifCondensed.pfb'; sha512 = '6ef13c3497862dc8e4c2a4261bc3a7ef3e2dd75e00ae2af4912b236b387225541db76c72854fbb2323d1064311ffdda9e64ed7065afc3a7d13f5b71b7df2f2ef'; license = 'Bitstream Vera and DejaVu licence'; notes = 'DejaVu Serif Condensed, Type 1 conversion' }
)

$rows = @()
foreach ($f in $fromSource) {
    Copy-Item (Join-Path $src $f.path) (Join-Path $dest $f.file) -Force
    $rows += ('{0};{1};{2};{3}' -f $f.file, ('https://archive.apache.org/dist/pdfbox/3.0.8/pdfbox-3.0.8-src.zip#' + $f.path.Replace('\', '/')), $f.license, $f.notes)
}
foreach ($f in $downloads) {
    $target = Join-Path $dest $f.file
    $ok = (Test-Path $target) -and ((Get-FileHash -Algorithm SHA512 $target).Hash.ToLower() -eq $f.sha512)
    if (-not $ok) {
        Invoke-WebRequest -Uri $f.url -OutFile $target -UseBasicParsing
        if ((Get-FileHash -Algorithm SHA512 $target).Hash.ToLower() -ne $f.sha512) { Remove-Item $target; throw "SHA-512 mismatch for $($f.file)" }
    }
    $rows += ('{0};{1};{2};{3}' -f $f.file, $f.url, $f.license, $f.notes)
}
$lines = @('file;source_url;license;notes') + ($rows | Sort-Object { $_ } -CaseSensitive)
[IO.File]::WriteAllText((Join-Path $dest 'manifest.csv'), (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "$($rows.Count) fonts in $dest"
