# tiny-skia reference hashes

Optional. Needs a Rust toolchain (cargo). Not part of the build or the test run.

The stroker and dash tests of the native renderer (`TestRustReference*` in `Pdf4D.Render.Native.Stroker.Tests` and
`Pdf4D.Render.Native.Dash.Tests`) pin the FNV-1a hash of the verbs and the point bits that tiny-skia v0.12.0 produces. This small
program builds the same paths, strokes or dashes them with tiny-skia and prints the hashes next to the values pinned in the Delphi tests.

```
pwsh tools/fetch-tiny-skia-src.ps1
cd tools/tiny-skia-reference
cargo run --release
```

The program exits with 1 when a hash differs. To pin a new case, add it to `main.rs` and to the Delphi test with the printed value.
