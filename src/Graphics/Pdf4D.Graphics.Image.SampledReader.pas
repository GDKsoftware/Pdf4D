// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/image/SampledImageReader.java (3.0.8): getRGBImage (from1Bit,
// from8bit and fromAny), applyColorKeyMask and getStencilImage, with the subsampling parameter of getRGBImage. The decode array is
// repaired by the image (getDecodeArray).
unit Pdf4D.Graphics.Image.SampledReader;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Graphics.Color,
  Pdf4D.Render.Bitmap;

type
  // What the reader needs of an image: the decoded sample bytes and the parameters that describe them
  TSampledImageSource = record
    Width: Integer;
    Height: Integer;
    BitsPerComponent: Integer;
    // Not owned; never nil
    ColorSpace: TPDColorSpace;
    // Two values per component, as getDecodeArray gives them
    Decode: TArray<Single>;
    // The data with all filters applied, rows padded to whole bytes
    Data: TBytes;
    // /Mask is an array; ColorKey holds its values
    HasColorKey: Boolean;
    ColorKey: TArray<Single>;
    // Not owned; may be nil
    Log: TPdfLog;
  end;

  TSampledImageReader = class
  private
    class function ReadBit(const Data: TBytes; const BitPosition: Int64): Integer; static;
    class function ReadSample(const Data: TBytes; const BitPosition: Int64; const Bits: Integer): Integer; static;
    class function AreEqual(const Left, Right: TArray<Single>): Boolean; static;
    class function ByteOf(const Value: Single): Byte; static;
    class procedure Validate(const Source: TSampledImageSource); static;
    class procedure CheckDataSize(const Source: TSampledImageSource; const Needed: Int64; const Message: string); static;
    class function From1Bit(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap; static;
    class function From8Bit(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap; static;
    class function FromAny(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap; static;

  public
    // Math.round(float) of Java: half up, not a number is 0, saturating
    class function JavaRound(const Value: Single): Integer; static;

    // The subsampling (every Nth column and row of the source) that makes the image of Width x Height with Components fit in
    // MaxImagePixels pixels and in the samples that a raster allows; 1 when it fits.
    class function Subsampling(const Width, Height, Components: Integer; const MaxImagePixels: Int64): Integer; static;

    // getRGBImage: the image as an RGBA bitmap of ceil(Width / Subsampling) x ceil(Height / Subsampling) pixels; pixel (x, y) is
    // the source pixel (x * Subsampling, y * Subsampling). The alpha is straight: the pixels that the colour key mask hides have
    // alpha 0 and keep their colour. Without a colour key mask the bitmap is opaque. Raises EPdfParseException for an image that
    // cannot be read (invalid size, empty or too short data) and EPdfLimitExceededException when the raster would be too large.
    class function ReadRgb(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap; static;

    // getStencilImage as a mask: alpha 255 where the stencil paints and 0 where it does not, colour 0. The decode array is that of
    // the stencil (two values).
    class function ReadStencil(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap; static;

    // The colour channels times the alpha, rounded, in the way that the PNG reader of the tests and the devices expect
    class procedure Premultiply(const Bitmap: TPdfBitmap); static;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names;

const
  MaxSampleBits = 16;
  ByteMax = 255;
  BitsPerByte = 8;
  ColorKeyValuesPerComponent = 2;

{ TSampledImageReader }

class function TSampledImageReader.Subsampling(const Width, Height, Components: Integer; const MaxImagePixels: Int64): Integer;
begin
  var Target := Max(MaxImagePixels, 1);
  const SampleLimit = MaxBitmapPixels div Max(Components, 1);
  Target := Max(Min(Target, SampleLimit), 1);

  const Total = Int64(Width) * Int64(Height);
  Result := 1;
  if Total > Target then
  begin
    Result := Max(Min(Ceil(Sqrt(Total / Target)), Max(Width, Height)), 1);
  end;

  const Longest = Max(Width, Height);
  while (Result < Longest) and (Int64((Int64(Width) + Result - 1) div Result) * ((Int64(Height) + Result - 1) div Result) > Target) do
  begin
    Inc(Result);
  end;
end;

class function TSampledImageReader.ReadBit(const Data: TBytes; const BitPosition: Int64): Integer;
begin
  Result := (Data[Integer(BitPosition shr 3)] shr (7 - Integer(BitPosition and 7))) and 1;
end;

class function TSampledImageReader.ReadSample(const Data: TBytes; const BitPosition: Int64; const Bits: Integer): Integer;
begin
  if Bits = BitsPerByte then
  begin
    Exit(Data[Integer(BitPosition shr 3)]);
  end;

  Result := 0;
  for var Index := 0 to Bits - 1 do
  begin
    Result := (Result shl 1) or ReadBit(Data, BitPosition + Index);
  end;
end;

class function TSampledImageReader.AreEqual(const Left, Right: TArray<Single>): Boolean;
begin
  Result := (Length(Left) = Length(Right));
  for var Index := 0 to Min(Length(Left), Length(Right)) - 1 do
  begin
    Result := (Result and (Left[Index] = Right[Index]));
  end;
end;

// Math.round(float) of Java: half up, not a number is 0, and the result saturates. The comparison is made on the Double before it
// is converted: Floor of System.Math returns an Integer, which would wrap.
class function TSampledImageReader.JavaRound(const Value: Single): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;

  const Shifted = Double(Value) + 0.5;
  if Shifted >= Double(High(Integer)) then
  begin
    Exit(High(Integer));
  end;
  if Shifted <= Double(Low(Integer)) then
  begin
    Exit(Low(Integer));
  end;
  Result := Floor(Shifted);
end;

// (byte) cast of Java: the low eight bits
class function TSampledImageReader.ByteOf(const Value: Single): Byte;
begin
  Result := Byte(JavaRound(Value) and ByteMax);
end;

class procedure TSampledImageReader.Validate(const Source: TSampledImageSource);
begin
  if (Source.Width <= 0) or (Source.Height <= 0) then
  begin
    raise EPdfParseException.CreateFmt('The image width and height must be positive, not %d x %d', [Source.Width, Source.Height]);
  end;

  if (Source.BitsPerComponent < 1) or (Source.BitsPerComponent > MaxSampleBits) then
  begin
    raise EPdfParseException.CreateFmt('The image has %d bits per component; 1 to %d are supported', [Source.BitsPerComponent, MaxSampleBits]);
  end;

  if not Assigned(Source.ColorSpace) then
  begin
    raise EPdfParseException.Create('The image has no colour space');
  end;

  if Length(Source.Decode) < Source.ColorSpace.NumberOfComponents * 2 then
  begin
    raise EPdfParseException.Create('The decode array of the image is too short for its colour space');
  end;

  if Length(Source.Data) = 0 then
  begin
    raise EPdfParseException.Create('Image stream is empty');
  end;
end;

class procedure TSampledImageReader.CheckDataSize(const Source: TSampledImageSource; const Needed: Int64; const Message: string);
begin
  if (Length(Source.Data) < Needed) and Assigned(Source.Log) then
  begin
    Source.Log.Warning(Message, [Length(Source.Data), Needed]);
  end;
end;

class function TSampledImageReader.ReadRgb(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap;
begin
  Validate(Source);
  const IsOneBit = ((Source.BitsPerComponent = 1) and (not Source.HasColorKey) and (Source.ColorSpace.NumberOfComponents = 1));
  if IsOneBit then
  begin
    Exit(From1Bit(Source, Subsampling));
  end;

  const IsDefaultDecode = AreEqual(Source.Decode, Source.ColorSpace.GetDefaultDecode(BitsPerByte));
  if (Source.BitsPerComponent = BitsPerByte) and (not Source.HasColorKey) and IsDefaultDecode then
  begin
    Result := From8Bit(Source, Subsampling);
  end
  else
  begin
    Result := FromAny(Source, Subsampling);
  end;
end;

// A raster of the size that the subsampling gives; the limits of the raster are reported as a limit of the image
function NewRaster(const Width, Height, Components, Subsampling: Integer): TPdfRaster;
begin
  const OutWidth = (Width + Subsampling - 1) div Subsampling;
  const OutHeight = (Height + Subsampling - 1) div Subsampling;
  try
    Result := TPdfRaster.Create(OutWidth, OutHeight, Components);
  except
    on Error: EArgumentOutOfRangeException do
    begin
      raise EPdfLimitExceededException.CreateFmt('The image of %d x %d pixels with %d components is too large: %s',
                                                 [Width, Height, Components, Error.Message]);
    end;
  end;
end;

class function TSampledImageReader.From1Bit(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap;
begin
  const Raster = NewRaster(Source.Width, Source.Height, 1, Subsampling);
  try
    const Stride = (Int64(Source.Width) + 7) div 8;
    const IsInverted = (Source.Decode[0] >= Source.Decode[1]);
    CheckDataSize(Source, Stride * Source.Height, 'premature EOF, image will be incomplete (%d of %d bytes)');

    for var OutY := 0 to Raster.Height - 1 do
    begin
      const RowStart = Int64(OutY) * Subsampling * Stride;
      const Available = Min(Max(Int64(Length(Source.Data)) - RowStart, 0), Stride);
      const Target = Raster.RowStart(OutY);
      for var OutX := 0 to Raster.Width - 1 do
      begin
        const X = Int64(OutX) * Subsampling;
        if (X shr 3) < Available then
        begin
          var Bit := ReadBit(Source.Data, RowStart * BitsPerByte + X);
          if IsInverted then
          begin
            Bit := Bit xor 1;
          end;
          if Bit = 1 then
          begin
            Target[OutX] := ByteMax;
          end;
        end;
      end;
    end;

    Result := Source.ColorSpace.ToRgbImage(Raster);
  finally
    Raster.Free;
  end;
end;

class function TSampledImageReader.From8Bit(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap;
begin
  const Components = Source.ColorSpace.NumberOfComponents;
  const Raster = NewRaster(Source.Width, Source.Height, Components, Subsampling);
  try
    const RowBytes = Int64(Source.Width) * Components;
    CheckDataSize(Source, RowBytes * Source.Height, 'Image data is shorter than expected (%d of %d bytes), the rest is 0');

    for var OutY := 0 to Raster.Height - 1 do
    begin
      const RowStart = Int64(OutY) * Subsampling * RowBytes;
      const Target = Raster.RowStart(OutY);
      if Subsampling = 1 then
      begin
        const Count = Min(Max(Int64(Length(Source.Data)) - RowStart, 0), RowBytes);
        if Count > 0 then
        begin
          Move(Source.Data[Integer(RowStart)], Target^, Count);
        end;
        Continue;
      end;

      for var OutX := 0 to Raster.Width - 1 do
      begin
        const Position = RowStart + Int64(OutX) * Subsampling * Components;
        for var Component := 0 to Components - 1 do
        begin
          if Position + Component < Length(Source.Data) then
          begin
            Target[OutX * Components + Component] := Source.Data[Integer(Position + Component)];
          end;
        end;
      end;
    end;

    Result := Source.ColorSpace.ToRgbImage(Raster);
  finally
    Raster.Free;
  end;
end;

class function TSampledImageReader.FromAny(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap;
begin
  const Components = Source.ColorSpace.NumberOfComponents;
  const Bits = Source.BitsPerComponent;
  const RowBytes = (Int64(Source.Width) * Components * Bits + 7) div 8;
  // The reader of PDFBox reads every bit of every row and fails at the end of the data
  if Int64(Length(Source.Data)) < RowBytes * Source.Height then
  begin
    raise EPdfParseException.CreateFmt('premature EOF: the image data has %d of %d bytes', [Length(Source.Data), RowBytes * Source.Height]);
  end;

  var KeyActive := False;
  if Source.HasColorKey then
  begin
    KeyActive := (Length(Source.ColorKey) >= Components * ColorKeyValuesPerComponent);
    if (not KeyActive) and Assigned(Source.Log) then
    begin
      Source.Log.Warning('colorKey mask size is %d, should be %d, ignored', [Length(Source.ColorKey), Components * ColorKeyValuesPerComponent]);
    end;
  end;

  const IsIndexed = (Source.ColorSpace.Name = TCosNames.Indexed);
  const SampleMax = Single(Power(2, Bits)) - 1;
  var MinimumOf: TArray<Single>;
  var RangeOf: TArray<Single>;
  var StepOf: TArray<Single>;
  SetLength(MinimumOf, Components);
  SetLength(RangeOf, Components);
  SetLength(StepOf, Components);
  for var Component := 0 to Components - 1 do
  begin
    const DecodeMinimum = Source.Decode[Component * 2];
    const DecodeMaximum = Source.Decode[Component * 2 + 1];
    MinimumOf[Component] := Min(DecodeMinimum, DecodeMaximum);
    RangeOf[Component] := Abs(DecodeMaximum - DecodeMinimum);
    StepOf[Component] := (DecodeMaximum - DecodeMinimum) / SampleMax;
  end;

  const Raster = NewRaster(Source.Width, Source.Height, Components, Subsampling);
  try
    var Masked: TBytes;
    if KeyActive then
    begin
      SetLength(Masked, Integer(Int64(Raster.Width) * Raster.Height));
    end;

    for var OutY := 0 to Raster.Height - 1 do
    begin
      const Target = Raster.RowStart(OutY);
      for var OutX := 0 to Raster.Width - 1 do
      begin
        var IsMasked := True;
        for var Component := 0 to Components - 1 do
        begin
          const BitPosition = (Int64(OutY) * Subsampling * RowBytes) * BitsPerByte + (Int64(OutX) * Subsampling * Components + Component) * Bits;
          const Value = ReadSample(Source.Data, BitPosition, Bits);
          if KeyActive then
          begin
            IsMasked := (IsMasked and (Value >= Source.ColorKey[Component * 2]) and (Value <= Source.ColorKey[Component * 2 + 1]));
          end;

          const DecodeMinimum = Source.Decode[Component * 2];
          const Output: Single = DecodeMinimum + Single(Value) * StepOf[Component];
          if IsIndexed then
          begin
            Target[OutX * Components + Component] := ByteOf(Output);
          end
          else
          begin
            Target[OutX * Components + Component] := ByteOf(((Output - MinimumOf[Component]) / RangeOf[Component]) * ByteMax);
          end;
        end;

        if KeyActive and IsMasked then
        begin
          Masked[Integer(Int64(OutY) * Raster.Width + OutX)] := 1;
        end;
      end;
    end;

    Result := Source.ColorSpace.ToRgbImage(Raster);
    if KeyActive then
    begin
      try
        for var Y := 0 to Result.Height - 1 do
        begin
          const Row = Result.ScanLine(Y);
          for var X := 0 to Result.Width - 1 do
          begin
            if Masked[Integer(Int64(Y) * Result.Width + X)] = 1 then
            begin
              Row[X * 4 + 3] := 0;
            end;
          end;
        end;
      except
        Result.Free;
        raise;
      end;
    end;
  finally
    Raster.Free;
  end;
end;

class function TSampledImageReader.ReadStencil(const Source: TSampledImageSource; const Subsampling: Integer): TPdfBitmap;
begin
  if (Source.Width <= 0) or (Source.Height <= 0) then
  begin
    raise EPdfParseException.CreateFmt('The image width and height must be positive, not %d x %d', [Source.Width, Source.Height]);
  end;
  if Length(Source.Decode) < 2 then
  begin
    raise EPdfParseException.Create('The decode array of the stencil mask is too short');
  end;
  if Length(Source.Data) = 0 then
  begin
    raise EPdfParseException.Create('Image stream is empty');
  end;

  const OutWidth = (Int64(Source.Width) + Subsampling - 1) div Subsampling;
  const OutHeight = (Int64(Source.Height) + Subsampling - 1) div Subsampling;
  try
    Result := TPdfBitmap.Create(OutWidth, OutHeight);
  except
    on Error: EArgumentOutOfRangeException do
    begin
      raise EPdfLimitExceededException.CreateFmt('The stencil mask of %d x %d pixels is too large: %s', [Source.Width, Source.Height, Error.Message]);
    end;
  end;

  try
    // Everything paints until a bit says otherwise; a missing byte does not say so
    for var Y := 0 to Result.Height - 1 do
    begin
      const Row = Result.ScanLine(Y);
      for var X := 0 to Result.Width - 1 do
      begin
        Row[X * 4 + 3] := ByteMax;
      end;
    end;

    const PaintBit = IfThen(Source.Decode[0] < Source.Decode[1], 1, 0);
    const RowLength = (Int64(Source.Width) + 7) div 8;
    CheckDataSize(Source, RowLength * Source.Height, 'premature EOF, image will be incomplete (%d of %d bytes)');
    for var OutY := 0 to Result.Height - 1 do
    begin
      const RowStart = Int64(OutY) * Subsampling * RowLength;
      const Available = Min(Max(Int64(Length(Source.Data)) - RowStart, 0), RowLength);
      const Row = Result.ScanLine(OutY);
      for var OutX := 0 to Result.Width - 1 do
      begin
        const X = Int64(OutX) * Subsampling;
        if ((X shr 3) < Available) and (ReadBit(Source.Data, RowStart * BitsPerByte + X) = PaintBit) then
        begin
          Row[OutX * 4 + 3] := 0;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class procedure TSampledImageReader.Premultiply(const Bitmap: TPdfBitmap);
begin
  for var Y := 0 to Bitmap.Height - 1 do
  begin
    const Row = Bitmap.ScanLine(Y);
    for var X := 0 to Bitmap.Width - 1 do
    begin
      const Alpha = Row[X * 4 + 3];
      if Alpha <> ByteMax then
      begin
        Row[X * 4] := Byte((Row[X * 4] * Alpha + 127) div ByteMax);
        Row[X * 4 + 1] := Byte((Row[X * 4 + 1] * Alpha + 127) div ByteMax);
        Row[X * 4 + 2] := Byte((Row[X * 4 + 2] * Alpha + 127) div ByteMax);
      end;
    end;
  end;
end;

end.
