# Runs the oracle (--color-batch) for DeviceCMYK and the ICC profiles in tests/icc and writes tests/reference/color/<name>.txt.
# Every reference file holds 200 fixed device colours per profile: a grid (with the corners) and values of a fixed generator.
# The format is described in docs/golden-format.md.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$out = Join-Path $script:RepoRoot 'tests\reference\color'
$icc = Join-Path $script:RepoRoot 'tests\icc'
New-Item -ItemType Directory -Force $out | Out-Null

# name, profile argument, number of components, intent to force (-1: the profile's own)
$profiles = @(
    @('DeviceCMYK', 'DeviceCMYK', 4, -1),
    @('sRGB', (Join-Path $icc 'sRGB.icc'), 3, -1),
    @('gray-small', (Join-Path $icc 'gray-small.icc'), 1, -1),
    @('gray-gamma', (Join-Path $icc 'gray-gamma.icc'), 1, -1),
    @('cmyk-printer', (Join-Path $icc 'cmyk-printer.icc'), 4, -1)
)

function Format-Value([double]$Value) {
    return $Value.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Inputs([int]$Components) {
    $points = New-Object System.Collections.Generic.List[string]
    $levels = switch ($Components) {
        1 { 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 }
        3 { 0, 0.25, 0.5, 0.75, 1 }
        default { 0, 0.5, 1 }
    }
    $index = New-Object int[] $Components
    while ($true) {
        $points.Add((($index | ForEach-Object { Format-Value $levels[$_] }) -join ' '))
        $position = $Components - 1
        while ($position -ge 0) {
            $index[$position]++
            if ($index[$position] -lt $levels.Count) { break }
            $index[$position] = 0
            $position--
        }
        if ($position -lt 0) { break }
    }
    # A fixed linear congruential generator fills up to 200 points
    [uint64]$state = 12345
    while ($points.Count -lt 200) {
        $values = for ($c = 0; $c -lt $Components; $c++) {
            $state = ($state * 1103515245 + 12345) % 2147483648
            Format-Value ([math]::Round($state / 2147483648.0, 4))
        }
        $points.Add($values -join ' ')
    }
    return $points
}

foreach ($p in $profiles) {
    $spec = [IO.Path]::GetTempFileName()
    $lines = @("profile: $($p[1])")
    if ($p[3] -ge 0) { $lines += "intent: $($p[3])" }
    foreach ($point in (Get-Inputs $p[2])) { $lines += "in: $point" }
    [IO.File]::WriteAllLines($spec, $lines, (New-Object Text.UTF8Encoding($false)))
    $target = Join-Path $out ($p[0] + '.txt')
    $tmp = [IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $java -ArgumentList @('-Xmx1g', '-cp', "`"$cp`"", 'Pdf4DOracle', '--color-batch', "`"$spec`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
    Remove-Item $spec
    if ($proc.ExitCode -ne 0 -or (Get-Item $tmp).Length -eq 0) { Remove-Item $tmp; throw "--color-batch failed for $($p[0])" }
    # The profile path is machine dependent: the file names the profile by its short name
    $content = (Get-Content $tmp -Encoding UTF8) | ForEach-Object { if ($_ -like 'profile:*') { 'profile: ' + $p[0] } else { $_ } }
    [IO.File]::WriteAllText($target, (($content -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Remove-Item $tmp
    Write-Host ('{0}: {1} colours' -f $p[0], (Select-String -Path $target -Pattern '^in:').Count)
}
