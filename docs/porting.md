# Porting from PDFBox

## Status

Milestone M1 (document structure) is complete: parsing with xref recovery, object streams, decryption (RC4 40/128, AES 128/256, revisions 2 to 6), the page tree, page boxes and labels, document information, outlines and destinations, name trees, form fields, embedded files and the public interface API. All 188 files of the test corpus load. 163 give a structure dump equal to the PDFBox 3.0.8 dump, 25 differ in documented ways (`tests/golden/*.known-differences.txt`, format in `golden-format.md`). Mutated corpus files only end in success or an `EPdfException` descendant and never hang (`tests/Acceptance/Pdf4D.Tests.Robustness.Tests.pas`). Text extraction, fonts and content streams belong to later milestones.

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

Not ported from PDFBox, but written for Pdf4D: the AES and RC4 primitives, the Unicode normalization behind `SaslPrep`, the `Common` helpers and the whole `Api` layer.

## Known deviations

The list under "Deliberate deviations" below is the full list for M1. For the corpus, the differences that show up in the golden comparison are in `tests/golden/*.known-differences.txt` with a reason per object, and `golden-format.md` explains how they are written.

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
- No bidirectional text processing.
- Images are not decoded.
- Loading a document changes nothing in it. PDFBox adds `/Type /Outlines` to the outline root when it reads it, and sets `/Length` of an encrypted stream to the decrypted size when it decrypts the stream while loading. Pdf4D keeps both as they are in the file (it decrypts when the data is read). The golden comparison lists the affected objects in `tests/golden/*.known-differences.txt`.
- Corrupt Flate data keeps every byte that was inflated before the error. `FlateFilterDecoderStream` of PDFBox loses the zeros at the end of the failing inflate call and, depending on the read size of its caller, what is left in its buffer (PDFBOX-3964, object 635).

## Unicode normalization (SASLprep)

The RTL has no Unicode normalization, and PDFBox gets NFKC from the JDK for the passwords of encryption revision 6. `Pdf4D.Encryption.UnicodeNormalization` is a port of the algorithm of UAX 15 (full compatibility decomposition, canonical ordering, canonical composition, Hangul by algorithm). Its tables are in `src/Encryption/Pdf4D.Encryption.UnicodeData.pas`, generated by `tools/unicode/generate-unicode-data.ps1` from `UnicodeData.txt` and `CompositionExclusions.txt` of Unicode 16.0.0 (pinned in the script; pass `-UnicodeVersion` to move on). The unit is generated, never edited by hand. Composition exclusions: the entries of `CompositionExclusions.txt`, the singleton decompositions and the decompositions that start with a non-starter. To update: run the script, rebuild, run the tests.

## Public API deviations from the plan

- `IPdfDocument.Permissions` returns an `IPdfPermissions` (a copy of the permission bits with the `Can...` queries, `IsOwnerPermission` and `Bits`) and not the inner-layer `TPdfAccessPermission`. The copy does not depend on the document, so every object of the API stays valid after the document is released. The inner-layer class remains reachable through `CosDocument.AccessPermission` for code that needs it.
- `IPdfDocumentInfo` has overloads `TryGetCreationDate(out Value; out OffsetMinutes)` and `TryGetModificationDate(out Value; out OffsetMinutes)` next to the simple ones. `OffsetMinutes` is the offset of the time zone of the date in minutes east of UTC; `Value` stays the wall clock time of the date, so `Value - OffsetMinutes` minutes is the UTC time.
- `TPdfLog` never raises: a malformed format string logs the raw format string, and an exception from the `OnLog` callback is swallowed. The text is not formatted when there is no callback.
