# Runs the oracle (--color-pdf-batch) for the colour spaces of tests/reference/color-spaces/colorspaces.pdf and writes
# tests/reference/color-spaces/colorspaces.txt: per colour space the RGB of fixed colours (in:) and of a row of 8-bit samples that
# goes through toRGBImage (img:). The format is described in docs/golden-format.md.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'oracle-lib.ps1')
$java = Get-OracleJava
$cp = Get-OracleClasspath
$colorFolder = Join-Path $script:RepoRoot 'tests\reference\color-spaces'
$pdf = Join-Path $colorFolder 'colorspaces.pdf'
$target = Join-Path $colorFolder 'colorspaces.txt'

function Format-Value([double]$Value) {
    return $Value.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Grid([double[][]]$Levels) {
    $points = @('')
    foreach ($componentLevels in $Levels) {
        $next = New-Object System.Collections.Generic.List[string]
        foreach ($point in $points) {
            foreach ($level in $componentLevels) { $next.Add((($point + ' ' + (Format-Value $level)).Trim())) }
        }
        $points = $next
    }
    return $points
}

$unit5 = [double[]](0, 0.25, 0.5, 0.75, 1)
$unit3 = [double[]](0, 0.5, 1)
$ten = [double[]](0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 0.25, 0.75, 1.5)
# No value over 1 for a tint: PDFBox does not clip the input of a type 2 function and the CMYK conversion of Java differs there
$tint = [double[]](0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 0.25, 0.75)
$labA = [double[]](-128, -50, 0, 50, 127)
$labC = [double[]](-100, -50, 0, 50, 100)
$bytes5 = [double[]](0, 64, 128, 192, 255)
$indexes = [double[]](0, 1, 2, 3, 4, -1, 1.4, 1.5, 0.5, 9, 255)
$indexBytes = [double[]](0, 1, 2, 3, 4, 7, 255)
$sampleBytes = [double[]](0, 51, 102, 153, 204, 255)

# name, components, levels of the colours, levels of the samples
$spaces = @(
    @('CalGrayDefault', 1, @(, $ten), @(, $sampleBytes)),
    @('CalGrayOne', 1, @(, $ten), @(, $sampleBytes)),
    @('CalGray65', 1, @(, $ten), @(, $sampleBytes)),
    @('CalRgbOne', 3, @($unit5, $unit5, $unit5), @($bytes5, $bytes5, $bytes5)),
    @('CalRgbPlain', 3, @($unit5, $unit5, $unit5), @($bytes5, $bytes5, $bytes5)),
    @('CalRgb65', 3, @($unit5, $unit5, $unit5), @($bytes5, $bytes5, $bytes5)),
    @('LabD50', 3, @([double[]](0, 25, 50, 75, 100), $labA, $labA), @($bytes5, $bytes5, $bytes5)),
    @('LabD65', 3, @([double[]](0, 25, 50, 75, 100), $labC, $labC), @($bytes5, $bytes5, $bytes5)),
    @('LabOne', 3, @([double[]](0, 25, 50, 75, 100), $labC, $labC), @($bytes5, $bytes5, $bytes5)),
    @('Idx', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxShort', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxShortOne', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxGray', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxCmyk', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxLab', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxStream', 1, @(, $indexes), @(, $indexBytes)),
    @('IdxCal', 1, @(, $indexes), @(, $indexBytes)),
    @('Sep', 1, @(, $tint), @(, $sampleBytes)),
    @('SepType4', 1, @(, $tint), @(, $sampleBytes)),
    @('SepAll', 1, @(, $tint), @(, $sampleBytes)),
    @('SepNone', 1, @(, $tint), @(, $sampleBytes)),
    @('SepGray', 1, @(, $tint), @(, $sampleBytes)),
    @('SepLab', 1, @(, $tint), @(, $sampleBytes)),
    @('DevN', 2, @($unit5, $unit5), @($bytes5, $bytes5)),
    @('DevNAttr', 3, @($unit3, $unit3, $unit3), @($bytes5, $bytes5, $bytes5)),
    @('DevNSpotWins', 3, @($unit3, $unit3, $unit3), @($bytes5, $bytes5, $bytes5)),
    @('DevNMissingSpot', 2, @($unit5, $unit5), @($bytes5, $bytes5)),
    @('DevNProcessRgb', 3, @($unit3, $unit3, $unit3), @($bytes5, $bytes5, $bytes5))
)

$lines = @("pdf: $pdf")
foreach ($space in $spaces) {
    $lines += "space: $($space[0])"
    foreach ($point in (Get-Grid $space[2])) { $lines += "in: $point" }
    $samples = (Get-Grid $space[3]) -join ' '
    $lines += "img: $($space[1]) $samples"
}
$spec = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllLines($spec, $lines, (New-Object Text.UTF8Encoding($false)))
$tmp = [IO.Path]::GetTempFileName()
$proc = Start-Process -FilePath $java -ArgumentList @('-Xmx1g', '-cp', "`"$cp`"", 'Pdf4DOracle', '--color-pdf-batch', "`"$spec`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
Remove-Item $spec
if ($proc.ExitCode -ne 0 -or (Get-Item $tmp).Length -eq 0) { Remove-Item $tmp; throw '--color-pdf-batch failed' }
# The path of the PDF file is machine dependent: the file names the PDF by its short name
$content = (Get-Content $tmp -Encoding UTF8) | ForEach-Object { if ($_ -like 'pdf:*') { 'pdf: colorspaces.pdf' } else { $_ } }
[IO.File]::WriteAllText($target, (($content -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Remove-Item $tmp
Write-Host ('{0} colour spaces, {1} colours' -f $spaces.Count, (Select-String -Path $target -Pattern '^in:').Count)
