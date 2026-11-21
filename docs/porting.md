# Porting from PDFBox

## Status

Milestone M1 (document structure) is complete: parsing with xref recovery, object streams, decryption (RC4 40/128, AES 128/256, revisions 2 to 6), the page tree, page boxes and labels, document information, outlines and destinations, name trees, form fields, embedded files and the public interface API. All 188 files of the test corpus load. 163 give a structure dump equal to the PDFBox 3.0.8 dump, 25 differ in documented ways (`tests/golden/*.known-differences.txt`, format in `golden-format.md`). Mutated corpus files only end in success or an `EPdfException` descendant and never hang (`tests/Acceptance/Pdf4D.Tests.Robustness.Tests.pas`).

Milestone M2 (text extraction) is complete: the content stream engine, the fonts (simple fonts, Type 0 with CID fonts, Type 3, the standard 14 fonts, embedded and system fonts through FontBox), the encodings, CMaps and glyph lists, and `PDFTextStripper` with its options (sorting, paragraph and article handling, page range, bookmarks, the `TTextWriter` output). It is reached through `IPdfDocument.ExtractText`, `IPdfPage.ExtractText` and `TPdfTextOptions`. The text goldens (`tests/golden/*.text.txt`) are written by the PDFBox 3.0.8 oracle with an empty font provider, so that they do not depend on installed fonts. They cover the same 188 files: every page (up to 50), the same pages sorted by position, and a page range.

- Number of files: all 188 files have a text golden and all 188 are compared.
- 182 files are equal to PDFBox.
- 6 files differ in documented ways (`tests/golden/*.text-known-differences.txt`): five files with right-to-left text because there is no bidi pass (`hello3.pdf`, `BidiSample.pdf`, `FC60_Times.pdf`, `PDFBOX-4531-bidi-ligature-1.pdf`, `PDFBOX-4531-bidi-ligature-2.pdf`), and page 4 of `PDFBOX-3950` (see the deviations).
- The comparison is lenient about white space: a section whose lines differ only in white space counts as equal, and is counted separately (`PDF4D_TEXT_LENIENT_REPORT` names a file that gets one line per such section). In the corpus that is two sections of one file (`PDFBOX-4531-bidi-ligature-2.pdf`, `default page 1` and `sorted page 1`), on all three platforms.

Generated and mutated input (content streams, font programs, CMaps, hostile documents) only ends in text or an `EPdfException` descendant and never hangs, leaks or runs out of memory (`Pdf4D.Tests.TextRobustness.Tests`; `building.md` describes larger sweeps).

Milestone M3, phase 2 (the renderer) is complete: `IPdfRenderer` (`TPdfRenderer`) draws a page of `IPdfDocument` through a device interface (`IPdfRenderBackend`, `IPdfGraphicsDevice`), the way `PDFRenderer` and `PageDrawer` draw through `Graphics2D`. The Skia backend (`TPdfSkiaBackend`, package `Pdf4D.Render.Skia`) is the one raster backend; the viewer, the VCL and FMX components and printing come in later phases. The render covers paths, strokes and dashes, clipping, text (all font types, glyph paths from the `glyf`, CFF and Type 1 programs, all text rendering modes, Type 3 glyph procedures), images (all bit depths, `/Decode`, masks, soft masks, matte, JPEG, CCITT, inline images), the colour spaces (the device spaces, CalGray, CalRGB, Lab, ICCBased, Indexed, Separation, DeviceN, Pattern), the functions (types 0, 2, 3 and 4), shadings (types 1 to 7), tiling patterns, blend modes, transparency groups, soft masks, optional content and annotations with an appearance stream.

- Reference comparison: the pages of the corpus are drawn with Skia and compared with the renders of PDFBox 3.0.8 (`tests/reference/render`, written by the oracle with `PDFRenderer.renderImageWithDPI(page, dpi, ImageType.RGB)`). 617 pages have a reference at 72 DPI (every page of a file up to page 50; 7 files that PDFBox cannot render have none and are listed in `no-reference.txt`): 612 are equal and 5 have a known difference. 22 pages have a reference at 150 DPI (a selection with fine details and the first page of every invoice): 19 are equal and 3 have a known difference. `pending.txt` is empty.
- The known differences (`tests/reference/render/*.render-known-differences.txt`, with the reason per page): the annotations without an appearance stream (`generated/render/annotations.pdf` pages 1 to 3 and page 1 of `pdfbox/input/compression/attachment.pdf`; see the deviations), page 1 of `pdfbox/input/rendering/survey.pdf` at 72 DPI (0.05% of the flat pixels: seams of Indexed images at fractional positions), and page 1 of `generated/render/transparency.pdf`, `softmask.pdf` and `patterns.pdf` at 150 DPI (the grid of transparency groups, see "Renderer: where Java2D and Skia are made to agree").
- The thresholds are constants of `TRenderCompare` (`tests/Support/Pdf4D.Tests.RenderCompare.pas`). A pixel is an edge pixel when a channel of the reference differs by more than `FlatRange` (8) inside the 3 x 3 pixels around it, and flat otherwise. A flat pixel differs when a channel differs by more than `FlatTolerance` (8), an edge pixel by more than `EdgeTolerance` (80). A page is equal when the sizes are equal, at most `MaxFlatDifferentFraction` (0.02%) of its flat pixels differ and at most `MaxEdgeDifferentFraction` (3.5%) of its edge pixels differ. `golden-format.md` has the distribution that the constants were taken from.

Generated and mutated input also holds for the renderer: pages of mutated corpus files, generated graphics streams and hostile image, recursion and geometry documents only end in a render or an `EPdfException` descendant, never hang, leak or run out of memory (`Pdf4D.Tests.RenderRobustness.Tests`; `building.md` has the sizes).

Not part of the port: JPEG 2000 and JBIG2 images (PDFBox needs plugins for them too), writing PDFs, embedding fonts, `constructAppearances` and overprint.

## Ported PDFBox classes (M1)

Taken from the `// Port of:` header of every unit.

| PDFBox package | Classes |
|---|---|
| `pdfbox-io` | `RandomAccessRead`, `RandomAccessReadBuffer`, `RandomAccessReadBufferedFile` |
| `cos` | `COSArray`, `COSBase`, `COSBoolean`, `COSDictionary`, `COSDocument`, `COSFloat`, `COSInteger`, `COSName`, `COSNull`, `COSNumber`, `COSObject`, `COSObjectKey`, `COSStream`, `COSString`, `ICOSParser`, `PDFDocEncoding` |
| `filter` | `ASCII85Filter` (and `ASCII85InputStream`), `ASCIIHexFilter`, `Filter`, `FilterFactory`, `FlateFilter` (and `FlateFilterDecoderStream`), `IdentityFilter`, `LZWFilter`, `Predictor`, `RunLengthDecodeFilter`, `CryptFilter` |
| `pdfparser` | `BaseParser`, `BruteForceParser`, `COSParser`, `EndstreamFilterStream`, `PDFObjectStreamParser`, `PDFParser`, `PDFXrefStreamParser`, `XrefTrailerResolver` |
| `pdmodel` | `PDDocument`, `PDDocumentCatalog`, `PDDocumentInformation`, `PDEmbeddedFilesNameTreeNode`, `PDPage`, `PDPageTree` |
| `pdmodel.common` | `PDNameTreeNode`, `PDNumberTreeNode`, `PDPageLabels`, `PDPageLabelRange`, `PDRectangle`, `PDComplexFileSpecification`, `PDEmbeddedFile` |
| `pdmodel.encryption` | `AccessPermission`, `PDEncryption`, `PDCryptFilterDictionary`, `SaslPrep`, `SecurityHandler`, `StandardSecurityHandler` |
| `pdmodel.interactive.documentnavigation` | `PDDestination`, `PDPageDestination`, `PDNamedDestination`, `PDDestinationNameTreeNode`, `PDDocumentNameDictionary`, `PDDocumentNameDestinationDictionary`, `PDDocumentOutline`, `PDOutlineNode`, `PDOutlineItem`, `PDOutlineItemIterator` |
| `pdmodel.interactive.form` | `PDAcroForm`, `PDFieldFactory`, `PDField`, `PDFieldTree`, `PDNonTerminalField`, `PDTerminalField`, `PDVariableText`, `PDButton`, `PDCheckBox`, `PDRadioButton`, `PDPushButton`, `PDChoice`, `PDComboBox`, `PDListBox`, `PDTextField`, `PDSignatureField` (the field classes are one `TPDField` with a kind, see the deviations) |
| `util` | `DateConverter` |

## Ported PDFBox classes (M2)

Taken from the `// Port of:` header of every unit. Where a class is ported in part, the deviation is under "Deliberate deviations".

| PDFBox package | Classes |
|---|---|
| `contentstream` | `PDFStreamEngine` (as far as text extraction uses it) |
| `contentstream.operator` | `Operator`, `OperatorName`, `OperatorProcessor`, `DrawObject`, `MissingOperandException` |
| `contentstream.operator.state` | `Concatenate`, `Restore`, `Save`, `SetGraphicsStateParameters`, `SetMatrix`, `EmptyGraphicsStackException` |
| `contentstream.operator.text` | the text operators: `BeginText`, `EndText`, `SetFontAndSize`, `SetCharSpacing`, `SetWordSpacing`, `SetTextHorizontalScaling`, `SetTextLeading`, `SetTextRenderingMode`, `SetTextRise`, `MoveText`, `MoveTextSetLeading`, `NextLine`, `SetMatrix`, `ShowText`, `ShowTextAdjusted`, `ShowTextLine`, `ShowTextLineAndSpace` |
| `contentstream.operator.markedcontent` | `BeginMarkedContentSequence`, `BeginMarkedContentSequenceWithProperties`, `EndMarkedContentSequence` |
| `pdmodel` | `PDResources` (the read side) |
| `pdmodel.font` | `PDFont`, `PDFontLike`, `PDFontFactory`, `PDSimpleFont`, `PDType1Font`, `PDType1CFont`, `PDMMType1Font`, `PDTrueTypeFont`, `PDType3Font`, `PDType3CharProc` (without the content stream interface), `PDType0Font`, `PDCIDFont`, `PDCIDFontType0`, `PDCIDFontType2`, `PDCIDSystemInfo`, `PDFontDescriptor` (the read side), `PDPanose`, `PDPanoseClassification`, `Standard14Fonts`, `CMapManager`, `UniUtil`, `FontMapper`, `FontMapperImpl`, `FontMapping`, `CIDFontMapping`, `FontMappers`, `FontProvider`, `FontInfo`, `FontFormat`, `FileSystemFontProvider` |
| `pdmodel.font.encoding` | `Encoding`, `DictionaryEncoding`, `BuiltInEncoding`, `Type1Encoding`, `StandardEncoding`, `WinAnsiEncoding`, `MacRomanEncoding`, `MacOSRomanEncoding`, `MacExpertEncoding`, `SymbolEncoding`, `ZapfDingbatsEncoding`, `GlyphList` |
| `pdmodel.graphics` | `PDFontSetting` |
| `pdmodel.graphics.form` | `PDFormXObject` (the read side), `PDTransparencyGroup` (as `IsTransparencyGroup`) |
| `pdmodel.graphics.state` | `PDGraphicsState` (without colour, clipping and line style), `PDTextState`, `RenderingMode`, `PDExtendedGraphicsState` (`/Font` only) |
| `text` | `PDFTextStripper` (pages, articles, actual text, sorting, paragraphs, bookmarks), `LegacyPDFStreamEngine`, `TextPosition`, `TextPositionComparator`, and the tables of the stripper as data |
| `util` | `Matrix` (as far as text extraction uses it), `Vector`, `IterativeMergeSort`, and `java.util.TimSort` of OpenJDK 21 (the sort behind `Collections.sort`) |
| `fontbox` | `FontBoxFont` |
| `fontbox.afm` | `AFMParser`, `FontMetrics`, `CharMetric`, `KernPair`, `Ligature` |
| `fontbox.cff` | `CFFParser`, `CFFOperator`, `CFFFont`, `CFFType1Font`, `CFFCIDFont`, `CFFCharset` (with the Type 1, CID, ISOAdobe, Expert and ExpertSubset charsets), `CFFEncoding` (with the standard and expert encodings), `CFFStandardString`, `FDSelect`, `DataInput`, `Type1CharStringParser`, `Type2CharStringParser`, `Type1FontUtil` |
| `fontbox.cmap` | `CMap`, `CMapParser`, `CMapStrings`, `CIDRange`, `CodespaceRange` |
| `fontbox.encoding` | `Encoding`, `StandardEncoding`, `MacRomanEncoding`, `BuiltInEncoding` |
| `fontbox.pfb` | `PfbParser` |
| `fontbox.ttf` | `TTFParser`, `OTFParser`, `OpenTypeFont`, `TrueTypeFont`, `TrueTypeCollection`, `TTFTable`, `TTFDataStream`, `RandomAccessReadDataStream`, `RandomAccessReadUnbufferedDataStream`, `FontHeaders`, `CmapTable`, `CmapSubtable`, `CmapLookup`, `HeaderTable`, `HorizontalHeaderTable`, `HorizontalMetricsTable`, `MaximumProfileTable`, `NamingTable`, `NameRecord`, `OS2WindowsMetricsTable`, `PostScriptTable`, `VerticalHeaderTable`, `VerticalMetricsTable`, `CFFTable`, `WGL4Names` |
| `fontbox.type1` | `Type1Font`, `Type1Lexer`, `Type1Parser` |
| `fontbox.util` | `BoundingBox` |
| `fontbox.util.autodetect` | `FontDirFinder`, `NativeFontDirFinder` (and the finders per operating system) |

Data: the Adobe Glyph List, the Zapf Dingbats list and the additional glyph list, the AFM files of the standard 14 fonts, the predefined CMaps and LiberationSans-Regular are resources in `src/Resources` (see `building.md`).

TrueType classes of FontBox that are left out:

| PDFBox class | Reason |
|---|---|
| `GlyphTable` (`glyf`) with `GlyphData` and the glyph description classes | They give outlines. Text extraction needs advance widths and the `cmap`, not glyph paths. |
| `KerningTable` (`kern`) | Text extraction uses the widths of the PDF, never the kerning of a font. |
| `GlyphSubstitutionTable` (GSUB) with `GsubWorker` and its language workers | They serve embedding and the display of substituted glyphs. Extraction maps codes to Unicode. |
| `SubstitutingCmapLookup` | It only exists next to GSUB. |
| `TTCDataStream` | Not a class of its own: a stream over the shared data of a collection is made per font by `TTrueTypeCollection` (`Pdf4D.FontBox.TrueType.Collection`). |

Left out as well: the subsetter and the embedders (`TTFSubsetter`, `PDType0Font.load`, `PDTrueTypeFont.load`, `ToUnicodeWriter`), because Pdf4D does not write.

Not ported from PDFBox, but written for Pdf4D: the AES and RC4 primitives, the Unicode normalization behind `SaslPrep`, the `Common` helpers and the whole `Api` layer.

## Ported PDFBox classes (M3, phase 2: the renderer)

Taken from the `// Port of:` header of every unit. The units of the first four rows are in `src/Render` and `src/Graphics` (package `Pdf4D.Render`); the Skia backend is in `src/Render/Skia` (package `Pdf4D.Render.Skia`). Where a class is ported in part, the deviation is under "Deliberate deviations".

| PDFBox package | Classes |
|---|---|
| `rendering` | `PDFRenderer` (`renderImage`, `hasBlendMode`, `isGroupEnabled`, the size and transform of the page; as `TPdfRenderer`, `TPdfRenderParams` and `TPdfPageTransform`), `PageDrawer` (the drawing of paths, clips, strokes and dashes, glyphs and Type 3 glyphs, images, shadings, soft masks, transparency groups, tiling patterns, optional content and annotations), `GroupGraphics` (as `TPdfGroupDevice`), `GlyphCache`, `TilingPaint` and `TilingPaintFactory`, `SoftMask` and the soft mask part of `PageDrawer` (`TPdfSoftMaskPaint`), `RenderDestination` |
| `contentstream` | `PDFGraphicsStreamEngine` (as `TPdfGraphicsEngine`) and the graphics operators on it: `operator.graphics` (without `Do` and `BI`), `operator.color`, `operator.state`, and the image part of `operator.DrawObject` with `BeginInlineImage` |
| `pdmodel.graphics` | `PDLineDashPattern` |
| `pdmodel.graphics.state` | `PDGraphicsState` (colour, line style, clipping, blending and alpha), `PDExtendedGraphicsState` (all entries), `PDSoftMask`, `RenderingIntent` |
| `pdmodel.graphics.color` | `PDColorSpace` and `PDColor` (with `PDColorSpace.create`), `PDDeviceGray`, `PDDeviceRGB`, `PDDeviceCMYK`, `PDCIEBasedColorSpace`, `PDCIEDictionaryBasedColorSpace`, `PDCalGray`, `PDCalRGB`, `PDLab`, `PDTristimulus`, `PDGamma`, `PDICCBased`, `PDIndexed`, `PDSeparation`, `PDDeviceN` (with `PDDeviceNAttributes` and `PDDeviceNProcess`), `PDPattern` |
| `pdmodel.graphics.image` | `PDImage`, `PDImageXObject` (`getImage`, `applyMask`, `scaleImage`, `extractMatte`, `getMask`, `getSoftMask`), `PDInlineImage`, `SampledImageReader` (`getRGBImage` and the readers per bit depth) |
| `pdmodel.graphics.pattern` | `PDAbstractPattern`, `PDTilingPattern` (the read side), `PDShadingPattern` |
| `pdmodel.graphics.shading` | `PDShading`, `PDShadingType1`, `PDShadingType2`, `PDShadingType3`, the mesh types 4 to 7 (`PDTriangleBasedShadingType`, `PDMeshBasedShadingType`; as one class that reads the mesh data), `ShadingContext` and `ShadingPaint`, `Type1ShadingContext`, `AxialShadingContext`, `RadialShadingContext`, `GouraudShadingContext` with `Type4ShadingContext` and `Type5ShadingContext`, `PatchMeshesShadingContext` with `Type6ShadingContext` and `Type7ShadingContext` |
| `pdmodel.graphics.optionalcontent` | `PDOptionalContentProperties` and `PDOptionalContentGroup` (the read side), `PDOptionalContentMembershipDictionary`, and `PDPropertyList.create` |
| `pdmodel.common.function` | `PDFunction`, `PDFunctionType0`, `PDFunctionType2`, `PDFunctionType3`, `PDFunctionType4` (with `type4.Parser`, `InstructionSequence` and the operators) and `PDFunctionTypeIdentity` |
| `pdmodel.interactive.annotation` (read only) | `PDAnnotation` (`createAnnotation` and the entries that the render needs: `/Rect`, `/F`, `/AP`, `/AS`), `PDAppearanceDictionary` (`getNormalAppearance`), `PDAppearanceEntry`. The classes that write an appearance (`PDAppearanceHandler` and the handlers per annotation type) are not ported. |
| `fontbox.ttf` (paths) | `GlyphTable` with `GlyphData`, `GlyfDescript`, `GlyfSimpleDescript`, `GlyfCompositeDescript`, `GlyfCompositeComp`, `GlyphRenderer` and `IndexToLocationTable`: the `glyf` outlines that M2 left out (`Pdf4D.FontBox.TrueType.Glyph`) |
| `fontbox.cff` (paths) | `Type1CharString` and `Type2CharString` (the path part, including `seac` and the flex operators; `Pdf4D.FontBox.CharStringPath`), the readers of the charstrings (`Pdf4D.FontBox.CharStringReaders`) |
| `filter` | `CCITTFaxFilter` and `CCITTFaxDecoderStream` (`Pdf4D.Codec.CCITTFax`, see below); `DCTFilter` for what the JPEG decoder hands on |
| pdf.js, not PDFBox | `src/core/jpg.js`, release tag `v6.5.438` (`Pdf4D.Codec.Jpeg`, see below) |
| Java, not PDFBox | `java.awt.image.AreaAveragingScaleFilter` of OpenJDK 21 (`Pdf4D.Render.ImageScaler`, the smooth scaling of `PDImageXObject.scaleImage` and of the downscaling optimization of `PageDrawer.drawBufferedImage`) |

Not ported from `pdmodel.graphics`: overprint, rendering intents other than the one Java uses for `toRGB`, `PDFRenderer.setSubsamplingAllowed` and `setImageDownscalingOptimizationThreshold` as options, and the handlers that construct appearances.

## Known deviations

The list under "Deliberate deviations" below is the full list for M1 to M3 phase 2. For the corpus, the differences that show up in the golden comparison are in `tests/golden/*.known-differences.txt` with a reason per object, and `golden-format.md` explains how they are written.

## Base version

Apache PDFBox 3.0.8 (git tag `3.0.8`). Upstream fixes are carried over selectively.

## Package to module mapping

| PDFBox | Pdf4D module |
|---|---|
| `pdfbox-io` (`RandomAccessRead*`) | IO |
| `org.apache.pdfbox.cos` | Cos |
| `org.apache.pdfbox.pdfparser` | Parser |
| `org.apache.pdfbox.filter` | Filter |
| `org.apache.pdfbox.pdmodel.encryption` and own crypto | Encryption |
| `org.apache.pdfbox.pdmodel` (document, catalog, pages, common, outline, interactive.form, embedded files, page labels) | Model |
| `org.apache.pdfbox.contentstream` | Content |
| `org.apache.pdfbox.pdmodel.font` (and `encoding`) | Font |
| `fontbox` (`ttf`, `cff`, `type1`, `cmap`, `afm`, `encoding`) | FontBox |
| `org.apache.pdfbox.text` | Text |
| `org.apache.pdfbox.rendering`, `pdmodel.graphics.*`, `pdmodel.common.function` | Render and Graphics (packages `Pdf4D.Render`, `Pdf4D.Render.Skia`) |
| `filter` (CCITT) and pdf.js (JPEG) | Codec |
| new: public API | Api |

Unit names use the application prefix `Pdf4D`, for example `Pdf4D.Cos.Dictionary.pas`.

## Naming

- `COSFoo` becomes `TCosFoo`.
- `PDFoo` becomes `TPDFoo`.
- Other PDFBox classes get the `T` prefix and keep their name.

## Deliberate deviations

- Names are returned as `string`, not as a separate name type.
- `TPDField` carries a `Kind` instead of a subclass per field type (`PDTextField`, `PDCheckBox`, `PDNonTerminalField` and the others). The kind is decided once, as `PDFieldFactory.createField` does, and every kind-specific property (`ValueAsString`, `Values`, `ExportValues`, `OnValues`) gives the value of an empty one when it does not belong to the kind.
- The field tree is walked without recursion and cut off at `MaxFieldDepth` (256) levels, which also bounds the `/Parent` chain that is followed for `/FT`; PDFBox recurses and has no such limit.
- A node or leaf of the page tree that is reachable twice is listed once.
- Lookup of a page by index uses the list that the walk of the tree found, not the `/Count` entries.
- `TPDDateConverter` keeps to the limits of the port: time zone names are recognised from a fixed list, there is no Julian calendar, and years run from 1 to 9999.
- The page labels are made for the smaller of `/Count` and the pages that the walk finds, not for `/Count` alone.
- `ValueAsString` of a non terminal field and of a signature field is empty (PDFBox prints Java object text there).
- No bidirectional text processing (UAX #9) and no mirroring of characters (`BidiMirroring.txt`). Right-to-left text comes out in the order of the file: `handleDirection` leaves the word as it is and `TextPosition.getVisuallyOrderedUnicode` gives `getUnicode`, so Hebrew and Arabic words differ from PDFBox (which reverses them).
- A font that cannot be created (for example a Type 0 font without `/DescendantFonts`) is logged and the page goes on with the default font. PDFBox lets the `IOException` of `PDResources.getFont` end `processPage`, so `getText` fails for the whole page (PDFBOX-3950, page 4 of the corpus file). Pdf4D extracts the text of the rest of the page; the golden comparison lists the two sections in `tests/golden/*.text-known-differences.txt`.
- The text goldens treat the sections of the right-to-left files (`hello3.pdf`, `BidiSample.pdf`, `FC60_Times.pdf`, `PDFBOX-4531-bidi-ligature-1/2.pdf`) as known differences, because of the missing bidi processing above.
- The system font provider has no disk cache: PDFBox's `.pdfbox.cache` is not ported, and Pdf4D never writes to the home folder or anywhere else. The font folders are scanned (headers only) when the font infos are first asked for, and the scan is bounded in depth, folders, files and file size.
- The core (document, text extraction) does not decode images, and Pdf4D has no accessor for the raw image streams of a page. The renderer decodes them (see the renderer deviations).
- Loading a document changes nothing in it. PDFBox adds `/Type /Outlines` to the outline root when it reads it, and sets `/Length` of an encrypted stream to the decrypted size when it decrypts the stream while loading. Pdf4D keeps both as they are in the file (it decrypts when the data is read). The golden comparison lists the affected objects in `tests/golden/*.known-differences.txt`.
- Corrupt Flate data keeps every byte that was inflated before the error. `FlateFilterDecoderStream` of PDFBox loses the zeros at the end of the failing inflate call and, depending on the read size of its caller, what is left in its buffer (PDFBOX-3964, object 635).

- In text extraction there are no glyph paths, no clipping and no colour. The graphics state of the core keeps what text extraction needs (matrices, the text state, the font). The operators for paths, colour, shading and clipping are skipped, and so are the image operators; an inline image is only read to find its end (`MaxInlineImageSize`). The renderer has its own stream engine on top of the core one (`Pdf4D.Render.GraphicsEngine`, `Pdf4D.Graphics.State`) that does all of this.
- Glyph widths from charstrings are read without interpreting the path: only the width operand of a charstring is decoded (`Pdf4D.FontBox.CharStringWidth`). PDFBox runs the whole charstring to get the path and the width.
- GSUB, the `glyf` and `kern` tables and the subsetter of FontBox are not ported (see the table above).
- There is no disk cache for the system fonts (see above). The system fonts that are used are shared by the whole process and are read completely into memory, once: a font that was picked stays in memory until the process ends.
- The list item patterns of the text stripper (the ten of `PDFTextStripper.LIST_ITEM_EXPRESSIONS`) are matched by hand-written code, not with regular expressions. The patterns and the results are the same.
- The Unicode tables of text extraction (the presentation forms U+FB00 to U+FDFF and U+FE70 to U+FEFF, and the diacritic characters) are generated from `java.text.Normalizer` (NFKC) and `Character.getType` of JDK 21 (Unicode 15.0), which is what PDFBox 3.0.8 calls. The Unicode 16.0 data of the SASLprep normalization (M1) is separate and only serves passwords.
- `/ExtGState` copies only `/Font`. The other entries of `PDExtendedGraphicsState` (line style, blend mode, transfer functions and the rest) are ignored, because they cannot change text.
- The glyph procedures of a Type 3 font are not run for text, as in PDFBox. Their width (the `d0` or `d1` operator) and, as a last resort, their bounding box are read, from at most 64 KiB of the decoded stream.
- A failing operator is logged and the content stream goes on, for every exception except the fatal ones (`TPdfFailure.IsFatal`: access violation and the other external exceptions, invalid pointer, abort). `EOutOfMemory` ends the page like a limit and keeps the text so far. PDFBox does this only for an `IOException`. The check `/Length > 0` of a form XObject is not ported.
- Floating point: Java computes with Infinity and NaN, Delphi raises `EMathError` on Windows. Known divisions and scalings have guards, and `TPdfFloatGuard` masks the floating point exceptions of the thread around the stream engine and the text API (and restores the mask afterwards). During a call of the text API the mask of the caller is therefore different.
- A ToUnicode stream that several fonts share is parsed and counted once.
- A font that fails to load is remembered per document, whatever the exception was (a fatal one excepted), so its font program is parsed once; a failure that is no `EPdfException` reaches the caller as `EPdfParseException`.
- Overlapping ranges in `/W2` of a CID font: the first range that covers a CID wins, where PDFBox lets the last one win.
- `TPDType1CFont.GetNameInFont` looks the name up in the glyph list that belongs to the font. This differs from the Adobe glyph list only for ZapfDingbats.
- The cache of system fonts is never evicted: a font that was picked stays in memory until the process ends (PDFBox keeps them in soft references). It is bounded by the installed fonts and the scan limits.
- The extra limits of the next section.

### Renderer (M3 phase 2)

- A device interface instead of Java2D. `PageDrawer` draws on a `Graphics2D`; Pdf4D draws on `IPdfGraphicsDevice` (paths, strokes, clips, images, blend modes, layers and soft masks, as `Pdf4D.Render.Device.Interfaces` lists them) made by an `IPdfRenderBackend`. `Paint`, `Stroke`, `Shape`, `BufferedImage`, `AffineTransform`, `Composite` and `RenderingHints` have no counterpart: a shading or tiling paint rasterizes into a bitmap that the device paints through, and the stroke normalization of Java2D (`TPdfStrokeNormalizer`) is its own unit. The Skia backend is the only raster backend; a device that records calls (`TRecordingDevice` in the tests) serves the unit tests of the core renderer, which runs without Skia. The core units under `src` (everything except `Graphics`, `Codec`, `Render` and `Pdf4D.Resources.Icc.*`) do not use these folders, and only `src/Render/Skia` uses `System.Skia`; `build.ps1` checks both rules.
- Own ICC conversion instead of Little CMS. `PDICCBased` and `PDDeviceCMYK` let `java.awt.color.ICC_ColorSpace` convert, which is LCMS. Pdf4D parses the profile itself (`Pdf4D.Graphics.Icc.Profile`) and converts with `Pdf4D.Graphics.Icc.Transform`: the A2B0 table (A2B1 and A2B2 only when the earlier ones are missing) whatever the rendering intent of the header says (the Java colours do not depend on it), no black point compensation, no white adaptation beyond the D50 profile connection space, and the CLUT interpolated like LCMS does (tetrahedral for three inputs). The profile of `DeviceCMYK` is the one PDFBox loads (`CGATS001Compat-v2-micro.icc`, a resource). Measured against Java the colours agree within 0.1/255 per channel for the reference profiles. A profile that cannot be parsed raises `EPdfParseException`, and `PDICCBased` then uses the alternate colour space, as PDFBox does for a profile that Java rejects. Limits on the profile are in the table below.
- The JPEG decoder is the one of pdf.js (`jpg.js`) instead of `javax.imageio`; the deviations of the port, among them libjpeg's fancy upsampling to match ImageIO, are in "Ported from pdf.js: the JPEG decoder".
- No `constructAppearances`. PDFBox draws an annotation whose `/AP` is missing by building an appearance (square, circle, line, highlight, link and the other handlers, `PDAppearanceHandler`). That needs a content stream writer; Pdf4D skips such an annotation with one debug line. An annotation with a normal appearance stream (`/AP /N`, with `/AS` for a sub-dictionary) is drawn as `PageDrawer.showAnnotation` does, with the flags (hidden, no view, print for the print destination, optional content, `NoRotate`; `NoZoom` is not applied in PDFBox either) and `RenderAnnotations` to turn all of them off. The `NoRotate` branch that calls `constructAppearances` for an appearance with a transparency group (PDFBOX-4744) is not ported either: that annotation is drawn with the appearance it has. The known differences of the corpus (`annotations.pdf`, `attachment.pdf`) are this.
- No `setSubsamplingAllowed` and no `setImageDownscalingOptimizationThreshold` as options, and no own `RenderingHints`. PDFBox 3.0.8 subsamples (`SampledImageReader.getRGBImage`: every Nth column and row) only when the caller asks for it; Pdf4D does it automatically for an image of more than `MaxImagePixels` pixels, with the same rule for N (the smallest N for which the image fits), so a huge image renders in bounded memory. Below that limit every image is read in full. The downscaling optimization of `PageDrawer.drawBufferedImage` (smooth scaling of an image that is drawn far smaller than it is) is part of the port with the threshold of PDFBox, not an option.
- The render is not cancellable inside a single operator, only between operators: `TPdfCancelToken` (thread safe) is looked at between operators and ends the page with `TPdfRenderStatus.Cancelled`. PDFBox has no cancellation.
- A problem inside a page is logged and the page goes on (an operator that fails, an image that cannot be decoded, a font or a pattern that cannot be made), as for text; an invalid argument raises `EArgument*` and a limit that stops the whole render raises `EPdfLimitExceededException` before anything is drawn. `TPdfFloatGuard` masks the floating point exceptions around every Skia call and the render, as in the text code.
- Additional limits of the renderer. They are fields of `TPdfRenderOptions` (the values are the defaults) unless they are fixed in the code; content that runs into one is skipped or drawn smaller, with a log line, and never hangs or grows without bound.

| Limit | Default | Applies to |
|---|---|---|
| `MaxRenderPixels` | 64 Mi pixels | width times height of one render target; `RenderToBitmap` and `RenderPage` raise `EPdfLimitExceededException` before they draw |
| `MaxBitmapPixels` (`TPdfBitmap`, fixed) | 256 Mi pixels | the size of any bitmap |
| `MaxImagePixels` | 64 Mi pixels | an image above it is subsampled until it fits |
| `MaxPatternDepth` | 8 | nesting of tiling patterns |
| `MaxSoftMaskDepth` | 8 | nesting of soft masks |
| `MaxTransparencyGroupDepth` | 16 | nesting of transparency groups; the layers that are alive together stay within about 4 times the pixels of the page |
| `MaxType3Depth` | 8 | nesting of Type 3 glyph procedures |
| `MaxTilingCells` | 1,048,576 | cells of a tiling pattern per fill |
| `MaxTileEdge` | 3000 | the pixels of one cell along an edge (`TilingPaint.MAXEDGE` of PDFBox); the cell is drawn smaller above it |
| `MaxShadingWork` | 400,000,000 | the work of all mesh shadings of one page together (one shading has 100,000,000, `MaxMeshWork`); the next mesh shadings of the page are skipped |
| `MaxAnnotations` | 10,000 | annotations drawn per page |
| ICC profile | 16 MB, 4096 tags, curves of 65,536 entries, 16 CLUT inputs, 16,777,216 grid points | the profile parser |
| CCITT | 1 Mi columns, `Columns * Rows` within `MaxPixels`, 8 steps per column of search work per row | see "Ported from PDFBox: the CCITT fax decoder" |
| JPEG | see "Ported from pdf.js: the JPEG decoder" | |

### Renderer: where Java2D and Skia are made to agree, and where not

The rules below were found by comparing renders with the PDFBox reference images; the JDK source was not consulted, so they are observations that the unit tests pin, not quotations of the JDK.

- A clip that is not anti-aliased: the reference images show an edge at `floor(x + 0.25)` in device pixels (consistent with `ShapeSpanIterator` moving the vertices to `floor(x + 0.25) + 0.25`), where Skia takes the nearest pixel boundary. `TPdfStrokeNormalizer.SnapForClip` moves the vertices and the Skia device clips with the result, so a 1 pixel border line on the edge of a form field box is cut off as in PDFBox.
- A fill that is not anti-aliased (PDFBox fills rectangles of more than one point in both directions that way): two regimes are seen. With a device matrix of scale 1 (72 DPI) the edge of a rectangle lies at `ceil(x - 0.001)`: the 1296 squares of the QR code of PDFBOX-6207 differ in 61 of 19044 pixels with `ceil`, in 1479 with `floor(x + 0.25)` and in 2766 with the nearest boundary. With another scale (150 DPI) it lies at `floor(x + 0.25)` like the clip: all 30 strips of `generated/render/colors-device.pdf` agree. What separates the two in Java2D is not known; `TPdfStrokeNormalizer.SnapForFill` picks by the scale of the matrix and the Skia device fills the snapped path. A scale of 4/3 (96 DPI, the viewer) is not in the reference set and takes the second regime.
- The stroke normalization of Java2D works on the double matrix of the page. The page matrix of Pdf4D is a Single matrix, and the translation (the page height times the scale, 833.33330154 at 150 DPI for 400 pt) is not exact in a Single; `TPdfPageTransform.TranslationResidualX/Y` and `TPdfPageDrawer` carry what the Single lacks so that the normalization decides the pixel as Java2D does. Painting itself uses the Single matrix, which Skia does anyway. The residual is zero inside a transparency group (PDFBox draws a group in a space with the scale only, so the translation of the page is not in it) and inside a tiling pattern cell. The clip and the fill snapping use the Single matrix too: an edge within about 1e-5 pixel of a quarter pixel (at 150 DPI a point value of 12 gives 24.999999) could land in the neighbouring pixel.
- Transparency groups, soft masks and pattern cells at a DPI at which the page height in pixels is not whole: PDFBox draws a group on an image in a y-up space with only the scale (`PageDrawer.TransparencyGroup`) and flips it onto the page with a whole-pixel offset, so its pixel grid is shifted against the page by the fraction of the page height in pixels. Pdf4D draws the group on the grid of the page. At 72 DPI (A4 and Letter heights are whole pixels) the two agree; at 150 DPI the edges of shapes inside groups are one pixel off (`transparency.pdf`, `softmask.pdf`, `patterns.pdf` of the generated corpus). This also holds at 96 DPI (A4 is 1122.67 px) for every page with groups, soft masks or tiling: shape edges there are at most one pixel off PDFBox. Not ported, by choice: the groups would have to be rendered on a y-up grid and composited with the whole-pixel offsets of PDFBox, a change to the group renderer that all equal pages rest on, for a difference of one pixel along edges. It is not planned for a milestone; revisit it when a user sees the difference.

## Ported from pdf.js: the JPEG decoder

`src/Codec/Pdf4D.Codec.Jpeg.pas` is a port of `src/core/jpg.js` of pdf.js, release tag `v6.5.438` (Apache License 2.0; NOTICE names it). `tools/fetch-pdfjs-src.ps1` downloads that file and the two it imports from, from this one tag, into `tools/pdfjs-src/` (ignored by git). The tag is also named in the unit header and in the script; change the three together. PDFBox leaves JPEG to `javax.imageio`, which has no Delphi counterpart; the Delphi code follows `DCTFilter` for what it hands on (gray, RGB, CMYK samples; YCCK converted to CMYK; no inversion of CMYK for a file from a PDF) and `jpg.js` for the decoding itself. The structure of `jpg.js` is kept (`TJpegDecoder` is `JpegImage`, `TJpegScanDecoder` is `decodeScan` with its nested functions, `QuantizeAndInverse`, `BuildComponentData`, `LinearizeBlockData` for `#getLinearizedBlockData`, `BuildImage` for `getData`). The deviations:

- The Huffman tables are canonical code tables (maximum and minimum code per length), not the nested arrays of `buildHuffmanTable`. Valid tables decode the same values; an over-subscribed table does not build a strange tree but raises `EPdfParseException`.
- The data of a scan that ends before the scan does ends the scan like an EOI marker does in `jpg.js` (one warning, the rows decoded so far stay). `jpg.js` reads `undefined` bytes there and goes on decoding zero bits.
- Every access is checked: the quantization and Huffman table indexes, the component ids of a scan, the block offsets, the data offsets. A `jpg.js` access outside an array gives `undefined` or a `RangeError`; the port raises `EPdfParseException` where the data is needed, and ignores a coefficient index past 63 (a store to an undefined index in JavaScript).
- A scan decodes at most the MCUs of the frame, also when stray restart markers follow a scan of a file without a restart interval (`jpg.js` would read the whole scan again).
- Limits, with the sizes in `Int64`: at most `MaxPixels` pixels, at most 256 MiB of samples, a block buffer of at most 4 samples per pixel and component (plus 1 Mi samples) and 128 Mi samples, at most 1000 scans and a work budget over all scans (the blocks that the scans walk over, with or without data, may not exceed 32 times the blocks of the frame; an end-of-band run over empty blocks takes almost no data but still costs a visit per block), 1, 3 or 4 components with sampling factors from 1 to 4, 8 bit samples. All of them raise `EPdfParseException`; `jpg.js` has none of them (and accepts 2 components and other precisions).
- A frame height of 0 (to be defined by a DNL marker) is an error; `jpg.js` produces an empty image. A DNL marker that corrects the number of lines and the re-parse that follows are ported.
- Arithmetic coding, lossless and hierarchical processes (SOF3, SOF5 to SOF7, SOF9 to SOF11, SOF13 to SOF15) raise `EPdfParseException`; `jpg.js` fails on them with a generic error.
- `JpegImage.getData` is called for the size of the JPEG itself, with neither `forceRGB` nor `forceRGBA`: the colour conversions to RGB(A) and the `decodeTransform` of `IMAGE_DECODERS` builds are not ported, except that a file that is not from a PDF has its CMYK inverted (`IsSourcePdf` false).
- The colour conversions write through a clamping and rounding function that follows `Uint8ClampedArray` (round half to even).
- `TPDImage` skips one line feed before the data and takes `/ColorTransform` from the decode parameters of the DCT filter, as `jpg.js` is called from pdf.js; PDFBox ignores `/ColorTransform` and asks the Adobe marker and `ImageIO`. A filter that follows DCTDecode is ignored with a warning.
- Upsampling of a component that is halved horizontally (4:2:2 and 4:2:0, h2v1 and h2v2) follows libjpeg ("fancy upsampling": a triangle filter with weights 3 and 1, `TJpegUpsampling`), because libjpeg inside ImageIO is the reference of PDFBox. jpg.js repeats the nearest sample, so this is a deviation from it; other sampling ratios repeat the nearest sample, as libjpeg does.

## Ported from PDFBox: the CCITT fax decoder

`src/Codec/Pdf4D.Codec.CCITTFax.pas` ports `CCITTFaxFilter.decode` (parameters, choice of the compression type, inversion of the bitmap) and `CCITTFaxDecoderStream` (decode1D, decode2D, getNextChangingElement, the row types, decodeRun, readBit, the code tables and trees) of PDFBox 3.0.8. PDFBox took the stream from TwelveMonkeys ImageIO (BSD 3-Clause; NOTICE and `licenses/TwelveMonkeys-BSD.txt`). The deviations:

- The decoder returns the whole image as a byte array. A damaged row (an unknown code, more changes than the row has columns) keeps the rows before it and leaves the rest white, with one warning; `CCITTFaxFilter` lets the IOException fail the image. A stream that ends early gives the same result without a warning, like PDFBox. `/DamagedRowsBeforeError` and `/EndOfBlock` are read and ignored, like PDFBox.
- Limits: `Columns * Rows` over `MaxPixels` (the image layer passes the smaller of `MaxBitmapPixels` and 8 times `MaxDecodedStreamSize`) and more than 1 Mi columns raise `EPdfParseException`; PDFBox allows 256 MiB of bytes, with a system property. The code trees are built per decode, so the decoder holds no shared state.
- `TCCITTFaxParameters.HasEndOfLine` records that `/EndOfLine` exists, because `CCITTFaxFilter` uses the entry for `/K 0` only then (PDFBOX-6080), and finds the type from the first 20 bytes otherwise.
- Run lengths and positions are limited to half the range of an `Integer`, so a stream of make-up codes cannot overflow.

## Limits that Pdf4D adds

PDFBox has few limits on hostile input. Pdf4D adds the limits below. The ones with a name are set through `TPdfLoadOptions` (the values are the defaults); the others are fixed in the code. A document that runs into a limit loses the content after it, with a log line, or raises an `EPdfException` descendant, and never hangs, crashes or grows without bound.

| Limit | Default | Applies to |
|---|---|---|
| `MaxDecodedStreamSize` | 256 MiB | the decoded size of one stream |
| `MaxNestingDepth` | 500 (never more than 2000) | nesting of arrays and dictionaries in the parser |
| `MaxFormXObjectDepth` | 50 | nesting of forms and Type 3 glyph procedures (also the limit of PDFBox) |
| `MaxOperatorsPerPage` | 10,000,000 | operators that a page may run, over its content streams and forms |
| `MaxGlyphsPerPage` | 2,000,000 | glyphs that a page may show |
| `MaxInlineImageSize` | 16 MiB | the data of one inline image |
| `MaxGraphicsStateDepth` | 4096 | the `q`/`Q` stack |
| `MaxToUnicodeMappings` | 16,777,216 | mappings of all ToUnicode CMaps of one document; the CMap that crosses the limit is dropped, and so is each one after it |
| `MaxContentBytesPerPage` | 256 MiB | decoded bytes of content that a page runs; every run of a form counts again |
| operands per operator, items per array in a content stream | 65,536 | fixed; what comes after is dropped |
| overlap check of the stripper | 256 neighbours | fixed |
| marked content nesting in the stripper | 1000 levels | fixed |
| beads (articles) read per page | 500 | fixed |
| font scan | depth 16, 20,000 folders, 50,000 font files, 100,000 fonts, files up to 256 MiB | fixed |
| Type 3 glyph procedures | decoded up to 64 KiB; the bounding box fallback looks at 4096 procedures | fixed |

The budgets for operators and glyphs are bounded but large. A hostile file that uses them completely can take 10 to 40 seconds for one page in a Debug build, less in Release. Measured on Win64 in Debug: a chain of 25 forms that each draw the next one twice, 39 s; a `Tj` with 3 million glyphs, 11 s; a Type 0 `Tj` with 2.1 million glyphs, 13 s. A caller that wants a shorter worst case lowers `MaxOperatorsPerPage` and `MaxGlyphsPerPage`. The fuzz tests of the hostile documents use 1,000,000 operators and 200,000 glyphs.

## Tested platforms

Pdf4D needs Delphi 12 or newer. It is built and tested on Delphi 13 (Studio 37.0) on Win32, Win64 and Linux64, and not yet verified on Delphi 12. The code uses no Delphi 13-only syntax, but Delphi 12 has not been tested, and the project files (the packages and both test projects) have only been built with Delphi 13. `building.md` has the checklist for the first Delphi 12 build, including the Skia API that the backend uses.

## Unicode normalization (SASLprep)

The RTL has no Unicode normalization, and PDFBox gets NFKC from the JDK for the passwords of encryption revision 6. `Pdf4D.Encryption.UnicodeNormalization` is a port of the algorithm of UAX 15 (full compatibility decomposition, canonical ordering, canonical composition, Hangul by algorithm). Its tables are in `src/Encryption/Pdf4D.Encryption.UnicodeData.pas`, generated by `tools/unicode/generate-unicode-data.ps1` from `UnicodeData.txt` and `CompositionExclusions.txt` of Unicode 16.0.0 (pinned in the script; pass `-UnicodeVersion` to move on). The unit is generated, never edited by hand. Composition exclusions: the entries of `CompositionExclusions.txt`, the singleton decompositions and the decompositions that start with a non-starter. To update: run the script, rebuild, run the tests.

## Public API deviations from the plan

- `IPdfDocument.Permissions` returns an `IPdfPermissions` (a copy of the permission bits with the `Can...` queries, `IsOwnerPermission` and `Bits`) and not the inner-layer `TPdfAccessPermission`. The copy does not depend on the document, so every object of the API stays valid after the document is released. The inner-layer class remains reachable through `CosDocument.AccessPermission` for code that needs it.
- `IPdfDocumentInfo` has overloads `TryGetCreationDate(out Value; out OffsetMinutes)` and `TryGetModificationDate(out Value; out OffsetMinutes)` next to the simple ones. `OffsetMinutes` is the offset of the time zone of the date in minutes east of UTC; `Value` stays the wall clock time of the date, so `Value - OffsetMinutes` minutes is the UTC time.
- `TPdfLog` never raises: a malformed format string logs the raw format string, and an exception from the `OnLog` callback is swallowed. The text is not formatted when there is no callback.
