# Helpers for tests/corpus/manifest.csv (columns file;source_url;license;notes, UTF-8, LF, no quoting).
$script:ManifestPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tests\corpus\manifest.csv'

function Read-Manifest {
    $rows = [ordered]@{}
    if (Test-Path $script:ManifestPath) {
        $lines = [IO.File]::ReadAllLines($script:ManifestPath, [Text.Encoding]::UTF8)
        foreach ($l in ($lines | Select-Object -Skip 1)) {
            if ($l.Trim() -eq '') { continue }
            $p = $l.Split(';', 4)
            $rows[$p[0]] = [pscustomobject]@{ file = $p[0]; source_url = $p[1]; license = $p[2]; notes = $p[3] }
        }
    }
    return $rows
}

function Write-Manifest($rows) {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('file;source_url;license;notes')
    foreach ($k in ($rows.Keys | Sort-Object { $_ }  -CaseSensitive)) {
        $r = $rows[$k]
        $clean = { param($s) if ($null -eq $s) { '' } else { ($s -replace '[;\r\n]', ',') } }
        $out.Add(('{0};{1};{2};{3}' -f (& $clean $r.file), (& $clean $r.source_url), (& $clean $r.license), (& $clean $r.notes)))
    }
    New-Item -ItemType Directory -Force (Split-Path $script:ManifestPath) | Out-Null
    [IO.File]::WriteAllText($script:ManifestPath, (($out -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
}

# Replaces every row whose file starts with $Prefix by $NewRows (array of objects with file/source_url/license/notes).
function Update-ManifestPrefix([string]$Prefix, $NewRows) {
    $rows = Read-Manifest
    foreach ($k in @($rows.Keys)) { if ($k.StartsWith($Prefix)) { $rows.Remove($k) } }
    foreach ($r in $NewRows) { $rows[$r.file] = $r }
    Write-Manifest $rows
}

function Add-ManifestNote([string]$File, [string]$Note) {
    $rows = Read-Manifest
    if ($rows.Contains($File)) {
        $cur = $rows[$File].notes
        if ($cur -notlike "*$Note*") { $rows[$File].notes = (($cur, $Note) | Where-Object { $_ }) -join ' '  }
        Write-Manifest $rows
    }
}
