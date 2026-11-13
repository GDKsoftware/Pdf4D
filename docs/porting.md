# Porting from PDFBox

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
- `TPDField` carries a `Kind` instead of a subclass per field type.
- No bidirectional text processing.
- Images are not decoded.
