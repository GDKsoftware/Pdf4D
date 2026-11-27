// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Png;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Bitmap;

type
  // Reads and writes the PNG files of the tests: 8-bit RGB, RGBA, gray and gray with alpha, and 8-bit palette images, without
  // interlace. Bitmaps are premultiplied like TPdfBitmap; the files hold straight alpha.
  TPng = record
  strict private
    const Signature: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
    class function Crc(const Data: TBytes): Cardinal; static;
    class procedure AppendChunk(var Target: TBytes; const ChunkType: string; const Body: TBytes); static;
    class procedure AppendBytes(var Target: TBytes; const Addition: TBytes); static;
    class function BigEndian(const Value: Cardinal): TBytes; static;
    class function ReadBigEndian(const Data: TBytes; const Offset: Integer): Cardinal; static;
    class function Paeth(const Left, Above, UpperLeft: Integer): Integer; static;
    class procedure Unfilter(var Data: TBytes; const Height, RowBytes, PixelBytes: Integer); static;
    class function Premultiply(const Value, Alpha: Byte): Byte; static;
    class function Unpremultiply(const Value, Alpha: Byte): Byte; static;
  public
    class function Read(const FileName: string): TPdfBitmap; static;
    class function FromBytes(const Data: TBytes): TPdfBitmap; static;
    // The pixels as the file holds them: straight (not premultiplied) RGBA, rows top to bottom
    class function DecodeStraight(const Data: TBytes; out Width, Height: Integer): TBytes; static;
    class function ReadStraight(const FileName: string; out Width, Height: Integer): TBytes; static;
    class procedure Write(const Bitmap: TPdfBitmap; const FileName: string); static;
    class function ToBytes(const Bitmap: TPdfBitmap): TBytes; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.ZLib;

const
  ColorTypeGray = 0;
  ColorTypeRgb = 2;
  ColorTypePalette = 3;
  ColorTypeGrayAlpha = 4;
  ColorTypeRgba = 6;
  ChunkOverhead = 12;
  // Width * Height * 4 stays below 2^31
  MaxDimension = 16384;
  Opaque = 255;

var
  CrcTable: array[0..255] of Cardinal;
  IsCrcTableReady: Boolean;

procedure PrepareCrcTable;
begin
  if IsCrcTableReady then
  begin
    Exit;
  end;

  for var Index := 0 to 255 do
  begin
    var Value := Cardinal(Index);
    for var Bit := 0 to 7 do
    begin
      if (Value and 1) <> 0 then
      begin
        Value := $EDB88320 xor (Value shr 1);
      end
      else
      begin
        Value := Value shr 1;
      end;
    end;
    CrcTable[Index] := Value;
  end;
  IsCrcTableReady := True;
end;

{ TPng }

class function TPng.Crc(const Data: TBytes): Cardinal;
begin
  PrepareCrcTable;
  Result := $FFFFFFFF;
  for var Value in Data do
  begin
    Result := CrcTable[(Result xor Value) and $FF] xor (Result shr 8);
  end;
  Result := Result xor $FFFFFFFF;
end;

class function TPng.BigEndian(const Value: Cardinal): TBytes;
begin
  Result := [Byte(Value shr 24), Byte(Value shr 16), Byte(Value shr 8), Byte(Value)];
end;

class function TPng.ReadBigEndian(const Data: TBytes; const Offset: Integer): Cardinal;
begin
  Result := (Cardinal(Data[Offset]) shl 24) or (Cardinal(Data[Offset + 1]) shl 16) or (Cardinal(Data[Offset + 2]) shl 8) or Data[Offset + 3];
end;

class procedure TPng.AppendBytes(var Target: TBytes; const Addition: TBytes);
begin
  if Length(Addition) > 0 then
  begin
    const OldLength = Length(Target);
    SetLength(Target, OldLength + Length(Addition));
    Move(Addition[0], Target[OldLength], Length(Addition));
  end;
end;

class procedure TPng.AppendChunk(var Target: TBytes; const ChunkType: string; const Body: TBytes);
begin
  var Checked := TEncoding.ASCII.GetBytes(ChunkType);
  AppendBytes(Checked, Body);
  AppendBytes(Target, BigEndian(Length(Body)));
  AppendBytes(Target, Checked);
  AppendBytes(Target, BigEndian(Crc(Checked)));
end;

class function TPng.Premultiply(const Value, Alpha: Byte): Byte;
begin
  Result := Byte((Value * Alpha + 127) div 255);
end;

class function TPng.Unpremultiply(const Value, Alpha: Byte): Byte;
begin
  if Alpha = 0 then
  begin
    Exit(0);
  end;
  Result := Byte(Min(255, (Value * 255 + Alpha div 2) div Alpha));
end;

class function TPng.Paeth(const Left, Above, UpperLeft: Integer): Integer;
begin
  const Estimate = Left + Above - UpperLeft;
  const DistanceLeft = Abs(Estimate - Left);
  const DistanceAbove = Abs(Estimate - Above);
  const DistanceUpperLeft = Abs(Estimate - UpperLeft);
  if (DistanceLeft <= DistanceAbove) and (DistanceLeft <= DistanceUpperLeft) then
  begin
    Result := Left;
  end
  else if DistanceAbove <= DistanceUpperLeft then
  begin
    Result := Above;
  end
  else
  begin
    Result := UpperLeft;
  end;
end;

// Data holds Height rows of a filter byte and RowBytes bytes; the filter bytes stay, the rows after them are restored
class procedure TPng.Unfilter(var Data: TBytes; const Height, RowBytes, PixelBytes: Integer);
begin
  for var Y := 0 to Height - 1 do
  begin
    const RowStart = Y * (RowBytes + 1);
    const FilterType = Data[RowStart];
    for var X := 0 to RowBytes - 1 do
    begin
      const Position = RowStart + 1 + X;
      var Left := 0;
      var Above := 0;
      var UpperLeft := 0;
      if X >= PixelBytes then
      begin
        Left := Data[Position - PixelBytes];
      end;
      if Y > 0 then
      begin
        Above := Data[Position - RowBytes - 1];
      end;
      if (Y > 0) and (X >= PixelBytes) then
      begin
        UpperLeft := Data[Position - RowBytes - 1 - PixelBytes];
      end;
      case FilterType of
        0: ;
        1: Data[Position] := Byte(Data[Position] + Left);
        2: Data[Position] := Byte(Data[Position] + Above);
        3: Data[Position] := Byte(Data[Position] + (Left + Above) div 2);
        4: Data[Position] := Byte(Data[Position] + Paeth(Left, Above, UpperLeft));
      else
        raise EInvalidOpException.CreateFmt('Unknown PNG filter %d', [FilterType]);
      end;
    end;
  end;
end;

class function TPng.DecodeStraight(const Data: TBytes; out Width, Height: Integer): TBytes;
begin
  if (Length(Data) < Length(Signature)) or (not CompareMem(@Data[0], @Signature[0], Length(Signature))) then
  begin
    raise EInvalidOpException.Create('Not a PNG file');
  end;

  Width := 0;
  Height := 0;
  var ColorType := -1;
  var BitDepth := 8;
  var Palette: TBytes;
  var Transparency: TBytes;
  var Compressed: TBytes;
  var Position := Length(Signature);
  while Position + ChunkOverhead <= Length(Data) do
  begin
    const BodyLength = Integer(ReadBigEndian(Data, Position));
    const ChunkType = TEncoding.ASCII.GetString(Data, Position + 4, 4);
    const Body = Copy(Data, Position + 8, BodyLength);
    Inc(Position, BodyLength + ChunkOverhead);
    if ChunkType = 'IHDR' then
    begin
      Width := Integer(ReadBigEndian(Body, 0));
      Height := Integer(ReadBigEndian(Body, 4));
      // The files are checked in, but a corrupt header must not overflow the size of the result
      if (Width < 1) or (Width > MaxDimension) or (Height < 1) or (Height > MaxDimension) then
      begin
        raise EInvalidOpException.CreateFmt('The PNG size %d x %d is not supported', [Width, Height]);
      end;
      BitDepth := Body[8];
      ColorType := Body[9];
      const IsSupportedDepth = (BitDepth = 8) or ((ColorType = ColorTypePalette) and (BitDepth in [1, 2, 4]));
      if (not IsSupportedDepth) or (Body[12] <> 0) then
      begin
        raise EInvalidOpException.Create('Only 8-bit PNG files (1, 2 and 4 bits for palette images) without interlace are supported');
      end;
    end
    else if ChunkType = 'PLTE' then
    begin
      Palette := Body;
    end
    else if ChunkType = 'tRNS' then
    begin
      Transparency := Body;
    end
    else if ChunkType = 'IDAT' then
    begin
      AppendBytes(Compressed, Body);
    end
    else if ChunkType = 'IEND' then
    begin
      Break;
    end;
  end;

  var PixelBytes: Integer;
  case ColorType of
    ColorTypeGray, ColorTypePalette: PixelBytes := 1;
    ColorTypeGrayAlpha: PixelBytes := 2;
    ColorTypeRgb: PixelBytes := 3;
    ColorTypeRgba: PixelBytes := 4;
  else
    raise EInvalidOpException.CreateFmt('Unsupported PNG colour type %d', [ColorType]);
  end;

  var Raw: TBytes;
  ZDecompress(Compressed, Raw);
  const RowBytes = (Width * PixelBytes * BitDepth + 7) div 8;
  if Length(Raw) < Height * (RowBytes + 1) then
  begin
    raise EInvalidOpException.Create('The PNG data is too short');
  end;
  // The filters work on bytes: a pixel of less than a byte counts as one byte
  Unfilter(Raw, Height, RowBytes, PixelBytes);

  SetLength(Result, Width * Height * 4);
  for var Y := 0 to Height - 1 do
  begin
    const Source = @Raw[Y * (RowBytes + 1) + 1];
    const Target = @Result[Y * Width * 4];
    for var X := 0 to Width - 1 do
    begin
      var R, G, B, A: Byte;
      const Pixel = PByte(Source) + X * PixelBytes;
      A := Opaque;
      case ColorType of
        ColorTypeGray:
        begin
          R := Pixel[0]; G := R; B := R;
        end;
        ColorTypeGrayAlpha:
        begin
          R := Pixel[0]; G := R; B := R; A := Pixel[1];
        end;
        ColorTypeRgb:
        begin
          R := Pixel[0]; G := Pixel[1]; B := Pixel[2];
        end;
        ColorTypeRgba:
        begin
          R := Pixel[0]; G := Pixel[1]; B := Pixel[2]; A := Pixel[3];
        end;
      else
        begin
          const BitOffset = X * BitDepth;
          const Index = (PByte(Source)[BitOffset div 8] shr (8 - BitDepth - (BitOffset mod 8))) and ((1 shl BitDepth) - 1);
          if Index * 3 + 2 >= Length(Palette) then
          begin
            raise EInvalidOpException.CreateFmt('The palette index %d is beyond the palette', [Index]);
          end;
          R := Palette[Index * 3]; G := Palette[Index * 3 + 1]; B := Palette[Index * 3 + 2];
          if Index < Length(Transparency) then
          begin
            A := Transparency[Index];
          end;
        end;
      end;
      PByte(Target)[X * 4] := R;
      PByte(Target)[X * 4 + 1] := G;
      PByte(Target)[X * 4 + 2] := B;
      PByte(Target)[X * 4 + 3] := A;
    end;
  end;
end;

class function TPng.ReadStraight(const FileName: string; out Width, Height: Integer): TBytes;
begin
  Result := DecodeStraight(TFile.ReadAllBytes(FileName), Width, Height);
end;

class function TPng.FromBytes(const Data: TBytes): TPdfBitmap;
begin
  var Width, Height: Integer;
  const Straight = DecodeStraight(Data, Width, Height);

  Result := TPdfBitmap.Create(Width, Height);
  try
    for var Y := 0 to Height - 1 do
    begin
      const Source = @Straight[Y * Width * 4];
      const Target = Result.ScanLine(Y);
      for var X := 0 to Width - 1 do
      begin
        const A = PByte(Source)[X * 4 + 3];
        Target[X * 4] := Premultiply(PByte(Source)[X * 4], A);
        Target[X * 4 + 1] := Premultiply(PByte(Source)[X * 4 + 1], A);
        Target[X * 4 + 2] := Premultiply(PByte(Source)[X * 4 + 2], A);
        Target[X * 4 + 3] := A;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TPng.Read(const FileName: string): TPdfBitmap;
begin
  Result := FromBytes(TFile.ReadAllBytes(FileName));
end;

class function TPng.ToBytes(const Bitmap: TPdfBitmap): TBytes;
begin
  var Raw: TBytes;
  const RowBytes = Bitmap.Width * 4;
  SetLength(Raw, Bitmap.Height * (RowBytes + 1));
  for var Y := 0 to Bitmap.Height - 1 do
  begin
    const RowStart = Y * (RowBytes + 1);
    Raw[RowStart] := 0;
    const Source = Bitmap.ScanLine(Y);
    for var X := 0 to Bitmap.Width - 1 do
    begin
      const A = Source[X * 4 + 3];
      Raw[RowStart + 1 + X * 4] := Unpremultiply(Source[X * 4], A);
      Raw[RowStart + 2 + X * 4] := Unpremultiply(Source[X * 4 + 1], A);
      Raw[RowStart + 3 + X * 4] := Unpremultiply(Source[X * 4 + 2], A);
      Raw[RowStart + 4 + X * 4] := A;
    end;
  end;

  var Compressed: TBytes;
  ZCompress(Raw, Compressed);

  var Header := BigEndian(Bitmap.Width);
  AppendBytes(Header, BigEndian(Bitmap.Height));
  AppendBytes(Header, [8, ColorTypeRgba, 0, 0, 0]);

  Result := nil;
  SetLength(Result, Length(Signature));
  Move(Signature[0], Result[0], Length(Signature));
  AppendChunk(Result, 'IHDR', Header);
  AppendChunk(Result, 'IDAT', Compressed);
  AppendChunk(Result, 'IEND', nil);
end;

class procedure TPng.Write(const Bitmap: TPdfBitmap; const FileName: string);
begin
  TFile.WriteAllBytes(FileName, ToBytes(Bitmap));
end;

end.
