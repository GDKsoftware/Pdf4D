# Pdf4D

Pdf4D is a native Delphi port of [Apache PDFBox](https://pdfbox.apache.org/) 3.0.8 for reading PDF files: document structure, pages, outlines, form fields and attachments. It has no dependencies besides the Delphi RTL.

## Platforms

- Delphi 12 or later (developed with Delphi 13)
- Win32, Win64 and Linux64
- RTL only: no `Winapi.*`, `Vcl.*` or `FMX.*` units and no inline assembler

## Status

Milestone M1 (document structure) is complete: loading, decryption, pages, document information, outlines, form fields, attachments and the public API. Text extraction, fonts and content streams follow in later milestones. See `coding-rules.md`, `docs/porting.md` and `docs/building.md`.

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

## Building and testing

```powershell
./build.ps1 -Platform All
```

## License

Apache License 2.0, see `LICENSE` and `NOTICE`. Pdf4D is a derived work of Apache PDFBox.
