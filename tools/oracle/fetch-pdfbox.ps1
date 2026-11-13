# Downloads pdfbox-app-3.0.8.jar into tools/oracle/lib/ and verifies its SHA-512.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$lib = Join-Path $PSScriptRoot 'lib'
New-Item -ItemType Directory -Force $lib | Out-Null
$name = 'pdfbox-app-3.0.8.jar'
$base = 'https://archive.apache.org/dist/pdfbox/3.0.8'
$jar = Join-Path $lib $name
if (-not (Test-Path $jar)) {
    Invoke-WebRequest -Uri "$base/$name" -OutFile $jar -UseBasicParsing
}
$expected = ((Invoke-WebRequest -Uri "$base/$name.sha512" -UseBasicParsing).Content -split '\s+')[0].Trim().ToLower()
$actual = (Get-FileHash -Algorithm SHA512 $jar).Hash.ToLower()
if ($expected -ne $actual) {
    Remove-Item $jar
    throw "SHA-512 mismatch for $name"
}
Write-Host "$name OK (sha512 verified)"
