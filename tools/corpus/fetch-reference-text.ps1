# Copies the expected text files of the PDFBox 3.0.8 test suite (<pdf>.txt, <pdf>-sorted.txt and eu-001.pdf-tabula.txt from
# pdfbox/src/test/resources/input, and the BidiSample files from org/apache/pdfbox/text) from tools/pdfbox-src (fetched when
# missing) to tests/reference/pdfbox-text, writes manifest.csv next to them and refreshes the header (the leading # lines)
# of known-differences.txt. The files are copied byte for byte, the byte order mark included.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
& (Join-Path $root 'tools\fetch-pdfbox-src.ps1') | Out-Null
$resources = Join-Path $root 'tools\pdfbox-src\pdfbox\src\test\resources'
$dest = Join-Path $root 'tests\reference\pdfbox-text'
New-Item -ItemType Directory -Force $dest | Out-Null

$baseUrl = 'https://archive.apache.org/dist/pdfbox/3.0.8/pdfbox-3.0.8-src.zip#pdfbox/src/test/resources/'
$sources = @(
    @{ folder = 'input'; filter = { param($n) $true } },
    @{ folder = 'org\apache\pdfbox\text'; filter = { param($n) $n -like 'BidiSample.pdf*' } }
)

$rows = @()
foreach ($source in $sources) {
    $folder = Join-Path $resources $source.folder
    foreach ($file in Get-ChildItem $folder -File -Filter '*.txt') {
        if (-not (& $source.filter $file.Name)) { continue }
        # Only the expected texts of a PDF in the same folder
        $pdfName = $file.Name -replace '(-sorted|-tabula)?\.txt$', ''
        if (-not (Test-Path (Join-Path $folder $pdfName))) { continue }
        Copy-Item $file.FullName (Join-Path $dest $file.Name) -Force
        $rows += ('{0};{1};Apache-2.0 (PDFBox test resource)' -f $file.Name, ($baseUrl + $source.folder.Replace('\', '/') + '/' + $file.Name))
    }
}
$lines = @('file;source_url;license') + ($rows | Sort-Object { $_ } -CaseSensitive)
[IO.File]::WriteAllText((Join-Path $dest 'manifest.csv'), (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))

$header = @(
    '# Known differences between Pdf4D and the expected texts of the PDFBox 3.0.8 test suite.',
    "# The expected texts in this folder are copies of the .txt files in pdfbox/src/test/resources (input and org/apache/pdfbox/text)",
    '# of apache-pdfbox 3.0.8 (https://archive.apache.org/dist/pdfbox/3.0.8/pdfbox-3.0.8-src.zip), licensed under Apache-2.0.',
    '# They are made by fetch-reference-text.ps1; see manifest.csv. A line is: <expected text file> # <reason>.'
)
$known = Join-Path $dest 'known-differences.txt'
$body = @()
if (Test-Path $known) { $body = @(Get-Content $known -Encoding UTF8 | Where-Object { $_ -notmatch '^#' }) }
[IO.File]::WriteAllText($known, ((($header + $body) -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
