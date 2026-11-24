// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Print;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Types,
  FMX.Graphics,
  FMX.Printer,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Print;

type
  // Draws a band of a page on an FMX canvas that works in pixels: the one way every FMX print target puts pixels on paper
  TPdfFmxBandDrawer = class
  public
    // Stretches the band over Dest and draws nothing outside Clip. Dest may reach outside Clip, and a Dest that is empty or lies outside
    // it draws nothing. The band is premultiplied; it is shown on white paper. The canvas is in a scene while it draws.
    class procedure Draw(const Canvas: TCanvas; const Band: TPdfBitmap; const Dest, Clip: TRect); static;
  end;

  // Prints on a printer of FMX.Printer. The printable area is the page of the printer; the printer is not changed by the target other
  // than by printing on it.
  TPdfFmxPrinterTarget = class(TInterfacedObject, IPdfPrintTarget)
  private
    FPrinter: TPrinter;
    FPageCount: Integer;

    // A printer that has no resolution set yet (the active index is -1) gets the one that is nearest to PreferredDpi; the page size of
    // FMX follows the active resolution, so it is set before the size is asked
    procedure EnsureResolution;

  public
    // Sets the resolution of the active printer when it has none
    constructor Create(const Printer: TPrinter);

    // The printer pixels of a page; raises EPrinter when there is no printer
    function PrintableSize: TSize;
    // From the resolution that the active printer has set
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
  System.UITypes,
  FMX.Types,
  Pdf4D.Viewer.ResourceStrings;

resourcestring
  SFmxPrinterNoResolution = 'The printer has no resolution';
  SFmxPrinterPixelFormatUnsupported = 'The pixel format %d of the bitmap is not supported.';
  SFmxPrinterBitmapNotWritable = 'The bitmap of the band cannot be written.';

const
  BytesPerPixel = 4;
  FullChannel = 255;
  // The resolution to print at when the printer has not been given one
  PreferredDpi = 300;
  RedByte = 0;
  GreenByte = 1;
  BlueByte = 2;
  AlphaByte = 3;

type
  // The band as an opaque bitmap: the premultiplied pixels are put on white paper
  TPaperBitmap = class
  public
    class function Make(const Band: TPdfBitmap): TBitmap; static;
  end;

{ TPaperBitmap }

class function TPaperBitmap.Make(const Band: TPdfBitmap): TBitmap;
begin
  Result := TBitmap.Create(Band.Width, Band.Height);
  try
    var Data: TBitmapData;
    if not Result.Map(TMapAccess.Write, Data) then
    begin
      raise EInvalidOpException.Create(SFmxPrinterBitmapNotWritable);
    end;

    try
      const IsSwapped = (Data.PixelFormat = TPixelFormat.BGRA);
      if (not IsSwapped) and (Data.PixelFormat <> TPixelFormat.RGBA) then
      begin
        raise ENotSupportedException.CreateFmt(SFmxPrinterPixelFormatUnsupported, [Ord(Data.PixelFormat)]);
      end;

      var RedTarget := RedByte;
      var BlueTarget := BlueByte;
      if IsSwapped then
      begin
        RedTarget := BlueByte;
        BlueTarget := RedByte;
      end;
      for var Row := 0 to Band.Height - 1 do
      begin
        var Source := Band.ScanLine(Row);
        var Target := PByte(Data.GetScanline(Row));
        for var Column := 0 to Band.Width - 1 do
        begin
          // What the band does not cover is white
          const Uncovered = FullChannel - Source[AlphaByte];
          Target[RedTarget] := Source[RedByte] + Uncovered;
          Target[GreenByte] := Source[GreenByte] + Uncovered;
          Target[BlueTarget] := Source[BlueByte] + Uncovered;
          Target[AlphaByte] := FullChannel;
          Inc(Source, BytesPerPixel);
          Inc(Target, BytesPerPixel);
        end;
      end;
    finally
      Result.Unmap(Data);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TPdfFmxBandDrawer }

class procedure TPdfFmxBandDrawer.Draw(const Canvas: TCanvas; const Band: TPdfBitmap; const Dest, Clip: TRect);
begin
  const IsVisible = (Dest.Width > 0) and (Dest.Height > 0) and (not TRect.Intersect(Dest, Clip).IsEmpty);
  if not IsVisible then
  begin
    Exit;
  end;

  const Paper = TPaperBitmap.Make(Band);
  try
    if not Canvas.BeginScene then
    begin
      raise EInvalidOpException.Create(SPrintStretchFailed);
    end;

    try
      const SavedState = Canvas.SaveState;
      try
        Canvas.IntersectClipRect(TRectF.Create(Clip));
        // A band that is not stretched is copied as it is
        const IsSameSize = (Dest.Width = Band.Width) and (Dest.Height = Band.Height);
        Canvas.DrawBitmap(Paper, TRectF.Create(0, 0, Band.Width, Band.Height), TRectF.Create(Dest), 1, IsSameSize);
      finally
        Canvas.RestoreState(SavedState);
      end;
    finally
      Canvas.EndScene;
    end;
  finally
    Paper.Free;
  end;
end;

{ TPdfFmxPrinterTarget }

constructor TPdfFmxPrinterTarget.Create(const Printer: TPrinter);
begin
  inherited Create;

  if not Assigned(Printer) then
  begin
    raise EArgumentNilException.Create(SPrinterTargetNeedsPrinter);
  end;

  FPrinter := Printer;
  EnsureResolution;
end;

procedure TPdfFmxPrinterTarget.EnsureResolution;
begin
  const Device = FPrinter.ActivePrinter;
  const HasNone = Assigned(Device) and (Device.ActiveDPI.X <= 0) and (Device.DPICount > 0);
  if HasNone then
  begin
    Device.SelectDPI(PreferredDpi, PreferredDpi);
  end;
end;

function TPdfFmxPrinterTarget.PrintableSize: TSize;
begin
  Result := TSize.Create(FPrinter.PageWidth, FPrinter.PageHeight);
end;

function TPdfFmxPrinterTarget.Dpi: TPointF;
begin
  const Resolution = FPrinter.ActivePrinter.ActiveDPI;
  if (Resolution.X <= 0) or (Resolution.Y <= 0) then
  begin
    raise EPrinter.Create(SFmxPrinterNoResolution);
  end;
  Result := TPointF.Create(Resolution.X, Resolution.Y);
end;

// The copies are made by the printer driver. A driver that cannot make copies ignores them and prints one; the pages are not sent again
// for it.
procedure TPdfFmxPrinterTarget.BeginDocument(const Title: string; const Copies: Integer);
begin
  FPrinter.Title := Title;
  FPrinter.Copies := Copies;
  FPrinter.BeginDoc;
  FPageCount := 0;
end;

procedure TPdfFmxPrinterTarget.BeginPage;
begin
  if FPageCount > 0 then
  begin
    FPrinter.NewPage;
  end;
  Inc(FPageCount);
end;

procedure TPdfFmxPrinterTarget.DrawBand(const Band: TPdfBitmap; const Dest: TRect);
begin
  TPdfFmxBandDrawer.Draw(FPrinter.Canvas, Band, Dest, TRect.Create(0, 0, FPrinter.PageWidth, FPrinter.PageHeight));
end;

procedure TPdfFmxPrinterTarget.EndDocument;
begin
  FPrinter.EndDoc;
end;

procedure TPdfFmxPrinterTarget.AbortDocument;
begin
  FPrinter.Abort;
end;

end.
