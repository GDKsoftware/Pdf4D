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
`label`: `''` (empty) when the catalog has no `/PageLabels` (or it is not a dictionary); otherwise the label of that page index from `PDDocumentCatalog.getPageLabels().getLabelsByPageIndices()`, escaped as text (below); a missing entry is empty. When PDFBox throws while reading the labels, every label of the document is `''`. The array has `PDDocument.getNumberOfPages()` (the `/Count` of the page tree) entries. `TPDPageLabels.Create(Document, Dictionary)` reads the number tree.

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

## Known differences

`tests/golden/<name>.known-differences.txt` lists lines of a dump that are allowed to differ from the golden file. One entry per line, in the form `<prefix> # <reason>`. Lines starting with `#` and empty lines are ignored.

- `<prefix>`: a line of the dump (expected or found) that starts with it is not compared, for example `object 12 0:`.
- `<prefix> ignore-key /Key`: the line is still compared, but the entry `/Key <value>` (an integer, a reference `n g R` or a name such as `/Outlines`) is removed from both sides first. The hash of a stream and all other keys stay in the comparison. Example: `object 12 0: ignore-key /Length # reason`. A name value is used for `object 296 0: ignore-key /Type`, where PDFBox adds `/Type /Outlines` to the outline root: `/Count`, `/First` and `/Last` of that line are still compared. This is used for the encrypted files, where PDFBox rewrites `/Length` of a stream dictionary to the decrypted size and Pdf4D keeps the value of the file.

## How dumps are compared

The acceptance test (`tests/Support/Pdf4D.Tests.Golden.pas`) compares the dump of Pdf4D with the golden file line by line:

- A line is compared exactly. Only a CR and spaces or tabs at the end of a line are dropped. Leading and inner whitespace is data: the two spaces per level of an `outline:` line carry the nesting, and spaces in titles, labels, field values and info values are part of the value.
- There is no whitespace leniency for the structure dump. The extracted text (`.text.txt` files) has its own comparison rule, see "Text goldens". Structure sections never get leniency.
- A number with a decimal point may differ by 0.001 from the golden value. The text around the numbers must be equal.
- Lines are matched by `object <n> <g>:`, `page <i>:` and `info <key>:` as their start, all others by kind and position. A key that occurs twice in one dump is a difference.
- Known differences (above) are the only other leniency.

## Text goldens

`tests/golden/<name>.text.txt` holds the text that the PDFBox 3.0.8 `PDFTextStripper` extracts, written by `Pdf4DOracle text <pdf> [password]` (`generate-golden.ps1 -Mode Text`). `<name>` and the password rule are the same as for the dump. UTF-8 without BOM, LF, no trailing spaces on a line, every line ends with LF.

### Sections

```
text: default page <n>        one section per page n = 1 .. min(pages, 50)
text: sorted page <n>         the same with setSortByPosition(true)
text: range 2-3               setStartPage(2), setEndPage(3), one section
text: separators 1-2          pages 1-2 with the separators below
```

The sections come in this order: all `default` pages, all `sorted` pages, `range`, `separators`. `pages` is the number of pages found by iterating the page tree (as in the dump). `range` and `separators` are always written, also when the document has fewer pages (the section is then empty).

Every section uses a new `PDFTextStripper` with `setLineSeparator("
")` and `setPageEnd("
")`, and for the per-page sections `setStartPage(n)`, `setEndPage(n)`. All other settings are the PDFBox defaults.
`separators` uses `setLineSeparator("<EOL>
")`, `setWordSeparator("<W>")`, `setParagraphStart("<P>")`, `setParagraphEnd("</P>")`, `setPageStart("<PAGE>")`, `setPageEnd("</PAGE>
")`, `setArticleStart("<A>")` and `setArticleEnd("</A>")`.

### Lines

The text is split at LF. The empty piece after the last LF is dropped (an empty text gives a section without lines). Every piece becomes `| ` + the text escaped as "Escaped text" above (so a CR is ``, a TAB is `	`); when the text ends in a space, that last space is written as ` ` so that no line ends in a space. A piece that is empty becomes `|`. Text that is outside the BMP is written as its UTF-8 sequence; an unpaired surrogate (which the stripper can produce from broken input) is written as `?` by the oracle.

When the stripper throws, the heading is followed by one line `error`. A file that cannot be opened gives only `load-error: <kind>` (kinds as for the dump).

### Hermetic fonts

The oracle (every mode) installs a font provider without fonts in `FontMappers.instance()` (`FontMapperImpl.setProvider`, by reflection), so installed system fonts never influence the result. A non-embedded font that is not one of the standard 14 falls back to the built-in LiberationSans. This only affects the text and the width files, not the structure dump.

### Comparison

1. The list of headings must be exactly equal. A missing or extra section is a difference.
2. For each section: when the lines are exactly equal, the section is fine.
3. Otherwise compare leniently: remove the leading `| ` (or `|`) on both sides, undo the escapes, replace every run of spaces and tabs by one space, trim, and drop lines that are empty after that. When the two lists are then equal, the section is *leniently equal*: not an error, but counted and reported in the test output.
4. Otherwise the difference is the first line that differs, reported with section heading and line number.
5. Known differences are listed in `tests/golden/<name>.text-known-differences.txt`, one per line: `<prefix of a heading> [<platform>] # <reason>`. The platform (`Win32`, `Win64` or `Linux64`) is optional. A section whose heading starts with the prefix is not compared on that platform (or on any platform). Empty lines and lines starting with `#` are ignored.
6. This leniency applies only to `.text.txt`. The structure dump is compared exactly.

## Font width files

`tests/fonts/<font file>.widths.txt` (for example `LiberationSans-Regular.ttf.widths.txt`) is written by `Pdf4DOracle --font-widths <font>` (`tools/oracle/generate-font-widths.ps1`) for the test fonts in `tests/fonts/` (sources and licences in `tests/fonts/manifest.csv`). One line `<key> <width>` per glyph, sorted by key in ordinal (character code) order, so `gid10` comes before `gid2`. Widths are in font units in float format.

- Type 1 (`.pfb`): key is the glyph name, width is `Type1Font.getWidth(name)`.
- CFF (also inside `.otf`): key `gid<n>` for n = 0 .. number of charstrings - 1, width is `CFFFont.getType2CharString(n).getWidth()`.
- TrueType (`.ttf`, and `.otf` without CFF): key `gid<n>`, width is the advance width from `hmtx` (`TrueTypeFont.getAdvanceWidth(n)`).
