# Pdf4D

Pdf4D is a native Delphi port of the reading side of [Apache PDFBox](https://pdfbox.apache.org/) 3.0.8: document structure, pages, outlines, form fields, attachments and text extraction. It renders pages to bitmaps with the same rules as PDFBox's `PDFRenderer`. It does not write PDF files. The core has no dependencies besides the Delphi RTL; rendering with the Skia backend also needs the Skia library that ships with RAD Studio.

## Platforms

- Delphi 12 or newer. Built and tested on Delphi 13 (Studio 37.0); not yet verified on Delphi 12.
- Win32, Win64 and Linux64
- RTL only for the core, the renderer and the viewer core: no `Winapi.*`, `Vcl.*` or `FMX.*` units and no inline assembler. Only the Skia backend (and its VCL component) uses `System.Skia`. The VCL components are for Win32 and Win64.

## Status

Milestone M1 (document structure) is complete: loading, decryption, pages, document information, outlines, form fields, attachments and the public API.

Milestone M2 (text extraction) is complete: `ExtractText` on a document or a page, with the options of PDFBox's `PDFTextStripper`. All 188 files of the test corpus give the same text as PDFBox 3.0.8, except 6 with documented differences (five with right-to-left text, one where Pdf4D is more lenient than PDFBox). Limits on hostile input and the other deviations are in `docs/porting.md`.

Milestone M3, phase 2 (rendering) is complete: `TPdfRenderer` draws a page into a bitmap through a device interface, and `TPdfSkiaBackend` implements it with Skia. Of the 617 corpus pages that PDFBox 3.0.8 renders at 72 DPI, 612 are equal to its images within the tolerances of `docs/golden-format.md` and 5 have a documented difference; at 150 DPI 19 of 22 pages are equal. Annotations without an appearance stream are not drawn (`constructAppearances` is not ported); see `docs/porting.md` for this and the other deviations. The viewer and the visual components are not part of this phase.

Milestone M3, phase 3 (the viewer and the VCL components) is complete: a viewer core without a framework (`Pdf4D.Viewer`) and the VCL components on top of it, see "Viewer (VCL)". The FMX components are described under "Viewer (FMX)"; the own rasterizer comes in phase 5.

Milestone M3, phase 4 (the FMX components) is complete and tested on Win64: the same viewer in FMX forms on top of the viewer core, see "Viewer (FMX)". The build and tests on Win32 and Linux64, the installation of both design-time packages in the IDE and the check on a real printer are still to be done (see `docs/building.md`). The own rasterizer comes in phase 5.

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

The own rasterizer, a Delphi port of tiny-skia, needs no library next to the program; it is also what the viewers use when the application sets no backend:

```delphi
uses
  Pdf4D.Render.Native.Backend;

const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TPdfNativeBackend.Create);
```

`RenderToBitmap` draws the whole page with a white background and anti-aliasing, like `PDFRenderer.renderImage` of PDFBox with `ImageType.RGB`. The other fields of `TPdfRenderParams` choose a region of the page, an extra rotation, a cancel token (the only thing that may be used from another thread) and the options (destination, background, annotations and the limits of `docs/porting.md`). A renderer is used by one thread at a time, the one that uses the document.

The renderer is split over three packages next to the core package `Pdf4D`:

| Package | Contents | Needs |
|---|---|---|
| `Pdf4D` | document, pages, text extraction | RTL |
| `Pdf4D.Render` | the renderer, the colour spaces, images, shadings and patterns, the JPEG and CCITT decoders, the device interface | `Pdf4D` |
| `Pdf4D.Render.Skia` | `TPdfSkiaBackend`, built on `System.Skia` | `Pdf4D`, `Pdf4D.Render`, `Skia.Package.RTL` |

The core does not need Skia. The Skia backend needs the Skia library next to the program: `sk4d.dll` on Windows (`Redist\win32` or `Redist\win64` of RAD Studio) and `libsk4d.so` on Linux64. An application that brings its own backend (anything that implements `IPdfRenderBackend`) uses `Pdf4D.Render` without `Pdf4D.Render.Skia` and without Skia. See `docs/building.md`.

## Viewer (VCL)

The viewer shows a PDF in a VCL form: continuous or single-page scrolling, zoom and rotation, thumbnails and outline, hover and text selection, links, search, copy to the clipboard and printing. Everything that is not VCL (layout, tiles and their cache, hit testing, search, the rules of the commands, the print plan) is in the viewer core `Pdf4D.Viewer`, which a later FMX version shares. A document is rendered on a worker thread; the UI thread only paints bitmaps.

| Package | Contents | Needs |
|---|---|---|
| `Pdf4D.Viewer` | the viewer core: types, view transform, layout, tiles, controllers, search, print plan, the document session | `Pdf4D`, `Pdf4D.Render` |
| `Pdf4D.Vcl` | `TPdf4DDocument`, `TPdf4DPageView`, `TPdf4DThumbnails`, `TPdf4DOutlineView`, `TPdf4DSearchBar`, `TPdf4DToolbar`, `TPdf4DViewer`, `TPdf4DPrintDialog` and the standard actions | `vcl`, `Pdf4D.Viewer` |
| `Pdf4D.Vcl.Skia` | the component `TPdf4DSkiaBackend` | `Pdf4D.Vcl`, `Pdf4D.Render.Skia` |
| `dclPdf4D.Vcl` | design time: the `Pdf4D` palette page, the actions in the action list editor, a file dialog for `FileName` | `designide`, `Pdf4D.Vcl`, `Pdf4D.Vcl.Skia` |

`TPdf4DViewer` is the whole viewer in one component (toolbar, search bar, side panel, page view); the parts can also be used on their own, all following one `TPdf4DDocument`. Without a backend the viewers render with the own rasterizer (`TPdfNativeBackend`), which needs no DLL. Skia is a choice for those who ship the library: drop a `TPdf4DSkiaBackend` on the form and link it to the `Backend` property of the document, or set `RenderBackend` of the document in code to any `IPdfRenderBackend`; an explicit backend is always used as it is. The Skia backend needs `sk4d.dll` next to the program (`Redist\win32` or `Redist\win64` of RAD Studio); `Pdf4D.Vcl` itself does not link Skia.

```delphi
Pdf4DDocument1.Backend := Pdf4DSkiaBackend1;
Pdf4DViewer1.Document := Pdf4DDocument1;
Pdf4DDocument1.FileName := 'invoice.pdf';
Pdf4DDocument1.Open;

// In OnOpened or when a field gets focus. FDocument is the application's own IPdfDocument of the same file
// (TPdfDocument.Load); the viewer's document lives on its worker and is never used from the UI thread.
const Text = FDocument.Page(0).ExtractTextWithPositions;
const Match = TRegEx.Match(Text.Text, '\d{4}-\d{4}');
if Match.Success then
begin
  for var Fragment in Text.Locate(Match.Index, Match.Length) do
  begin
    // The ellipse is filled: use a translucent colour to keep the text under it readable
    Pdf4DDocument1.Overlays.Add(Fragment.PageIndex, Fragment.Quads, TPdfOverlayStyle.Ellipse, TAlphaColor($66FF0000));
    Pdf4DViewer1.PageView.ScrollIntoView(Fragment.PageIndex, Fragment.Quads);
  end;
end;
```

`demos\Vcl\Pdf4DInvoiceDemo.dproj` is a complete example: an invoice form on the left and the viewer on the right. A field that gets the focus is looked up in the text of the PDF and marked there, a click on a word in the PDF fills the field that has the focus. It runs Per-Monitor v2 and opens the file given on the command line (`Pdf4DInvoiceDemo.exe invoice.pdf`) or through the Open button. `tests\corpus\generated\invoices\skia-draw.pdf` is an invoice with invented data that fits the default values of the form.

What the viewer does not do (yet): selection across pages, searching across a page boundary or with regular expressions, hit testing on annotations other than links, filling in forms, saving markings, screen readers and right-to-left text, vector printing (it prints raster) and a visible focus frame and keys in the thumbnails. A document that is opened from a file and needs a password gets a question for it (three tries); a document that is opened from a stream does not, because the document does not keep the data: `OnOpenError` reports `InvalidPassword` and the application sets `Password` and opens the stream again. The events that the viewer forwards (`OnTextSelected`, `OnHoverChanged`, `OnLinkClick`) have its page view as `Sender`.

## Viewer (FMX)

The FMX viewer has the same components, properties and behaviour as the VCL viewer (continuous or single-page scrolling, zoom and rotation, thumbnails and outline, hover and text selection, links, search, copy and printing), on the same viewer core `Pdf4D.Viewer`. It is for Windows (Win32 and Win64; so far built and tested on Win64); other FMX platforms and touch gestures are not part of this phase. The scale of the screen is the scale of the form: a page is rendered at the pixels of the device, so it stays sharp on a 150 % screen and after a move to another screen.

| Package | Contents | Needs |
|---|---|---|
| `Pdf4D.FMX` | `TPdf4DDocument`, `TPdf4DPageView`, `TPdf4DThumbnails`, `TPdf4DOutlineView`, `TPdf4DSearchBar`, `TPdf4DToolbar`, `TPdf4DViewer`, `TPdf4DPrintDialog` and the standard actions | `fmx`, `Pdf4D.Viewer` |
| `Pdf4D.FMX.Skia` | the component `TPdf4DSkiaBackend` | `Pdf4D.FMX`, `Pdf4D.Render.Skia` |
| `dclPdf4D.FMX` | design time: the `Pdf4D` palette page, the actions in the action list editor, a file dialog for `FileName` | `designide`, `Pdf4D.FMX`, `Pdf4D.FMX.Skia` |

Install `dclPdf4D.Vcl` and `dclPdf4D.FMX` together if you use both: each is meant to show its components on the `Pdf4D` page of its own kind of project (this has not been checked in the IDE yet). The backend is chosen like in VCL: without one the own rasterizer is used, and a `TPdf4DSkiaBackend` linked to `Backend` (or `RenderBackend` in code) selects Skia, which needs `sk4d.dll` next to the program. The example is that of the VCL viewer, with the colours of FMX:

```delphi
Pdf4DDocument1.Backend := Pdf4DSkiaBackend1;
Pdf4DViewer1.Document := Pdf4DDocument1;
Pdf4DDocument1.FileName := 'invoice.pdf';
Pdf4DDocument1.Open;

// In OnOpened or when a field gets focus. FDocument is the application's own IPdfDocument of the same file
// (TPdfDocument.Load); the viewer's document lives on its worker and is never used from the UI thread.
const Text = FDocument.Page(0).ExtractTextWithPositions;
const Match = TRegEx.Match(Text.Text, '\d{4}-\d{4}');
if Match.Success then
begin
  for var Fragment in Text.Locate(Match.Index, Match.Length) do
  begin
    // The ellipse is filled: use a translucent colour to keep the text under it readable
    Pdf4DDocument1.Overlays.Add(Fragment.PageIndex, Fragment.Quads, TPdfOverlayStyle.Ellipse, TAlphaColors.Red and $66FFFFFF);
    Pdf4DViewer1.PageView.ScrollIntoView(Fragment.PageIndex, Fragment.Quads);
  end;
end;
```

`demos\FMX\Pdf4DInvoiceDemoFmx.dproj` is the invoice demo as an FMX form.

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

The script builds the packages, compiles the demo (Windows only) and builds and runs the three test projects (`tests/Pdf4D.Tests.dproj` without Skia, `tests/Skia/Pdf4D.Skia.Tests.dproj` with it, `tests/Vcl/Pdf4D.Vcl.Tests.dproj` for the VCL components on Windows); see `docs/building.md`.

## License

Apache License 2.0, see `LICENSE` and `NOTICE`. Pdf4D is a derived work of Apache PDFBox.
