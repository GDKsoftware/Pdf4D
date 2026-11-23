// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Painter;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  Vcl.Graphics,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Painter.Interfaces;

type
  // What the painter needs from an image of this unit: the GDI bitmap that holds its pixels
  IPdfVclImageSource = interface
    ['{5E2B7C94-1A63-4D08-B9F5-3C8E0D6A2174}']
    function Bitmap: Vcl.Graphics.TBitmap;
  end;

  // A picture in the format of GDI: a 32 bit bitmap in BGRA order that holds a copy of the pixels
  TPdfVclImage = class(TInterfacedObject, IPdfViewImage, IPdfVclImageSource)
  private
    FBitmap: Vcl.Graphics.TBitmap;

    function GetBitmap: Vcl.Graphics.TBitmap;
    function IPdfVclImageSource.Bitmap = GetBitmap;

  public
    // Copies the pixels of Bitmap and swaps its R and B bytes, so that they are in the order of GDI
    constructor Create(const Bitmap: TPdfBitmap);
    destructor Destroy; override;

    function Width: Integer;
    function Height: Integer;

    // Owned by the image
    property Bitmap: Vcl.Graphics.TBitmap read GetBitmap;
  end;

  // Paints in device pixels on a canvas: images with GDI, shapes with GDI+ so that they are anti-aliased and can be translucent
  TPdfVclPainter = class(TInterfacedObject, IPdfViewPainter)
  private
    FCanvas: TCanvas;

    class function ToArgb(const Color: TAlphaColor): Cardinal; static;
    class function ToGdiColor(const Color: TAlphaColor): TColor; static;

  public
    // The canvas must outlive the painter
    constructor Create(const Canvas: TCanvas);

    procedure FillRect(const Rect: TRectF; const Color: TAlphaColor);
    procedure DrawImage(const Image: IPdfViewImage; const Source: TRect; const Dest: TRectF);
    procedure FillPolygon(const Points: TArray<TPointF>; const Color: TAlphaColor);
    procedure FramePolygon(const Points: TArray<TPointF>; const Color: TAlphaColor; const Width: Single);
    procedure FillEllipse(const Rect: TRectF; const Color: TAlphaColor);
    procedure FrameEllipse(const Rect: TRectF; const Color: TAlphaColor; const Width: Single);
    procedure DrawText(const Text: string; const Rect: TRectF; const Color: TAlphaColor);
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.GDIPAPI,
  Winapi.GDIPOBJ;

type
  // GDI+ must be started once per process and stopped at the end. The painters are used on the UI thread only.
  TPdfGdiPlus = class
  private
    class var FToken: ULONG_PTR;
    class var FIsStarted: Boolean;

    class destructor Destroy;

  public
    class procedure EnsureStarted; static;
  end;

const
  RedByte = 0;
  GreenByte = 1;
  BlueByte = 2;
  AlphaByte = 3;
  BytesPerPixel = 4;
  FirstGdiPlusVersion = 1;

{ TPdfGdiPlus }

class procedure TPdfGdiPlus.EnsureStarted;
begin
  if FIsStarted then
  begin
    Exit;
  end;

  var Input: TGdiplusStartupInput;
  Input.GdiplusVersion := FirstGdiPlusVersion;
  Input.DebugEventCallback := nil;
  Input.SuppressBackgroundThread := False;
  Input.SuppressExternalCodecs := False;

  FIsStarted := (GdiplusStartup(FToken, @Input, nil) = Ok);
end;

class destructor TPdfGdiPlus.Destroy;
begin
  if FIsStarted then
  begin
    GdiplusShutdown(FToken);
    FIsStarted := False;
  end;
end;

{ TPdfVclImage }

{$POINTERMATH ON}

constructor TPdfVclImage.Create(const Bitmap: TPdfBitmap);
begin
  inherited Create;
  FBitmap := Vcl.Graphics.TBitmap.Create;
  try
    FBitmap.PixelFormat := pf32bit;
    FBitmap.SetSize(Bitmap.Width, Bitmap.Height);

    for var Row := 0 to Bitmap.Height - 1 do
    begin
      var Source := Bitmap.ScanLine(Row);
      var Target := PByte(FBitmap.ScanLine[Row]);
      for var Column := 0 to Bitmap.Width - 1 do
      begin
        Target[BlueByte] := Source[RedByte];
        Target[GreenByte] := Source[GreenByte];
        Target[RedByte] := Source[BlueByte];
        Target[AlphaByte] := Source[AlphaByte];
        Inc(Source, BytesPerPixel);
        Inc(Target, BytesPerPixel);
      end;
    end;
  except
    FBitmap.Free;
    raise;
  end;
end;

destructor TPdfVclImage.Destroy;
begin
  FBitmap.Free;
  inherited;
end;

{$POINTERMATH OFF}

function TPdfVclImage.GetBitmap: Vcl.Graphics.TBitmap;
begin
  Result := FBitmap;
end;

function TPdfVclImage.Width: Integer;
begin
  Result := FBitmap.Width;
end;

function TPdfVclImage.Height: Integer;
begin
  Result := FBitmap.Height;
end;

{ TPdfVclPainter }

constructor TPdfVclPainter.Create(const Canvas: TCanvas);
begin
  inherited Create;
  FCanvas := Canvas;
  TPdfGdiPlus.EnsureStarted;
end;

// TAlphaColor and the ARGB of GDI+ have the same layout
class function TPdfVclPainter.ToArgb(const Color: TAlphaColor): Cardinal;
begin
  Result := Cardinal(Color);
end;

class function TPdfVclPainter.ToGdiColor(const Color: TAlphaColor): TColor;
begin
  const Parts = TAlphaColorRec(Color);
  Result := TColor(RGB(Parts.R, Parts.G, Parts.B));
end;

procedure TPdfVclPainter.FillRect(const Rect: TRectF; const Color: TAlphaColor);
begin
  const Graphics = TGPGraphics.Create(FCanvas.Handle);
  try
    // Rectangles in whole pixels: no smoothing, so that neighbours do not show seams
    Graphics.SetSmoothingMode(SmoothingModeNone);
    const Brush = TGPSolidBrush.Create(ToArgb(Color));
    try
      Graphics.FillRectangle(Brush, Rect.Left, Rect.Top, Rect.Width, Rect.Height);
    finally
      Brush.Free;
    end;
  finally
    Graphics.Free;
  end;
end;

procedure TPdfVclPainter.DrawImage(const Image: IPdfViewImage; const Source: TRect; const Dest: TRectF);
begin
  var ImageSource: IPdfVclImageSource;
  if (not Supports(Image, IPdfVclImageSource, ImageSource)) or Source.IsEmpty then
  begin
    Exit;
  end;

  // The edges are rounded, not the size, so that tiles that touch stay touching
  const Target = TRect.Create(Round(Dest.Left), Round(Dest.Top), Round(Dest.Right), Round(Dest.Bottom));
  if Target.IsEmpty then
  begin
    Exit;
  end;

  const TargetDc = FCanvas.Handle;
  const MemoryDc = CreateCompatibleDC(TargetDc);
  const OldBitmap = SelectObject(MemoryDc, ImageSource.Bitmap.Handle);
  try
    const IsSameSize = (Source.Width = Target.Width) and (Source.Height = Target.Height);
    if IsSameSize then
    begin
      BitBlt(TargetDc, Target.Left, Target.Top, Target.Width, Target.Height, MemoryDc, Source.Left, Source.Top, SRCCOPY);
    end
    else
    begin
      SetStretchBltMode(TargetDc, HALFTONE);
      SetBrushOrgEx(TargetDc, 0, 0, nil);
      StretchBlt(TargetDc, Target.Left, Target.Top, Target.Width, Target.Height, MemoryDc, Source.Left, Source.Top, Source.Width,
                 Source.Height, SRCCOPY);
    end;
  finally
    SelectObject(MemoryDc, OldBitmap);
    DeleteDC(MemoryDc);
  end;
end;

procedure TPdfVclPainter.FillPolygon(const Points: TArray<TPointF>; const Color: TAlphaColor);
begin
  if Length(Points) < 3 then
  begin
    Exit;
  end;

  var GdiPoints: TArray<TGPPointF>;
  SetLength(GdiPoints, Length(Points));
  for var Index := 0 to High(Points) do
  begin
    GdiPoints[Index] := MakePoint(Points[Index].X, Points[Index].Y);
  end;

  const Graphics = TGPGraphics.Create(FCanvas.Handle);
  try
    Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    const Brush = TGPSolidBrush.Create(ToArgb(Color));
    try
      Graphics.FillPolygon(Brush, PGPPointF(@GdiPoints[0]), Length(GdiPoints));
    finally
      Brush.Free;
    end;
  finally
    Graphics.Free;
  end;
end;

procedure TPdfVclPainter.FramePolygon(const Points: TArray<TPointF>; const Color: TAlphaColor; const Width: Single);
begin
  if Length(Points) < 2 then
  begin
    Exit;
  end;

  var GdiPoints: TArray<TGPPointF>;
  SetLength(GdiPoints, Length(Points));
  for var Index := 0 to High(Points) do
  begin
    GdiPoints[Index] := MakePoint(Points[Index].X, Points[Index].Y);
  end;

  const Graphics = TGPGraphics.Create(FCanvas.Handle);
  try
    Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    const Pen = TGPPen.Create(ToArgb(Color), Width);
    try
      Pen.SetLineJoin(LineJoinMiter);
      Graphics.DrawPolygon(Pen, PGPPointF(@GdiPoints[0]), Length(GdiPoints));
    finally
      Pen.Free;
    end;
  finally
    Graphics.Free;
  end;
end;

procedure TPdfVclPainter.FillEllipse(const Rect: TRectF; const Color: TAlphaColor);
begin
  const Graphics = TGPGraphics.Create(FCanvas.Handle);
  try
    Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    const Brush = TGPSolidBrush.Create(ToArgb(Color));
    try
      Graphics.FillEllipse(Brush, Rect.Left, Rect.Top, Rect.Width, Rect.Height);
    finally
      Brush.Free;
    end;
  finally
    Graphics.Free;
  end;
end;

procedure TPdfVclPainter.FrameEllipse(const Rect: TRectF; const Color: TAlphaColor; const Width: Single);
begin
  const Graphics = TGPGraphics.Create(FCanvas.Handle);
  try
    Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    const Pen = TGPPen.Create(ToArgb(Color), Width);
    try
      Graphics.DrawEllipse(Pen, Rect.Left, Rect.Top, Rect.Width, Rect.Height);
    finally
      Pen.Free;
    end;
  finally
    Graphics.Free;
  end;
end;

procedure TPdfVclPainter.DrawText(const Text: string; const Rect: TRectF; const Color: TAlphaColor);
begin
  if Text = '' then
  begin
    Exit;
  end;

  FCanvas.Brush.Style := bsClear;
  FCanvas.Font.Color := ToGdiColor(Color);

  var TextRect := TRect.Create(Round(Rect.Left), Round(Rect.Top), Round(Rect.Right), Round(Rect.Bottom));
  Winapi.Windows.DrawText(FCanvas.Handle, PChar(Text), Length(Text), TextRect,
                          DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
end;

end.
