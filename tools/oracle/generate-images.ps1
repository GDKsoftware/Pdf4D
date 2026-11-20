# Runs the oracle (images) over the files of tests/reference/images/selection.txt and writes
# tests/reference/images/<file with / replaced by __>/p<page>-<index>.png, the PDImageXObject.getImage() of every image XObject in
# the resources of each page (ARGB, or the gray or RGB image that PDFBox gives). A listing of what was written (with the colour
# space and the filters) goes to images.txt in the same folder. The format is described in docs/golden-format.md.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$corpus = Join-Path $script:RepoRoot 'tests\corpus'
$root = Join-Path $script:RepoRoot 'tests\reference\images'
$selection = Get-Content (Join-Path $root 'selection.txt') | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') }
foreach ($entry in $selection) {
    $target = Join-Path $root ($entry.Trim().Replace('/', '__'))
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Force $target | Out-Null
    $listing = & $java -Xmx2g -cp $cp Pdf4DOracle images (Join-Path $corpus $entry.Trim()) $target
    if ($LASTEXITCODE -ne 0) { throw "images failed for $entry" }
    [IO.File]::WriteAllText((Join-Path $target 'images.txt'), (($listing -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Host ('{0}: {1} images' -f $entry, @(Get-ChildItem $target -Filter *.png).Count)
}
