# Runs the oracle (PDFBox PrintImageLocations, mode image-locations) for every PDF in tests/corpus, the generated files of
# tests/corpus/generated/extract included, and writes tests/golden/<path with '/' replaced by '__'>.images.txt. The format is in
# docs/golden-format.md ("Image location goldens").
# A file whose manifest notes contain password=<x> is opened with that password. Each file runs in its own JVM with a timeout; a timeout
# is recorded as "load-error: timeout".
param([int]$TimeoutSeconds = 60, [int]$Parallel = 4, [string]$Filter = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
. (Join-Path $PSScriptRoot '..\corpus\manifest-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$corpus = Join-Path $script:RepoRoot 'tests\corpus'
$golden = Join-Path $script:RepoRoot 'tests\golden'
New-Item -ItemType Directory -Force $golden | Out-Null
if (-not $Filter) { Get-ChildItem $golden -Filter '*.images.txt' | Remove-Item }
$manifest = Read-Manifest
$errBase = Join-Path ([IO.Path]::GetTempPath()) 'pdf4d-oracle-err'
New-Item -ItemType Directory -Force $errBase | Out-Null

$files = Get-ChildItem $corpus -Recurse -File -Filter *.pdf | Sort-Object FullName
if ($Filter) { $files = $files | Where-Object { $_.FullName.Replace([char]92, [char]47) -like "*$Filter*" } }
$queue = New-Object System.Collections.Queue
foreach ($f in $files) { $queue.Enqueue($f) }
$running = @()
$timeouts = @()

function Start-One($f) {
    $rel = $f.FullName.Substring($corpus.Length + 1).Replace('\', '/')
    $out = Join-Path $golden (($rel.Replace('/', '__')) + '.images.txt')
    $pw = ''
    if ($manifest.Contains($rel) -and $manifest[$rel].notes -match 'password=(\S+)') { $pw = $Matches[1] }
    $a = @('-Xmx2g', '-cp', "`"$cp`"", 'Pdf4DOracle', 'image-locations', "`"$($f.FullName)`"")
    if ($pw) { $a += $pw }
    $err = Join-Path $errBase ([Guid]::NewGuid().ToString('N') + '.txt')
    $p = Start-Process -FilePath $java -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    return [pscustomobject]@{ Proc = $p; Out = $out; Rel = $rel; Start = Get-Date }
}

while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $Parallel) { $running += Start-One ($queue.Dequeue()) }
    Start-Sleep -Milliseconds 100
    $still = @()
    foreach ($r in $running) {
        if ($r.Proc.HasExited) { continue }
        if (((Get-Date) - $r.Start).TotalSeconds -gt $TimeoutSeconds) {
            try { $r.Proc.Kill() } catch {}
            $r.Proc.WaitForExit()
            [IO.File]::WriteAllText($r.Out, "load-error: timeout`n", (New-Object Text.UTF8Encoding($false)))
            $timeouts += $r.Rel
            Write-Warning "timeout: $($r.Rel)"
        } else { $still += $r }
    }
    $running = $still
}
Remove-Item $errBase -Recurse -Force -ErrorAction SilentlyContinue

$images = Get-ChildItem $golden -Filter '*.images.txt'
Write-Host ('{0} image location goldens' -f $images.Count)
Write-Host ('{0} of them are empty: the file draws no image' -f @($images | Where-Object { $_.Length -eq 0 }).Count)
if ($timeouts) { Write-Host ('timeouts: ' + ($timeouts -join ', ')) }
