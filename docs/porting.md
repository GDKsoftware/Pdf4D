# Porting from PDFBox

## Status

Milestone M1 (document structure) is complete: parsing with xref recovery, object streams, decryption (RC4 40/128, AES 128/256, revisions 2 to 6), the page tree, page boxes and labels, document information, outlines and destinations, name trees, form fields, embedded files and the public interface API. All 188 files of the test corpus load. 163 give a structure dump equal to the PDFBox 3.0.8 dump, 25 differ in documented ways (`tests/golden/*.known-differences.txt`, format in `golden-format.md`). Mutated corpus files only end in success or an `EPdfException` descendant and never hang (`tests/Acceptance/Pdf4D.Tests.Robustness.Tests.pas`).

Milestone M2 (text extraction) is complete: the content stream engine, the fonts (simple fonts, Type 0 with CID fonts, Type 3, the standard 14 fonts, embedded and system fonts through FontBox), the encodings, CMaps and glyph lists, and `PDFTextStripper` with its options (sorting, paragraph and article handling, page range, bookmarks, the `TTextWriter` output). It is reached through `IPdfDocument.ExtractText`, `IPdfPage.ExtractText` and `TPdfTextOptions`. The text goldens (`tests/golden/*.text.txt`) are written by the PDFBox 3.0.8 oracle with an empty font provider, so that they do not depend on installed fonts. They cover the same 188 files: every page (up to 50), the same pages sorted by position, and a page range.

- Number of files: all 188 files have a text golden and all 188 are compared.
- 182 files are equal to PDFBox.
- 6 files differ in documented ways (`tests/golden/*.text-known-differences.txt`): five files with right-to-left text because there is no bidi pass (`hello3.pdf`, `BidiSample.pdf`, `FC60_Times.pdf`, `PDFBOX-4531-bidi-ligature-1.pdf`, `PDFBOX-4531-bidi-ligature-2.pdf`), and page 4 of `PDFBOX-3950` (see the deviations).
- The comparison is lenient about white space: a section whose lines differ only in white space counts as equal, and is counted separately (`PDF4D_TEXT_LENIENT_REPORT` names a file that gets one line per such section). In the corpus that is two sections of one file (`PDFBOX-4531-bidi-ligature-2.pdf`, `default page 1` and `sorted page 1`), on all three platforms.

Generated and mutated input (content streams, font programs, CMaps, hostile documents) only ends in text or an `EPdfException` descendant and never hangs, leaks or runs out of memory (`Pdf4D.Tests.TextRobustness.Tests`; `building.md` describes larger sweeps).

Not part of the port: rendering, decoding images, glyph paths, writing PDFs and embedding fonts.

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

## Known deviations

The list under "Deliberate deviations" below is the full list for M1 and M2. For the corpus, the differences that show up in the golden comparison are in `tests/golden/*.known-differences.txt` with a reason per object, and `golden-format.md` explains how they are written.

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
- Images are not decoded, and Pdf4D has no accessor for the raw image streams of a page.
- Loading a document changes nothing in it. PDFBox adds `/Type /Outlines` to the outline root when it reads it, and sets `/Length` of an encrypted stream to the decrypted size when it decrypts the stream while loading. Pdf4D keeps both as they are in the file (it decrypts when the data is read). The golden comparison lists the affected objects in `tests/golden/*.known-differences.txt`.
- Corrupt Flate data keeps every byte that was inflated before the error. `FlateFilterDecoderStream` of PDFBox loses the zeros at the end of the failing inflate call and, depending on the read size of its caller, what is left in its buffer (PDFBOX-3964, object 635).

- No glyph paths, no clipping and no colour. The graphics state keeps what text extraction needs (matrices, the text state, the font). The operators for paths, colour, shading and clipping are skipped, and so are the image operators; an inline image is only read to find its end (`MaxInlineImageSize`).
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
- Upsampling of subsampled components repeats the nearest sample (`jpg.js`), where `ImageIO` (libjpeg) interpolates ("fancy upsampling"); the comparison with PDFBox in the tests allows for that.

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

Pdf4D needs Delphi 12 or newer. It is built and tested on Delphi 13 (Studio 37.0) on Win32, Win64 and Linux64, and not yet verified on Delphi 12. The code uses no Delphi 13-only syntax, but Delphi 12 has not been tested, and the project file (`tests/Pdf4D.Tests.dproj`) has only been built with Delphi 13.

## Unicode normalization (SASLprep)

The RTL has no Unicode normalization, and PDFBox gets NFKC from the JDK for the passwords of encryption revision 6. `Pdf4D.Encryption.UnicodeNormalization` is a port of the algorithm of UAX 15 (full compatibility decomposition, canonical ordering, canonical composition, Hangul by algorithm). Its tables are in `src/Encryption/Pdf4D.Encryption.UnicodeData.pas`, generated by `tools/unicode/generate-unicode-data.ps1` from `UnicodeData.txt` and `CompositionExclusions.txt` of Unicode 16.0.0 (pinned in the script; pass `-UnicodeVersion` to move on). The unit is generated, never edited by hand. Composition exclusions: the entries of `CompositionExclusions.txt`, the singleton decompositions and the decompositions that start with a non-starter. To update: run the script, rebuild, run the tests.

## Public API deviations from the plan

- `IPdfDocument.Permissions` returns an `IPdfPermissions` (a copy of the permission bits with the `Can...` queries, `IsOwnerPermission` and `Bits`) and not the inner-layer `TPdfAccessPermission`. The copy does not depend on the document, so every object of the API stays valid after the document is released. The inner-layer class remains reachable through `CosDocument.AccessPermission` for code that needs it.
- `IPdfDocumentInfo` has overloads `TryGetCreationDate(out Value; out OffsetMinutes)` and `TryGetModificationDate(out Value; out OffsetMinutes)` next to the simple ones. `OffsetMinutes` is the offset of the time zone of the date in minutes east of UTC; `Value` stays the wall clock time of the date, so `Value - OffsetMinutes` minutes is the UTC time.
- `TPdfLog` never raises: a malformed format string logs the raw format string, and an exception from the `OnLog` callback is swallowed. The text is not formatted when there is no callback.
