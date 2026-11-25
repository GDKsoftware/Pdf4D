# Downloads the tiny-skia v0.12.0 source archive, checks its SHA-256 and extracts it to tools/tiny-skia-src/ (ignored by git).
# With -CopyTestImages the reference images of tiny-skia (tests/images, without gradients/) are copied to tests/reference/tiny-skia/.
param(
    [switch]$CopyTestImages
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tag = 'v0.12.0'
$archiveSha256 = '8497d5cac8a1995608d492d48072c8ac7e0bf9f01372478e87ef4088137e039f'
$archiveUrl = "https://github.com/linebender/tiny-skia/archive/refs/tags/$tag.zip"
$dest = Join-Path $PSScriptRoot 'tiny-skia-src'

if (-not (Test-Path (Join-Path $dest 'Cargo.toml'))) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    $zip = Join-Path $dest 'src.zip'
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zip -UseBasicParsing
    $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($actual -ne $archiveSha256) {
        Remove-Item $zip
        throw "SHA-256 mismatch for $archiveUrl, got $actual"
    }
    $tmp = Join-Path $dest '_x'
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Get-ChildItem $root.FullName -Force | Move-Item -Destination $dest -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip
    Set-Content -Path (Join-Path $dest 'VERSION.txt') -Value @("tag: $tag", "sha256: $archiveSha256") -Encoding ascii
}

if ($CopyTestImages) {
    $imagesSource = Join-Path $dest 'tests\images'
    $imagesDest = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\reference\tiny-skia'
    foreach ($group in Get-ChildItem $imagesSource -Directory | Where-Object { $_.Name -ne 'gradients' }) {
        $target = Join-Path $imagesDest $group.Name
        New-Item -ItemType Directory -Force $target | Out-Null
        Copy-Item -Path (Join-Path $group.FullName '*') -Destination $target -Recurse -Force
    }
    Write-Host "Test images copied to $imagesDest"
}

Write-Host "tiny-skia $tag source at $dest"
