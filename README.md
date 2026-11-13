# Pdf4D

Pdf4D is a native Delphi port of [Apache PDFBox](https://pdfbox.apache.org/) 3.0.8 for reading PDF files: document structure, pages, text extraction, outlines, form fields and attachments. It has no dependencies besides the Delphi RTL.

## Platforms

- Delphi 12 or later (developed with Delphi 13)
- Win32, Win64 and Linux64
- RTL only: no `Winapi.*`, `Vcl.*` or `FMX.*` units and no inline assembler

## Status

Early development. The repository currently holds the conventions and the test harness. See `coding-rules.md`, `docs/porting.md` and `docs/building.md`.

## Building and testing

```powershell
./build.ps1 -Platform All
```

## License

Apache License 2.0, see `LICENSE` and `NOTICE`. Pdf4D is a derived work of Apache PDFBox.
