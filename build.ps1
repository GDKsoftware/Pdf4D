param(
    [ValidateSet('Win32', 'Win64', 'Linux64', 'All')]
    [string]$Platform = 'All',

    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Debug',

    # The Linux64 SDK folder; by default the one the IDE has registered as the default Linux64 SDK
    [string]$LinuxSdkPath
)

$ErrorActionPreference = 'Stop'

$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$WslDistro = 'Ubuntu'
$ProjectFile = Join-Path $PSScriptRoot 'tests\Pdf4D.Tests.dproj'
$PackageFiles = @('packages\Pdf4D.dproj', 'packages\Pdf4D.Render.dproj') | ForEach-Object { Join-Path $PSScriptRoot $_ }

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
    foreach ($packageFile in $PackageFiles) {
        Write-Host "=== Package $([IO.Path]::GetFileNameWithoutExtension($packageFile)) $TargetPlatform $Config ==="
        $output = Invoke-MsBuild $packageFile $TargetPlatform

        if ($output | Where-Object { $_ -match 'W1033' }) {
            throw "A package for $TargetPlatform implicitly imports a unit that is missing from its contains clause (W1033)"
        }
        Test-NoBuildProblems $output $TargetPlatform
    }
}

function Invoke-Build([string]$TargetPlatform) {
    Write-Host "=== Build $TargetPlatform $Config ==="
    $output = Invoke-MsBuild $ProjectFile $TargetPlatform
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

# Layer boundaries: the core (everything under src except Graphics, Codec, Render and the ICC resources) uses no unit of those
# folders, and only units under src\Render\Skia use System.Skia. Comment lines are skipped.
function Get-UsesViolations([string]$Folder, [string]$Pattern, [string[]]$ExcludedFolders) {
    $sourceFolder = Join-Path $PSScriptRoot 'src'
    $excluded = $ExcludedFolders | ForEach-Object { (Join-Path $sourceFolder $_) + [IO.Path]::DirectorySeparatorChar }
    Get-ChildItem -Path $Folder -Include '*.pas', '*.inc' -Recurse |
        Where-Object { $file = $_.FullName; -not ($excluded | Where-Object { $file.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) } |
        Select-String -Pattern $Pattern |
        Where-Object { $_.Line -notmatch '^\s*//' }
}

function Test-LayerBoundaries {
    $sourceFolder = Join-Path $PSScriptRoot 'src'
    $layerFolders = 'Graphics', 'Codec', 'Render'

    $coreViolations = Get-UsesViolations $sourceFolder '\bPdf4D\.(Render|Graphics|Codec)\.\w|\bPdf4D\.Resources\.Icc\b' $layerFolders |
        Where-Object { $_.Path -notmatch 'Pdf4D\.Resources\.Icc' }
    $skiaViolations = Get-UsesViolations $sourceFolder '\bSystem\.Skia\b' @('Render\Skia')

    $violations = @($coreViolations) + @($skiaViolations)
    if ($violations) {
        $violations | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
        throw 'Layer boundary violated: the core must not use src\Graphics, src\Codec, src\Render or the ICC resources, and only src\Render\Skia may use System.Skia'
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

function Invoke-Tests([string]$TargetPlatform) {
    Write-Host "=== Test $TargetPlatform $Config ==="
    $outputFolder = Join-Path $PSScriptRoot "tests\$TargetPlatform\$Config"

    if ($TargetPlatform -eq 'Linux64') {
        $linuxBinary = Get-WslPath (Join-Path $outputFolder 'Pdf4D.Tests')
        & wsl -d $WslDistro -- chmod +x $linuxBinary
        & wsl -d $WslDistro -- $linuxBinary
    }
    else {
        & (Join-Path $outputFolder 'Pdf4D.Tests.exe')
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Tests failed for $TargetPlatform (exit code $LASTEXITCODE)"
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
    Invoke-Build $targetPlatform
    Invoke-Tests $targetPlatform
}

Write-Host 'All platforms OK'
