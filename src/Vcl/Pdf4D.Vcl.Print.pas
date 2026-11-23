// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Print;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Types,
  Winapi.Windows,
  Vcl.Printers,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Print;

type
  // Draws a band of a page on a device context: the one way every VCL print target puts pixels on paper
  TPdfVclBandDrawer = class
  public
    // Stretches the band over Dest and draws nothing outside Clip. Dest may reach outside Clip, and a Dest that is empty or lies outside
    // it draws nothing. The band is premultiplied; it is shown on white paper.
    class procedure Draw(const DC: HDC; const Band: TPdfBitmap; const Dest, Clip: TRect); static;
  end;

  // Prints on a printer of Vcl.Printers. The printable area is the page of the printer; the printer is not changed by the target other
  // than by printing on it.
  TPdfVclPrinterTarget = class(TInterfacedObject, IPdfPrintTarget)
  private
    FPrinter: TPrinter;
    FPageCount: Integer;

  public
    constructor Create(const Printer: TPrinter);

    // The printer pixels of a page; raises EPrinter when there is no printer
    function PrintableSize: TSize;
    // From the resolution of the printer device
    function Dpi: TPointF;
    procedure BeginDocument(const Title: string; const Copies: Integer);
    // The first page is begun by BeginDocument; a new page is started from the second page on
    procedure BeginPage;
    procedure DrawBand(const Band: TPdfBitmap; const Dest: TRect);
    procedure EndDocument;
    procedure AbortDocument;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Viewer.ResourceStrings;

const
  BytesPerPixel = 4;
  FullChannel = 255;

{ TPdfVclBandDrawer }

class procedure TPdfVclBandDrawer.Draw(const DC: HDC; const Band: TPdfBitmap; const Dest, Clip: TRect);
begin
  const IsVisible = (Dest.Width > 0) and (Dest.Height > 0) and (not TRect.Intersect(Dest, Clip).IsEmpty);
  if not IsVisible then
  begin
    Exit;
  end;

  // Bytes B, G, R and an unused byte, rows top to bottom; the band is premultiplied, so what is not covered is white
  var Pixels: TBytes;
  SetLength(Pixels, Int64(Band.Width) * Band.Height * BytesPerPixel);
  for var Y := 0 to Band.Height - 1 do
  begin
    var Source := Band.ScanLine(Y);
    var Target := PByte(@Pixels[Int64(Y) * Band.Width * BytesPerPixel]);
    for var X := 0 to Band.Width - 1 do
    begin
      const Uncovered = FullChannel - Source[3];
      Target[0] := Source[2] + Uncovered;
      Target[1] := Source[1] + Uncovered;
      Target[2] := Source[0] + Uncovered;
      Target[3] := 0;
      Inc(Source, BytesPerPixel);
      Inc(Target, BytesPerPixel);
    end;
  end;

  var Info: TBitmapInfo;
  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(Info.bmiHeader);
  Info.bmiHeader.biWidth := Band.Width;
  // A negative height: the rows are top to bottom
  Info.bmiHeader.biHeight := -Band.Height;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;

  const SavedState = SaveDC(DC);
  try
    IntersectClipRect(DC, Clip.Left, Clip.Top, Clip.Right, Clip.Bottom);
    SetStretchBltMode(DC, HALFTONE);
    SetBrushOrgEx(DC, 0, 0, nil);
    const Lines = StretchDIBits(DC, Dest.Left, Dest.Top, Dest.Width, Dest.Height, 0, 0, Band.Width, Band.Height, @Pixels[0], Info,
                                DIB_RGB_COLORS, SRCCOPY);
    if Lines <= 0 then
    begin
      raise EInvalidOpException.Create(SPrintStretchFailed);
    end;
  finally
    RestoreDC(DC, SavedState);
  end;
end;

{ TPdfVclPrinterTarget }

constructor TPdfVclPrinterTarget.Create(const Printer: TPrinter);
begin
  inherited Create;

  if not Assigned(Printer) then
  begin
    raise EArgumentNilException.Create('A printer target needs a printer');
  end;

  FPrinter := Printer;
end;

function TPdfVclPrinterTarget.PrintableSize: TSize;
begin
  Result := TSize.Create(FPrinter.PageWidth, FPrinter.PageHeight);
end;

function TPdfVclPrinterTarget.Dpi: TPointF;
begin
  Result := TPointF.Create(GetDeviceCaps(FPrinter.Handle, LOGPIXELSX), GetDeviceCaps(FPrinter.Handle, LOGPIXELSY));
end;

procedure TPdfVclPrinterTarget.BeginDocument(const Title: string; const Copies: Integer);
begin
  FPrinter.Title := Title;
  FPrinter.Copies := Copies;
  FPrinter.BeginDoc;
  FPageCount := 0;
end;

procedure TPdfVclPrinterTarget.BeginPage;
begin
  if FPageCount > 0 then
  begin
    FPrinter.NewPage;
  end;
  Inc(FPageCount);
end;

procedure TPdfVclPrinterTarget.DrawBand(const Band: TPdfBitmap; const Dest: TRect);
begin
  TPdfVclBandDrawer.Draw(FPrinter.Canvas.Handle, Band, Dest, TRect.Create(0, 0, FPrinter.PageWidth, FPrinter.PageHeight));
end;

procedure TPdfVclPrinterTarget.EndDocument;
begin
  FPrinter.EndDoc;
end;

procedure TPdfVclPrinterTarget.AbortDocument;
begin
  FPrinter.Abort;
end;

end.
