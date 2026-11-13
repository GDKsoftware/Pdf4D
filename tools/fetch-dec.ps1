# Downloads Delphi Encryption Compendium (DEC) tag V6.4.1 to tests/ThirdParty/DEC (ignored by git).
# DEC is used by the tests only, as a reference implementation. The library does not depend on it.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag = 'V6.4.1'
$dest = Join-Path $PSScriptRoot '..\tests\ThirdParty\DEC'
if (-not (Test-Path (Join-Path $dest 'Source\DECCipherBase.pas'))) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    $zip = Join-Path $dest 'dec.zip'
    $url = "https://github.com/MHumm/DelphiEncryptionCompendium/archive/refs/tags/$tag.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    $tmp = Join-Path $dest '_x'
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Get-ChildItem $root.FullName -Force | Move-Item -Destination $dest -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip
}
Write-Host "DEC $tag at $((Resolve-Path $dest).Path)"
