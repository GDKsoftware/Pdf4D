// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tooling for the test corpus, not part of the library: draws the fictional invoice of tools/invoices/invoice.html with Skia
// (TSkDocument.MakePDF) into the PDF file named by the first argument, using the TrueType font named by the second argument.
program Pdf4D.InvoiceGen;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Skia;

type
  TInvoiceLine = record
    Item: string;
    Description: string;
    Quantity: string;
    UnitPrice: string;
    Amount: string;
  end;

const
  PageWidth = 595.28;
  PageHeight = 841.89;
  LeftMargin = 42.5;
  RightMargin = 552.8;
  BodyColor = $FF222222;
  GreyColor = $FF555555;
  RuleColor = $FF999999;
  AltRowColor = $FFEEF3F8;
  HeaderColor = $FF1F4E79;
  ColumnItem = 48.5;
  ColumnDescription = 110;
  ColumnQuantity = 380;
  ColumnUnitPrice = 460;
  ColumnAmount = 552.8;
  Lines: array[0..5] of TInvoiceLine = (
    (Item: 'A-100'; Description: 'Cedar planter box, small'; Quantity: '12'; UnitPrice: '18.50'; Amount: '222.00'),
    (Item: 'A-205'; Description: 'Copper watering can, 5 litre'; Quantity: '6'; UnitPrice: '42.75'; Amount: '256.50'),
    (Item: 'B-310'; Description: 'Garden twine, 200 m spool'; Quantity: '40'; UnitPrice: '3.20'; Amount: '128.00'),
    (Item: 'B-415'; Description: 'Pruning shears, forged steel'; Quantity: '8'; UnitPrice: '27.90'; Amount: '223.20'),
    (Item: 'C-020'; Description: 'Seed tray set, 12 pieces'; Quantity: '25'; UnitPrice: '9.95'; Amount: '248.75'),
    (Item: 'S-001'; Description: 'Freight and handling'; Quantity: '1'; UnitPrice: '35.00'; Amount: '35.00'));

  DetailLabels: array[0..3] of string = ('Invoice number', 'Invoice date', 'Due date', 'Customer number');
  DetailValues: array[0..3] of string = ('INV-2031-0417', '2031-03-14', '2031-04-13', 'C-90417');

var
  Typeface: ISkTypeface;

function MakeFont(const Size: Single; const Bold: Boolean): ISkFont;
begin
  Result := TSkFont.Create(Typeface, Size);
  Result.Embolden := Bold;
end;

function MakePaint(const Color: TAlphaColor; const Stroke: Boolean = False; const Width: Single = 1): ISkPaint;
begin
  Result := TSkPaint.Create;
  Result.AntiAlias := True;
  Result.Color := Color;
  if Stroke then
  begin
    Result.Style := TSkPaintStyle.Stroke;
    Result.StrokeWidth := Width;
  end;
end;

procedure DrawText(const Canvas: ISkCanvas; const Text: string; const X, Y, Size: Single; const Color: TAlphaColor; const Bold: Boolean = False);
begin
  Canvas.DrawSimpleText(Text, X, Y, MakeFont(Size, Bold), MakePaint(Color));
end;

procedure DrawRightText(const Canvas: ISkCanvas; const Text: string; const Right, Y, Size: Single; const Color: TAlphaColor; const Bold: Boolean = False);
begin
  const Font = MakeFont(Size, Bold);
  Canvas.DrawSimpleText(Text, Right - Font.MeasureText(Text), Y, Font, MakePaint(Color));
end;

procedure DrawHeader(const Canvas: ISkCanvas);
begin
  DrawText(Canvas, 'INVOICE', LeftMargin, 70, 26, HeaderColor, True);
  DrawText(Canvas, 'Quillon Harbor Trading Ltd', LeftMargin, 94, 10, BodyColor, True);
  DrawText(Canvas, '14 Foxglove Lane', LeftMargin, 107, 10, BodyColor);
  DrawText(Canvas, 'Exampleton 00000', LeftMargin, 120, 10, BodyColor);
  DrawText(Canvas, 'Testland', LeftMargin, 133, 10, BodyColor);

  for var Index := 0 to High(DetailLabels) do
  begin
    DrawText(Canvas, DetailLabels[Index], 380, 70 + Index * 14, 10, BodyColor);
    DrawRightText(Canvas, DetailValues[Index], RightMargin, 70 + Index * 14, 10, BodyColor, Index = 0);
  end;

  DrawText(Canvas, 'Bill to', LeftMargin, 175, 10, BodyColor, True);
  DrawText(Canvas, 'Marlowe Orchard Supplies Inc.', LeftMargin, 188, 10, BodyColor);
  DrawText(Canvas, '3 Imaginary Street', LeftMargin, 201, 10, BodyColor);
  DrawText(Canvas, 'Sampletown 99999', LeftMargin, 214, 10, BodyColor);
  DrawText(Canvas, 'Testland', LeftMargin, 227, 10, BodyColor);
end;

procedure DrawLines(const Canvas: ISkCanvas);
begin
  const Top = 250;
  const RowHeight = 20;
  Canvas.DrawRect(TRectF.Create(LeftMargin, Top, RightMargin, Top + RowHeight), MakePaint(HeaderColor));
  DrawText(Canvas, 'Item', ColumnItem, Top + 14, 9, TAlphaColors.White, True);
  DrawText(Canvas, 'Description', ColumnDescription, Top + 14, 9, TAlphaColors.White, True);
  DrawRightText(Canvas, 'Qty', ColumnQuantity, Top + 14, 9, TAlphaColors.White, True);
  DrawRightText(Canvas, 'Unit price', ColumnUnitPrice, Top + 14, 9, TAlphaColors.White, True);
  DrawRightText(Canvas, 'Amount', ColumnAmount - 6, Top + 14, 9, TAlphaColors.White, True);

  for var Index := 0 to High(Lines) do
  begin
    const RowTop = Top + RowHeight * (Index + 1);
    if Odd(Index) then
    begin
      Canvas.DrawRect(TRectF.Create(LeftMargin, RowTop, RightMargin, RowTop + RowHeight), MakePaint(AltRowColor));
    end;
    DrawText(Canvas, Lines[Index].Item, ColumnItem, RowTop + 14, 10, BodyColor);
    DrawText(Canvas, Lines[Index].Description, ColumnDescription, RowTop + 14, 10, BodyColor);
    DrawRightText(Canvas, Lines[Index].Quantity, ColumnQuantity, RowTop + 14, 10, BodyColor);
    DrawRightText(Canvas, Lines[Index].UnitPrice, ColumnUnitPrice, RowTop + 14, 10, BodyColor);
    DrawRightText(Canvas, Lines[Index].Amount, ColumnAmount - 6, RowTop + 14, 10, BodyColor);
    Canvas.DrawLine(LeftMargin, RowTop + RowHeight, RightMargin, RowTop + RowHeight, MakePaint(RuleColor, True, 0.5));
  end;
end;

procedure DrawTotals(const Canvas: ISkCanvas);
begin
  DrawText(Canvas, 'Subtotal', 380, 420, 10, BodyColor);
  DrawRightText(Canvas, '1,113.45', ColumnAmount - 6, 420, 10, BodyColor);
  DrawText(Canvas, 'VAT 21%', 380, 436, 10, BodyColor);
  DrawRightText(Canvas, '233.82', ColumnAmount - 6, 436, 10, BodyColor);
  Canvas.DrawLine(380, 444, RightMargin, 444, MakePaint(HeaderColor, True, 1.5));
  DrawText(Canvas, 'Total due (EUR)', 380, 460, 12, BodyColor, True);
  DrawRightText(Canvas, '1,347.27', ColumnAmount - 6, 460, 12, BodyColor, True);
end;

procedure DrawFooter(const Canvas: ISkCanvas);
begin
  DrawText(Canvas, 'Please pay within 30 days to account TL00 0000 0000 0000 00, quoting invoice number INV-2031-0417.', LeftMargin, 500, 10, BodyColor);
  DrawText(Canvas, 'This invoice is entirely fictional and was made as test data. All names, addresses, numbers and amounts are invented.', LeftMargin, 524, 7, GreyColor);
  DrawText(Canvas, 'Terms: late payments are subject to an interest charge of 1.5% per month on the outstanding balance. Goods remain the property', LeftMargin, 533, 7, GreyColor);
  DrawText(Canvas, 'of the seller until paid in full. Complaints must be reported in writing within 14 days after the date of delivery.', LeftMargin, 542, 7, GreyColor);
end;

procedure WriteInvoice(const PdfPath, FontPath: string);
begin
  Typeface := TSkTypeface.MakeFromFile(FontPath);
  if Typeface = nil then
  begin
    raise Exception.CreateFmt('Cannot load the font %s', [FontPath]);
  end;

  const Stream = TFileStream.Create(PdfPath, fmCreate);
  try
    // Neutral metadata: no author, fixed creation date
    const Moment = EncodeDate(2031, 3, 14);
    const Document = TSkDocument.MakePDF(Stream, TSkPDFMetadata.Create('Invoice INV-2031-0417', '', '', '', 'Pdf4D.InvoiceGen', Moment, Moment, 'Skia/PDF'));
    const Canvas = Document.BeginPage(PageWidth, PageHeight);
    DrawHeader(Canvas);
    DrawLines(Canvas);
    DrawTotals(Canvas);
    DrawFooter(Canvas);
    Document.EndPage;
    Document.Close;
  finally
    Stream.Free;
  end;
end;

begin
  try
    if ParamCount <> 2 then
    begin
      raise Exception.Create('Usage: Pdf4D.InvoiceGen <output.pdf> <font.ttf>');
    end;
    WriteInvoice(ParamStr(1), ParamStr(2));
  except
    on Failure: Exception do
    begin
      Writeln(ErrOutput, Failure.ClassName, ': ', Failure.Message);
      ExitCode := 1;
    end;
  end;
end.
