# Writes the synthetic render test files of tests/corpus/generated/render: the Python script (standard library only) writes the files
# that do not need PDFBox, the oracle writes ccitt.pdf with PDFBox's CCITTFactory from the TIFF files in tests/reference/ccitt.
# images.pdf and jpeg.pdf come from make-render-tests.py and make-jpeg-tests.py. Run generate-golden.ps1 -Mode All -Filter generated/render
# and generate-render.ps1 afterwards.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
python (Join-Path $PSScriptRoot 'make-render-pdfs.py')
if ($LASTEXITCODE -ne 0) { throw 'make-render-pdfs.py failed' }
$out = Join-Path $script:RepoRoot 'tests\corpus\generated\render'
$tif = Join-Path $script:RepoRoot 'tests\reference\ccitt'
& $java -Xmx1g '-Djava.awt.headless=true' -cp $cp Pdf4DOracle make-render-tests ccitt $out $tif
if ($LASTEXITCODE -ne 0) { throw 'make-render-tests ccitt failed' }
Write-Host 'ccitt'
