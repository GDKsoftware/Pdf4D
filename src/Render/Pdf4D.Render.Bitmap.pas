// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Bitmap;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math;

const
  // Hard ceiling; TPdfRenderOptions has the configurable limits
  MaxBitmapPixels: Int64 = 256 * 1024 * 1024;

type
  // sRGB with straight (not premultiplied) alpha; TPdfBitmap.GetPixel uses the same record for premultiplied values
  TPdfDeviceColor = record
    R, G, B, A: Byte;

    class function Create(const R, G, B: Byte; const A: Byte = 255): TPdfDeviceColor; static;
    class function White: TPdfDeviceColor; static;
    class function Transparent: TPdfDeviceColor; static;
  end;

  // Premultiplied RGBA, 8 bits per channel, bytes R, G, B, A, rows top to bottom, stride Width * 4. Not thread safe.
  TPdfBitmap = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FPixels: TBytes;

    function GetStride: Integer;
    function OffsetOf(const X, Y: Integer): Integer;
    class function FlattenChannel(const Premultiplied, Alpha, Background: Byte): Byte; static;

  public
    // Raises EArgumentOutOfRangeException when Width or Height < 1 or Width * Height > MaxBitmapPixels
    class procedure CheckSize(const Width, Height: Integer); static;

    // All pixels transparent black; same exception as CheckSize
    constructor Create(const Width, Height: Integer);

    function Clone: TPdfBitmap;
    // A pointer to the first byte of row Y; raises EArgumentOutOfRangeException outside the bitmap
    function ScanLine(const Y: Integer): PByte;
    // Premultiplied values as stored; raises EArgumentOutOfRangeException outside the bitmap
    function GetPixel(const X, Y: Integer): TPdfDeviceColor;
    procedure SetPixel(const X, Y: Integer; const Value: TPdfDeviceColor);
    // Source-over of every pixel on an opaque Background (its alpha is ignored); the result is opaque
    procedure FlattenOn(const Background: TPdfDeviceColor);

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Stride: Integer read GetStride;
    property Pixels: TBytes read FPixels;
  end;

  // An 8-bit alpha mask in device pixels, for soft masks. Value 0 is transparent, 255 opaque.
  TPdfAlphaMask = class
  private
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FOutsideValue: Byte;
    FValues: TBytes;

  public
    // All values 0. Raises EArgumentOutOfRangeException when Width or Height < 0 or Width * Height > MaxBitmapPixels
    constructor Create(const Left, Top, Width, Height: Integer; const OutsideValue: Byte);

    // Device coordinates; OutsideValue outside the rectangle
    function ValueAt(const X, Y: Integer): Byte;

    property Left: Integer read FLeft;
    property Top: Integer read FTop;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property OutsideValue: Byte read FOutsideValue;
    // Row major, Width * Height
    property Values: TBytes read FValues;
  end;

implementation

const
  BytesPerPixel = 4;
  MaxChannel    = 255;

{ TPdfDeviceColor }

class function TPdfDeviceColor.Create(const R, G, B: Byte; const A: Byte): TPdfDeviceColor;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
  Result.A := A;
end;

class function TPdfDeviceColor.White: TPdfDeviceColor;
begin
  Result := Create(MaxChannel, MaxChannel, MaxChannel);
end;

class function TPdfDeviceColor.Transparent: TPdfDeviceColor;
begin
  Result := Create(0, 0, 0, 0);
end;

{ TPdfBitmap }

class procedure TPdfBitmap.CheckSize(const Width, Height: Integer);
begin
  const IsTooSmall = ((Width < 1) or (Height < 1));
  if IsTooSmall then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Bitmap size %d x %d is not positive', [Width, Height]);
  end;

  const IsTooLarge = (Int64(Width) * Int64(Height) > MaxBitmapPixels);
  if IsTooLarge then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Bitmap size %d x %d exceeds the limit of %d pixels', [Width, Height, MaxBitmapPixels]);
  end;
end;

constructor TPdfBitmap.Create(const Width, Height: Integer);
begin
  CheckSize(Width, Height);

  inherited Create;
  FWidth := Width;
  FHeight := Height;
  SetLength(FPixels, Width * Height * BytesPerPixel);
  FillChar(FPixels[0], Length(FPixels), 0);
end;

function TPdfBitmap.Clone: TPdfBitmap;
begin
  Result := TPdfBitmap.Create(FWidth, FHeight);
  Move(FPixels[0], Result.FPixels[0], Length(FPixels));
end;

function TPdfBitmap.ScanLine(const Y: Integer): PByte;
begin
  Result := @FPixels[OffsetOf(0, Y)];
end;

function TPdfBitmap.GetPixel(const X, Y: Integer): TPdfDeviceColor;
begin
  const Offset = OffsetOf(X, Y);
  Result.R := FPixels[Offset];
  Result.G := FPixels[Offset + 1];
  Result.B := FPixels[Offset + 2];
  Result.A := FPixels[Offset + 3];
end;

procedure TPdfBitmap.SetPixel(const X, Y: Integer; const Value: TPdfDeviceColor);
begin
  const Offset = OffsetOf(X, Y);
  FPixels[Offset]     := Value.R;
  FPixels[Offset + 1] := Value.G;
  FPixels[Offset + 2] := Value.B;
  FPixels[Offset + 3] := Value.A;
end;

procedure TPdfBitmap.FlattenOn(const Background: TPdfDeviceColor);
begin
  var Offset := 0;
  while Offset < Length(FPixels) do
  begin
    const Alpha = FPixels[Offset + 3];
    FPixels[Offset]     := FlattenChannel(FPixels[Offset], Alpha, Background.R);
    FPixels[Offset + 1] := FlattenChannel(FPixels[Offset + 1], Alpha, Background.G);
    FPixels[Offset + 2] := FlattenChannel(FPixels[Offset + 2], Alpha, Background.B);
    FPixels[Offset + 3] := MaxChannel;
    Inc(Offset, BytesPerPixel);
  end;
end;

function TPdfBitmap.GetStride: Integer;
begin
  Result := FWidth * BytesPerPixel;
end;

function TPdfBitmap.OffsetOf(const X, Y: Integer): Integer;
begin
  const IsInside = ((X >= 0) and (X < FWidth) and (Y >= 0) and (Y < FHeight));
  if not IsInside then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Pixel (%d, %d) is outside the %d x %d bitmap', [X, Y, FWidth, FHeight]);
  end;

  Result := Y * GetStride + X * BytesPerPixel;
end;

// C + Bg * (255 - A) / 255, rounded to the nearest integer
class function TPdfBitmap.FlattenChannel(const Premultiplied, Alpha, Background: Byte): Byte;
begin
  const Visible = (Background * (MaxChannel - Alpha) + MaxChannel div 2) div MaxChannel;
  Result := Byte(Min(Premultiplied + Visible, MaxChannel));
end;

{ TPdfAlphaMask }

constructor TPdfAlphaMask.Create(const Left, Top, Width, Height: Integer; const OutsideValue: Byte);
begin
  const IsNegative = ((Width < 0) or (Height < 0));
  if IsNegative then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Mask size %d x %d is negative', [Width, Height]);
  end;

  const IsTooLarge = (Int64(Width) * Int64(Height) > MaxBitmapPixels);
  if IsTooLarge then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Mask size %d x %d exceeds the limit of %d pixels', [Width, Height, MaxBitmapPixels]);
  end;

  inherited Create;
  FLeft := Left;
  FTop := Top;
  FWidth := Width;
  FHeight := Height;
  FOutsideValue := OutsideValue;
  SetLength(FValues, Width * Height);
  if Length(FValues) > 0 then
  begin
    FillChar(FValues[0], Length(FValues), 0);
  end;
end;

function TPdfAlphaMask.ValueAt(const X, Y: Integer): Byte;
begin
  const Column = X - FLeft;
  const Row = Y - FTop;
  const IsInside = ((Column >= 0) and (Column < FWidth) and (Row >= 0) and (Row < FHeight));
  if not IsInside then
  begin
    Exit(FOutsideValue);
  end;

  Result := FValues[Row * FWidth + Column];
end;

end.
