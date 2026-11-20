# Building and testing

## Prerequisites

- Delphi 13 (RAD Studio 37.0) in `C:\Program Files (x86)\Embarcadero\Studio\37.0`. The build script calls `rsvars.bat` from there.
- DUnitX from `$(BDS)\source\DUnitX` (ships with Delphi).
- For Linux64: the Linux64 SDK (for example `ubuntu26.04.sdk` in `Documents\Embarcadero\Studio\SDKs`) registered as the default Linux64 SDK in the IDE (Tools > Options > Deployment > SDK Manager), and WSL with a distribution named `Ubuntu`.
- Linux64 links `System.ZLib` against the system zlib (`-lz`). The SDK therefore needs `usr/lib/x86_64-linux-gnu/libz.so`, the development link that `zlib1g-dev` provides. When the SDK only has `libz.so.1`, copy or link it as `libz.so` in that folder. `build.ps1` checks for the file before it builds Linux64, in the default Linux64 SDK that the IDE has registered (or in the folder given with `-LinuxSdkPath`), and stops with an error that names the path when it is missing. The script never copies anything itself.

## The PDF4D_TESTS define

`tests\Pdf4D.Tests.dproj` defines `PDF4D_TESTS` for every configuration and platform. It switches on test hooks that the library does not have without it: `TPDFontFactory.CreatorOverride` (replaces the font creation in `GetFont`) and the setter of `TCMap.MappingLimit`. Do not define it in a project that uses the library.

## Building and running

```powershell
./build.ps1                          # all platforms, Debug
./build.ps1 -Platform Win64          # one platform
./build.ps1 -Platform All -Config Release
```

For each platform the script first builds the packages (`packages\Pdf4D.dproj`, `Pdf4D.Render.dproj` and `Pdf4D.Render.Skia.dproj`), then `tests\Pdf4D.Tests.dproj` and `tests\Skia\Pdf4D.Skia.Tests.dproj` (see "The Skia backend"), with msbuild. It fails on any hint or warning from the project's own code, on W1033 in a package build, and on a failing test. It exits non-zero on a failure.

## Packages

`packages\Pdf4D.dpk` is the core runtime package (`requires rtl`): every unit under `src` except the tests (`*.Tests.pas`, `*.Tests.Support.pas`) and the folders `Graphics`, `Codec` and `Render` (and `src\Resources\Pdf4D.Resources.Icc.*`), which later phases put in their own packages. `packages\Pdf4D.groupproj` holds the package; the test projects stay outside it. The package builds for Win32, Win64 and Linux64 (`Pdf4D.bpl` on Windows, `bplPdf4D.so` on Linux64), with output in `packages\<Platform>\<Config>` (ignored by git).

The package lists its units in the `contains` clause, and nothing else is on its search path, so a unit that is missing there stops the build with F2613 (and an implicit import would show as W1033, which `build.ps1` also treats as a failure). When you add a unit under `src`, add it to `packages\Pdf4D.dpk` and `packages\Pdf4D.dproj` as well as to the test project.

The Delphi compiler builds Linux64 packages (the linker writes `bplPdf4D.so`), so Linux64 builds the package like the other platforms. The tests do not link the package: they compile the units from the search path, which keeps the test program free of a package dependency.

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

## Fuzz sweeps

`Pdf4D.Tests.Robustness.Tests` and `Pdf4D.Tests.TextRobustness.Tests` mutate corpus files, generate content streams and mutate font programs; every run happens on a worker thread with a time limit and may only succeed or end in an `EPdfException`. The seeds and sizes in the code are fixed. For a larger sweep with other seeds, set these environment variables and run one fixture (the test program takes DUnitX options such as `-r:`):

| Variable | Meaning |
|---|---|
| `PDF4D_FUZZ_SEED` | Added to every seed (default 0). The name of a failure holds the seed and the index of the case. |
| `PDF4D_FUZZ_SCALE` | Multiplies the number of cases (default 1). |
| `PDF4D_FUZZ_SECONDS` | The time limit of one run (default 10). |
| `PDF4D_FUZZ_TRACE` | A file that gets the duration and the outcome of every run. |
| `PDF4D_ROBUSTNESS_OUTPUT` | A folder that gets the bytes of every failing case. |

```powershell
$env:PDF4D_FUZZ_SEED = 100000; $env:PDF4D_FUZZ_SCALE = 4
tests\Win64\Debug\Pdf4D.Tests.exe -r:Pdf4D.Tests.TextRobustness.Tests.TTextRobustnessTests
```

A run that hits the time limit keeps its thread, so the process can crash when it ends; the failure is reported before that.

## Test fonts

`tests\Fonts` holds the fonts that the font tests load (two TrueType fonts, two CFF OpenType fonts and two Type 1 `.pfb` fonts), with `manifest.csv` (file, source, licence, notes) and, per font, a `<font>.widths.txt` with the PDFBox 3.0.8 widths and Unicode values that the tests compare with. The widths files are generated by `tools\oracle\generate-font-widths.ps1`; fetch missing fonts with `tools\corpusetch-fonts.ps1`. The text goldens use an empty font provider, so they do not depend on the fonts installed on the machine.

## Oracle modes

The golden files in `tests\golden` are written by the PDFBox 3.0.8 oracle. `tools\oracle\generate-golden.ps1` takes `-Mode Dump` (the structure dump, `*.dump.txt`), `-Mode Text` (the text dump, `*.text.txt`), `-Mode Positions` (the line positions, `*.positions.txt`) or `-Mode All` (the default, all three), and `-Filter` for part of the corpus. Without a filter the script first removes the files of the chosen modes. The formats are in `golden-format.md`. The comparison of the text goldens counts sections that are only equal after white space is ignored; set `PDF4D_TEXT_LENIENT_REPORT` to a file name to get one line per such section.

## Render reference images

`tools\oracle\generate-render.ps1 -Dpi 72` writes the PDFBox renders of every corpus page to `tests\reference\render\72` (about 45 MB, in plain git) and `-Dpi 150` those of `tests\reference\render\150\selection.txt`; `tools\oracle\generate-render-tests.ps1` writes the synthetic render test files. `PDF4D_RENDER_OUTPUT` names a folder where `Pdf4D.Skia.Tests` writes the Pdf4D render and a difference image of every page that differs from its reference. The format and the comparison are in `golden-format.md`.

## Resources (rebuilding)

The glyph lists, the AFM files of the standard 14 fonts, the predefined CMaps and LiberationSans live in `src\Resources` as one `.res` file per group. Each source file is a zlib-compressed `RCDATA` resource, named by `TPdfResourceData.NameOf` (for example `PDF4D_CMAP_UNIGB_UCS2_H`), and one small unit per group (`Pdf4D.Resources.<Group>.pas`) links the `.res` with `{$R}`. The `.res` files, `resources.csv` (name, source, SHA-256 of the uncompressed bytes, licence) and `afm-MustRead.html` are committed; never edit them by hand.

To rebuild them, run `tools\fetch-pdfbox-src.ps1` once and then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\resources\build-resources.ps1
```

The script needs `brcc32` from the Delphi `bin` folder (it calls `rsvars.bat`), fails on a duplicate resource name, and gives byte-identical output for identical sources. `TestResourceHashesMatchCsv` compares every resource with `resources.csv`.

Do not name a resource file after the project (`Pdf4D.Tests.res` is regenerated by the build and overwritten). Resource names are matched case-insensitively on Linux64, so they are all upper case. `RT_RCDATA` comes from `System.Types`.

## The Skia backend

`src\Render\Skia` holds the Skia render backend (`TPdfSkiaBackend`, built on `System.Skia`, the Skia that ships with RAD Studio). It has its own package, `packages\Pdf4D.Render.Skia.dpk` (`requires rtl, Skia.Package.RTL, Pdf4D, Pdf4D.Render`), so an application that does not choose Skia never needs `sk4d.dll`. Only units under `src\Render\Skia` may use `System.Skia`; `build.ps1` checks that.

The Skia tests are a separate project, `tests\Skia\Pdf4D.Skia.Tests.dproj` (output in `tests\Skia\<Platform>\<Config>`, results in `tests\Skia\results-<platform>.xml`). It has the same leak check (two runs) and the `PDF4D_TESTS` define as `Pdf4D.Tests`. `Pdf4D.Tests` gets no Skia library in its folder: it runs without one, which proves that the core and the renderer do not need Skia. `build.ps1` builds and runs both projects; `-Suite Pdf4D.Skia.Tests` (or `Pdf4D.Tests`) runs one of them.

- Before the Skia tests run, `build.ps1` copies `Redist\win32\sk4d.dll`, `Redist\win64\sk4d.dll` or `Redist\linux64\libsk4d.so` from the RAD Studio folder into the output folder of the Skia test project.
- `System.Skia` masks all floating point exceptions of the process when it starts, so the test program sets the Delphi default mask again before the tests. The device itself runs every Skia call inside `TPdfFloatGuard`, which gives the mask back as it found it.
- On Linux64 `SafeLoadLibrary('libsk4d.so')` does not search the folder of the program. `build.ps1` starts the Skia tests with `LD_LIBRARY_PATH` set to the output folder, and first runs `ldd` on `libsk4d.so` in WSL. A dependency that is not found stops the script with the missing libraries and an `apt` hint, like the check for `libz.so`.

### Delphi 12

The Skia code only uses `System.Skia` API that Delphi 12 and 13 share, and it has not been compiled with Delphi 12. Every use of something outside this list gets a line below.

- `TSkSurface.MakeRaster`, `ISkSurface.Canvas`, `ISkSurface.MakeImageSnapshot`, `ISkImage.ReadPixels`.
- `ISkCanvas`: `Save`, `Restore`, `RestoreToCount`, `SetMatrix`, `Concat`, `ClipPath`, `DrawPath`, `DrawImageRect`, `Clear`, `SaveLayer`.
- `TSkPathBuilder` (`MoveTo`, `LineTo`, `QuadTo`, `CubicTo`, `Close`, `Detach`, `FillType`), `TSkPaint` (`Style`, `StrokeWidth`, `StrokeCap`, `StrokeJoin`, `StrokeMiter`, `Color`, `Alpha`, `AntiAlias`, `Shader`, `PathEffect`).
- `TSkPathEffect.MakeDash`, `TSkImage.MakeRasterCopy`, `ISkImage.MakeShader`, `TSkSamplingOptions` (also `Create(TSkCubicResampler.Mitchell)`), `TSkBlendMode`, `TSkTileMode`.

Also used, outside that list:

- Blend modes use `ISkPaint.Blender` with `TSkBlender.MakeMode(TSkBlendMode)`, not a `BlendMode` property: Delphi 13 has no `ISkPaint.BlendMode`. Check on the first Delphi 12 build that `Blender` and `TSkBlender.MakeMode` exist there (Skia4Delphi 6 has them); if not, `ISkPaint.BlendMode` is the replacement.
- Soft masks and layers: `ISkCanvas.SaveLayer(Bounds, Paint)`, `ISkCanvas.DrawImage(Image, X, Y, Sampling, Paint)`, `TSkBlendMode.DestIn`, `TSkBlendMode.Hue`, `Saturation`, `Color`, `Luminosity` (the four non-separable modes), `System.Skia` only.
- `TSkImageInfo.Create(Width, Height, ColorType, AlphaType)` and the enums `TSkColorType`, `TSkAlphaType`, `TSkPaintStyle`, `TSkStrokeCap`, `TSkStrokeJoin`, `TSkPathFillType`, `TSkClipOp`, `TSkFilterMode`, `TSkMipmapMode`: the types that the listed calls take. All of them exist in Delphi 12.
- `TMatrix` from `System.Math.Vectors` as the matrix type of `SetMatrix` and `MakeShader`.
- The package `Skia.Package.RTL` in the `requires` clause of `Pdf4D.Render.Skia.dpk`. The Skia package has had this name since Delphi 12; check it when the first Delphi 12 build is made.
- `TSkSurface.MakeRaster` with `TSkColorType.RGBA8888` and `TSkAlphaType.Premul` is assumed to give the byte order R, G, B, A on every platform; `TestToBitmapIsPremultipliedRgba` checks it.
