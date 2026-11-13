# Downloads a portable Temurin 21 JDK (Windows x64) into tools/oracle/jdk/. No installation.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$here = $PSScriptRoot
$jdkDir = Join-Path $here 'jdk'
if (Get-ChildItem -Path (Join-Path $jdkDir '*\bin\java.exe') -ErrorAction SilentlyContinue) {
    Write-Host 'JDK already present.'
} else {
    New-Item -ItemType Directory -Force $jdkDir | Out-Null
    $zip = Join-Path $jdkDir 'jdk.zip'
    $url = 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse'
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $jdkDir -Force
    Remove-Item $zip
}
$java = (Resolve-Path (Join-Path $jdkDir '*\bin\java.exe') | Select-Object -First 1).Path
& $java -version
