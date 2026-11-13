# Downloads the PDFBox 3.0.8 source release and extracts it to tools/pdfbox-src/ (ignored by git).
# Dot-source or run directly; prints the path of the extracted source root.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = Join-Path $PSScriptRoot 'pdfbox-src'
if (-not (Test-Path (Join-Path $dest 'pdfbox\pom.xml'))) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    $zip = Join-Path $dest 'src.zip'
    $name = 'pdfbox-3.0.8-src.zip'
    $base = 'https://archive.apache.org/dist/pdfbox/3.0.8'
    Invoke-WebRequest -Uri "$base/$name" -OutFile $zip -UseBasicParsing
    $expected = ((Invoke-WebRequest -Uri "$base/$name.sha512" -UseBasicParsing).Content -split '\s+')[0].Trim().ToLower()
    if ((Get-FileHash -Algorithm SHA512 $zip).Hash.ToLower() -ne $expected) { Remove-Item $zip; throw "SHA-512 mismatch for $name" }
    $tmp = Join-Path $dest '_x'
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Get-ChildItem $root.FullName -Force | Move-Item -Destination $dest -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip
}
Write-Host "PDFBox source at $dest"
