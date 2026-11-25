# Runs the oracle (--function) over every tools/oracle/function-specs/*.spec and writes tests/reference/functions/<name>.txt.
# The format is described in docs/golden-format.md.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$specs = Join-Path $PSScriptRoot 'function-specs'
$out = Join-Path $script:RepoRoot 'tests\reference\functions'
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($f in Get-ChildItem $specs -Filter *.spec | Sort-Object Name) {
    $target = Join-Path $out ($f.BaseName + '.txt')
    $tmp = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $java -ArgumentList @('-Xmx1g', '-cp', "`"$cp`"", 'Pdf4DOracle', '--function', "`"$($f.FullName)`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
    if ($p.ExitCode -ne 0 -or (Get-Item $tmp).Length -eq 0) { Remove-Item $tmp; throw "--function failed for $($f.Name)" }
    Move-Item $tmp $target -Force
    Write-Host ('{0}: {1} evaluations' -f $f.BaseName, (Select-String -Path $target -Pattern '^in:').Count)
}
