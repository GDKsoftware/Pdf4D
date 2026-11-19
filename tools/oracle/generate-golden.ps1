# Runs the oracle for every PDF in tests/corpus and writes tests/golden/<path with '/' replaced by '__'>.dump.txt
# (-Mode Dump), .text.txt (-Mode Text) and .positions.txt (-Mode Positions); the default -Mode All writes all three.
# A file whose manifest notes contain password=<x> is opened with that password.
# Each file runs in its own JVM with a timeout; a timeout is recorded as "load-error: parse" in a dump and as "load-error: timeout" in a text or positions golden.
# Files that end in a load-error get an "oracle:load-error-<kind>" note in the manifest.
param([int]$TimeoutSeconds = 60, [int]$Parallel = 4, [string]$Filter = '', [ValidateSet('Dump','Text','Positions','All')][string]$Mode = 'All')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
. (Join-Path $PSScriptRoot '..\corpus\manifest-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$corpus = Join-Path $script:RepoRoot 'tests\corpus'
$golden = Join-Path $script:RepoRoot 'tests\golden'
New-Item -ItemType Directory -Force $golden | Out-Null
$modes = @(); if ($Mode -in 'Dump','All') { $modes += 'dump' }; if ($Mode -in 'Text','All') { $modes += 'text' }; if ($Mode -in 'Positions','All') { $modes += 'positions' }
if (-not $Filter) { foreach ($m in $modes) { Get-ChildItem $golden -Filter "*.$m.txt" | Remove-Item } }
$manifest = Read-Manifest
$errBase = Join-Path ([IO.Path]::GetTempPath()) 'pdf4d-oracle-err'
New-Item -ItemType Directory -Force $errBase | Out-Null

$files = Get-ChildItem $corpus -Recurse -File -Filter *.pdf | Sort-Object FullName
if ($Filter) { $files = $files | Where-Object { $_.FullName -like "*$Filter*" } }
$queue = New-Object System.Collections.Queue
foreach ($f in $files) { foreach ($m in $modes) { $queue.Enqueue([pscustomobject]@{ File = $f; Mode = $m }) } }
$fileCount = $files.Count
$running = @()
$timeouts = @()
$textTimeouts = @()
$positionTimeouts = @()

function Start-One($item) {
    $f = $item.File
    $mode = $item.Mode
    $rel = $f.FullName.Substring($corpus.Length + 1).Replace('\', '/')
    $out = Join-Path $golden (($rel.Replace('/', '__')) + ".$mode.txt")
    $pw = ''
    if ($manifest.Contains($rel) -and $manifest[$rel].notes -match 'password=(\S+)') { $pw = $Matches[1] }
    $a = @('-Xmx2g', '-cp', "`"$cp`"", 'Pdf4DOracle', $mode, "`"$($f.FullName)`"")
    if ($pw) { $a += $pw }
    $err = Join-Path $errBase ([Guid]::NewGuid().ToString('N') + '.txt')
    $p = Start-Process -FilePath $java -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    return [pscustomobject]@{ Proc = $p; Out = $out; Rel = $rel; Mode = $mode; Start = Get-Date }
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
            $marker = if ($r.Mode -eq 'dump') { 'load-error: parse' } else { 'load-error: timeout' }
            [IO.File]::WriteAllText($r.Out, "$marker`n", (New-Object Text.UTF8Encoding($false)))
            if ($r.Mode -eq 'dump') { $timeouts += $r.Rel } elseif ($r.Mode -eq 'text') { $textTimeouts += $r.Rel } else { $positionTimeouts += $r.Rel }
            Write-Warning "timeout ($($r.Mode)): $($r.Rel)"
        } else { $still += $r }
    }
    $running = $still
}
Remove-Item $errBase -Recurse -Force -ErrorAction SilentlyContinue

# summary and manifest notes
if ($modes -contains 'text') {
    $texts = Get-ChildItem $golden -Filter *.text.txt
    Write-Host ('{0} text goldens' -f $texts.Count)
    foreach ($t in $texts) { if ($t.Length -eq 0) { Write-Warning "empty text golden: $($t.Name)" } }
    if ($textTimeouts) { Write-Host ('text timeouts: ' + ($textTimeouts -join ', ')) }
}
if ($modes -contains 'positions') {
    $positions = Get-ChildItem $golden -Filter *.positions.txt
    Write-Host ('{0} position goldens' -f $positions.Count)
    Write-Host ('{0} of them are empty: the file has no page with text' -f @($positions | Where-Object { $_.Length -eq 0 }).Count)
    if ($positionTimeouts) { Write-Host ('position timeouts: ' + ($positionTimeouts -join ', ')) }
}
if ($modes -notcontains 'dump') { return }
$dumps = Get-ChildItem $golden -Filter *.dump.txt
Write-Host ("{0} files, {1} dumps" -f $fileCount, $dumps.Count)
$errs = @{}
$rows = Read-Manifest
foreach ($d in $dumps) {
    if ($d.Length -eq 0) { Write-Warning "empty dump: $($d.Name)"; continue }
    $first = Get-Content $d.FullName -TotalCount 1
    if ($first -like 'load-error:*') {
        $errs[$first] = 1 + [int]$errs[$first]
        $rel = $d.Name.Substring(0, $d.Name.Length - '.dump.txt'.Length).Replace('__', '/')
        Write-Host ("  {0}  {1}" -f $first, $rel)
        if ($rows.Contains($rel)) {
            $note = 'oracle:' + $first.Replace(': ', '-')
            if ($timeouts -contains $rel) { $note += ' (timeout)' }
            if ($rows[$rel].notes -notlike "*$note*") { $rows[$rel].notes = (($rows[$rel].notes, $note) | Where-Object { $_ }) -join ' ' }
        }
    }
}
Write-Manifest $rows
$errs.GetEnumerator() | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Key, $_.Value) }
if ($timeouts) { Write-Host ("timeouts: " + ($timeouts -join ', ')) }
