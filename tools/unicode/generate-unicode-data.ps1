# Generates src/Encryption/Pdf4D.Encryption.UnicodeData.pas from the Unicode character database.
# It downloads UnicodeData.txt and CompositionExclusions.txt of the pinned Unicode version and writes the tables that
# Pdf4D.Encryption.UnicodeNormalization needs for NFKC (the SASLprep of the passwords of encryption revision 6):
#   - the full compatibility decomposition (NFKD) of each code point that has one,
#   - the canonical combining classes,
#   - the primary composites: canonical decompositions of two code points, without the composition exclusions of UAX 15
#     (the entries of CompositionExclusions.txt, the singleton decompositions and the decompositions that start with a
#     non-starter).
# Hangul syllables are left out, the normalizer handles them by algorithm.
param(
    [string]$UnicodeVersion = '16.0.0',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\src\Encryption\Pdf4D.Encryption.UnicodeData.pas')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseUrl = "https://www.unicode.org/Public/$UnicodeVersion/ucd"
$work = Join-Path ([IO.Path]::GetTempPath()) "pdf4d-unicode-$UnicodeVersion"
New-Item -ItemType Directory -Force $work | Out-Null
foreach ($name in 'UnicodeData.txt', 'CompositionExclusions.txt') {
    $target = Join-Path $work $name
    if (-not (Test-Path $target)) {
        Invoke-WebRequest -Uri "$baseUrl/$name" -OutFile $target -UseBasicParsing
    }
}

$hangulFirst = 0xAC00
$hangulLast = 0xD7A3

# code point -> @{ Class; Tag (true for a compatibility decomposition); Parts }
$characters = @{}
foreach ($line in [IO.File]::ReadLines((Join-Path $work 'UnicodeData.txt'))) {
    $fields = $line.Split(';')
    $codePoint = [Convert]::ToInt32($fields[0], 16)
    $decomposition = $fields[5]
    $isCompatibility = $decomposition.StartsWith('<')
    if ($isCompatibility) {
        $decomposition = $decomposition.Substring($decomposition.IndexOf('>') + 1).Trim()
    }
    $parts = @()
    if ($decomposition -ne '') {
        $parts = @($decomposition.Split(' ') | ForEach-Object { [Convert]::ToInt32($_, 16) })
    }
    $characters[$codePoint] = @{ Class = [int]$fields[3]; Compatibility = $isCompatibility; Parts = $parts }
}

$exclusions = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($line in [IO.File]::ReadLines((Join-Path $work 'CompositionExclusions.txt'))) {
    $text = $line.Split('#')[0].Trim()
    if ($text -ne '') {
        [void]$exclusions.Add([Convert]::ToInt32($text, 16))
    }
}

function Get-FullDecomposition([int]$codePoint) {
    $entry = $characters[$codePoint]
    if ($null -eq $entry -or $entry.Parts.Count -eq 0) {
        return , @($codePoint)
    }
    $result = New-Object 'System.Collections.Generic.List[int]'
    foreach ($part in $entry.Parts) {
        $result.AddRange([int[]](Get-FullDecomposition $part))
    }
    return , $result.ToArray()
}

$decompositions = New-Object 'System.Collections.Generic.List[string]'
$compositions = New-Object 'System.Collections.Generic.List[string]'
foreach ($codePoint in ($characters.Keys | Sort-Object)) {
    $isHangul = ($codePoint -ge $hangulFirst -and $codePoint -le $hangulLast)
    $entry = $characters[$codePoint]
    if ($isHangul -or $entry.Parts.Count -eq 0) {
        continue
    }

    $full = Get-FullDecomposition $codePoint
    $decompositions.Add(('{0:X}={1}' -f $codePoint, (($full | ForEach-Object { '{0:X}' -f $_ }) -join ' ')))

    $isPrimaryComposite = ((-not $entry.Compatibility) -and $entry.Parts.Count -eq 2 -and
        (-not $exclusions.Contains($codePoint)) -and $characters[$entry.Parts[0]].Class -eq 0)
    if ($isPrimaryComposite) {
        $compositions.Add(('{0:X} {1:X}={2:X}' -f $entry.Parts[0], $entry.Parts[1], $codePoint))
    }
}

# Canonical combining classes, consecutive code points with the same class as one range
$classes = New-Object 'System.Collections.Generic.List[string]'
$rangeFirst = -1; $rangeLast = -1; $rangeClass = 0
foreach ($codePoint in ($characters.Keys | Sort-Object)) {
    $class = $characters[$codePoint].Class
    if ($class -eq 0) { continue }
    if ($rangeFirst -ge 0 -and $codePoint -eq $rangeLast + 1 -and $class -eq $rangeClass) {
        $rangeLast = $codePoint
        continue
    }
    if ($rangeFirst -ge 0) {
        if ($rangeFirst -eq $rangeLast) { $classes.Add(('{0:X}={1}' -f $rangeFirst, $rangeClass)) }
        else { $classes.Add(('{0:X}-{1:X}={2}' -f $rangeFirst, $rangeLast, $rangeClass)) }
    }
    $rangeFirst = $codePoint; $rangeLast = $codePoint; $rangeClass = $class
}
if ($rangeFirst -eq $rangeLast) { $classes.Add(('{0:X}={1}' -f $rangeFirst, $rangeClass)) }
else { $classes.Add(('{0:X}-{1:X}={2}' -f $rangeFirst, $rangeLast, $rangeClass)) }

function Format-Constant([string]$name, $items, [string]$comment) {
    $text = (($items -join ';') + ';')
    $lines = for ($index = 0; $index -lt $text.Length; $index += 100) {
        "    '" + $text.Substring($index, [Math]::Min(100, $text.Length - $index)) + "'"
    }
    return "  // $comment`n  $name =`n" + ($lines -join " +`n") + ";`n`n"
}

$unit = "// Licensed under the Apache License, Version 2.0; see the LICENSE file.`n"
$unit += "// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.`n"
$unit += "// Contains data of the Unicode Character Database, Copyright (c) 1991-2024 Unicode, Inc., under the Unicode License v3 (see NOTICE).`n"
$unit += "// Data of the Unicode normalization forms, generated from the Unicode $UnicodeVersion character database (UnicodeData.txt and`n"
$unit += "// CompositionExclusions.txt) by tools/unicode/generate-unicode-data.ps1. Do not edit by hand.`n"
$unit += "// Composition exclusions: the entries of CompositionExclusions.txt, the singleton decompositions and the decompositions that`n"
$unit += "// start with a non-starter (UAX 15, full composition exclusion).`n"
$unit += "// Not ported from PDFBox: Java has this data in the JDK, the Delphi RTL has no normalization.`n"
$unit += "unit Pdf4D.Encryption.UnicodeData;`n`ninterface`n`nconst`n"
$unit += Format-Constant 'CompatibilityDecompositions' $decompositions 'Code point = full compatibility decomposition (NFKD) of that code point, in hexadecimal, without Hangul'
$unit += Format-Constant 'CombiningClasses' $classes 'Code point or range = canonical combining class'
$unit += Format-Constant 'CanonicalCompositions' $compositions 'First and second code point = the primary composite (NFC)'
$unit += "implementation`n`nend.`n"

[IO.File]::WriteAllText($OutputPath, $unit, (New-Object Text.UTF8Encoding($false)))
Write-Host "Unicode ${UnicodeVersion}: $($decompositions.Count) decompositions, $($classes.Count) combining class ranges, $($compositions.Count) compositions -> $OutputPath"
