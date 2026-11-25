// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ViewerDocuments;

interface

uses
  System.SysUtils,
  Pdf4D.Tests.PdfBuilder;

type
  // Small documents for the tests of the viewer, with Helvetica 12 on Letter pages unless the method says otherwise
  TViewerDocuments = class
  private
    const InvoiceFont = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
    const FontObject = 10;
    const ImageObject = 11;
    const FirstPageObject = 100;
    const FirstContentObject = 1000;
    const FirstLinkObject = 20;

  private
    class function ContentBytes(const Content: string): TBytes; static;
    class function PageBody(const Content: Integer; const Entries: string): string; static;
    class function Finish(const Builder: TTestPdfBuilder): TBytes; static;
    class function NewBuilder(const Kids: string; const Count: Integer): TTestPdfBuilder; static;
    class function PagesBody(const PageCount: Integer): string; static;

  public
    // Two Letter pages. Page 0 has "Factuur 2024-0815" at (100,700), "Nummer: 2024-0815" at (100,680), a GoTo link [100 600 200 620] to
    // page 1 and a URI link [100 560 200 580] to https://example.com/. Page 1 has "Bedrag" and, on a line of its own below it, the euro
    // sign and "12,50".
    class function Invoice: TBytes; static;
    // PageCount pages of the given size and rotation, each with the text "Page <n>" (n from 1)
    class function Pages(const PageCount: Integer; const Width, Height, Rotation: Integer): TBytes; static;
    // One page that holds an image and no text
    class function Scanned: TBytes; static;
    // The page of the invoice with /Rotate 90 and /CropBox [50 50 562 742]
    class function RotatedCropped: TBytes; static;
    // A page tree without pages
    class function ZeroPages: TBytes; static;
    // Two Letter pages and an outline of two levels: "Chapter 1" (page 0) with "Section 1.1" (page 1), then "Chapter 2" (page 1)
    class function Outlined: TBytes; static;
    // One Letter page and an outline of ItemCount items on one level, all pointing at that page
    class function LargeOutline(const ItemCount: Integer): TBytes; static;
  end;

implementation

uses
  Pdf4D.Model.Tests.Support;

const
  FirstOutlineObject = 31;
  OutlineRootObject = 30;
  FirstPageContent = 'BT /F1 12 Tf 100 700 Td (Factuur 2024-0815) Tj 0 -20 Td (Nummer: 2024-0815) Tj ET';
  SecondPageContent = 'BT /F1 12 Tf 100 700 Td (Bedrag) Tj 0 -20 Td (\200 12,50) Tj ET';
  ScannedContent = 'q 400 0 0 400 100 200 cm /Im1 Do Q';
  PageFormat = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 10 0 R >> >> %s >>';
  ScannedPageFormat = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /XObject << /Im1 11 0 R >> >> >>';
  ImageDictionary = '/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8';

{ TViewerDocuments }

class function TViewerDocuments.ContentBytes(const Content: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Content);
end;

class function TViewerDocuments.PageBody(const Content: Integer; const Entries: string): string;
begin
  Result := Format(PageFormat, [Content, Entries]);
end;

class function TViewerDocuments.NewBuilder(const Kids: string; const Count: Integer): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder(Format('<< /Type /Pages /Kids [%s] /Count %d >>', [Kids, Count]));
end;

class function TViewerDocuments.Finish(const Builder: TTestPdfBuilder): TBytes;
begin
  try
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

class function TViewerDocuments.Invoice: TBytes;
begin
  const Builder = NewBuilder('3 0 R 5 0 R', 2);
  try
    const FirstLink = FirstLinkObject;
    const SecondLink = FirstLinkObject + 1;
    Builder.AddObject(3, PageBody(4, Format('/Annots [%d 0 R %d 0 R]', [FirstLink, SecondLink])));
    Builder.AddStreamObject(4, '', ContentBytes(FirstPageContent));
    Builder.AddObject(5, PageBody(6, ''));
    Builder.AddStreamObject(6, '', ContentBytes(SecondPageContent));
    Builder.AddObject(FirstLink, '<< /Type /Annot /Subtype /Link /Rect [100 600 200 620] /Border [0 0 0] /Dest [5 0 R /XYZ 0 792 0] >>');
    Builder.AddObject(SecondLink, '<< /Type /Annot /Subtype /Link /Rect [100 560 200 580] /Border [0 0 0] ' +
                                  '/A << /S /URI /URI (https://example.com/) >> >>');
    Builder.AddObject(FontObject, InvoiceFont);
  except
    Builder.Free;
    raise;
  end;
  Result := Finish(Builder);
end;

class function TViewerDocuments.PagesBody(const PageCount: Integer): string;
begin
  const Kids = TStringBuilder.Create;
  try
    for var Index := 0 to PageCount - 1 do
    begin
      Kids.AppendFormat('%d 0 R ', [FirstPageObject + Index]);
    end;
    Result := Kids.ToString;
  finally
    Kids.Free;
  end;
end;

class function TViewerDocuments.Pages(const PageCount: Integer; const Width, Height, Rotation: Integer): TBytes;
begin
  const Builder = NewBuilder(PagesBody(PageCount), PageCount);
  try
    for var Index := 0 to PageCount - 1 do
    begin
      const Entries = Format('/MediaBox [0 0 %d %d] /Rotate %d', [Width, Height, Rotation]);
      Builder.AddObject(FirstPageObject + Index,
                        Format('<< /Type /Page /Parent 2 0 R /Contents %d 0 R /Resources << /Font << /F1 10 0 R >> >> %s >>',
                               [FirstContentObject + Index, Entries]));
      Builder.AddStreamObject(FirstContentObject + Index, '', ContentBytes(Format('BT /F1 12 Tf 20 20 Td (Page %d) Tj ET', [Index + 1])));
    end;
    Builder.AddObject(FontObject, InvoiceFont);
  except
    Builder.Free;
    raise;
  end;
  Result := Finish(Builder);
end;

class function TViewerDocuments.Scanned: TBytes;
begin
  const Builder = NewBuilder('3 0 R', 1);
  try
    Builder.AddObject(3, Format(ScannedPageFormat, [4]));
    Builder.AddStreamObject(4, '', ContentBytes(ScannedContent));
    Builder.AddStreamObject(ImageObject, ImageDictionary, TBytes.Create(0, 85, 170, 255));
  except
    Builder.Free;
    raise;
  end;
  Result := Finish(Builder);
end;

class function TViewerDocuments.RotatedCropped: TBytes;
begin
  const Builder = NewBuilder('3 0 R', 1);
  try
    Builder.AddObject(3, PageBody(4, '/Rotate 90 /CropBox [50 50 562 742]'));
    Builder.AddStreamObject(4, '', ContentBytes(FirstPageContent));
    Builder.AddObject(FontObject, InvoiceFont);
  except
    Builder.Free;
    raise;
  end;
  Result := Finish(Builder);
end;

class function TViewerDocuments.ZeroPages: TBytes;
begin
  Result := Finish(NewBuilder('', 0));
end;

class function TViewerDocuments.Outlined: TBytes;
begin
  const Builder = NewBuilder('3 0 R 5 0 R', 2);
  try
    Builder.AddObject(1, Format('<< /Type /Catalog /Pages 2 0 R /Outlines %d 0 R >>', [OutlineRootObject]));
    Builder.AddObject(3, PageBody(4, ''));
    Builder.AddStreamObject(4, '', ContentBytes(FirstPageContent));
    Builder.AddObject(5, PageBody(6, ''));
    Builder.AddStreamObject(6, '', ContentBytes(SecondPageContent));
    Builder.AddObject(FontObject, InvoiceFont);
    Builder.AddObject(OutlineRootObject, '<< /Type /Outlines /First 31 0 R /Last 32 0 R /Count 3 >>');
    Builder.AddObject(31, '<< /Title (Chapter 1) /Parent 30 0 R /Next 32 0 R /First 33 0 R /Last 33 0 R /Count 1 /Dest [3 0 R /Fit] >>');
    Builder.AddObject(32, '<< /Title (Chapter 2) /Parent 30 0 R /Prev 31 0 R /Dest [5 0 R /Fit] >>');
    Builder.AddObject(33, '<< /Title (Section 1.1) /Parent 31 0 R /Dest [5 0 R /Fit] >>');
  except
    Builder.Free;
    raise;
  end;
  Result := Finish(Builder);
end;

class function TViewerDocuments.LargeOutline(const ItemCount: Integer): TBytes;
begin
  const Builder = NewBuilder('3 0 R', 1);
  try
    Builder.AddObject(1, Format('<< /Type /Catalog /Pages 2 0 R /Outlines %d 0 R >>', [OutlineRootObject]));
    Builder.AddObject(3, PageBody(4, ''));
    Builder.AddStreamObject(4, '', ContentBytes(FirstPageContent));
    Builder.AddObject(FontObject, InvoiceFont);
    const LastItem = FirstOutlineObject + ItemCount - 1;
    Builder.AddObject(OutlineRootObject, Format('<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count %d >>',
                                                [FirstOutlineObject, LastItem, ItemCount]));
    for var Index := 0 to ItemCount - 1 do
    begin
      const Number = FirstOutlineObject + Index;
      var Entries := Format('/Title (Item %d) /Parent %d 0 R /Dest [3 0 R /Fit]', [Index, OutlineRootObject]);
      if Index > 0 then
      begin
        Entries := Entries + Format(' /Prev %d 0 R', [Number - 1]);
      end;
      if Index < ItemCount - 1 then
      begin
        Entries := Entries + Format(' /Next %d 0 R', [Number + 1]);
      end;
      Builder.AddObject(Number, '<< ' + Entries + ' >>');
    end;
  except
    Builder.Free;
    raise;
  end;
  Result := Finish(Builder);
end;

end.
