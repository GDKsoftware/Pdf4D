# Builds tests/corpus/pdfbox (PDF test resources of PDFBox 3.0.8) and tests/corpus/pdfbox-jira
# (the JIRA attachments that the PDFBox build downloads), and writes their rows in tests/corpus/manifest.csv.
# Also makes sure the PDFBox source is available in tools/pdfbox-src/ (ignored by git).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'manifest-lib.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
& (Join-Path $root 'tools\fetch-pdfbox-src.ps1') | Out-Null
$src = Join-Path $root 'tools\pdfbox-src'
$license = 'Apache-2.0 (PDFBox test resource)'
$outOfScope = 'jbig2|jpx|jpeg2000|jpeg-2000|sign|render|pdfa|pdf-a|writ|flatten|print'
$broken = 'corrupt|broken|malformed|truncated|invalid|garbage|damaged'

function Get-Notes([string]$name) {
    $n = @()
    if ($name -match $outOfScope) { $n += 'out-of-scope-feature' }
    if ($name -match $broken) { $n += 'possibly-broken-on-purpose' }
    if ($name -match 'PasswordSample') { $n += 'password=user' }
    if ($name -match 'PDFBOX-5639') { $n += 'password=JUL2023rfi' }
    if ($name -match 'PDFBOX-4517-cryptfilter') { $n += 'password=userpassword1234' }
    if ($name -match 'PDFBOX-6041-example') { $n += 'broken-on-purpose (Missing root object specification in trailer)' }
    if ($name -match '(AES128|AES256)ExposedMeta|AESkeylength(128|256)') { $n += 'public-key-encryption (needs keystore, expected load-error unsupported)' }
    return ($n -join ' ')
}

$rows = @()
$seen = @{}
# 1. PDFs in the test resources of pdfbox and fontbox
$destRoot = Join-Path $root 'tests\corpus\pdfbox'
foreach ($mod in @('pdfbox', 'fontbox')) {
    $res = Join-Path $src "$mod\src\test\resources"
    if (-not (Test-Path $res)) { continue }
    foreach ($f in Get-ChildItem $res -Recurse -File -Filter *.pdf) {
        $rel = $f.FullName.Substring($res.Length + 1).Replace('\', '/')
        if ($mod -eq 'fontbox') { $rel = "fontbox/$rel" }
        $dest = Join-Path $destRoot $rel
        if ($seen.ContainsKey($rel)) { Write-Warning "name collision, skipped: $rel"; continue }
        $seen[$rel] = 1
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item $f.FullName $dest -Force
        $gh = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
        $rows += [pscustomobject]@{ file = "pdfbox/$rel"; source_url = "https://github.com/apache/pdfbox/blob/3.0.8/$gh"; license = $license; notes = (Get-Notes $rel) }
    }
}
Write-Host ("Copied {0} test resource PDFs" -f $rows.Count)

# 2. JIRA attachments from pdfbox/pom.xml
$jiraDir = Join-Path $root 'tests\corpus\pdfbox-jira'
New-Item -ItemType Directory -Force $jiraDir | Out-Null
$pom = Get-Content (Join-Path $src 'pdfbox\pom.xml') -Raw
if ($failed.Count) { $failed | Set-Content (Join-Path $root "toolsrpusailed-downloads.txt") -Encoding UTF8 }
$jiraRows = @()
foreach ($m in [regex]::Matches($pom, '(?s)<url>([^<]+)</url>\s*<outputDirectory>[^<]*</outputDirectory>\s*<outputFileName>([^<]+)</outputFileName>(?:\s*<sha512>([0-9a-fA-F]+)</sha512>)?')) {
    $url = $m.Groups[1].Value.Trim(); $name = $m.Groups[2].Value.Trim(); $sha = $m.Groups[3].Value.Trim().ToLower()
    if ($name -notmatch '\.pdf$') { continue }
    $dest = Join-Path $jiraDir $name
    try {
        if (-not (Test-Path $dest)) { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 120 }
        if ($sha -and ((Get-FileHash -Algorithm SHA512 $dest).Hash.ToLower() -ne $sha)) {
            Remove-Item $dest
            throw 'SHA-512 mismatch'
        }
        $jiraRows += [pscustomobject]@{ file = "pdfbox-jira/$name"; source_url = $url; license = $license; notes = (Get-Notes $name) }
    } catch {
        Write-Warning "JIRA download failed, skipped: $name ($url): $($_.Exception.Message)"
        $failed += "$name $url"
        if (Test-Path $dest) { Remove-Item $dest -ErrorAction SilentlyContinue }
    }
}
Write-Host ("Downloaded {0} JIRA PDFs, {1} failed" -f $jiraRows.Count, $failed.Count)
if ($failed.Count) { $failed | Set-Content (Join-Path $PSScriptRoot "failed-downloads.txt") -Encoding UTF8 }

Update-ManifestPrefix 'pdfbox/' $rows
Update-ManifestPrefix 'pdfbox-jira/' $jiraRows
