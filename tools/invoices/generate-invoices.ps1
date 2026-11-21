# Makes the fictional invoice PDFs of tests/corpus/generated/invoices with every producer that this machine has:
#   edge-print.pdf       Microsoft Edge headless (--print-to-pdf) of tools/invoices/invoice.html
#   skia-draw.pdf        tools/invoices/Pdf4D.InvoiceGen.dpr (Delphi, TSkDocument.MakePDF), set in LiberationSans from tests/fonts
#   word-export.pdf      Microsoft Word through COM, Document.ExportAsFixedFormat of invoice.html
#   word-print.pdf       Microsoft Word through COM, printed to "Microsoft Print to PDF" with PrintToFile
#   libreoffice.pdf      soffice --headless --convert-to pdf of invoice.html
# A producer that is not installed is skipped with a warning. The invoices contain invented data only. The script checks every PDF for
# the user name and the machine name (the producers may put them in /Info, in the XMP packet or in a link) and fails when it finds one.
# It writes the manifest rows of the PDFs it made; run tools/oracle/generate-golden.ps1 and generate-render.ps1 afterwards.
param([string]$OutputFolder = '', [string]$RsVars = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\corpus\manifest-lib.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutputFolder) { $OutputFolder = Join-Path $repoRoot 'tests\corpus\generated\invoices' }
New-Item -ItemType Directory -Force $OutputFolder | Out-Null
$html = Join-Path $PSScriptRoot 'invoice.html'
$made = [ordered]@{}
# The document is CC0; the fonts that Edge and Word embed (subsets of Arial) are not
$arialNote = '; CC0 covers the document, the embedded Arial subsets stay under the licence of the font'

function Add-Made([string]$Name, [string]$Producer, [string]$Notes) {
    $made[$Name] = [pscustomobject]@{ Producer = $Producer; Notes = $Notes }
}

function Wait-ForFile([string]$Path) {
    for ($i = 0; $i -lt 100; $i++) {
        if ((Test-Path $Path) -and ((Get-Item $Path).Length -gt 0)) {
            try { [IO.File]::OpenRead($Path).Dispose(); return } catch { }
        }
        Start-Sleep -Milliseconds 200
    }
    throw "The producer did not write $Path"
}

# Microsoft Print to PDF writes the Windows account name into /Author. Replaces the text of /Author by "Example Author" (padded or cut to
# the same length, so that no offset of the file changes), in the form of the original: PDFDocEncoding or UTF-16BE with a byte order mark.
function Set-NeutralAuthor([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $latin = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $match = [regex]::Match($latin, '/Author\s*\(')
    if (-not $match.Success) { return }
    $start = $match.Index + $match.Length
    $end = $start
    while ($end -lt $bytes.Length -and $bytes[$end] -ne 0x29) {
        if ($bytes[$end] -eq 0x5C) { throw "The /Author of $Path has an escape sequence: neutralise it by hand" }
        $end++
    }
    $replacement = 'Example Author'
    if ($end - $start -ge 2 -and $bytes[$start] -eq 0xFE -and $bytes[$start + 1] -eq 0xFF) {
        $characters = ($end - $start - 2) / 2
        $text = $replacement.PadRight($characters).Substring(0, $characters)
        $new = [Text.Encoding]::BigEndianUnicode.GetBytes($text)
        [Array]::Copy($new, 0, $bytes, $start + 2, $new.Length)
    } else {
        $text = $replacement.PadRight($end - $start).Substring(0, $end - $start)
        $new = [Text.Encoding]::GetEncoding(28591).GetBytes($text)
        [Array]::Copy($new, 0, $bytes, $start, $new.Length)
    }
    [IO.File]::WriteAllBytes($Path, $bytes)
}

# 1. Edge headless, with a profile of its own so that nothing of the user's profile reaches the file
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($edge) {
    $target = Join-Path $OutputFolder 'edge-print.pdf'
    Remove-Item $target -ErrorAction SilentlyContinue
    $profile = Join-Path ([IO.Path]::GetTempPath()) ('pdf4d-edge-' + [Guid]::NewGuid().ToString('N'))
    $url = ([Uri]$html).AbsoluteUri
    $p = Start-Process -FilePath $edge -ArgumentList @('--headless=new', '--disable-gpu', '--no-first-run', "--user-data-dir=`"$profile`"", '--no-pdf-header-footer', '--print-to-pdf-no-header', "--print-to-pdf=`"$target`"", "`"$url`"") -PassThru -Wait
    Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue
    Wait-ForFile $target
    $version = (Get-Item $edge).VersionInfo.ProductVersion
    Add-Made 'edge-print.pdf' "Microsoft Edge $version (--print-to-pdf)" ('invoice.html printed by headless Edge, A4' + $arialNote)
} else { Write-Warning 'Microsoft Edge not found: edge-print.pdf skipped' }

# 2. Delphi program with Skia. rsvars.bat comes from -RsVars, from the BDS environment variable (set in a RAD Studio command prompt) or
# from the newest RAD Studio under Program Files (x86)
$rsvars = $RsVars
if (-not $rsvars -and $env:BDS) { $rsvars = Join-Path $env:BDS 'bin\rsvars.bat' }
if (-not $rsvars) {
    $rsvars = Get-ChildItem "${env:ProgramFiles(x86)}\Embarcadero\Studio\*\bin\rsvars.bat" -ErrorAction SilentlyContinue |
        Sort-Object { [version](Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $_.FullName))) } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if ($rsvars -and (Test-Path $rsvars)) {
    $project = Join-Path $PSScriptRoot 'Pdf4D.InvoiceGen.dproj'
    & cmd /c "call `"$rsvars`" && msbuild `"$project`" /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Build of Pdf4D.InvoiceGen failed' }
    $binary = Join-Path $PSScriptRoot 'Win64\Release'
    $bds = Split-Path -Parent (Split-Path -Parent $rsvars)
    Copy-Item (Join-Path $bds 'Redist\win64\sk4d.dll') $binary -Force
    $target = Join-Path $OutputFolder 'skia-draw.pdf'
    & (Join-Path $binary 'Pdf4D.InvoiceGen.exe') $target (Join-Path $repoRoot 'tests\fonts\LiberationSans-Regular.ttf')
    if ($LASTEXITCODE -ne 0) { throw 'Pdf4D.InvoiceGen failed' }
    $studioName = switch (Split-Path -Leaf $bds) { '37.0' { 'RAD Studio 13' } '23.0' { 'RAD Studio 12' } default { "RAD Studio BDS $(Split-Path -Leaf $bds)" } }
    Add-Made 'skia-draw.pdf' "Skia/PDF through System.Skia TSkDocument.MakePDF ($studioName)" 'drawn by tools/invoices/Pdf4D.InvoiceGen.dpr, LiberationSans-Regular, A4'
} else { Write-Warning 'RAD Studio not found: skia-draw.pdf skipped' }

# 3 and 4. Word through COM, in a process of its own (word-convert.ps1) that is ended after two minutes
$wordPath = @("$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE", "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\WINWORD.EXE") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($wordPath) {
    $exportTarget = Join-Path $OutputFolder 'word-export.pdf'
    $printTarget = Join-Path $OutputFolder 'word-print.pdf'
    Remove-Item $exportTarget, $printTarget -ErrorAction SilentlyContinue
    $hasPrinter = [bool](Get-Printer -Name 'Microsoft Print to PDF' -ErrorAction SilentlyContinue)
    if (-not $hasPrinter) { Write-Warning 'Microsoft Print to PDF not found: word-print.pdf skipped'; $printTarget = '' }
    $versionFile = Join-Path ([IO.Path]::GetTempPath()) ('pdf4d-word-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'word-convert.ps1')`"", '-Html', "`"$html`"", '-ExportPath', "`"$exportTarget`"")
    if ($printTarget) { $arguments += @('-PrintPath', "`"$printTarget`"") }
    $wordBefore = @(Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $versionFile
    if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { } }
    # Whatever happened, no Word is left behind that this script started; a Word that ran before the helper started is not touched
    Get-Process WINWORD -ErrorAction SilentlyContinue | Where-Object { $wordBefore -notcontains $_.Id } | Stop-Process -Force
    $wordVersion = (Get-Content $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    Remove-Item $versionFile -ErrorAction SilentlyContinue
    if (Test-Path $exportTarget) { Wait-ForFile $exportTarget; Add-Made 'word-export.pdf' "Microsoft Word $wordVersion (ExportAsFixedFormat)" ('invoice.html opened in Word and exported as PDF, A4' + $arialNote) } else { Write-Warning 'Word did not write word-export.pdf' }
    if ($printTarget) {
        if (Test-Path $printTarget) { Wait-ForFile $printTarget; Add-Made 'word-print.pdf' "Microsoft Print to PDF (Windows) from Microsoft Word $wordVersion" ('invoice.html opened in Word and printed to the Microsoft Print to PDF printer with PrintToFile' + $arialNote) } else { Write-Warning 'Word did not write word-print.pdf' }
    }
} else { Write-Warning 'Microsoft Word not found: word-export.pdf and word-print.pdf skipped' }

# 5. LibreOffice
$soffice = @("$env:ProgramFiles\LibreOffice\program\soffice.exe", "${env:ProgramFiles(x86)}\LibreOffice\program\soffice.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($soffice) {
    $profile = Join-Path ([IO.Path]::GetTempPath()) ('pdf4d-lo-' + [Guid]::NewGuid().ToString('N'))
    $profileUrl = ([Uri]$profile).AbsoluteUri
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('pdf4d-lo-out-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $temp | Out-Null
    Start-Process -FilePath $soffice -ArgumentList @('--headless', "-env:UserInstallation=$profileUrl", '--convert-to', 'pdf', '--outdir', "`"$temp`"", "`"$html`"") -Wait -NoNewWindow
    Move-Item (Join-Path $temp 'invoice.pdf') (Join-Path $OutputFolder 'libreoffice.pdf') -Force
    Remove-Item $temp, $profile -Recurse -Force -ErrorAction SilentlyContinue
    Add-Made 'libreoffice.pdf' 'LibreOffice (soffice --convert-to pdf)' 'invoice.html converted by headless LibreOffice'
} else { Write-Warning 'LibreOffice not found: libreoffice.pdf skipped' }

if (Test-Path (Join-Path $OutputFolder 'word-print.pdf')) { Set-NeutralAuthor (Join-Path $OutputFolder 'word-print.pdf') }

# Personal data check: the user name, the machine name and the profile path, in the raw bytes and in UTF-16BE (XMP and /Info strings)
$fullName = try { (Get-CimInstance Win32_UserAccount -Filter "Name='$env:USERNAME'").FullName } catch { '' }
$needles = @($fullName, $env:USERNAME, $env:COMPUTERNAME, $env:USERPROFILE, [Environment]::UserName) | Where-Object { $_ -and $_.Length -ge 3 } | Select-Object -Unique
$problems = @()
foreach ($name in $made.Keys) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $OutputFolder $name))
    $latin = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $utf16 = [Text.Encoding]::BigEndianUnicode.GetString($bytes)
    $utf16le = [Text.Encoding]::Unicode.GetString($bytes)
    foreach ($needle in $needles) {
        foreach ($haystack in $latin, $utf16, $utf16le) {
            if ($haystack.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $problems += "$name contains a personal value ($($needle.Length) characters)"; break }
        }
    }
}
if ($problems) {
    # The files with personal data must not stay in the corpus folder, where a later commit would pick them up
    foreach ($name in $made.Keys) { Remove-Item (Join-Path $OutputFolder $name) -ErrorAction SilentlyContinue }
    $problems | ForEach-Object { Write-Warning $_ }
    throw 'Personal data in a generated invoice: strip it from the producer settings' }

$rows = Read-Manifest
foreach ($k in @($rows.Keys)) { if ($k.StartsWith('generated/invoices/')) { $rows.Remove($k) } }
foreach ($name in $made.Keys) {
    $rel = "generated/invoices/$name"
    $rows[$rel] = [pscustomobject]@{ file = $rel; source_url = "generated by tools/invoices/generate-invoices.ps1: $($made[$name].Producer)"; license = 'CC0 (generated)'; notes = "fictional invoice INV-2031-0417, $($made[$name].Notes)" }
}
Write-Manifest $rows
Write-Host ("{0} invoices: {1}" -f $made.Count, ($made.Keys -join ', '))
