# Golden dump format

The golden files in `tests/golden/` are written by the PDFBox 3.0.8 oracle (`tools/oracle/Pdf4DOracle.java`). The Delphi dump tool must produce byte-identical output for the same input file. This document is the contract; where PDFBox behavior decides a value, the PDFBox class is named so the rule can be ported one to one.

Golden file name: path of the PDF relative to `tests/corpus/`, with `/` replaced by `__`, plus `.dump.txt` (for example `pdfbox-jira__PDFBOX-1031-1.pdf.dump.txt`).
A file whose `notes` column in `tests/corpus/manifest.csv` contains `password=<x>` is opened with that password, all others with the empty password.

## Encoding

UTF-8 without BOM, LF line endings, every line ends with LF (also the last one), one fact per line. No trailing spaces.

## Lines, in this order

```
version: <v>
encrypted: <true|false>
permissions: <P integer or none>
pages: <n>
page <i>: media=<r> crop=<r> rotate=<0|90|180|270> label=<text>      (one per page, i from 1)
info <Key>: <value>                                                   (zero or more)
xmp: <bytes or none>
outline: <2 spaces per level><title> -> <page number or ?>            (zero or more)
field: <qualified name> | <kind> | <value>                            (zero or more)
attachment: <file name> | <size or ?>                                 (zero or more)
object <num> <gen>: <canonical>                                       (zero or more)
```

A file that cannot be opened gives only one line: `load-error: <kind>` where kind is:

- `wrong-password`: PDFBox throws `InvalidPasswordException` (also when it is the cause of the exception).
- `unsupported`: the exception chain has a message containing (case-insensitive) one of: `security handler`, `unsupported`, `not supported`, `unknown encryption`, `unknown algorithm`, `public key`, `decryption material`. In practice: public key encryption.
- `parse`: everything else, including a timeout of the oracle (60 s per file) and out of memory.

When a section fails after the file did load, its lines are replaced by one line with the value `error` or `<error>` as noted per field below. Such lines should not occur in the current corpus.

## Section rules

**version**: `PDDocument.getVersion()` printed with `Float.toString`: the larger of the header version and the catalog `/Version`, where `/Version` is only considered when the header version is at least 1.4 (so `1.7`, `1.6`, `2.0`). An unparsable catalog version counts as absent.

**encrypted / permissions**: `PDDocument.isEncrypted()`. `permissions` is the `/P` entry of the Encrypt dictionary as signed 32 bit integer (`PDEncryption.getPermissions`, default 0), independent of the password used. `none` when not encrypted.

**pages / page**: pages are enumerated by iterating the page tree (`PDDocument.getPages()`, depth-first, `/Kids` order). `pages` is the number of pages found by that iteration, not the `/Count` value. `media` is `PDPage.getMediaBox()` (inherited; PDFBox returns its Letter default `[0 0 612 792]` when there is none), `crop` is `PDPage.getCropBox()` (inherited, clipped to the media box, falls back to the media box), `rotate` is `PDPage.getRotation()`. `<r>` is `[llx lly urx ury]` from `PDRectangle.getLowerLeftX/Y/UpperRightX/Y` (so already normalized so that ll is the smaller), each number in float format (below).
`label`: `''` (empty) when the catalog has no `/PageLabels`, otherwise the label of that page index from `new PDPageLabels(doc).getLabelsByPageIndices()`, escaped as text (below); a missing entry is empty. `new PDPageLabels(doc)` makes only the default range (decimal, from 1) and does not read `/PageLabels`, so every label is the decimal page number as long as the catalog has `/PageLabels`; the array has `PDDocument.getNumberOfPages()` (the `/Count` of the page tree) entries. `TPDPageLabels.Create(Document)` is that constructor, `TPDPageLabels.Create(Document, Dictionary)` reads the number tree.

**info**: only when the trailer `/Info` resolves to a dictionary. One line per key, ordered by the printed key (ordinal comparison of the encoded name, see Name text). Value:
- key `CreationDate` or `ModDate` whose value is a string that `COSDictionary.getDate` can parse (`DateConverter`): ISO-8601 `yyyy-MM-ddTHH:mm:ss+HH:MM`, using the time zone of the parsed date (UTC is `+00:00`, never `Z`), no fractional seconds.
- any other string (also an unparsable date): `COSString.getString()` (UTF-16 BOM, UTF-8 BOM or PDFDocEncoding) escaped as text.
- any non-string value: its canonical form (below), for example `/True`, `null`, `12`.
Values are the decrypted values for encrypted files.

**xmp**: `none` when the catalog has no `/Metadata`; otherwise the number of bytes of the decoded stream (`PDMetadata.exportXMPMetadata()`); `error` when reading fails.

**outline**: pre-order walk of `/Outlines` through `PDOutlineNode.children()` (first child, then `/Next` siblings). A dictionary that is met a second time (identity) is skipped together with its children; depth beyond 64 is skipped. Indentation is two spaces per level, level 0 has none. Title is `PDOutlineItem.getTitle()` escaped as text (missing title: empty). Target is the 1-based index in the page list of `PDOutlineItem.findDestinationPage(doc)` (handles `/Dest`, GoTo action, named destinations, page numbers); `?` when there is no page, the page is not in the page tree, or resolving throws.

**field**: only when `PDDocumentCatalog.getAcroForm(null)` (without fix ups) is not null. One line per field in the order of `PDAcroForm.getFieldTree()` (pre-order, document order, non-terminal fields included). Name is `PDField.getFullyQualifiedName()` escaped as text. Kind: `nonterminal` (PDNonTerminalField), `checkbox`, `radio`, `pushbutton`, `combo`, `list`, `text`, `signature`, else `unknown`. Value: nonterminal is empty; choice fields (combo, list) join `PDChoice.getValue()` entries with `,` (each entry escaped as text, a comma inside an entry is not escaped); all others `getValueAsString()` escaped as text. `<error>` when PDFBox throws. The three separators are ` | ` (space bar space).

**attachment**: names tree `/Names /EmbeddedFiles` of the catalog, walked depth-first: a node with `/Kids` is walked through its kids in order (its `/Names` is ignored), a leaf node through its `/Names` pairs in array order (`PDNameTreeNode.getNames()` keeps array order). Name is `PDComplexFileSpecification.getFilename()` (UF, DOS, Mac, Unix, F, in that order) and the name tree key when that is null, escaped as text. Size is `PDEmbeddedFile.getSize()` (the `/Params /Size` entry of the embedded file stream) when it is 0 or more, else `?`; the real stream length is never used, and a specification without embedded file stream gives `?`. File attachment annotations are not listed.

**object**: all entries of `COSDocument.getXrefTable()` (the final, merged cross reference table, including objects in object streams, and objects found by a PDFBox rebuild of a damaged file), ordered by object number then generation. Free entries are not in PDFBox's table and are not printed. The object is the loaded, decrypted object `COSObject.getObject()`.
- Objects whose dictionary has `/Type /ObjStm` or `/Type /XRef` are left out completely (also not as error), because they are only carriers.
- A Java `null` result prints `object <n> <g>: error`; an exception while loading or printing also prints `error`.
- COSNull prints `null`.

## Canonical object form

| Value | Output |
|---|---|
| null | `null` |
| boolean | `true`, `false` |
| integer | decimal, with `-` for negatives |
| real | float format below |
| name | `/` + name text |
| string | `<` + lowercase hex of the decrypted bytes (`COSString.getBytes()`) + `>` |
| array | `[a b c]`, elements separated by one space, empty `[]` |
| dictionary | `<<` + entries `/Key value` separated by one space + `>>`, entries ordered by the encoded key (ordinal), empty `<<>>`. No space after `<<` or before `>>`. |
| indirect reference | `<num> <gen> R` (references are never followed in a nested position) |
| stream | the dictionary (with `/Length` and `/Filter` as in the file) followed by ` stream sha256=<64 lowercase hex>` |

**Stream data**: SHA-256 of the data after decryption and after decoding the `/Filter` chain with the PDFBox filters, stopping before the first filter in this set: `DCTDecode`, `DCT`, `JPXDecode`, `JBIG2Decode`, `CCITTFaxDecode`, `CCF` (names as written in the stream; `PDStream.createInputStream(stopFilters)`). When the chain stops early the output is ` stream partial=<names from the stopping filter to the end, joined by ,> sha256=<hash of the data at that point>`, for example `stream partial=DCTDecode sha256=...`. When reading or decoding throws, the output is ` stream error` (no hash). A stream without filters hashes its raw (decrypted) bytes. PDFBox decoders are lenient (a damaged Flate stream gives the bytes decoded so far), and the Delphi decoders must do the same to match.

**Float format**: take the 32-bit float value of the number (`COSFloat.floatValue()`, parsed like PDFBox), write it as `Float.toString` does (shortest decimal that round trips as single), round that decimal half up to 4 decimals, strip trailing zeros and a trailing dot, `-0` and `0.0` print `0`. Never an exponent. Example: `595.2756`, `0.5`, `12`. NaN and Infinity print as in Java.

**Name text** (names in objects, `info` keys): UTF-8 bytes of the decoded name; a byte that is below 0x21, above 0x7E, or one of `# ( ) < > [ ] { } / %` is written as `#` + two uppercase hex digits, all other bytes as the ASCII character.

**Escaped text** (info values, titles, labels, field names and values, attachment names): the Unicode string, UTF-8 encoded, where `\` becomes `\\`, LF `\n`, CR `\r`, TAB `\t`, any other character below 0x20 or equal to 0x7F becomes `\xNN` (uppercase hex). Everything else is written as is.

## Generated encrypted variants

`tests/corpus/generated/encrypted/` holds files made by `tools/oracle/generate-encrypted.ps1` from `base.pdf` (an unencrypted file with an `/Info /Producer`, a `/Metadata` XMP stream and two content streams, made by `Pdf4DOracle.java --prepare`): `rc4-40` (R2), `rc4-128` (R3), `aes-128` (R4), `aes-256` (R6), each with `-empty` (empty user password) and `-user` (user password `user`, noted as `password=user` in the manifest), owner password `owner`; `aes-256-nometa.pdf` (R6, `/EncryptMetadata false`, XMP stored unencrypted); `r5-sample.pdf` (R5, copy of a PDFBox test file). All decrypt to the same content as `base.pdf`, so apart from `encrypted`, `permissions` and the Encrypt dictionary object, their dumps equal the dump of `base.pdf`.
