// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDColorSpace.java and PDColor.java (3.0.8), without the
// colour spaces themselves (see Pdf4D.Graphics.Color.Device and Pdf4D.Graphics.Color.IccBased) and the factory (see
// Pdf4D.Graphics.Color.Factory)
unit Pdf4D.Graphics.Color;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.Render.Bitmap;

const
  // Components per pixel of a raster
  MaxRasterComponents = 32;

type
  // A colour in sRGB with components of 0..1
  TPdfRgb = record
    R: Single;
    G: Single;
    B: Single;

    class function Create(const R, G, B: Single): TPdfRgb; static;
    // One channel as 8 bits, rounded like the constructor java.awt.Color(float, float, float); outside 0..1 clamps
    class function ChannelToByte(const Value: Single): Byte; static;

    // Opaque; the rounding is that of java.awt.Color(float, float, float)
    function ToDeviceColor: TPdfDeviceColor;
  end;

  // The samples of an image, 8 bits each, Components per pixel, row by row (the WritableRaster of bytes in PDFBox)
  TPdfRaster = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FComponents: Integer;
    FSamples: TBytes;

    function GetStride: Integer;

  public
    // All samples 0. Raises EArgumentOutOfRangeException when Width or Height is under 1, Components is outside 1..MaxRasterComponents,
    // or the size or the number of samples is over the limit of a bitmap (MaxBitmapPixels).
    constructor Create(const Width, Height, Components: Integer);

    // A pointer to the first sample of row Y; raises EArgumentOutOfRangeException outside the raster
    function RowStart(const Y: Integer): PByte;

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Components: Integer read FComponents;
    property Stride: Integer read GetStride;
    property Samples: TBytes read FSamples;
  end;

  TPDColorSpace = class;

  // A colour: the components of a colour space (0..1 for the device spaces), or the name of a pattern. The colour space is not
  // owned: it belongs to the document context or is shared by the process.
  TPDColor = record
    Components: TArray<Single>;
    // Empty unless the colour is a pattern colour
    PatternName: string;
    ColorSpace: TPDColorSpace;

    class function Create(const ColorSpace: TPDColorSpace; const Components: TArray<Single>): TPDColor; static;

    // Raises EInvalidOpException without a colour space
    function ToRgb: TPdfRgb;
  end;

  // A colour space. The spaces are not thread safe unless said otherwise (the device spaces are), like the objects of a document.
  TPDColorSpace = class abstract
  protected
    // PageDrawer.clampColor of PDFBox; not a number is 0
    class function ClampColor(const Value: Single): Single; static;
    // PDFBox reads the first NumberOfComponents values and fails on fewer; Pdf4D gives 0 for a missing one and ignores the extra ones
    function NormalizeComponents(const Components: TArray<Single>): TArray<Single>;
    // Raises EArgumentNilException, or EArgumentException when the raster has another number of components than the space
    procedure CheckRaster(const Raster: TPdfRaster);
    // A bitmap with the pixels of the RGB bytes of Output, row by row (3 bytes a pixel); the bitmap is opaque
    class procedure StoreRgbRow(const Bitmap: TPdfBitmap; const Y: Integer; const Rgb: PByte); static;
    // Converts the raster with the transform, row by row with its cache
    class function ConvertWithTransform(const Raster: TPdfRaster; const Transform: TIccTransform): TPdfBitmap; static;

  public
    function Name: string; virtual; abstract;
    function NumberOfComponents: Integer; virtual; abstract;
    // The Decode array of an image that has none: 0 and 1 for every component
    function GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>; virtual;
    function InitialColor: TPDColor; virtual; abstract;
    // Components of 0..1 in, sRGB of 0..1 out
    function ToRgb(const Components: TArray<Single>): TPdfRgb; virtual; abstract;
    // The raster (8-bit samples, NumberOfComponents per pixel) as an opaque premultiplied RGBA bitmap. The caller owns it. The
    // conversion goes pixel by pixel through ToRgb; the spaces with a faster way override it.
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; virtual;
  end;

implementation

uses
  System.Math;

const
  ByteScale = 255.0;
  RoundingOffset = 0.5;
  BytesPerRgbPixel = 3;

{ TPdfRgb }

class function TPdfRgb.Create(const R, G, B: Single): TPdfRgb;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

class function TPdfRgb.ChannelToByte(const Value: Single): Byte;
begin
  const IsNotANumber = IsNan(Value);
  if IsNotANumber or (Value <= 0.0) then
  begin
    Exit(0);
  end;

  if Value >= 1.0 then
  begin
    Exit(255);
  end;

  Result := Byte(Trunc(Value * ByteScale + RoundingOffset));
end;

function TPdfRgb.ToDeviceColor: TPdfDeviceColor;
begin
  Result := TPdfDeviceColor.Create(ChannelToByte(R), ChannelToByte(G), ChannelToByte(B), 255);
end;

{ TPdfRaster }

constructor TPdfRaster.Create(const Width, Height, Components: Integer);
begin
  TPdfBitmap.CheckSize(Width, Height);
  const IsComponentCountValid = ((Components >= 1) and (Components <= MaxRasterComponents));
  if not IsComponentCountValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('A raster has 1 to %d components, not %d', [MaxRasterComponents, Components]);
  end;

  // Int64: Width * Height * Components of a bitmap that is within its limit still overflows an Integer
  const SampleCount = Int64(Width) * Height * Components;
  if SampleCount > MaxBitmapPixels then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('A raster of %d x %d pixels with %d components exceeds the limit of %d samples',
                                                 [Width, Height, Components, MaxBitmapPixels]);
  end;

  inherited Create;
  FWidth := Width;
  FHeight := Height;
  FComponents := Components;
  SetLength(FSamples, SampleCount);
end;

function TPdfRaster.GetStride: Integer;
begin
  Result := FWidth * FComponents;
end;

function TPdfRaster.RowStart(const Y: Integer): PByte;
begin
  const IsInside = ((Y >= 0) and (Y < FHeight));
  if not IsInside then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Row %d is outside a raster of %d rows', [Y, FHeight]);
  end;

  Result := @FSamples[Int64(Y) * GetStride];
end;

{ TPDColor }

class function TPDColor.Create(const ColorSpace: TPDColorSpace; const Components: TArray<Single>): TPDColor;
begin
  Result.ColorSpace := ColorSpace;
  Result.Components := Components;
  Result.PatternName := '';
end;

function TPDColor.ToRgb: TPdfRgb;
begin
  if not Assigned(ColorSpace) then
  begin
    raise EInvalidOpException.Create('A colour without a colour space has no RGB value');
  end;

  Result := ColorSpace.ToRgb(Components);
end;

{ TPDColorSpace }

class function TPDColorSpace.ClampColor(const Value: Single): Single;
begin
  if IsNan(Value) or (Value <= 0.0) then
  begin
    Exit(0.0);
  end;

  if Value >= 1.0 then
  begin
    Exit(1.0);
  end;

  Result := Value;
end;

function TPDColorSpace.NormalizeComponents(const Components: TArray<Single>): TArray<Single>;
begin
  SetLength(Result, NumberOfComponents);
  for var Index := 0 to Length(Result) - 1 do
  begin
    const IsGiven = (Index < Length(Components));
    if IsGiven then
    begin
      Result[Index] := Components[Index];
    end
    else
    begin
      Result[Index] := 0.0;
    end;
  end;
end;

procedure TPDColorSpace.CheckRaster(const Raster: TPdfRaster);
begin
  if not Assigned(Raster) then
  begin
    raise EArgumentNilException.Create('Raster');
  end;

  if Raster.Components <> NumberOfComponents then
  begin
    raise EArgumentException.CreateFmt('The raster has %d components, the colour space %s has %d', [Raster.Components, Name, NumberOfComponents]);
  end;
end;

class procedure TPDColorSpace.StoreRgbRow(const Bitmap: TPdfBitmap; const Y: Integer; const Rgb: PByte);
begin
  const Target = Bitmap.ScanLine(Y);
  for var X := 0 to Bitmap.Width - 1 do
  begin
    Target[X * 4] := Rgb[X * BytesPerRgbPixel];
    Target[X * 4 + 1] := Rgb[X * BytesPerRgbPixel + 1];
    Target[X * 4 + 2] := Rgb[X * BytesPerRgbPixel + 2];
    Target[X * 4 + 3] := 255;
  end;
end;

class function TPDColorSpace.ConvertWithTransform(const Raster: TPdfRaster; const Transform: TIccTransform): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    var Row: TBytes;
    SetLength(Row, Raster.Width * BytesPerRgbPixel);
    for var Y := 0 to Raster.Height - 1 do
    begin
      Transform.ToRgbRow(Raster.RowStart(Y), @Row[0], Raster.Width);
      StoreRgbRow(Result, Y, @Row[0]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPDColorSpace.GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>;
begin
  SetLength(Result, NumberOfComponents * 2);
  for var Index := 0 to NumberOfComponents - 1 do
  begin
    Result[Index * 2] := 0.0;
    Result[Index * 2 + 1] := 1.0;
  end;
end;

function TPDColorSpace.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    var Components: TArray<Single>;
    SetLength(Components, NumberOfComponents);
    var Row: TBytes;
    SetLength(Row, Raster.Width * BytesPerRgbPixel);
    for var Y := 0 to Raster.Height - 1 do
    begin
      const Source = Raster.RowStart(Y);
      for var X := 0 to Raster.Width - 1 do
      begin
        for var Component := 0 to NumberOfComponents - 1 do
        begin
          Components[Component] := Source[X * NumberOfComponents + Component] / ByteScale;
        end;
        const Rgb = ToRgb(Components);
        Row[X * BytesPerRgbPixel] := TPdfRgb.ChannelToByte(Rgb.R);
        Row[X * BytesPerRgbPixel + 1] := TPdfRgb.ChannelToByte(Rgb.G);
        Row[X * BytesPerRgbPixel + 2] := TPdfRgb.ChannelToByte(Rgb.B);
      end;
      StoreRgbRow(Result, Y, @Row[0]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
