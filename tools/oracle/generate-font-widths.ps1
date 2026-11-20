# Runs the oracle (--font-widths) for every test font in tests/fonts and writes tests/fonts/<font>.widths.txt.
# With -Paths it runs --glyph-paths instead and writes tests/fonts/<font>.paths.txt for the Type 1, CFF and TrueType test fonts.
# With -PdfPaths it runs --pdf-glyph-paths over tests/fonts/glyph-paths/*.pdf (see make-glyph-path-pdfs.py) and writes <file>.pdf.paths.txt.
param([switch]$Paths, [switch]$PdfPaths)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$fonts = Join-Path $script:RepoRoot 'tests\fonts'
if ($PdfPaths) {
    $folder = Join-Path $fonts 'glyph-paths'
    foreach ($f in Get-ChildItem $folder -Filter *.pdf | Sort-Object Name) {
        # The codes of a composite font are CIDs, which the test fonts have up to 299
        $range = if ($f.Name.StartsWith('cid-')) { '0-299' } else { '0-255' }
        $out = Join-Path $folder ($f.Name + '.paths.txt')
        $tmp = [IO.Path]::GetTempFileName()
        $p = Start-Process -FilePath $java -ArgumentList @('-Xmx1g', '-cp', "`"$cp`"", 'Pdf4DOracle', '--pdf-glyph-paths', "`"$($f.FullName)`"", 'F1', $range) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
        if ($p.ExitCode -ne 0 -or (Get-Item $tmp).Length -eq 0) { Remove-Item $tmp; throw "--pdf-glyph-paths failed for $($f.Name)" }
        Move-Item $tmp $out -Force
        Write-Host ('{0}: {1} codes' -f $f.Name, (Get-Content $out).Count)
    }
    return
}
if ($Paths) {
    $mode = '--glyph-paths'
    $suffix = '.paths.txt'
    $extensions = '.otf', '.pfb', '.ttf'
}
else {
    $mode = '--font-widths'
    $suffix = '.widths.txt'
    $extensions = '.ttf', '.otf', '.pfb'
}
foreach ($f in Get-ChildItem $fonts -File | Where-Object { $_.Extension -in $extensions } | Sort-Object Name) {
    $out = Join-Path $fonts ($f.Name + $suffix)
    $tmp = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $java -ArgumentList @('-Xmx1g', '-cp', "`"$cp`"", 'Pdf4DOracle', $mode, "`"$($f.FullName)`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
    if ($p.ExitCode -ne 0 -or (Get-Item $tmp).Length -eq 0) { Remove-Item $tmp; throw "$mode failed for $($f.Name)" }
    Move-Item $tmp $out -Force
    Write-Host ('{0}: {1} glyphs' -f $f.Name, (Get-Content $out).Count)
}
