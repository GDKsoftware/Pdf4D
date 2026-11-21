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

Every section uses a new `PDFTextStripper` with `setLineSeparator("\n")` and `setPageEnd("\n")`, and for the per-page sections `setStartPage(n)`, `setEndPage(n)`. All other settings are the PDFBox defaults.
`separators` uses `setLineSeparator("<EOL>\n")`, `setWordSeparator("<W>")`, `setParagraphStart("<P>")`, `setParagraphEnd("</P>")`, `setPageStart("<PAGE>")`, `setPageEnd("</PAGE>\n")`, `setArticleStart("<A>")` and `setArticleEnd("</A>")`.

### Lines

The text is split at LF. The empty piece after the last LF is dropped (an empty text gives a section without lines). Every piece becomes `| ` + the text escaped as "Escaped text" above (so a CR is `\r`, a TAB is `\t`); when the text ends in a space, that last space is written as `\x20` so that no line ends in a space. A piece that is empty becomes `|`. Text that is outside the BMP is written as its UTF-8 sequence; an unpaired surrogate (which the stripper can produce from broken input) is written as `?` by the oracle.

When the stripper throws, the heading is followed by one line `error`. A Pdf4D exception (any `EPdfException` descendant, or any other exception) raised while extracting a section maps to that same single `error` line; the message is not compared. A file that cannot be opened gives only `load-error: <kind>` (kinds as for the dump). When the oracle run for a text golden hits the time limit while the dump loaded, `generate-golden.ps1` writes `load-error: timeout` (a kind that only text goldens have). Pdf4D never produces it, so such a golden fails the comparison until the file is looked at; it is never silently accepted.

### Hermetic fonts

The oracle (every mode) installs a font provider without fonts in `FontMappers.instance()` (`FontMapperImpl.setProvider`, by reflection), so installed system fonts never influence the result. A non-embedded font that is not one of the standard 14 falls back to the built-in LiberationSans. This only affects the text and the width files, not the structure dump.

### Comparison

1. The list of headings must be exactly equal. A missing or extra section is a difference.
2. For each section: when the lines are exactly equal, the section is fine.
3. Otherwise compare leniently, in this order, on both sides: (a) remove the leading `| ` (or `|`); (b) undo the escapes; (c) replace every run of spaces and tabs by one space ("space" is U+0020 only, so a no-break space U+00A0 is data and never collapsed); (d) trim, which removes U+0020 and TAB at both ends of the line; (e) drop lines that are empty after that. The leniency hides runs of spaces, leading indentation, a trailing `\x20`, and the number and position of blank lines. Paragraph structure is therefore only checked in the `separators` section, where the `<P>` and `</P>` markers are text. When the two lists are then equal, the section is *leniently equal*: not an error, but counted and reported in the test output.
4. Otherwise the difference is the first line that differs, reported with section heading and line number.
5. Known differences are listed in `tests/golden/<name>.text-known-differences.txt`, one per line: `<heading> [<platform>] # <reason>`. `<heading>` is the complete heading, matched exactly: `text: default page 1` does not match `text: default page 10`. A line is skipped only when its heading text before the optional platform and the `#` (trailing spaces removed) equals the section heading. The platform (`Win32`, `Win64` or `Linux64`) is optional and written in literal square brackets. A section with a matching entry is not compared on that platform (or on any platform when there is none). Empty lines and lines starting with `#` are ignored.

   Examples:

   ```
   text: default page 1 [Win64] # glyph order differs on Win64 only
   text: sorted page 10 # differs on every platform
   ```

   The first line skips only `text: default page 1`, and only on Win64. The second skips only `text: sorted page 10`, on all platforms.
6. This leniency applies only to `.text.txt`. The structure dump is compared exactly.

## Position goldens

`tests/golden/<name>.positions.txt` holds the positions of the text lines that the PDFBox 3.0.8 `PDFTextStripper` finds, written by `Pdf4DOracle positions <pdf> [password]` (`generate-golden.ps1 -Mode Positions`). `<name>` and the password rule are the same as for the dump. UTF-8 without BOM, LF. One file per corpus file, one line per line of the stripper (not per word, which would make the files seven times larger).

```
page <n>
line: <x> <y> <endX> <endY> <glyphs>
```

The stripper is a subclass with `setSortByPosition(true)`, `setStartPage(1)` and `setEndPage(min(pages, 50))`; all other settings are the PDFBox defaults. `startPage` writes the `page <n>` line, so a page that the stripper skips (a page without content) has no line. `writeString(String, List<TextPosition>)` collects the positions of a line; `writeLineSeparator` and `endPage` end the line. A line without positions is not written.

- `x`, `y`: translate of the text matrix of the first glyph of the line (`TextPosition.getTextMatrix().getTranslateX()` and `getTranslateY()`), relative to the lower left corner of the crop box;
- `endX`, `endY`: `getEndX()` and `getEndY()` of the last glyph of the line;
- `glyphs`: the number of positions in the line.

Numbers are written with `%.2f` in `Locale.ROOT` (so `NaN` and `Infinity` as Java writes them). When the stripper throws, a line `error` ends the file. A file that cannot be opened gives only `load-error: <kind>`, as for the text goldens. A file without any page with text gives an empty golden, which is correct and is compared as such.

Comparison (`tests/Acceptance/Pdf4D.Tests.PositionGolden.Tests.pas`):

1. The `page` and `line` lines of both sides are compared one by one: the line kinds and the `glyphs` values must be equal.
2. The four numbers of a line may differ by 0.02.
3. Known differences are listed in `tests/golden/<name>.positions.known-differences.txt`, one per line: `<page> [<platform>] # <reason>`, where `<page>` is the number of a page. The page is then skipped (on that platform, or on every platform without one). Empty lines and lines starting with `#` are ignored. A load error or a different set of pages is always compared. An `error` line is a line of the last page before it, so it is skipped together with that page.

## Font width files

`tests/fonts/<font file>.widths.txt` (for example `LiberationSans-Regular.ttf.widths.txt`) is written by `Pdf4DOracle --font-widths <font>` (`tools/oracle/generate-font-widths.ps1`) for the test fonts in `tests/fonts/` (sources and licences in `tests/fonts/manifest.csv`). One line `<key> <width>` per glyph, sorted by key in ordinal (character code) order, so `gid10` comes before `gid2`. Widths are in font units in float format.

- Type 1 (`.pfb`): key is the glyph name, width is `Type1Font.getWidth(name)`.
- CFF (also inside `.otf`): key `gid<n>` for n = 0 .. number of charstrings - 1, width is `CFFFont.getType2CharString(n).getWidth()`.
- TrueType (`.ttf`, and `.otf` without CFF): key `gid<n>`, width is the advance width from `hmtx` (`TrueTypeFont.getAdvanceWidth(n)`).

## Glyph path files

`tests/fonts/<font file>.paths.txt` is written by `Pdf4DOracle --glyph-paths <font>` (`tools/oracle/generate-font-widths.ps1 -Paths`) for the Type 1, CFF and TrueType test fonts (`.pfb`, `.otf` and `.ttf`). One line `<key> <commands>` per glyph, the first 300 glyphs of the font, sorted by key in ordinal order. The commands come from the path iterator of the `getPath()` of FontBox, in glyph space and separated by single spaces: `M x y`, `L x y`, `Q x1 y1 x y`, `C x1 y1 x2 y2 x y` and `Z`, with the numbers in float format. A glyph with an empty path has the key only. A glyph whose charstring PDFBox cannot turn into a path is left out.

- Type 1 (`.pfb`): key is the glyph name, the first 300 names in ordinal order, path is `Type1Font.getPath(name)`.
- CFF (inside `.otf`): key `gid<n>` for n = 0 .. 299 for a name-keyed font (`CFFType1Font.getType2CharString(n).getPath()`), and `cid<n>` for a CID-keyed font, where n is the CID of the first 300 GIDs (`CFFCIDFont.getType2CharString(n).getPath()`).
- TrueType (`.ttf`): key `gid<n>` for n = 0 .. 299, path is `TrueTypeFont.getGlyph().getGlyph(n).getPath()` in font units (a glyph without contours has the key only).

### Paths of PDF fonts

`tests/fonts/glyph-paths/<file>.pdf.paths.txt` is written by `Pdf4DOracle --pdf-glyph-paths <file>.pdf F1 <first>-<last>` (`tools/oracle/generate-font-widths.ps1 -PdfPaths`) for the small PDF files next to it, which `tools/oracle/make-glyph-path-pdfs.py` writes from the test fonts (one page, the font under test is `/F1`). One line per character code from `<first>` to `<last>` (0-255 for a simple font, 0-299 for the files that start with `cid-`): `<code> <hasGlyph> <commands>`. `hasGlyph` is `1` or `0` from `PDVectorFont.hasGlyph(code)`. The commands are those of `PDVectorFont.getNormalizedPath(code)`, in the format of the glyph path files above; a code with an empty path has no commands, and `!` stands for a code that PDFBox fails on. The path is in the glyph space of the font program that PDFBox gives, which is not always 1000 units per em: only the TrueType and CIDFontType2 fonts are scaled to 1000 (the font matrix of the font scales the others, for instance a standard 14 font that is replaced by LiberationSans stays in its 2048 units).

## Function reference files

`tests/reference/functions/<name>.txt` is written by `Pdf4DOracle --function <spec>` (`tools/oracle/generate-functions.ps1`) from the spec files `tools/oracle/function-specs/<name>.spec`. A spec file holds blocks that start with a `case: <name>` line, followed by `key: value` lines that describe one function and one `in: <numbers>` line for every evaluation. The oracle builds the function with PDFBox (`PDFunction.create`) and repeats every line of the spec; it adds ` out: <numbers>` behind each `in:` line, the result of `PDFunction.eval` in float format (`NaN` and `Infinity` as Java writes them). Lines that start with `#` are comments.

- Keys: `type` (0, 2, 3 or 4), `domain`, `range`, `size`, `encode`, `decode`, `c0`, `c1`, `bounds` (numbers separated by blanks), `n`, `bps` (BitsPerSample), `samples` (hex digits of the data of a type 0 function; a half byte at the end is dropped), `code` (the program of a type 4 function, where `\n` stands for a line break) and `sub2` (type 3: `c0 | c1 | n` of one type 2 function with Domain `[0 1]`, once for every function).
- `out: !` is an evaluation that PDFBox fails on (an exception). Pdf4D must not raise there, and its result is not compared.
- `create: !` (before the first `in:` line of a case) is a function that PDFBox cannot make; Pdf4D raises `EPdfParseException` for it.
- `TestFunctionsMatchPdfBox` compares every other value with a tolerance of 1e-4 (and 1e-6 relative for values above 100).

## Colour reference files

`tests/reference/color/<name>.txt` is written by `Pdf4DOracle --color-batch <spec>` (`tools/oracle/generate-colors.ps1`), one file for `DeviceCMYK` (the profile that `PDDeviceCMYK` loads) and one for each ICC profile in `tests/icc` (`sRGB`, `gray-small`, `gray-gamma`, `cmyk-printer`; the grey and CMYK profiles are the ICC streams of three PDFs in the corpus, see `tests/icc/manifest.csv`). The file starts with `profile: <name>` and holds 200 `in: <numbers>` lines: a grid over the device values (11 steps for 1 component, 5 for 3, 3 for 4) followed by values of a fixed linear congruential generator. The oracle repeats every line and adds ` out: r g b` behind each `in:` line: `ICC_ColorSpace.toRGB` of the profile, in float format. `--color <profile.icc|DeviceCMYK> c1 c2 ...` does one colour, and `intent: n` in a spec (not used in the reference files) overwrites the rendering intent of the header; Java gives the same colour for every intent, so the A2B0 table is the one to use.

- `TestCmykMatchesJava`, `TestSrgbMatchesJava` and `TestCorpusProfilesMatchJava` compare every value with a tolerance of 0.25/255 per channel; the largest difference measured is 0.05/255.

## Image reference files

`tests/reference/images/<file with / replaced by __>/p<page>-<index>.png` is written by `Pdf4DOracle images <pdf> <outdir> [password]` (`tools/oracle/generate-images.ps1`) for the files listed in `tests/reference/images/selection.txt` (one path relative to `tests/corpus` per line, `#` starts a comment). The oracle walks the pages in order (`<page>` counts from 1) and, per page, the entries of `/XObject` in the resources in the order of the dictionary; `<index>` counts from 0 over the image XObjects among them. Each file is `PDImageXObject.getImage()` written by `ImageIO` as it is: an RGB, ARGB or 8-bit gray PNG (a one-bit gray image is written as gray), without any scaling. Images of more than 360000 pixels and images that PDFBox cannot decode (for instance JPEG 2000 without a plugin) have no file. At most 24 images per page. `images.txt` in the same folder lists every image of the file as `<page>-<index>`, the resource name, `<width>x<height>`, `bpc`, the colour space, the filters and `ok`, `skipped: large` or `error: <exception>`.

- `tests/corpus/generated/render/images.pdf` is written by `tools/oracle/make-render-tests.py` (standard library only, deterministic): 1, 2, 4, 8 and 16 bits, `/Decode`, a colour key mask, stencil masks, an `/SMask` smaller and larger than its image, a `/Mask` stream, `/Interpolate`, DeviceCMYK, an ASCIIHexDecode image and three inline images. It has the usual dump, text and position goldens.
- `TestImagesMatchPdfBox` (`Pdf4D.Graphics.Image.SampledReader.Tests`) compares `TPDImage.TryGetImage` with each file, both flattened on white, with at most 1 per channel. Images with a CCITT, JPEG 2000 or JBIG2 filter, and with a JPEG filter (see `TestCorpusJpegImagesMatch`), and the colour spaces that are not ported yet are left out until their tasks are done.
- `tests/corpus/generated/render/jpeg.pdf` is written by `tools/oracle/make-jpeg-tests.py` (Pillow, only to run the script) from the JPEG files in `tests/reference/jpeg`: the generated `gray.jpg`, `rgb420.jpg`, `rgb444.jpg`, `progressive.jpg` (the same coefficients as `rgb420.jpg`), `restart.jpg` (a restart interval, the same coefficients), `cmyk.jpg` (Adobe transform 0), and `pdfbox-jpeg.jpg`, `pdfbox-jpeg256.jpg` and `pdfbox-jpegcmyk.jpg` (the YCCK file), which are `jpeg.jpg`, `jpeg256.jpg` and `jpegcmyk.jpg` of the PDFBox test resources. The files are committed, so the PDF does not depend on the Pillow version; running the script again rewrites the PDF from them. The page lists the images as 11 XObjects, each with the usual image reference in `tests/reference/images/generated__render__jpeg.pdf` (`generate-images.ps1` and `selection.txt`) and the usual dump, text and position goldens.
- `Pdf4D.Codec.Jpeg.Tests` compares the DCT images of `jpeg.pdf` and of the other files of the selection with those references: at most 4 per channel and 0.5 on average for the named tests (the inverted CMYK image 12 per channel), and 12 and 0.4 over the images of the corpus (`TestCorpusJpegImagesMatch`). The measured differences are 3 and 0.13 for the generated 4:2:0 images. What is left comes from the integer IDCT and the colour conversion of pdf.js against libjpeg; the chroma upsampling is the same (triangle filter of libjpeg, `TJpegUpsampling`).
- `Pdf4D.Codec.CCITTFax.Tests` decodes the Group 3 and Group 4 images of `ccitt.pdf` and compares them byte for byte with `tests/reference/ccitt/ccitt.raw`: the picture of `ccittg3.tif` and `ccittg4.tif` as Pillow decodes it, in the samples of the DeviceGray image (1 bit per pixel, black is 0, rows padded to bytes). The other tests build their bit streams in the test; `TestCorpusCcittImages` decodes the CCITT images of the corpus files and the render comparison of `pending.txt` holds the pixels.

## Render reference files

`tests/reference/render/<dpi>/` holds the pages as PDFBox 3.0.8 renders them: `PDFRenderer.renderImageWithDPI(page, dpi, ImageType.RGB)` with the hermetic font mapper, white background, anti-aliasing on, written as an 8-bit RGB PNG with the strongest compression of the Java writer. `tools/oracle/generate-render.ps1 -Dpi 72|150 [-Filter <part of the path>]` runs `Pdf4DOracle render <pdf> <dpi> <outdir> [password]` for every file of the corpus (72) or for the pages in `150/selection.txt` (`<corpus file>;<page>` per line, `#` starts a comment), four files at a time, with a time-out of 120 seconds per file, and reports the total size in MB at the end. The references come from the pinned Temurin release in `tools/oracle/fetch-jdk.ps1` (the Marlin rasterizer inside the JDK draws the pixels); change the release and its checksum there, and regenerate the references, together.

- `<name>.p<nnn>.png`: page `nnn` (three digits, from 1) of the file; `<name>` is the path relative to `tests/corpus` with `/` replaced by `__`, with the `.pdf`, as in `tests/golden` (`generated__render__paths.pdf.p001.png`). The 72 DPI set holds pages 1 to min(pages, 50); the 150 DPI set only the listed pages.
- `<name>.render.txt`: one line per page, `page <n> <width> <height> ok` or `page <n> error <JavaExceptionClass>` (no PNG for such a page), or only `load-error: <kind>` (`parse`, `unsupported`, `wrong-password`, `timeout`). A file whose manifest notes contain `password=<x>` is opened with that password.

### Comparison

`TRenderCompare` (`tests/Support/Pdf4D.Tests.RenderCompare.pas`) compares two bitmaps; the acceptance test `TRenderGoldenTests.TestCorpus72Dpi` (`tests/Skia/Acceptance`) renders every page of the `render.txt` that says `ok` with `RenderToBitmap(FromDpi(72))` and compares it with the PNG.

- The reference decides what a pixel is. A pixel is an *edge* pixel when one colour channel of the reference differs by more than `FlatRange` (8) inside the 3 x 3 pixels around it; the others are *flat*. A flat pixel differs when a channel differs by more than `FlatTolerance` (8), an edge pixel when a channel differs by more than `EdgeTolerance` (80).
- A page is equal when the sizes are equal, at most `MaxFlatDifferentFraction` (0.02%) of its flat pixels differ and at most `MaxEdgeDifferentFraction` (3.5%) of its edge pixels differ. So a wrong colour or a missing shape fails (flat), and the coverage noise of the two rasterizers at the edges of shapes and glyphs does not. All these numbers are constants of `TRenderCompare`.
- The constants are the smallest values that every compared page passes, taken from the distribution of the 631 pages that are compared (612 at 72 DPI, 19 at 150 DPI of the selection; the pages with a known difference are not in it). The share is that of the pixels of the kind (flat or edge) of the page that differ by more than the tolerance; the worst page of the corpus is listed:

  | Flat tolerance | worst page, share of its flat pixels | | Edge tolerance | worst page, share of its edge pixels |
  |---|---|---|---|---|
  | 0 | softmask.pdf 18.3% | | 16 | a page of PDFBOX-3949 36.6% |
  | 2 | softmask.pdf 0.79% | | 32 | PDFBOX-3053-reduced.pdf 15.7% |
  | 4 | softmask.pdf 0.14% | | 64 | PDFBOX-3053-reduced.pdf 5.7% |
  | 5 | softmask.pdf 0.062% | | 70 | PDFBOX-3053-reduced.pdf 4.7% |
  | 6 | softmask.pdf 0.0145% | | 80 | PDFBOX-3053-reduced.pdf 3.2% |
  | 8 | survey.pdf at 150 DPI 0.0099% | | 96 | generated/render/clip.pdf 2.5% |
  | 16 | survey.pdf at 150 DPI 0.0099% | | 224 | generated/render/clip.pdf 1.8% |

  Over all compared pages with the constants: flat share median 0, 90th percentile 0, 99th percentile 0.0005%, largest 0.0099%; edge share median 0, 90th percentile 0.05%, 99th percentile 1.35%, largest 3.23%. The causes of what remains: JPEG IDCT and ICC conversion (PDFBox uses LittleCMS, Pdf4D its own code) give up to 6 levels in flat areas; anti-aliasing of glyphs and shapes gives the edge differences. The flat tolerance is 8: the worst page falls from 0.14% at 4 and 0.062% at 5 to 0.0145% at 6 and 0.0099% at 8, and stays there to 32 (survey.pdf at 150 DPI, the seams of the Indexed images, which is real); 8 is the first value of that plateau and leaves a margin for the rounding of one level on another platform. The edge tolerance is 80: the curve falls without a plateau (5.7% at 64, 3.2% at 80), 80 is the value from which the worst page is a page with glyph edges only. The edge limit is 8% above the worst page. An earlier set of constants (5.5%) was only needed for PDFBOX-6207.pdf, whose QR code of 1296 small squares is filled without anti-aliasing and differed by a pixel at the edge of every square; that was a defect (the fill edge rule, see `docs/porting.md`) and is fixed.
- The test fails, also for a pending file, when the `render.txt` or a PNG of a listed page is missing or cannot be read, when the `render.txt` is empty, or when its number of `page` lines is not min(pages, 50). A file without pages gets the line `pages: 0`. An exception of the render is a difference of a file that is not pending; in a pending file only `EPdfUnsupportedFeatureException` is.
- `tests/reference/render/no-reference.txt` (`<corpus file> # <listing>`) names the files that have no `ok` page (`load-error`, `pages: 0`); `TestFilesWithoutReferenceAreListed` fails when the files in the generated listings differ from it, so a timeout or a truncated listing cannot make a file pass unseen. `generate-render.ps1` exits with an error when a file timed out.
- `TestRegionEqualsCropOfFullPage`: a region is the crop of the full page, with a tolerance of 8 and 0.06% of the pixels, leaving out 4 pixels along the border (Skia covers a path that the border cuts differently); `generated/render/images.pdf` gets 1.35% (1.23% measured) because of texels that lie exactly on a pixel centre in the nearest neighbour sampling. The reasons are in the test unit.
- A page that PDFBox cannot render (`error` in `render.txt`) and a file with a `load-error` are not compared; Pdf4D must not raise on them, which the robustness tests cover.
- When `PDF4D_RENDER_FILTER` holds substrings of corpus paths separated by semicolons, `TestCorpus72Dpi` only runs the files that match (for looking at one difference without the whole corpus).
- When `PDF4D_RENDER_OUTPUT` names a folder, `summary.txt` gets a line per compared page, `distribution.txt` the histogram of the differences of its flat and its edge pixels (what the constants above were taken from), `region.txt` the pixels of each region that differ for a range of tolerances and `performance.txt` the medians of the performance test. A page that differs is written there as `<name>.p<nnn>.png` (the Pdf4D render) and `<name>.p<nnn>.diff.png` (red where a pixel differs, the reference dimmed elsewhere).
- Known differences: `tests/reference/render/<name>.render-known-differences.txt`, one line `page <n> [<platform>] # <reason>` per page (`<platform>` is `Win32`, `Win64` or `Linux64`; without it the page is skipped everywhere). Empty lines and lines that start with `#` are ignored. The differences of a 150 DPI page are in `<name>.render-150dpi-known-differences.txt` in the same folder (same format), so that a page that differs only at 150 DPI keeps its 72 DPI comparison.
- The 150 DPI set is `tests/reference/render/150/selection.txt` (`<corpus file>;<page>`): about twenty pages with fine details (thin lines, small text, patterns, shadings, CCITT, tiger) and the first page of every invoice of `tests/corpus/generated/invoices`. `TestSelection150Dpi` renders the selected pages at 150 DPI and compares them with the same rules; a missing listing or reference, or an image without a selection line, fails.
- Performance: `TRenderPerformanceTests` (`tests/Skia/Acceptance`, Release on Win64 only; skipped elsewhere) renders the first page of every invoice of `tests/corpus/generated/invoices` at 96 DPI (scale 4/3) with Skia five times and requires a median of at most 100 ms. Measured medians: edge-print 10 ms, word-print 13 ms, word-export 13 ms, skia-draw 33 ms.
- Known differences left: the annotations without `/AP` (`constructAppearances` is not ported; `generated/render/annotations.pdf` pages 1 to 3 and `pdfbox/input/compression/attachment.pdf` page 1), `pdfbox/input/rendering/survey.pdf` page 1 (0.05% flat pixels: seams of the Indexed images at fractional positions), and the 150 DPI pages `generated/render/transparency.pdf`, `softmask.pdf` and `patterns.pdf` (PDFBox draws a transparency group in a y-up space with the scale only and flips it onto the page with a whole-pixel offset; the pixel grid of the group is then shifted against the page by the fraction of the page height in pixels, which is whole at 72 DPI and not at 150 DPI for 400 pt). `pending.txt` is empty.
- Pending: `tests/reference/render/pending.txt`, one line `<corpus file> # Task <n>: <subject>` per file that uses a feature that is not built yet. The pages of a pending file are rendered and reported but a difference is not a failure. When every page of a pending file is equal the test fails with "remove from pending.txt", so the list only shrinks. It must be empty when the renderer is done.

### Synthetic test files

`tests/corpus/generated/render/` also holds the files that `tools/oracle/generate-render-tests.ps1` writes: `make-render-pdfs.py` (standard library only, deterministic) writes `paths`, `clip`, `text-modes`, `colors-device`, `colors-special`, `transparency`, `softmask`, `shadings`, `patterns`, `optional-content`, `annotations` and `rotated`; `Pdf4DOracle make-render-tests ccitt` writes `ccitt.pdf` with `CCITTFactory` from `tests/reference/ccitt/ccittg3.tif` and `ccittg4.tif` (written with Pillow, committed). They have the usual dump, text and position goldens.
