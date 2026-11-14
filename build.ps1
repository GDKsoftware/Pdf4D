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

function Invoke-Build([string]$TargetPlatform) {
    Write-Host "=== Build $TargetPlatform $Config ==="
    $command = "call ""$RsVars"" && msbuild ""$ProjectFile"" /t:Build /p:Config=$Config /p:Platform=$TargetPlatform /v:minimal"
    $output = & cmd /c $command 2>&1 | ForEach-Object { "$_" }
    $buildExitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($buildExitCode -ne 0) {
        throw "Build failed for $TargetPlatform (exit code $buildExitCode)"
    }

    # Hints inside the Embarcadero-supplied DUnitX source are not ours to fix
    $problems = $output | Where-Object { $_ -match '(warning|hint) [WH]\d{4}' -and $_ -notmatch [regex]::Escape('\Studio\37.0\source\') }
    if ($problems) {
        throw "Build for $TargetPlatform reported hints or warnings"
    }
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

$platforms = if ($Platform -eq 'All') { @('Win32', 'Win64', 'Linux64') } else { @($Platform) }

if ($platforms -contains 'Linux64') {
    Test-LinuxSdkHasLibz
}

foreach ($targetPlatform in $platforms) {
    Invoke-Build $targetPlatform
    Invoke-Tests $targetPlatform
}

Write-Host 'All platforms OK'
