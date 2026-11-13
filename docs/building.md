# Building and testing

## Prerequisites

- Delphi 13 (RAD Studio 37.0) in `C:\Program Files (x86)\Embarcadero\Studio\37.0`. The build script calls `rsvars.bat` from there.
- DUnitX from `$(BDS)\source\DUnitX` (ships with Delphi).
- For Linux64: the Linux64 SDK (for example `ubuntu26.04.sdk` in `Documents\Embarcadero\Studio\SDKs`) registered as the default Linux64 SDK in the IDE (Tools > Options > Deployment > SDK Manager), and WSL with a distribution named `Ubuntu`.
- Linux64 links `System.ZLib` against the system zlib (`-lz`). The SDK therefore needs `usr/lib/x86_64-linux-gnu/libz.so`, the development link that `zlib1g-dev` provides. When the SDK only has `libz.so.1`, copy or link it as `libz.so` in that folder.

## Building and running

```powershell
./build.ps1                          # all platforms, Debug
./build.ps1 -Platform Win64          # one platform
./build.ps1 -Platform All -Config Release
```

The script builds `tests\Pdf4D.Tests.dproj` with msbuild, fails on any hint or warning from the project's own code, and runs the tests. It exits non-zero on a failure.

## Linux via WSL

The Linux64 binary is built with msbuild on Windows and run in WSL. The script converts the Windows path of the binary with `wslpath`, so the repository can live anywhere. WSL starts the distribution on demand.

## Test results and leaks

- Each run writes NUnit XML to `tests\results-<platform>.xml`.
- The test program runs the suite twice and compares the number of outstanding memory blocks before and after the second run, on every platform. A difference gives exit code 2. In Debug on Windows, `ReportMemoryLeaksOnShutdown` is also enabled.
- Exit codes: 0 all passed, 1 test failure, 2 memory leak.

## Adding source folders

The test project's unit search path lists each folder under `src\` explicitly (Delphi has no wildcards). Add a new folder to `DCC_UnitSearchPath` in `tests\Pdf4D.Tests.dproj` and add new test units to `tests\Pdf4D.Tests.dpr`.

## DEC for the crypto tests

The AES tests compare against Delphi Encryption Compendium (DEC) 6.4.1. DEC is used by the tests only and the library does not depend on it. Run `tools/fetch-dec.ps1` once; it puts DEC in `tests\ThirdParty\DEC` (ignored by git). The test project's search path contains `tests\ThirdParty\DEC\Source`, and Linux64 defines `NO_ASM`.

## Test corpus location

Tests that read corpus files look for a `corpus` folder with a `manifest.csv`, starting at the folder of the test program and going up. From `tests\<Platform>\<Config>` that finds `tests\corpus`, also for the Linux64 binary that WSL runs from the Windows file system (`/mnt/c/...`). The environment variable `PDF4D_CORPUS` names the folder when the program runs somewhere else. The working directory plays no part.
