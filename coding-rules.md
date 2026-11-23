# Coding rules

Pdf4D follows the GDK Delphi rules. This file lists where it deviates. Where it conflicts with the standard rule set, this file wins.

## Exceptions

1. **`System.Generics.Collections` instead of Spring4D.** Overrides: "use Spring.Collections". Reason: the library has no dependencies besides the RTL.
2. **Objects with explicit ownership instead of interfaces in the inner layer** (`Cos`, `Parser`, `Filter`, `Crypto`, `Encryption`, `Model`, `Content`, `Font`, `FontBox`, `Text`), with `try..finally` where needed. Overrides: "use interface references for automatic memory management". Reason: the object graph has cycles (page and `/Parent`), which reference counting would leak. The public API layer (`Api`) does use interfaces.
3. **Method names in the inner layer follow PDFBox** (`GetDictionaryObject`, `ParseCosDictionary`). Overrides: naming for behaviour. Reason: the Delphi code can be laid next to the Java code, so upstream fixes can be carried over.
4. **`var` parameters only** where a ported algorithm has to update a position or state and that cannot be done through a field. Overrides: "no `var` parameters".
5. **Long ported methods may keep the PDFBox order** as long as they stay readable. Splitting into private methods is preferred. Overrides: method decomposition.
6. **Inline variables and `const` stay mandatory**, as in the GDK rules.
7. **Shared, lazily made objects go through `TPdfSharedInstance` and `TPdfSharedCache`.** A `class destructor` may free such an object. No `initialization` or `finalization` sections. Overrides: the GDK rule on singletons. Reason: thread-safe lazy publication and leak detection (an object that is filled once and freed at shutdown is no leak).
8. **A global `procedure Register` in `Pdf4D.Vcl.Registration`.** Overrides: no global procedures. Reason: the IDE calls it by name when it loads the design-time package `dclPdf4D.Vcl`; it is the only global procedure of the library.

## Additions

- Language level: Delphi 12. No Delphi 13-only syntax, such as the ternary `if` expression.
- Only `System.*` units in the library: the core, `Pdf4D.Render` and `Pdf4D.Viewer`. No `Winapi.*`, `Vcl.*`, `FMX.*` or inline assembler there. Exception: `src\Vcl` may use `Vcl.*` and `Winapi.*` (overrides: only `System.*` units), because it holds the VCL components; it does not use `FMX.*`. Events of components are `procedure of object` without `var` parameters.
- Every unit that ports PDFBox code names the PDFBox source files and the PDFBox version in its header.
- Zero hints and zero warnings on all platforms.
- Test hooks (`TPDFontFactory.CreatorOverride`, the setter of `TCMap.MappingLimit`) exist only when `PDF4D_TESTS` is defined. The define is set in the test projects only (`tests/Pdf4D.Tests.dproj`, `tests/Skia/Pdf4D.Skia.Tests.dproj` and `tests/Vcl/Pdf4D.Vcl.Tests.dproj`), so the packages, the library code and the demo never see the hooks.
- Layers of the renderer: the core (everything under `src` except `Graphics`, `Codec`, `Render` and `Resources\Pdf4D.Resources.Icc.*`) uses no unit from those folders, and only units under `src\Render\Skia` and `src\Vcl\Skia` use `System.Skia` or `Pdf4D.Render.Skia`. `src\Viewer` uses only `System.*` and `Pdf4D.*` units of the core and `Pdf4D.Render`, and the core and `src\Render` use no unit from `src\Viewer`. `build.ps1` checks these rules and fails on a violation.
- The renderer draws through `IPdfGraphicsDevice` and `IPdfRenderBackend` only; it never calls a backend library directly.
- Code that computes with floating point in the renderer and the Skia device runs inside `TPdfFloatGuard` (Skia masks all floating point exceptions of the process when it loads, Delphi raises on them) and uses `Single` with `{$EXCESSPRECISION OFF}`, as the text code does.
- The demos under `demos` follow the same rules (zero hints and warnings, built by `build.ps1`) and use the components through their public API only: a demo has no logic of its own for the viewer.
- A Skia call that is not in the list of `docs\building.md` ("Skia API of the backend") gets a line in the Delphi 12 checklist there.
- `Graphics`, `Codec` and `Render` follow exception 2 only for the objects that mirror the PDFBox object graph (the colour spaces and the page drawer); the device interface, the renderer and the bitmap use interfaces.
