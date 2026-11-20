# Downloads the pdf.js sources that the JPEG decoder is ported from to tools/pdfjs-src/ (ignored by git), from one fixed release tag.
# Dot-source or run directly; prints the path of the folder. The tag is also named in the header of
# src/Codec/Pdf4D.Codec.Jpeg.pas, in docs/porting.md and in NOTICE; change all of them together.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag = 'v6.5.438'
$files = 'src/core/jpg.js', 'src/core/core_utils.js', 'src/shared/image_utils.js'
$dest = Join-Path $PSScriptRoot 'pdfjs-src'
foreach ($file in $files) {
    $target = Join-Path $dest $file
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/mozilla/pdf.js/$tag/$file" -OutFile $target -UseBasicParsing
    }
}
Set-Content -Path (Join-Path $dest 'TAG.txt') -Value $tag
Write-Host "pdf.js $tag sources at $dest"
