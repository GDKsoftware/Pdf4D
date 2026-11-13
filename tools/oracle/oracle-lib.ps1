# Shared helpers for the oracle scripts (dot-source this file).
$script:OracleDir = $PSScriptRoot
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Get-OracleJava {
    $j = Get-ChildItem -Path (Join-Path $script:OracleDir 'jdk\*\bin\java.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $j) { throw 'No JDK found. Run tools/oracle/fetch-jdk.ps1 first.' }
    return $j.FullName
}

# Compiles Pdf4DOracle.java into tools/oracle/classes/ when needed and returns the java classpath.
function Get-OracleClasspath {
    $jar = Join-Path $script:OracleDir 'lib\pdfbox-app-3.0.8.jar'
    if (-not (Test-Path $jar)) { throw 'pdfbox-app-3.0.8.jar missing. Run tools/oracle/fetch-pdfbox.ps1 first.' }
    $src = Join-Path $script:OracleDir 'Pdf4DOracle.java'
    $classes = Join-Path $script:OracleDir 'classes'
    $cls = Join-Path $classes 'Pdf4DOracle.class'
    if (-not (Test-Path $cls) -or (Get-Item $cls).LastWriteTime -lt (Get-Item $src).LastWriteTime) {
        $javac = Join-Path (Split-Path (Get-OracleJava)) 'javac.exe'
        New-Item -ItemType Directory -Force $classes | Out-Null
        & $javac -cp $jar -d $classes $src
        if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
    }
    return "$classes;$jar"
}
