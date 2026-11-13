# Runs the oracle (--font-widths) for every test font in tests/fonts and writes tests/fonts/<font>.widths.txt.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$fonts = Join-Path $script:RepoRoot 'tests\fonts'
foreach ($f in Get-ChildItem $fonts -File | Where-Object { $_.Extension -in '.ttf', '.otf', '.pfb' } | Sort-Object Name) {
    $out = Join-Path $fonts ($f.Name + '.widths.txt')
    $tmp = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $java -ArgumentList @('-Xmx1g', '-cp', "`"$cp`"", 'Pdf4DOracle', '--font-widths', "`"$($f.FullName)`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
    if ($p.ExitCode -ne 0 -or (Get-Item $tmp).Length -eq 0) { Remove-Item $tmp; throw "font widths failed for $($f.Name)" }
    Move-Item $tmp $out -Force
    Write-Host ('{0}: {1} glyphs' -f $f.Name, (Get-Content $out).Count)
}
