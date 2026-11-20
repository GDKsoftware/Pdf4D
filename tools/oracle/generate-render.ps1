# Runs the oracle (render) for the PDF files of tests/corpus and writes the reference renders of PDFBox 3.0.8
# (PDFRenderer.renderImageWithDPI, ImageType.RGB) to tests/reference/render/<dpi>/:
#   <name>.p<nnn>.png   page nnn (three digits) of the file, <name> is the relative path with '/' replaced by '__' (as in tests/golden)
#   <name>.render.txt   "page <n> <w> <h> ok" or "page <n> error <JavaExceptionClass>" per page, or only "load-error: <kind>"
# -Dpi 72 renders pages 1 to min(pages, 50) of every file. -Dpi 150 renders the pages listed in tests/reference/render/150/selection.txt
# (<corpus file>;<page> per line, # starts a comment) only. A file that takes more than 120 seconds gets "load-error: timeout".
# The format is described in docs/golden-format.md. A file whose manifest notes contain password=<x> is opened with that password.
param([ValidateSet(72, 150)][int]$Dpi = 72, [string]$Filter = '', [int]$Parallel = 4, [int]$TimeoutSeconds = 120)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
. (Join-Path $PSScriptRoot '..\corpus\manifest-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$corpus = Join-Path $script:RepoRoot 'tests\corpus'
$root = Join-Path $script:RepoRoot 'tests\reference\render'
$target = Join-Path $root "$Dpi"
New-Item -ItemType Directory -Force $target | Out-Null
$manifest = Read-Manifest

# One job per file: the page to render (0: all pages)
$jobs = @()
if ($Dpi -eq 150) {
    $selection = Get-Content (Join-Path $target 'selection.txt') | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') }
    foreach ($line in $selection) {
        $parts = $line.Split(';')
        $jobs += [pscustomobject]@{ Rel = $parts[0].Trim(); Page = [int]$parts[1].Trim() }
    }
} else {
    $files = Get-ChildItem $corpus -Recurse -File -Filter *.pdf | Sort-Object FullName
    foreach ($f in $files) { $jobs += [pscustomobject]@{ Rel = $f.FullName.Substring($corpus.Length + 1).Replace('\', '/'); Page = 0 } }
}
if ($Filter) { $jobs = @($jobs | Where-Object { $_.Rel -like "*$Filter*" }) }

# A full run replaces the folder; a filtered run replaces the files of the filtered names only
foreach ($job in $jobs) {
    $name = $job.Rel.Replace('/', '__')
    Get-ChildItem $target -Filter "$name.p*.png" -ErrorAction SilentlyContinue | Remove-Item
    Remove-Item (Join-Path $target "$name.render.txt") -ErrorAction SilentlyContinue
}
if (-not $Filter -and $Dpi -eq 72) {
    Get-ChildItem $target -File | Where-Object { $_.Name -like '*.png' -or $_.Name -like '*.render.txt' } | Remove-Item
}

$errBase = Join-Path ([IO.Path]::GetTempPath()) 'pdf4d-oracle-render-err'
New-Item -ItemType Directory -Force $errBase | Out-Null
$queue = New-Object System.Collections.Queue
foreach ($job in $jobs) { $queue.Enqueue($job) }
$running = @()
$timeouts = @()

function Start-One($job) {
    $name = $job.Rel.Replace('/', '__')
    $out = Join-Path $target "$name.render.txt"
    $pw = ''
    if ($manifest.Contains($job.Rel) -and $manifest[$job.Rel].notes -match 'password=(\S+)') { $pw = $Matches[1] }
    $pdf = Join-Path $corpus $job.Rel.Replace('/', '\')
    $a = @('-Xmx2g', '-Djava.awt.headless=true', "`"-Dpdf4d.render.name=$name`"", '-cp', "`"$cp`"", 'Pdf4DOracle', 'render', "`"$pdf`"", "$Dpi", "`"$target`"")
    # The password and the page are positional; <empty> stands for the empty password
    $a += $(if ($pw) { $pw } else { '<empty>' })
    $a += "$($job.Page)"
    $err = Join-Path $errBase ([Guid]::NewGuid().ToString('N') + '.txt')
    $p = Start-Process -FilePath $java -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    return [pscustomobject]@{ Proc = $p; Out = $out; Rel = $job.Rel; Name = $name; Start = Get-Date }
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
            Get-ChildItem $target -Filter "$($r.Name).p*.png" | Remove-Item
            [IO.File]::WriteAllText($r.Out, "load-error: timeout`n", (New-Object Text.UTF8Encoding($false)))
            $timeouts += $r.Rel
            Write-Warning "timeout: $($r.Rel)"
        } else { $still += $r }
    }
    $running = $still
}
Remove-Item $errBase -Recurse -Force -ErrorAction SilentlyContinue

$pngs = @(Get-ChildItem $target -Filter *.png)
$bytes = ($pngs | Measure-Object Length -Sum).Sum
$listings = @(Get-ChildItem $target -Filter *.render.txt)
$loadErrors = @($listings | Where-Object { (Get-Content $_.FullName -TotalCount 1) -like 'load-error:*' })
$pageErrors = @($listings | Where-Object { (Get-Content $_.FullName) -match ' error ' })
Write-Host ('{0} files, {1} PNG files, {2:N1} MB in total ({3:N1} MB of PNG)' -f $listings.Count, $pngs.Count, ((($pngs + $listings) | Measure-Object Length -Sum).Sum / 1MB), ($bytes / 1MB))
Write-Host ('{0} files with a load error, {1} files with a page error' -f $loadErrors.Count, $pageErrors.Count)
if ($timeouts) {
    Write-Host ("timeouts: " + ($timeouts -join ", "))
    Write-Error "$($timeouts.Count) files timed out, the references of those files are not usable: run again or raise -TimeoutSeconds"
    exit 1
}
