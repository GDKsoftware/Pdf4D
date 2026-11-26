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

For each platform the script first builds the packages (`packages\Pdf4D.dproj`, `Pdf4D.Render.dproj`, `Pdf4D.Render.Native.dproj`, `Pdf4D.Render.Skia.dproj` and `Pdf4D.Viewer.dproj`, and for Win32 and Win64 also `Pdf4D.Vcl.dproj`, `Pdf4D.Vcl.Skia.dproj`, the design-time package `dclPdf4D.Vcl.dproj`, `Pdf4D.FMX.dproj`, `Pdf4D.FMX.Skia.dproj` and the design-time package `dclPdf4D.FMX.dproj`), then `tests\Pdf4D.Tests.dproj`, `tests\Skia\Pdf4D.Skia.Tests.dproj` (see "The Skia backend") and, for Win32 and Win64, `tests\Vcl\Pdf4D.Vcl.Tests.dproj` (see "The VCL tests") and `tests\FMX\Pdf4D.FMX.Tests.dproj` (see "The FMX tests"), with msbuild. For Win32 and Win64 it also compiles the demos (`demos\Vcl\Pdf4DInvoiceDemo.dproj` and `demos\FMX\Pdf4DInvoiceDemoFmx.dproj`, see "The demo") after the packages; the demos are not run. It fails on any hint or warning from the project's own code, on W1033 in a package build, and on a failing test. It exits non-zero on a failure.

## Packages

`packages\Pdf4D.dpk` is the core runtime package (`requires rtl`): every unit under `src` except the tests (`*.Tests.pas`, `*.Tests.Support.pas`) and the folders `Graphics`, `Codec`, `Render` and `Viewer` (and `src\Resources\Pdf4D.Resources.Icc.*`), which are in the other packages. `packages\Pdf4D.groupproj` holds the ten packages (see below), in build order; the test projects and the demo stay outside it. The package builds for Win32, Win64 and Linux64 (`Pdf4D.bpl` on Windows, `bplPdf4D.so` on Linux64), with output in `packages\<Platform>\<Config>` (ignored by git).

The package lists its units in the `contains` clause, and nothing else is on its search path, so a unit that is missing there stops the build with F2613 (and an implicit import would show as W1033, which `build.ps1` also treats as a failure). When you add a unit under `src`, add it to `packages\Pdf4D.dpk` and `packages\Pdf4D.dproj` as well as to the test project.

The Delphi compiler builds Linux64 packages (the linker writes `bplPdf4D.so`), so Linux64 builds the package like the other platforms. The tests do not link the package: they compile the units from the search path, which keeps the test program free of a package dependency.

The packages and what they contain:

| Package | `requires` | Contents |
|---|---|---|
| `Pdf4D.dpk` | `rtl` | the core: everything under `src` except the folders below |
| `Pdf4D.Render.dpk` | `rtl, Pdf4D` | `src\Graphics`, `src\Codec`, `src\Render` (without `Skia`) and `src\Resources\Pdf4D.Resources.Icc.*` |
| `Pdf4D.Render.Native.dpk` | `rtl, Pdf4D, Pdf4D.Render` | `src\Render\Native` (the native rasterizer, a port of tiny-skia; see `porting.md`) |
| `Pdf4D.Render.Skia.dpk` | `rtl, Skia.Package.RTL, Pdf4D, Pdf4D.Render` | `src\Render\Skia` |
| `Pdf4D.Viewer.dpk` | `rtl, Pdf4D, Pdf4D.Render` | `src\Viewer` (the viewer core: types, transforms and layout, no VCL and no Skia) |
| `Pdf4D.Vcl.dpk` | `rtl, vcl, Pdf4D.Viewer` | `src\Vcl` (`TPdf4DDocument`, `TPdf4DPageView` and the GDI and GDI+ painter) |
| `Pdf4D.Vcl.Skia.dpk` | `rtl, Pdf4D.Vcl, Pdf4D.Render.Skia` | `src\Vcl\Skia` (the `TPdf4DSkiaBackend` component) |
| `dclPdf4D.Vcl.dpk` | `rtl, vcl, designide, Pdf4D.Vcl, Pdf4D.Vcl.Skia` | `src\Vcl\Design` (design time only: the palette registration, the property editor of `FileName` and the palette icons) |
| `Pdf4D.FMX.dpk` | `rtl, fmx, Pdf4D.Viewer` | `src\FMX` (the FMX components: `TPdf4DDocument`, the page view, thumbnails, outline view, search bar, toolbar, viewer, print dialog and the actions, and the painter) |
| `Pdf4D.FMX.Skia.dpk` | `rtl, Pdf4D.FMX, Pdf4D.Render.Skia` | `src\FMX\Skia` (the `TPdf4DSkiaBackend` component) |
| `dclPdf4D.FMX.dpk` | `rtl, fmx, designide, Pdf4D.FMX, Pdf4D.FMX.Skia` | `src\FMX\Design` (design time only: the palette registration, the property editor of `FileName` and the palette icons) |

The first five build for Win32, Win64 and Linux64; the three VCL packages and the three FMX packages build for Win32 and Win64 only. `build.ps1` also checks the layers and fails on a violation: a unit of the core and of the renderer must not use a unit from `Viewer`, `Vcl` or `FMX`; a unit of the core must not use a unit from `Graphics`, `Codec`, `Render` or `Pdf4D.Resources.Icc.*`; a unit under `src\Viewer` uses only `System.*` and `Pdf4D.*` units, without Skia (the check rejects the other namespaces it knows, such as `Vcl`, `Winapi`, `FMX`, `Data`, `Xml`, `REST` and `Spring`); only `src\Vcl` uses `Vcl.*` and `Winapi.*` (and no `FMX.*`); only `src\FMX` uses `FMX.*` (and no `Vcl.*`, `Winapi.*` or `Pdf4D.Vcl.*`, so that the units can compile for macOS and Linux64; compiling for macOS and Linux64 has not been tried yet, and Linux64 needs FMXLinux); only units under `src\Render\Skia`, `src\Vcl\Skia` and `src\FMX\Skia` may use `System.Skia` or `Pdf4D.Render.Skia`; a unit under `src\Render\Native` uses only `System.*`, core units and units of `Pdf4D.Render` (the check rejects the namespaces it knows, as for `src\Viewer`), and only `src\Render\Native` and the viewer layer (`src\Viewer`, `src\Vcl`, `src\FMX`) use `Pdf4D.Render.Native.*`.

## The four test projects

- `tests\Pdf4D.Tests.dproj` tests the core and the renderer without Skia, with a device that records calls. Its folder has no Skia library, so it proves that the core and the renderer do not need one.
- `tests\Skia\Pdf4D.Skia.Tests.dproj` tests the Skia backend, compares the renders with the PDFBox reference images and runs the fuzz through the renderer (see "The Skia backend").

- `tests\Vcl\Pdf4D.Vcl.Tests.dproj` tests the VCL components (see "The VCL tests"); Win32 and Win64 only.
- `tests\FMX\Pdf4D.FMX.Tests.dproj` tests the FMX components (see "The FMX tests"); Win32 and Win64 only, and it runs last.

`./build.ps1 -Suite Pdf4D.Tests`, `-Suite Pdf4D.Skia.Tests`, `-Suite Pdf4D.Vcl.Tests` or `-Suite Pdf4D.FMX.Tests` runs one of them. `-Fixtures <name>[,<name>]` builds everything as usual but runs only those fixtures of each test project (DUnitX `-r:`, with full names such as `Pdf4D.Render.Native.Path.Tests.TTsPathTests`); combine it with `-Suite` while working on one area, and run the whole suite before a release.

## The VCL tests

`tests\Vcl\Pdf4D.Vcl.Tests.dproj` is a console program that makes VCL forms in its own process (`TVclTestHost` in `tests\Vcl\Support`): a form of 96 PPI, shown outside the visible desktop, with a `TPdf4DDocument` on Skia and a `TPdf4DPageView`. The tests send input with `Perform` (mouse messages, `WM_KEYDOWN` with the Ctrl state set through `SetKeyboardState`), pump the message queue with `CheckSynchronize` and `Application.ProcessMessages`, and read what the control paints with `PaintTo`. No desktop automation tool is involved, so the suite runs from `build.ps1`. `build.ps1` copies `sk4d.dll` next to the program, like for the Skia tests, and the program uses the same two-run leak check.

The process is not marked DPI aware: `ScaleForPPI` on the form drives the `ChangeScale(M, D, isDpiChange)` of the page view, which is what a Per-Monitor v2 application gets on a move to another monitor. The clipboard tests assert on the text that the page view hands to the clipboard; they also assert on `Clipboard.AsText` when the session allows access to the clipboard of the window system (some sessions refuse it with "access denied").

The run in `build.ps1` needs no printer. Printing on a real printer is tested only when the environment variable `PDF4D_TEST_PRINTER` names an installed printer (`TestRealPrinter` in `Pdf4D.Vcl.Print.Tests`): set it before the run, for example `$env:PDF4D_TEST_PRINTER = 'Microsoft Print to PDF'`, and look at the page that comes out. Without the variable the test ends as passed without printing. The print job itself is tested against `TBitmapPrintTarget` (`tests\Vcl\Support`).

## The FMX tests

`tests\FMX\Pdf4D.FMX.Tests.dproj` is a console program that makes FMX forms in its own process (`TFmxTestHost` in `tests\FMX\Support`): a form shown outside the visible desktop, with a `TPdf4DDocument` on Skia and a filled `Content` rectangle whose pixels `Snapshot` reads back (`MakeScreenshot`, in device pixels). The scale of the form is chosen by the test: `TFmxTestHost.Create(Width, Height, Scale)` forces it with `TWinWindowHandle.SetForcedScaleForForm` of `FMX.Platform.Win`, which gives the canvas of the form that scale (`Canvas.Scale`) and makes the client area `Width x Height` logical units and `Width * Scale` pixels. The setting holds for the whole process, so every host sets it, also on scale 1. The painter tests draw on a `TBitmap` whose `BitmapScale` is the scale. FMX forms run without the Skia canvas of Skia4Delphi: the project does not use `FMX.Skia`, so FMX draws with its default canvas for the platform and the pixel checks hold for that canvas. `sk4d.dll` is copied next to the program for the document renders, and the project has the same leak check (two runs) and the `PDF4D_TESTS` define as the other test projects. The tests do not need a visible desktop, but the process needs a desktop session (a window station) to make a window. FMX on Windows keeps small blocks for its windows and for some controls (one for a bare window, four for a window with a page view and its scroll bars) and lets go of them when 16 have built up, so the leak check of this project first brings that count to the start of a batch, before and after the second run, by making bare windows until a batch is let go; the difference in outstanding blocks must then be exactly 0.

The acceptance tests are in `tests\FMX\Acceptance`. `Pdf4D.Tests.FmxViewerFlows.Tests` runs the same way through a `TPdf4DViewer` as the VCL test (`TestEndToEndFlow`), with the mouse going through the overrides of the control (`MouseMove`, `MouseDown`, `MouseUp`, `DoMouseLeave`). The flow records the events of a viewer, one line each (kind, page, text and the quads rounded to 0.01 in PDF user space): the hover and the selection when the invoice number is clicked, the mouse leaving, the hover and the selection when the number is clicked again after two zoom steps and a rotation (the number is scrolled into view and the click is placed with `TryPageToViewport`, so the position is the same every run), and the hits of the search. `TestEventsEqualVcl` and `TestEventsEqualVclOnScale150` compare them with `tests\reference\viewer\flow-events.txt` in the source tree, on scale 1 and on scale 1.5. The file is found from the program folder upward and does not depend on `PDF4D_CORPUS`. A missing file is a failure. To write it, set `PDF4D_RECORD_FLOW_EVENTS=1` and run the VCL suite (`.\build.ps1 -Platform Win64 -Config Release -Suite Pdf4D.Vcl.Tests`); only the VCL flow test writes, the FMX tests never do. Do this only after a deliberate change of the events, and read the diff of the file before it is committed. `Pdf4D.Tests.FmxPerformance.Tests` has the limits of the VCL viewer (first page of an invoice, also on scale 1.5, the hover, the paint with the hover frame, the longest page down while scrolling 200 pages), measured in Release on Win64 only, and appends its measurements to `pdf4d-fmx-performance.txt` in the temporary folder. The page down is the key `PageDown` on the page view (`HandleKey`), because FMX has no `WM_VSCROLL`.

`TestRealPrinter` in `Pdf4D.FMX.Print.Tests` prints the invoice on the printer that `PDF4D_TEST_PRINTER` names. With `Microsoft Print to PDF` it runs unattended: that printer asks for the file name in a dialog of its own, in the thread of the program, and FMX has no way to name the file. `TSaveAsDialogDriver` (`tests\FMX\Support`) is a thread that waits for that dialog among the windows of the main thread, sets the file name box to a path in a temporary folder with `WM_SETTEXT` and posts `BM_CLICK` to Save. These are window messages to windows of the test process; no input is synthesised. The thread watches until the dialog is gone; after 60 seconds it cancels every dialog or message box that is still open on the main thread, so that the print ends and the test fails instead of hanging. The test then loads the PDF with Pdf4D, checks the page count, and renders every page and compares its ink (the distance of the pixels from white) with the same page of the original: at least a quarter of it must be there. The file is left in the temporary folder as `pdf4d-real-printer.pdf` for a look. Without the variable the test ends as passed without printing; a printer with another name is used as it is, with its own dialogs, if it has any.

## The demo

`demos\FMX\Pdf4DInvoiceDemoFmx.dproj` is the same demo as an FMX form (a `TPdf4DViewer` of `Pdf4D.FMX` with a `TPdf4DSkiaBackend`); it is compiled from `src` like the VCL demo, is built by `build.ps1` for Win32 and Win64 and is not run by it. Run it with `sk4d.dll` next to the program. The project has the same Per-Monitor v2 setting as the VCL demo (`AppDPIAwarenessMode`, `AppEnableHighDPI` and the default manifest), and the manual check below applies to it too (at 100 % and 150 %).

`demos\Vcl\Pdf4DInvoiceDemo.dproj` is the invoice demo of the README: a form with three fields and a `TPdf4DViewer`, linked to a `TPdf4DDocument` and a `TPdf4DSkiaBackend`, with a manifest for Per-Monitor v2 (`AppDPIAwarenessMode` in the project, which makes msbuild write the manifest). It compiles the units from `src` through its search path, not through the packages, so it needs no installed package. `build.ps1` compiles it for Win32 and Win64 and does not run it. To run it, put `sk4d.dll` of the same platform next to the program (`Redist\win32` or `Redist\win64` of RAD Studio) and start it with a PDF on the command line, for example `tests\corpus\generated\invoices\skia-draw.pdf`.

Checking Per-Monitor v2 by hand (needs two monitors with different scale factors, or a change of the scale in the Windows display settings while the demo runs):

1. Start the demo with an invoice and set the zoom to 100 % in the toolbar. Note the size of the toolbar icons and the text of the fields.
2. Drag the window to the other monitor (or change the scale of the monitor, Settings > System > Display). The window, the toolbar, the side panel, the fields and the page must all become larger or smaller by the ratio of the scales, the page must stay sharp (it is rendered again at the new scale, not stretched) and the current page and the zoom must not change.
3. Click in the fields and on a word of the PDF: the marker (a translucent ellipse) must sit on the text at the new scale.
4. Press Ctrl+P and look at the print dialog: it must have the size and fonts of the new scale (it takes the scale of the active form).

What was checked in this repository without a second monitor: the manifest of the Win64 build holds `dpiAwareness` `PerMonitorV2` and the process runs with that awareness context. A throwaway program that holds the demo form sent `WM_DPICHANGED` to it at 144 and 192 DPI and back (a real message to the form, with a suggested rectangle): the panel, the toolbar and the side panel scaled by 1.5 and 2, and the content of the page view at zoom 100 % went from 809 to 1214 and 1618 pixels wide and back to 809, with the current page and the zoom unchanged. This does not replace the check above: the window itself stayed at 96 DPI, so `CurrentPPI` of the form stayed 96 (the page view takes its scale from the `ChangeScale(M, D, isDpiChange)` of the message and not from `CurrentPPI`; the print dialog does use `CurrentPPI` of the active form, and that path is only checked by hand).

## Linux via WSL

The Linux64 binary is built with msbuild on Windows and run in WSL. The script converts the Windows path of the binary with `wslpath`, so the repository can live anywhere. WSL starts the distribution on demand.

## Test results and leaks

- Each run writes NUnit XML to `tests\results-<platform>.xml`.
- The test program runs the suite twice and compares the number of outstanding memory blocks before and after the second run, on every platform. A difference gives exit code 2. In Debug on Windows, `ReportMemoryLeaksOnShutdown` is also enabled.
- Exit codes: 0 all passed, 1 test failure, 2 memory leak, 3 (FMX tests only) the memory check could not be trusted: FMX did not let go of its blocks in the batch of windows that the check expects (see "The FMX tests").

## Adding source folders

The test project's unit search path lists each folder under `src\` explicitly (Delphi has no wildcards). Add a new folder to `DCC_UnitSearchPath` in `tests\Pdf4D.Tests.dproj` and add new test units to `tests\Pdf4D.Tests.dpr`.

## DEC for the crypto tests

The AES tests compare against Delphi Encryption Compendium (DEC) 6.4.1. DEC is used by the tests only and the library does not depend on it. Run `tools/fetch-dec.ps1` once; it puts DEC in `tests\ThirdParty\DEC` (ignored by git). The test project's search path contains `tests\ThirdParty\DEC\Source`, and Linux64 defines `NO_ASM`.

## Test corpus location

Tests that read corpus files look for a `corpus` folder with a `manifest.csv`, starting at the folder of the test program and going up. From `tests\<Platform>\<Config>` that finds `tests\corpus`, also for the Linux64 binary that WSL runs from the Windows file system (`/mnt/c/...`). The environment variable `PDF4D_CORPUS` names the folder when the program runs somewhere else. The working directory plays no part.

## Fuzz sweeps

The fuzz runs are `Pdf4D.Tests.Robustness.Tests` (mutated corpus files and mutated decoder input: JPEG, CCITT, ICC profile, PostScript function, Type 1 and CFF charstrings, `glyf` table), `Pdf4D.Tests.TextRobustness.Tests` (generated content streams, font programs, hostile documents) in the core test project, and `Pdf4D.Tests.RenderRobustness.Tests` in the Skia test project (every page of the mutated corpus and of 2000 generated graphics streams rendered at 36 DPI with the Skia backend, and hostile image, recursion and geometry documents). The work and the mutation machinery are in `tests\Support\Pdf4D.Tests.Fuzz.pas`. Every run happens on a worker thread with a time limit and may only succeed or end in an `EPdfException`. The seeds and sizes in the code are fixed. A Debug build renders about three times slower than a Release build, so the render runs of a Debug build are smaller: 6 mutations per corpus file instead of 20, and 600 generated graphics streams instead of 2000 (both counts are constants of `TFuzzSettings` in `tests\Support\Pdf4D.Tests.Fuzz.pas`). For a larger sweep with other seeds, set these environment variables and run one fixture (the test programs take DUnitX options such as `-r:`):

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
tests\Skia\Win64\Debug\Pdf4D.Skia.Tests.exe -r:Pdf4D.Tests.RenderRobustness.Tests.TRenderRobustnessTests
tests\Win64\Debug\Pdf4D.Tests.exe -r:Pdf4D.Tests.RenderRobustness.Native.Tests.TNativeRenderRobustnessTests
```

The render fuzz tests have one base class, `TRenderRobustnessTestsBase` in `tests\Support\Pdf4D.Tests.RenderRobustness.Base.pas` (the content stream generator, the hostile documents and the tests); the Skia test project and the core test project each derive a fixture that says which backend draws. The native fixture (`TNativeRenderRobustnessTests`) adds two hostile documents: a path of 5 000 000 segments and a dash of a million pieces. Hostile calls of the native device itself (non-finite and huge values, soft masks at the edges of the integer range, long clip chains, 5000 random calls) are in `TPdfNativeHostileTests` (`src\Render\Native\Pdf4D.Render.Native.Device.Hostile.Tests.pas`).

A run that hits the time limit keeps its thread, so the process can crash when it ends; the failure is reported before that.

## Viewer robustness and performance

`TestMutatedCorpusInViewer` in `Pdf4D.Tests.Robustness.Tests` gives the mutated corpus (the seeds of the first fuzz test) to a viewer session with the recording backend: the tiles at scale 0.5, the text and a hit test on 20 points of every page (the first 10) and one search. The work is `TFuzzWork.Viewer`; the probe is `TViewerFuzzProbe` in `tests\Support\Pdf4D.Tests.ViewerFuzz.pas`, which the test sets in `TFuzzViewing.Probe`. The `PDF4D_FUZZ_*` variables apply to it as to the other runs. `TestCachesStayWithinBudget` scrolls and zooms a document of 1000 pages and checks the tile, thumbnail and page text caches against their maximum.

The performance tests are in `tests\Vcl\Acceptance\Pdf4D.Tests.VclPerformance.Tests.pas` (the VCL test project, Skia backend). They measure only in a Release build; in a Debug build they end as passed without measuring. The limits are the constants at the top of the unit: the first page of an invoice (median of 5 runs per invoice of `tests\corpus\generated\invoices`), a mouse move with the hover on (median of 200) and the paint of the page view with the hover frame, and the longest `WM_VSCROLL` message while scrolling a document of 200 pages. Every run appends the measurements to `pdf4d-vcl-performance.txt` in the temporary folder of the user. The FMX project has the same tests in `tests\FMX\Acceptance\Pdf4D.Tests.FmxPerformance.Tests.pas`, with the same limits and `pdf4d-fmx-performance.txt` for the measurements (see "The FMX tests"). `TestGdiObjectsStayWithinBudget` pins the number of GDI objects that the tiles take. `Pdf4D.Tests.VclViewerFlows.Tests` runs the whole way through a viewer in one test: open, hover, click, mark, scroll into view, zoom, rotate, search, print to bitmaps and close.

## Test fonts

`tests\Fonts` holds the fonts that the font tests load (two TrueType fonts, two CFF OpenType fonts and two Type 1 `.pfb` fonts), with `manifest.csv` (file, source, licence, notes) and, per font, a `<font>.widths.txt` with the PDFBox 3.0.8 widths and Unicode values that the tests compare with. The widths files are generated by `tools\oracle\generate-font-widths.ps1`; fetch missing fonts with `tools\corpus\fetch-fonts.ps1`. The text goldens use an empty font provider, so they do not depend on the fonts installed on the machine.

## Oracle modes

The golden files in `tests\golden` are written by the PDFBox 3.0.8 oracle. `tools\oracle\generate-golden.ps1` takes `-Mode Dump` (the structure dump, `*.dump.txt`), `-Mode Text` (the text dump, `*.text.txt`), `-Mode Positions` (the line positions, `*.positions.txt`) or `-Mode All` (the default, all three), and `-Filter` for part of the corpus. Without a filter the script first removes the files of the chosen modes. The formats are in `golden-format.md`. The comparison of the text goldens counts sections that are only equal after white space is ignored; set `PDF4D_TEXT_LENIENT_REPORT` to a file name to get one line per such section.

The other oracle modes (`Pdf4DOracle.java`) and the scripts that run them, all with the pinned JDK of `tools\oracle\fetch-jdk.ps1`:

| Script | Oracle mode | Writes |
|---|---|---|
| `generate-colors.ps1` | `--color-batch` | `tests\reference\color`: `DeviceCMYK` and the ICC profiles of `tests\icc` through `ICC_ColorSpace.toRGB` |
| `generate-color-spaces.ps1` | `--color-pdf-batch` | `tests\reference\color-spaces`: the colour spaces of `colorspaces.pdf` |
| `generate-functions.ps1` | `--function` | `tests\reference\functions`: PDF functions of `tools\oracle\function-specs` |
| `generate-images.ps1` | `images` | `tests\reference\images`: `PDImageXObject.getImage()` of the images of the selected pages |
| `generate-font-widths.ps1` | `--font-widths`, `--glyph-paths`, `--pdf-glyph-paths` | `tests\fonts`: widths, Unicode values and glyph paths of the test fonts |
| `generate-render.ps1` | `render` | `tests\reference\render`: the pages as `PDFRenderer` draws them (next section) |
| `generate-render-tests.ps1` | `make-render-tests` | `tests\corpus\generated\render`: the synthetic render test files (with `make-render-pdfs.py`, `make-render-tests.py` and `make-jpeg-tests.py`) |

Run `generate-golden.ps1 -Mode All -Filter <path>` for every new corpus file as well; the formats are in `golden-format.md`. `tools\fetch-pdfjs-src.ps1` downloads the `jpg.js` of pdf.js (the tag is pinned in the script) into `tools\pdfjs-src`, which is ignored by git; the JPEG decoder is ported from it, and the file is only needed to review that port.

## Render reference images

`tools\oracle\generate-render.ps1 -Dpi 72` writes the PDFBox renders of every corpus page to `tests\reference\render\72` (about 45 MB, in plain git) and `-Dpi 150` those of `tests\reference\render\150\selection.txt`; `tools\oracle\generate-render-tests.ps1` writes the synthetic render test files. `PDF4D_RENDER_OUTPUT` names a folder where `Pdf4D.Skia.Tests` writes the Pdf4D render and a difference image of every page that differs from its reference, and the files `summary.txt`, `distribution.txt`, `region.txt` and `performance.txt`; `PDF4D_RENDER_FILTER` (substrings of corpus paths, separated by semicolons) limits the comparison to the matching files. The format and the comparison are in `golden-format.md`.

## Native determinism and performance

`tests\Acceptance\Pdf4D.Tests.RenderPerformance.Native.Tests.pas` (core test project) checks the native backend three ways. `TestRenderTwiceIsByteIdentical` renders a page, another page and the first page again and compares the bytes. `TestNativeHashesMatch` renders every page of `generated/render/*.pdf` and of the invoices at 72 DPI and compares the SHA-256 of the pixels with `tests\reference\render\native-hashes.txt` (lines `<corpus file> page <n> <sha256>`; a line that starts with `[Linux64] ` is the hash for Linux64 alone, with the reason after the hash). On Win64 and Linux64 a difference fails; on Win32 it is only reported. `TRenderPerformanceNativeTests.TestInvoiceFirstPage` renders the first page of every invoice at 96 DPI five times and holds the median to a threshold; it measures only in a Release build on Win64. The hashes are made on Win64: set `PDF4D_NATIVE_HASHES_WRITE=1` and run `TNativeRenderDeterminismTests.TestNativeHashesMatch`, which then writes the file instead of reading it; read the diff before it is committed (a changed hash is a changed pixel). With `PDF4D_RENDER_OUTPUT` set, the time of every hashed page goes to `native-page-times.txt` and the medians of the invoices to `performance-native.txt` in that folder. A line of the hash file that no rendered page has fails the test, and writing the file keeps the `[Linux64]` lines of the pages that are still rendered. The median threshold of `TestInvoiceFirstPage` is 250 ms (the slowest invoice takes about 50 ms on an idle machine).

`TPdfNativeHostileTests.TestWorstCaseOfTheEdgeWalkIsBounded` (core test project, `Pdf4D.Render.Native.Device.Hostile.Tests`) draws paths with as many segments as `MaxPathVerbs` allows (about 25 s and 1.5 GB), so it is a stress run: it ends as passed without doing anything unless the environment variable `PDF4D_STRESS` is set. Run it on its own, in Release, for example `$env:PDF4D_STRESS = 1; ./build.ps1 -Platform Win64 -Config Release -Suite Pdf4D.Tests -Fixtures Pdf4D.Render.Native.Device.Hostile.Tests.TPdfNativeHostileTests`. The limit of the work of the edge walk itself (`MaxEdgeWork` of `TPdfNativeLimits`) is tested in the default run with a lowered limit.

## tiny-skia source

`tools\fetch-tiny-skia-src.ps1` downloads the tiny-skia `v0.12.0` source archive from GitHub, checks its SHA-256 (a constant in the script) and extracts it to `tools\tiny-skia-src` (ignored by git), with a `VERSION.txt` that names the tag and the hash. The native rasterizer is ported from it, and the file is only needed to review that port. With `-CopyTestImages` the script copies the reference images of tiny-skia (`tests\images`, without `gradients`) to `tests\reference\tiny-skia` (about 63 KB of PNG files in plain git); the tests of the port compare against them.

## Invoice PDFs

`tests\corpus\generated\invoices` holds the same fictional invoice (Quillon Harbor Trading Ltd, INV-2031-0417; all names, addresses and amounts are invented) as made by every producer that is installed: `tools\invoices\generate-invoices.ps1` runs Microsoft Edge headless on `tools\invoices\invoice.html`, the Delphi program `tools\invoices\Pdf4D.InvoiceGen.dpr` (Skia `TSkDocument.MakePDF`, tooling and not part of the library; it needs RAD Studio and builds for Win64 only), Microsoft Word through COM (`tools\invoices\word-convert.ps1`: `ExportAsFixedFormat`, and a print to the Microsoft Print to PDF printer) and LibreOffice (`soffice --convert-to pdf`). A producer that is not installed is skipped with a warning. The script neutralises the account name that Microsoft Print to PDF writes into `/Author`, checks every file for the user name, the full name of the account and the machine name, and writes the manifest rows (licence `CC0 (generated)`). Afterwards run `tools\oracle\generate-golden.ps1 -Filter generated/invoices` and `tools\oracle\generate-render.ps1 -Dpi 72 -Filter generated/invoices` (and `-Dpi 150`).

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

## Delphi 12

Pdf4D needs Delphi 12 or newer, but every build and test so far was done with Delphi 13. Do this checklist on the first machine with Delphi 12 and write down what differs; new differences are noted, not fixed in the same step.

1. Open `packages\Pdf4D.groupproj` and build all three packages (`Pdf4D`, `Pdf4D.Render`, `Pdf4D.Render.Skia`) for Win32 and Win64, without hints or warnings (`build.ps1` is written for Delphi 13 and calls `rsvars.bat` of Studio 37.0; point it at Studio 23.0 or build in the IDE).
2. Check that the Skia package is called `Skia.Package.RTL` in Delphi 12, as `Pdf4D.Render.Skia.dpk` requires.
3. Build and run `tests\Pdf4D.Tests.dproj` and `tests\Skia\Pdf4D.Skia.Tests.dproj`, the second one with the `sk4d.dll` of Delphi 12 (`Redist\win64\sk4d.dll` of that installation, next to the test program).
4. Run the reference tests (the render comparison with the PDFBox images, `TRenderGoldenTests`) on Win64 and compare the number of pages that differ with Delphi 13 (612 of 617 pages equal at 72 DPI, 19 of 22 at 150 DPI). The Skia version is another one, so pages can differ at the edges; note the new differences and do not fix them in this step.
5. For every `System.Skia` API that the backend uses outside the list of the next section, check that it exists in Delphi 12 (the lines below say which ones those are and what the replacement is).

### Delphi 12: the viewer (phase 3)

Do this too on the first machine with Delphi 12, and write down what differs.

1. Open `packages\Pdf4D.groupproj` and build `Pdf4D.Viewer`, `Pdf4D.Vcl`, `Pdf4D.Vcl.Skia` and `dclPdf4D.Vcl` for Win32 and Win64, without hints or warnings.
2. Install `dclPdf4D.Vcl`: all components are on the `Pdf4D` palette page with their icons, and the actions are in the action list editor under `Pdf4D`.
3. Build `tests\Vcl\Pdf4D.Vcl.Tests.dproj` and run it with the `sk4d.dll` of Delphi 12 next to the program.
4. Build the demo and go through the steps of the README use case (field gets the focus, marker and scroll, click fills the field), also after dragging the window to a screen with another scale (the manual check in "The demo").
5. Check that `GroupDescendentsWith`, `ScaleForPPI` and `ChangeScale(M, D, isDpiChange)` behave in Delphi 12 as in Delphi 13: `Pdf4D.Vcl.Registration` calls `GroupDescendentsWith` for the three non-visual components (so that they show on the palette of a VCL form and not of an FMX form: check both), the VCL tests use `ScaleForPPI` for the DPI tests, and the page view relies on `isDpiChange` and the new scale `M` of `ChangeScale`.

### Delphi 12: the FMX viewer (phase 4)

Do this too on the first machine with Delphi 12, and write down what differs.

1. Build `Pdf4D.FMX`, `Pdf4D.FMX.Skia` and `dclPdf4D.FMX` for Win32 and Win64 without hints or warnings.
2. Install `dclPdf4D.Vcl` and `dclPdf4D.FMX` together and check the palette per framework: a VCL project shows the VCL components on the `Pdf4D` page, an FMX project the FMX components (see "The FMX design-time package"). This needs a person at the IDE; it has not been done yet.
3. Build `tests\FMX\Pdf4D.FMX.Tests.dproj` and run it with the `sk4d.dll` of Delphi 12 next to the program.
4. Go through the FMX demo at 100 % and at 150 % scale, also after dragging the window to another screen (the manual check in "The demo"): the page stays sharp, the marker sits on the text, the current page and the zoom do not change.
5. Check in Delphi 12 the FMX APIs that were taken from the FMX source of Delphi 13 and have not been run on Delphi 12: the scale of the canvas (`Canvas.Scale`, `IFMXScreenService`), a message for a change of scale (`TScaleChangedMessage`), the printer resolution (`Printer.ActivePrinter.ActiveDPI`), the masking of `InputQuery` (the prompt that starts with `#31`) and the setup dialog of the printer.
6. Run `TestRealPrinter` in `Pdf4D.FMX.Print.Tests` with `PDF4D_TEST_PRINTER` set to `Microsoft Print to PDF` (it runs unattended, see "The FMX tests") and, on a desktop session, with a physical printer: look at the pages that come out. On Delphi 13 the unattended run was done on Windows 11 and found nothing to fix; on Delphi 12 and on a physical printer it has not been done yet.

### The design-time package

`dclPdf4D.Vcl.dpk` is `{$DESIGNONLY}`. It registers the components on the `Pdf4D` palette page (`TPdf4DDocument`, `TPdf4DSkiaBackend`, `TPdf4DPageView`, `TPdf4DThumbnails`, `TPdf4DOutlineView`, `TPdf4DSearchBar`, `TPdf4DToolbar`, `TPdf4DViewer`, `TPdf4DPrintDialog`), the standard actions of `Pdf4D.Vcl.Actions` and a file dialog for the `FileName` of a document. The palette icons are drawn by `tools\make-palette-icons.ps1` (PNG files in `src\Vcl\Design\icons` and the linked `Pdf4D.Vcl.Palette.res`; the bitmaps are named after the class, `TPDF4DVIEWER` for 24 pixels and `TPDF4DVIEWER16` and `TPDF4DVIEWER32` for the other sizes, as the packages of the IDE itself name theirs) and are placeholders. `build.ps1` builds the package but nothing in the test run loads it: the registration needs the IDE. The IDE of Delphi 13 is a 64-bit program and loads the Win64 build; a 32-bit IDE needs the Win32 build, which the project is set up for but which has not been built or installed here.

Check by hand, once per Delphi version:

1. Open `packages\Pdf4D.groupproj`, build everything and install `dclPdf4D.Vcl` (right-click, Install).
2. On a new VCL form drop a `TPdf4DViewer`, a `TPdf4DDocument` and a `TPdf4DSkiaBackend` from the `Pdf4D` page, link the viewer and the backend to the document, pick a PDF in `FileName` with the dialog and run the application with `sk4d.dll` next to it.
3. Check that the three icons appear on the palette (16, 24 and 32 pixels), and that the actions show in the action list editor under the category `Pdf4D`.

### The FMX design-time package

`dclPdf4D.FMX.dpk` is `{$DESIGNONLY}` and registers the same components and actions (those of `Pdf4D.FMX.*`) on the same `Pdf4D` palette page as `dclPdf4D.Vcl`, with `GroupDescendentsWith(<non-visual class>, FMX.Controls.TControl)` for the three non-visual components, and a file dialog (`FMX.Dialogs`) for the `FileName` of a document. It links the palette bitmaps of the VCL package as a copy (`src\FMX\Design\icons\Pdf4D.FMX.Palette.res`; `tools\make-palette-icons.ps1 -FmxResourceFile` writes both). `build.ps1` builds it like `dclPdf4D.Vcl`; nothing in the test run loads it.

Check by hand, once per Delphi version, with `dclPdf4D.Vcl` and `dclPdf4D.FMX` installed together:

1. Install both packages: there is no name conflict message, and the IDE loads both.
2. In a VCL project the `Pdf4D` page holds only the VCL components; in an FMX project only the FMX components. The actions show in the action list editor under `Pdf4D` in both kinds of project.
3. On an FMX form drop a `TPdf4DViewer`, a `TPdf4DDocument` and a `TPdf4DSkiaBackend`, link them, pick a PDF in `FileName` and run the application with `sk4d.dll` next to it.
4. On a VCL form, with both packages still installed, pick a PDF in `FileName` of a `TPdf4DDocument`: the VCL file dialog opens, not the FMX one. Each package registers its editor for its own `TPdf4DDocument` class, so the load order does not matter, but this is checked only here.

This IDE check is open for Delphi 13 (the IDE of the build machine) as well as for Delphi 12: neither has been done.

### Skia API of the backend

The Skia code only uses `System.Skia` API that Delphi 12 and 13 share, and it has not been compiled with Delphi 12. Every use of something outside this list gets a line below.

- `TSkSurface.MakeRaster`, `ISkSurface.Canvas`, `ISkSurface.MakeImageSnapshot`, `ISkImage.ReadPixels`.
- `ISkCanvas`: `Save`, `Restore`, `RestoreToCount`, `SetMatrix`, `Concat`, `ClipPath`, `DrawPath`, `DrawImageRect`, `Clear`, `SaveLayer`.
- `TSkPathBuilder` (`MoveTo`, `LineTo`, `QuadTo`, `CubicTo`, `Close`, `Detach`, `FillType`), `TSkPaint` (`Style`, `StrokeWidth`, `StrokeCap`, `StrokeJoin`, `StrokeMiter`, `Color`, `Alpha`, `AntiAlias`, `Shader`, `PathEffect`).
- `TSkPathEffect.MakeDash`, `TSkImage.MakeRasterCopy`, `ISkImage.MakeShader`, `TSkSamplingOptions` (also `Create(TSkCubicResampler.Mitchell)`), `TSkBlendMode`, `TSkTileMode`.

Also used, outside that list:

- Blend modes use `ISkPaint.Blender` with `TSkBlender.MakeMode(TSkBlendMode)`, not a `BlendMode` property: Delphi 13 has no `ISkPaint.BlendMode`. Check on the first Delphi 12 build that `Blender` and `TSkBlender.MakeMode` exist there (Skia4Delphi 6 has them); if not, `ISkPaint.BlendMode` is the replacement.
- Soft masks and layers: `ISkCanvas.SaveLayer(Bounds, Paint)`, `ISkCanvas.DrawImage(Image, X, Y, Sampling, Paint)`, `TSkBlendMode.DestIn`, `TSkBlendMode.Hue`, `Saturation`, `Color`, `Luminosity` (the four non-separable modes), `System.Skia` only.
- `TSkImageInfo.Create(Width, Height, ColorType, AlphaType)` and the enums `TSkColorType`, `TSkAlphaType`, `TSkPaintStyle`, `TSkStrokeCap`, `TSkStrokeJoin`, `TSkPathFillType`, `TSkClipOp`, `TSkFilterMode`, `TSkMipmapMode`: the types that the listed calls take. They are expected to exist in Delphi 12 (step 5 of the checklist).
- `TMatrix` from `System.Math.Vectors` as the matrix type of `SetMatrix` and `MakeShader`.
- The package `Skia.Package.RTL` in the `requires` clause of `Pdf4D.Render.Skia.dpk`. The Skia package has had this name since Delphi 12; check it when the first Delphi 12 build is made.
- `TSkSurface.MakeRaster` with `TSkColorType.RGBA8888` and `TSkAlphaType.Premul` is assumed to give the byte order R, G, B, A on every platform; `TestToBitmapIsPremultipliedRgba` checks it.
