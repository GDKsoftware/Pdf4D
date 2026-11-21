# Pdf4D

Pdf4D is a native Delphi port of the reading side of [Apache PDFBox](https://pdfbox.apache.org/) 3.0.8: document structure, pages, outlines, form fields, attachments and text extraction. It renders pages to bitmaps with the same rules as PDFBox's `PDFRenderer`. It does not write PDF files. The core has no dependencies besides the Delphi RTL; rendering with the Skia backend also needs the Skia library that ships with RAD Studio.

## Platforms

- Delphi 12 or newer. Built and tested on Delphi 13 (Studio 37.0); not yet verified on Delphi 12.
- Win32, Win64 and Linux64
- RTL only: no `Winapi.*`, `Vcl.*` or `FMX.*` units and no inline assembler. Only the Skia backend uses `System.Skia`.

## Status

Milestone M1 (document structure) is complete: loading, decryption, pages, document information, outlines, form fields, attachments and the public API.

Milestone M2 (text extraction) is complete: `ExtractText` on a document or a page, with the options of PDFBox's `PDFTextStripper`. All 188 files of the test corpus give the same text as PDFBox 3.0.8, except 6 with documented differences (five with right-to-left text, one where Pdf4D is more lenient than PDFBox). Limits on hostile input and the other deviations are in `docs/porting.md`.

Milestone M3, phase 2 (rendering) is complete: `TPdfRenderer` draws a page into a bitmap through a device interface, and `TPdfSkiaBackend` implements it with Skia. Of the 617 corpus pages that PDFBox 3.0.8 renders at 72 DPI, 612 are equal to its images within the tolerances of `docs/golden-format.md` and 5 have a documented difference; at 150 DPI 19 of 22 pages are equal. Annotations without an appearance stream are not drawn (`constructAppearances` is not ported); see `docs/porting.md` for this and the other deviations. The viewer and the visual components are not part of this phase.

See also `coding-rules.md` and `docs/building.md`.

## Usage

```delphi
uses
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Page.Interfaces;

begin
  const Document = TPdfDocument.Load('invoice.pdf');
  Writeln(Document.Info.Title, ', ', Document.PageCount, ' pages');

  for var Page in Document.Pages do
  begin
    Writeln(Page.Index, ': ', Page.MediaBox.Width:0:0, ' x ', Page.MediaBox.Height:0:0);
  end;

  for var Attachment in Document.Attachments do
  begin
    Writeln(Attachment.FileName, ': ', Length(Attachment.Data), ' bytes');
  end;
end;
```

The interfaces keep the document alive: a page, an outline item, a field or an attachment stays valid after the
`IPdfDocument` reference is released, and the file is closed when the last reference is gone. A file that cannot be
opened or parsed raises an `EPdfException` descendant. `CosDocument` and the `CosObject` functions give access to the
inner layer; what they return is valid only while an interface of the document is alive.

## Extracting text

```delphi
uses
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.TextOptions,
  System.RegularExpressions;

begin
  const Document = TPdfDocument.Load('invoice.pdf');
  const Text = Document.ExtractText;
  Writeln(Text);

  // The options are those of PDFBox's PDFTextStripper, with the same defaults
  var Options := TPdfTextOptions.Default;
  Options.SortByPosition := True;
  Options.StartPage := 2;
  Options.EndPage := 3;
  Writeln(Document.ExtractText(Options));

  // One page only
  Writeln(Document.Page(0).ExtractText);

  // The same text with the place of every character. Text.Locate takes a 1-based range, like Match.Index.
  const Positioned = Document.Page(0).ExtractTextWithPositions;
  const Match = TRegEx.Match(Positioned.Text, '\d{4}-\d{4}');
  if Match.Success then
  begin
    for var Fragment in Positioned.Locate(Match.Index, Match.Length) do
      Writeln(Fragment.PageIndex, ': ', Fragment.Quads[0].Bounds.Left:0:2);
  end;
end;
```

`ExtractTextWithPositions` (on a document or a page) returns the same text and, per range, the quads of its characters, one per line, in PDF user space. `Page(n).TextLayout` gives the words, segments and lines of a page, with `TryFindSegmentAt` and `TryFindWordAt` for hover.

The text is what PDFBox's `PDFTextStripper` writes, with one deviation: right-to-left text (Hebrew, Arabic) comes in the
order of the file, because there is no bidi pass. See `docs/porting.md`.

Fonts that are not embedded are looked up among the standard 14 fonts (their metrics are part of the library), then among the fonts installed on the system (the font folders are scanned once, headers only, and nothing is written to disk). When no font matches, Pdf4D falls back to LiberationSans, which is part of the library, as PDFBox does.

One page has a budget of operators and glyphs, so that a hostile file ends in bounded time. The defaults are large (10 million operators and 2 million glyphs); a caller who wants a shorter worst case lowers `MaxOperatorsPerPage` and `MaxGlyphsPerPage` in `TPdfLoadOptions` and passes it to `TPdfDocument.Load`. See `docs/porting.md` for all limits.

## Rendering

```delphi
uses
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.Skia.Backend;

begin
  const Document = TPdfDocument.Load('invoice.pdf');
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TPdfSkiaBackend.Create);

  var Bitmap: TPdfBitmap;
  if Renderer.RenderToBitmap(0, TPdfRenderParams.FromDpi(96), Bitmap) = TPdfRenderStatus.Completed then
  try
    // Bitmap.Pixels: premultiplied RGBA, 8 bits per channel, rows from top to bottom, Bitmap.Stride bytes per row
    Writeln(Bitmap.Width, ' x ', Bitmap.Height);
  finally
    Bitmap.Free;
  end;
end;
```

`RenderToBitmap` draws the whole page with a white background and anti-aliasing, like `PDFRenderer.renderImage` of PDFBox with `ImageType.RGB`. The other fields of `TPdfRenderParams` choose a region of the page, an extra rotation, a cancel token (the only thing that may be used from another thread) and the options (destination, background, annotations and the limits of `docs/porting.md`). A renderer is used by one thread at a time, the one that uses the document.

The renderer is split over three packages next to the core package `Pdf4D`:

| Package | Contents | Needs |
|---|---|---|
| `Pdf4D` | document, pages, text extraction | RTL |
| `Pdf4D.Render` | the renderer, the colour spaces, images, shadings and patterns, the JPEG and CCITT decoders, the device interface | `Pdf4D` |
| `Pdf4D.Render.Skia` | `TPdfSkiaBackend`, built on `System.Skia` | `Pdf4D`, `Pdf4D.Render`, `Skia.Package.RTL` |

The core does not need Skia. The Skia backend needs the Skia library next to the program: `sk4d.dll` on Windows (`Redist\win32` or `Redist\win64` of RAD Studio) and `libsk4d.so` on Linux64. An application that brings its own backend (anything that implements `IPdfRenderBackend`) uses `Pdf4D.Render` without `Pdf4D.Render.Skia` and without Skia. See `docs/building.md`.

## What the resources add

The glyph lists, the AFM metrics of the standard 14 fonts, the predefined CMaps and LiberationSans-Regular are linked into the binary as compressed resources, so nothing has to be installed next to the program. Together they add about 1.6 MB (compressed) to an executable. Licences and sources are in `NOTICE`, `licenses/` and `src/Resources/resources.csv`.

A document is not thread-safe, but different documents can be used in different threads. Input problems (the file or its
content) raise `EPdfException` descendants; invalid arguments raise `EArgument*` exceptions. A bookmark option
(`StartBookmark`, `EndBookmark`) that belongs to another document, or that this library did not make, raises
`EArgumentException`. An exception of the `TTextWriter` that you give to `WriteText` is raised as it was, with its own
class and message.

## Building and testing

```powershell
./build.ps1 -Platform All
```

The script builds the three packages and both test projects (`tests/Pdf4D.Tests.dproj` without Skia, `tests/Skia/Pdf4D.Skia.Tests.dproj` with it) and runs them; see `docs/building.md`.

## License

Apache License 2.0, see `LICENSE` and `NOTICE`. Pdf4D is a derived work of Apache PDFBox.
