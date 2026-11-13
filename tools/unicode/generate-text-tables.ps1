# Generates tools/unicode/text-tables.txt with the JDK of the oracle (tools/oracle/fetch-jdk.ps1) and rebuilds the
# UNICODE resource group (src/Resources/Pdf4D.Resources.Unicode.res) from it. A second run gives identical output.
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'text-tables.txt')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\oracle\oracle-lib.ps1')

$java = Get-OracleJava
$javac = Join-Path (Split-Path $java) 'javac.exe'
$classes = Join-Path ([IO.Path]::GetTempPath()) ('pdf4d-texttables-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes | Out-Null
try {
    & $javac -d $classes (Join-Path $PSScriptRoot 'GenerateTextTables.java')
    if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
    & $java -cp $classes GenerateTextTables $OutputPath
    if ($LASTEXITCODE -ne 0) { throw 'GenerateTextTables failed' }
}
finally {
    Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
}

& (Join-Path $PSScriptRoot '..\resources\build-resources.ps1') -OnlyGroup UNICODE
if (-not $?) { throw 'build-resources.ps1 failed' }
