param(
    [ValidateSet('Win32', 'Win64', 'Linux64', 'All')]
    [string]$Platform = 'All',

    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Debug',

    # The Linux64 SDK folder; by default the one the IDE has registered as the default Linux64 SDK
    [string]$LinuxSdkPath,

    # Build and run one test project only; the packages are always built
    [ValidateSet('Pdf4D.Tests', 'Pdf4D.Skia.Tests', 'Pdf4D.Vcl.Tests', 'Pdf4D.FMX.Tests', 'All')]
    [string]$Suite = 'All'
)

$ErrorActionPreference = 'Stop'

$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$WslDistro = 'Ubuntu'
$BdsFolder = Split-Path -Parent (Split-Path -Parent $RsVars)

# The tests of the core and the renderer run without Skia; the Skia tests get the Skia library next to their program. The VCL and FMX tests
# run last, on Windows only, and need the Skia library as well.
$TestProjects = @(
    @{ Name = 'Pdf4D.Tests'; Folder = 'tests'; NeedsSkia = $false; WindowsOnly = $false },
    @{ Name = 'Pdf4D.Skia.Tests'; Folder = 'tests\Skia'; NeedsSkia = $true; WindowsOnly = $false },
    @{ Name = 'Pdf4D.Vcl.Tests'; Folder = 'tests\Vcl'; NeedsSkia = $true; WindowsOnly = $true },
    @{ Name = 'Pdf4D.FMX.Tests'; Folder = 'tests\FMX'; NeedsSkia = $true; WindowsOnly = $true }
)
$PackageFiles = @('packages\Pdf4D.dproj', 'packages\Pdf4D.Render.dproj', 'packages\Pdf4D.Render.Skia.dproj', 'packages\Pdf4D.Viewer.dproj') | ForEach-Object { Join-Path $PSScriptRoot $_ }
# The VCL and FMX packages are built for Windows only (Win32 and Win64); dclPdf4D.Vcl is the design-time package for the IDE (a 64-bit IDE
# loads the Win64 build, a 32-bit IDE the Win32 build)
$WindowsPackageFiles = @('packages\Pdf4D.Vcl.dproj', 'packages\Pdf4D.Vcl.Skia.dproj', 'packages\dclPdf4D.Vcl.dproj', 'packages\Pdf4D.FMX.dproj', 'packages\Pdf4D.FMX.Skia.dproj') | ForEach-Object { Join-Path $PSScriptRoot $_ }
# The demo applications, built for Windows only (compiled, not run)
$DemoFiles = @('demos\Vcl\Pdf4DInvoiceDemo.dproj') | ForEach-Object { Join-Path $PSScriptRoot $_ }

# Hints and warnings of our own code fail the build; hints inside the Embarcadero-supplied DUnitX source are not ours to fix
function Test-NoBuildProblems([string[]]$Output, [string]$TargetPlatform) {
    $problems = $Output | Where-Object { $_ -match '(warning|hint) [WH]\d{4}' -and $_ -notmatch [regex]::Escape('\Studio\37.0\source\') }
    if ($problems) {
        throw "Build for $TargetPlatform reported hints or warnings"
    }
}

function Invoke-MsBuild([string]$Project, [string]$TargetPlatform) {
    $command = "call ""$RsVars"" && msbuild ""$Project"" /t:Build /p:Config=$Config /p:Platform=$TargetPlatform /v:minimal"
    $output = & cmd /c $command 2>&1 | ForEach-Object { "$_" }
    $buildExitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($buildExitCode -ne 0) {
        throw "Build of $Project failed for $TargetPlatform (exit code $buildExitCode)"
    }

    return $output
}

# A unit that the package uses but does not contain is reported as W1033 (implicitly imported); that is a forgotten unit in the
# contains clause, and the message names it
function Invoke-PackageBuild([string]$TargetPlatform) {
    $files = if ($TargetPlatform -eq 'Linux64') { $PackageFiles } else { $PackageFiles + $WindowsPackageFiles }
    foreach ($packageFile in $files) {
        Write-Host "=== Package $([IO.Path]::GetFileNameWithoutExtension($packageFile)) $TargetPlatform $Config ==="
        $output = Invoke-MsBuild $packageFile $TargetPlatform

        if ($output | Where-Object { $_ -match 'W1033' }) {
            throw "A package for $TargetPlatform implicitly imports a unit that is missing from its contains clause (W1033)"
        }
        Test-NoBuildProblems $output $TargetPlatform
    }
}

# The demo is compiled only, for Windows; it is not run
function Invoke-DemoBuild([string]$TargetPlatform) {
    foreach ($demoFile in $DemoFiles) {
        Write-Host "=== Demo $([IO.Path]::GetFileNameWithoutExtension($demoFile)) $TargetPlatform $Config ==="
        $output = Invoke-MsBuild $demoFile $TargetPlatform
        Test-NoBuildProblems $output $TargetPlatform
    }
}

function Invoke-Build($TestProject, [string]$TargetPlatform) {
    Write-Host "=== Build $($TestProject.Name) $TargetPlatform $Config ==="
    $projectFile = Join-Path $PSScriptRoot "$($TestProject.Folder)\$($TestProject.Name).dproj"
    $output = Invoke-MsBuild $projectFile $TargetPlatform
    Test-NoBuildProblems $output $TargetPlatform
}
# Shared state is published lazily and freed by class destructors; initialization and finalization sections are not allowed
function Test-NoInitializationSections {
    $folders = 'src', 'tests\Support', 'tests\Acceptance' | ForEach-Object { Join-Path $PSScriptRoot $_ } | Where-Object { Test-Path $_ }
    $offenders = Get-ChildItem -Path $folders -Include '*.pas', '*.inc' -Recurse |
        Select-String -Pattern '^\s*(initialization|finalization)\b' -CaseSensitive:$false
    if ($offenders) {
        $offenders | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
        throw 'Units under src, tests/Support and tests/Acceptance must not have initialization or finalization sections'
    }
}

# Layer boundaries. Comment lines are skipped.
# - The core (everything under src except Graphics, Codec, Render, Viewer, Vcl and the ICC resources) uses no unit of those folders.
# - The core and the renderer use no unit from src\Viewer.
# - src\Viewer uses only System.* and Pdf4D.* units, none of the VCL, FMX, Skia or the VCL and FMX components.
# - Only src\Vcl uses Vcl.* and Winapi.*, and src\Vcl uses no FMX.*.
# - Only src\FMX uses FMX.*, and src\FMX uses no Vcl.* and no Winapi.*.
# - Only src\Render\Skia, src\Vcl\Skia and src\FMX\Skia use System.Skia or Pdf4D.Render.Skia.
function Get-UsesViolations([string]$Folder, [string]$Pattern, [string[]]$ExcludedFolders) {
    $sourceFolder = Join-Path $PSScriptRoot 'src'
    $excluded = $ExcludedFolders | ForEach-Object { (Join-Path $sourceFolder $_) + [IO.Path]::DirectorySeparatorChar }
    if (-not (Test-Path -LiteralPath $Folder)) {
        return
    }
    Get-ChildItem -Path $Folder -Include '*.pas', '*.inc' -Recurse |
        Where-Object { $file = $_.FullName; -not ($excluded | Where-Object { $file.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) } |
        Select-String -Pattern $Pattern |
        Where-Object { $_.Line -notmatch '^\s*//' }
}

function Test-LayerBoundaries {
    $sourceFolder = Join-Path $PSScriptRoot 'src'
    $layerFolders = 'Graphics', 'Codec', 'Render', 'Viewer', 'Vcl', 'FMX'
    $notNamespacePrefix = '(?<![\w.])'

    $coreViolations = Get-UsesViolations $sourceFolder '\bPdf4D\.(Render|Graphics|Codec|Viewer|Vcl|FMX)\.\w|\bPdf4D\.Resources\.Icc\b' $layerFolders |
        Where-Object { $_.Path -notmatch 'Pdf4D\.Resources\.Icc' }
    $viewerUsers = Get-UsesViolations $sourceFolder '\bPdf4D\.Viewer\.\w' @('Viewer', 'Vcl', 'FMX')
    $viewerViolations = Get-UsesViolations (Join-Path $sourceFolder 'Viewer') "${notNamespacePrefix}(Vcl|Winapi|FMX|Skia|Data|Xml|REST|Soap|Spring|IdHTTP|Indy)\.\w|\bPdf4D\.(Vcl|FMX)\b" @()
    $vclViolations = Get-UsesViolations $sourceFolder "${notNamespacePrefix}(Vcl|Winapi)\.\w" @('Vcl')
    $fmxInVclViolations = Get-UsesViolations (Join-Path $sourceFolder 'Vcl') "${notNamespacePrefix}FMX\.\w|\bPdf4D\.FMX\b" @()
    $fmxOutsideViolations = Get-UsesViolations $sourceFolder "${notNamespacePrefix}FMX\.\w" @('FMX', 'Vcl', 'Viewer')
    $vclInFmxViolations = Get-UsesViolations (Join-Path $sourceFolder 'FMX') '\bPdf4D\.Vcl\b' @()
    $skiaViolations = Get-UsesViolations $sourceFolder '\bSystem\.Skia\b|\bPdf4D\.Render\.Skia\b' @('Render\Skia', 'Vcl\Skia', 'FMX\Skia')

    $violations = @($coreViolations) + @($viewerUsers) + @($viewerViolations) + @($vclViolations) + @($fmxInVclViolations) +
        @($fmxOutsideViolations) + @($vclInFmxViolations) + @($skiaViolations)
    if ($violations) {
        $violations | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
        throw 'Layer boundary violated: the core and the renderer must not use src\Viewer, src\Vcl or src\FMX; src\Viewer uses only System.* and Pdf4D.* units without Skia; only src\Vcl uses Vcl.* and Winapi.* (and no FMX.*); only src\FMX uses FMX.* (and no Vcl.* and Winapi.*); only src\Render\Skia, src\Vcl\Skia and src\FMX\Skia use System.Skia or Pdf4D.Render.Skia'
    }
}

# System.ZLib links against the system zlib (-lz), which needs the libz.so development link in the SDK
function Get-LinuxSdkPath {
    if ($LinuxSdkPath) {
        return $LinuxSdkPath
    }

    $sdkRegistryKey = 'HKCU:\Software\Embarcadero\BDS\37.0\PlatformSDKs'
    $sdkName = (Get-ItemProperty -Path $sdkRegistryKey -ErrorAction SilentlyContinue).Default_Linux64
    if (-not $sdkName) {
        throw "No default Linux64 SDK is registered under $sdkRegistryKey. Register one in the IDE (Tools > Options > Deployment > SDK Manager) or pass -LinuxSdkPath."
    }

    $systemRoot = (Get-ItemProperty -Path (Join-Path $sdkRegistryKey $sdkName)).SystemRoot
    $sdkFolder = if ($env:BDSPLATFORMSDKSDIR) { $env:BDSPLATFORMSDKSDIR } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Embarcadero\Studio\SDKs' }
    return $systemRoot.Replace('$(BDSPLATFORMSDKSDIR)', $sdkFolder)
}

function Test-LinuxSdkHasLibz {
    $libzPath = Join-Path (Get-LinuxSdkPath) 'usr\lib\x86_64-linux-gnu\libz.so'
    if (-not (Test-Path -LiteralPath $libzPath)) {
        throw "The Linux64 SDK has no libz.so: $libzPath is missing. Copy or link libz.so.1 as libz.so in that folder, or install zlib1g-dev and update the SDK in the SDK Manager."
    }
}

function Get-WslPath([string]$WindowsPath) {
    $linuxPath = (& wsl -d $WslDistro -- wslpath -a ($WindowsPath -replace '\\', '/') | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $linuxPath) {
        throw "Cannot convert $WindowsPath to a WSL path"
    }
    return $linuxPath
}

# The library that System.Skia loads at run time, from the RAD Studio redistributables
function Get-SkiaLibraryPath([string]$TargetPlatform) {
    $relativePath = switch ($TargetPlatform) {
        'Win32'   { 'Redist\win32\sk4d.dll' }
        'Win64'   { 'Redist\win64\sk4d.dll' }
        'Linux64' { 'Redist\linux64\libsk4d.so' }
    }
    $libraryPath = Join-Path $BdsFolder $relativePath
    if (-not (Test-Path -LiteralPath $libraryPath)) {
        throw "The Skia library for $TargetPlatform is missing: $libraryPath"
    }
    return $libraryPath
}

# SafeLoadLibrary does not look in the folder of the program on Linux, so the test run gets LD_LIBRARY_PATH; the dependencies of
# libsk4d.so must be there as well
function Test-SkiaLibraryDependencies([string]$LinuxLibrary) {
    $dependencies = & wsl -d $WslDistro -- ldd $LinuxLibrary | ForEach-Object { "$_" }
    $missing = $dependencies | Where-Object { $_ -match 'not found' } | ForEach-Object { ($_ -split '=>')[0].Trim() }
    if ($missing) {
        throw "libsk4d.so cannot be loaded in WSL, these libraries are missing: $($missing -join ', '). Install them in the $WslDistro distribution with apt, for example: sudo apt install libfontconfig1 libfreetype6 libgl1"
    }
}

function Invoke-Tests($TestProject, [string]$TargetPlatform) {
    Write-Host "=== Test $($TestProject.Name) $TargetPlatform $Config ==="
    $outputFolder = Join-Path $PSScriptRoot "$($TestProject.Folder)\$TargetPlatform\$Config"

    if ($TestProject.NeedsSkia) {
        Copy-Item -LiteralPath (Get-SkiaLibraryPath $TargetPlatform) -Destination $outputFolder -Force
    }

    if ($TargetPlatform -eq 'Linux64') {
        $linuxBinary = Get-WslPath (Join-Path $outputFolder $TestProject.Name)
        & wsl -d $WslDistro -- chmod +x $linuxBinary
        if ($TestProject.NeedsSkia) {
            $linuxFolder = Get-WslPath $outputFolder
            Test-SkiaLibraryDependencies "$linuxFolder/libsk4d.so"
            & wsl -d $WslDistro -- env "LD_LIBRARY_PATH=$linuxFolder" $linuxBinary
        }
        else {
            & wsl -d $WslDistro -- $linuxBinary
        }
    }
    else {
        & (Join-Path $outputFolder "$($TestProject.Name).exe")
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Tests of $($TestProject.Name) failed for $TargetPlatform (exit code $LASTEXITCODE)"
    }
}

Test-NoInitializationSections
Test-LayerBoundaries

$platforms = if ($Platform -eq 'All') { @('Win32', 'Win64', 'Linux64') } else { @($Platform) }

if ($platforms -contains 'Linux64') {
    Test-LinuxSdkHasLibz
}

foreach ($targetPlatform in $platforms) {
    Invoke-PackageBuild $targetPlatform
    if ($targetPlatform -ne 'Linux64') {
        Invoke-DemoBuild $targetPlatform
    }
    foreach ($testProject in ($TestProjects | Where-Object { $Suite -eq 'All' -or $_.Name -eq $Suite })) {
        if ($testProject.WindowsOnly -and $targetPlatform -eq 'Linux64') {
            continue
        }
        Invoke-Build $testProject $targetPlatform
        Invoke-Tests $testProject $targetPlatform
    }
}

Write-Host 'All platforms OK'
