// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Painter;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  System.Math.Vectors,
  FMX.Graphics,
  FMX.Types,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Painter.Interfaces;

type
  // What the painter needs from an image of this unit: the FMX bitmap that holds its pixels
  IPdfFmxImageSource = interface
    ['{B3F0A5D2-6E19-4C87-A2D4-91C75E08B3F6}']
    function Bitmap: FMX.Graphics.TBitmap;
  end;

  // A picture in the format of FMX: a bitmap in the pixel format of the platform, with premultiplied alpha, that holds a copy of the pixels
  TPdfFmxImage = class(TInterfacedObject, IPdfViewImage, IPdfFmxImageSource)
  private
    FBitmap: FMX.Graphics.TBitmap;

    function GetBitmap: FMX.Graphics.TBitmap;
    function IPdfFmxImageSource.Bitmap = GetBitmap;
    // One 32-bit word per pixel: the red and the blue byte trade places
    class procedure SwapRedAndBlue(const Source: PByte; const Target: PByte; const PixelCount: Integer); static;

  public
    // Copies the pixels of Bitmap into a bitmap of the platform; the colours keep their value and their premultiplied alpha
    constructor Create(const Bitmap: TPdfBitmap);
    destructor Destroy; override;

    // Writes the pixels of Source into the memory that Target describes, in the pixel format of Target (RGBA and BGRA, both with
    // premultiplied alpha). Raises ENotSupportedException for another format and EArgumentException when Target is smaller than Source.
    class procedure CopyPixels(const Source: TPdfBitmap; const Target: TBitmapData); static;

    function Width: Integer;
    function Height: Integer;

    // Owned by the image
    property Bitmap: FMX.Graphics.TBitmap read GetBitmap;
  end;

  // Paints in device pixels on an FMX canvas that works in logical units: every coordinate is divided by the scale of the canvas
  TPdfFmxPainter = class(TInterfacedObject, IPdfViewPainter)
  private
    FCanvas: TCanvas;
    FScale: Single;
    FOrigin: TPointF;
    FFont: TFont;

    function ToLogical(const Point: TPointF): TPointF; overload;
    // The device pixel that an edge falls on: the position on the screen is rounded, not the position in the control, so that a control at
    // a fractional offset still draws on whole device pixels. The result is relative to the control.
    function SnapEdge(const Edge, Origin: Single): Single;
    // The edges are rounded to whole device pixels before the division, so that neighbours touch without a seam
    function ToLogicalPixels(const Rect: TRectF): TRectF;
    function ToLogicalExact(const Rect: TRectF): TRectF;
    function ToPolygon(const Points: TArray<TPointF>): TPolygon;
    procedure UseFill(const Color: TAlphaColor);
    procedure UseStroke(const Color: TAlphaColor; const Width: Single);

  public
    // The canvas and the font must outlive the painter. Scale is the scale of the canvas: device pixels per logical unit.
    constructor Create(const Canvas: TCanvas; const Scale: Single; const Font: TFont); overload;
    // Origin is where the origin of the canvas lies on the screen, in device pixels, which is not a whole number when the control that
    // paints sits at a fractional offset
    constructor Create(const Canvas: TCanvas; const Scale: Single; const Font: TFont; const Origin: TPointF); overload;

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
  FMX.TextLayout;

resourcestring
  SFmxPixelFormatUnsupported = 'The pixel format %d of the bitmap is not supported.';
  SFmxTargetTooSmall = 'The target of %d x %d pixels is smaller than the %d x %d pixels of the source.';
  SFmxBitmapNotWritable = 'The bitmap of the picture cannot be written.';
  SFmxScaleInvalid = 'Scale %g is not a positive number';

const
  BytesPerPixel = 4;
  // As a little-endian word, a pixel is alpha, blue, green, red; the red and blue bytes are 16 bits apart
  GreenAndAlphaMask = $FF00FF00;
  LowByteMask = $FF;
  RedBlueDistance = 16;
  FullOpacity = 1;

{ TPdfFmxImage }

{$POINTERMATH ON}

constructor TPdfFmxImage.Create(const Bitmap: TPdfBitmap);
begin
  inherited Create;
  FBitmap := FMX.Graphics.TBitmap.Create(Bitmap.Width, Bitmap.Height);
  try
    var Data: TBitmapData;
    if not FBitmap.Map(TMapAccess.Write, Data) then
    begin
      raise EInvalidOpException.Create(SFmxBitmapNotWritable);
    end;

    try
      CopyPixels(Bitmap, Data);
    finally
      FBitmap.Unmap(Data);
    end;
  except
    FBitmap.Free;
    raise;
  end;
end;

destructor TPdfFmxImage.Destroy;
begin
  FBitmap.Free;
  inherited;
end;

class procedure TPdfFmxImage.CopyPixels(const Source: TPdfBitmap; const Target: TBitmapData);
begin
  const IsSwapped = (Target.PixelFormat = TPixelFormat.BGRA);
  if (not IsSwapped) and (Target.PixelFormat <> TPixelFormat.RGBA) then
  begin
    raise ENotSupportedException.CreateFmt(SFmxPixelFormatUnsupported, [Ord(Target.PixelFormat)]);
  end;

  if (Target.Width < Source.Width) or (Target.Height < Source.Height) then
  begin
    raise EArgumentException.CreateFmt(SFmxTargetTooSmall, [Target.Width, Target.Height, Source.Width, Source.Height]);
  end;

  const RowBytes = Source.Width * BytesPerPixel;
  for var Row := 0 to Source.Height - 1 do
  begin
    if IsSwapped then
    begin
      SwapRedAndBlue(Source.ScanLine(Row), PByte(Target.GetScanline(Row)), Source.Width);
    end
    else
    begin
      Move(Source.ScanLine(Row)^, Target.GetScanline(Row)^, RowBytes);
    end;
  end;
end;

// One 32-bit word per pixel: the red and the blue byte trade places, the green and the alpha byte stay
class procedure TPdfFmxImage.SwapRedAndBlue(const Source: PByte; const Target: PByte; const PixelCount: Integer);
begin
  var Pixel := PCardinal(Source);
  var Line := PCardinal(Target);
  for var Column := 0 to PixelCount - 1 do
  begin
    const Value = Pixel^;
    Line^ := (Value and GreenAndAlphaMask) or ((Value and LowByteMask) shl RedBlueDistance) or ((Value shr RedBlueDistance) and LowByteMask);
    Inc(Pixel);
    Inc(Line);
  end;
end;

{$POINTERMATH OFF}

function TPdfFmxImage.GetBitmap: FMX.Graphics.TBitmap;
begin
  Result := FBitmap;
end;

function TPdfFmxImage.Width: Integer;
begin
  Result := FBitmap.Width;
end;

function TPdfFmxImage.Height: Integer;
begin
  Result := FBitmap.Height;
end;

{ TPdfFmxPainter }

constructor TPdfFmxPainter.Create(const Canvas: TCanvas; const Scale: Single; const Font: TFont);
begin
  Create(Canvas, Scale, Font, TPointF.Zero);
end;

constructor TPdfFmxPainter.Create(const Canvas: TCanvas; const Scale: Single; const Font: TFont; const Origin: TPointF);
begin
  inherited Create;
  if not (Scale > 0) then
  begin
    raise EArgumentOutOfRangeException.CreateFmt(SFmxScaleInvalid, [Scale]);
  end;

  FCanvas := Canvas;
  FScale := Scale;
  FOrigin := Origin;
  FFont := Font;
end;

function TPdfFmxPainter.ToLogical(const Point: TPointF): TPointF;
begin
  Result := TPointF.Create(Point.X / FScale, Point.Y / FScale);
end;

function TPdfFmxPainter.SnapEdge(const Edge, Origin: Single): Single;
begin
  Result := Round(Origin + Edge) - Origin;
end;

function TPdfFmxPainter.ToLogicalPixels(const Rect: TRectF): TRectF;
begin
  Result := TRectF.Create(SnapEdge(Rect.Left, FOrigin.X) / FScale, SnapEdge(Rect.Top, FOrigin.Y) / FScale,
                          SnapEdge(Rect.Right, FOrigin.X) / FScale, SnapEdge(Rect.Bottom, FOrigin.Y) / FScale);
end;

function TPdfFmxPainter.ToLogicalExact(const Rect: TRectF): TRectF;
begin
  Result := TRectF.Create(Rect.Left / FScale, Rect.Top / FScale, Rect.Right / FScale, Rect.Bottom / FScale);
end;

function TPdfFmxPainter.ToPolygon(const Points: TArray<TPointF>): TPolygon;
begin
  SetLength(Result, Length(Points));
  for var Index := 0 to High(Points) do
  begin
    Result[Index] := ToLogical(Points[Index]);
  end;
end;

procedure TPdfFmxPainter.UseFill(const Color: TAlphaColor);
begin
  FCanvas.Fill.Kind := TBrushKind.Solid;
  FCanvas.Fill.Color := Color;
end;

procedure TPdfFmxPainter.UseStroke(const Color: TAlphaColor; const Width: Single);
begin
  FCanvas.Stroke.Kind := TBrushKind.Solid;
  FCanvas.Stroke.Color := Color;
  FCanvas.Stroke.Thickness := Width / FScale;
  FCanvas.Stroke.Join := TStrokeJoin.Miter;
end;

procedure TPdfFmxPainter.FillRect(const Rect: TRectF; const Color: TAlphaColor);
begin
  UseFill(Color);
  FCanvas.FillRect(ToLogicalPixels(Rect), FullOpacity);
end;

procedure TPdfFmxPainter.DrawImage(const Image: IPdfViewImage; const Source: TRect; const Dest: TRectF);
begin
  var ImageSource: IPdfFmxImageSource;
  if (not Supports(Image, IPdfFmxImageSource, ImageSource)) or Source.IsEmpty then
  begin
    Exit;
  end;

  // The edges are rounded, not the size, so that tiles that touch stay touching
  const Target = ToLogicalPixels(Dest);
  const TargetWidth = Round(Target.Width * FScale);
  const TargetHeight = Round(Target.Height * FScale);
  if (TargetWidth <= 0) or (TargetHeight <= 0) then
  begin
    Exit;
  end;

  // A picture that is not scaled is copied pixel for pixel, without filtering
  const IsSameSize = (Source.Width = TargetWidth) and (Source.Height = TargetHeight);
  FCanvas.DrawBitmap(ImageSource.Bitmap, TRectF.Create(Source), Target, FullOpacity, IsSameSize);
end;

procedure TPdfFmxPainter.FillPolygon(const Points: TArray<TPointF>; const Color: TAlphaColor);
begin
  if Length(Points) < 3 then
  begin
    Exit;
  end;

  UseFill(Color);
  FCanvas.FillPolygon(ToPolygon(Points), FullOpacity);
end;

procedure TPdfFmxPainter.FramePolygon(const Points: TArray<TPointF>; const Color: TAlphaColor; const Width: Single);
begin
  if Length(Points) < 2 then
  begin
    Exit;
  end;

  UseStroke(Color, Width);
  FCanvas.DrawPolygon(ToPolygon(Points), FullOpacity);
end;

procedure TPdfFmxPainter.FillEllipse(const Rect: TRectF; const Color: TAlphaColor);
begin
  UseFill(Color);
  FCanvas.FillEllipse(ToLogicalExact(Rect), FullOpacity);
end;

procedure TPdfFmxPainter.FrameEllipse(const Rect: TRectF; const Color: TAlphaColor; const Width: Single);
begin
  UseStroke(Color, Width);
  FCanvas.DrawEllipse(ToLogicalExact(Rect), FullOpacity);
end;

procedure TPdfFmxPainter.DrawText(const Text: string; const Rect: TRectF; const Color: TAlphaColor);
begin
  if Text = '' then
  begin
    Exit;
  end;

  const Area = ToLogicalExact(Rect);
  const Layout = TTextLayoutManager.DefaultTextLayout.Create(FCanvas);
  try
    Layout.BeginUpdate;
    try
      Layout.Text := Text;
      if Assigned(FFont) then
      begin
        Layout.Font.Assign(FFont);
      end;
      Layout.Color := Color;
      Layout.Opacity := FullOpacity;
      Layout.TopLeft := Area.TopLeft;
      Layout.MaxSize := TPointF.Create(Area.Width, Area.Height);
      Layout.WordWrap := False;
      Layout.Trimming := TTextTrimming.Character;
      Layout.HorizontalAlign := TTextAlign.Center;
      Layout.VerticalAlign := TTextAlign.Center;
    finally
      Layout.EndUpdate;
    end;
    Layout.RenderLayout(FCanvas);
  finally
    Layout.Free;
  end;
end;

end.
