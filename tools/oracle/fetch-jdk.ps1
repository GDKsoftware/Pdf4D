# Downloads a portable Temurin 21 JDK (Windows x64) into tools/oracle/jdk/. No installation.
# The release is pinned: the Marlin rasterizer inside it draws the reference images, so a newer JDK could change them. To move on,
# change $jdkRelease and $sha256 together (the checksum is published next to the zip on the Temurin release page) and regenerate
# the references with generate-render.ps1.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$jdkRelease = 'jdk-21.0.13+9'
$sha256 = 'a4dbaa05fca4bd89d84584e58c459bd732efebb1722af80ab13c6516832004f9'
$here = $PSScriptRoot
$jdkDir = Join-Path $here 'jdk'
if (Get-ChildItem -Path (Join-Path $jdkDir '*\bin\java.exe') -ErrorAction SilentlyContinue) {
    Write-Host 'JDK already present.'
} else {
    New-Item -ItemType Directory -Force $jdkDir | Out-Null
    $zip = Join-Path $jdkDir 'jdk.zip'
    $url = "https://api.adoptium.net/v3/binary/version/$([Uri]::EscapeDataString($jdkRelease))/windows/x64/jdk/hotspot/normal/eclipse"
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
    if ($actual -ne $sha256.ToUpperInvariant()) {
        Remove-Item $zip
        throw "The download of $jdkRelease has SHA-256 $actual, expected $sha256"
    }
    Expand-Archive -Path $zip -DestinationPath $jdkDir -Force
    Remove-Item $zip
}
$java = (Resolve-Path (Join-Path $jdkDir '*\bin\java.exe') | Select-Object -First 1).Path
& $java -version
