// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.Png;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Render.Bitmap;

type
  TPdfPngColorType = (Rgb, Rgba);

  // Writes 8-bit RGB and RGBA PNG files without interlace, as one zlib stream in IDAT chunks of at most 1 MB
  TPdfPngEncoder = class
  strict private
    const
      FilterNone = 0;
      FilterSub = 1;
      FilterUp = 2;
      FilterPaeth = 4;
      TrialFilters: array[0..2] of Integer = (FilterSub, FilterUp, FilterPaeth);
      MaxIdatBytes = 1024 * 1024;
      PixelBytes = 4;

    class function BytesPerPixel(const ColorType: TPdfPngColorType): Integer; static;
    class procedure CheckArguments(const Width, Height: Integer; const Pixels: TBytes); static;
    class procedure CopyRow(const Pixels: TBytes; const Row, Width: Integer; const ColorType: TPdfPngColorType; const Target: PByte); static;
    class function Paeth(const Left, Above, UpperLeft: Integer): Integer; static;
    class function ApplyFilter(const FilterType: Integer; const Current, Previous, Target: PByte; const RowBytes, Step: Integer): Integer; static;
    class function FilterRows(const Width, Height: Integer; const Pixels: TBytes; const ColorType: TPdfPngColorType): TBytes; static;
    class function Compress(const Data: TBytes): TBytes; static;
    class procedure WriteBigEndian(const Stream: TStream; const Value: Cardinal); static;
    class procedure WriteChunk(const Stream: TStream; const ChunkType: AnsiString; const Body: PByte; const Size: Integer); static;
    class procedure WriteHeader(const Stream: TStream; const Width, Height: Integer; const ColorType: TPdfPngColorType); static;
    class procedure WriteImageData(const Stream: TStream; const Compressed: TBytes); static;
    class function ToStraightPixels(const Bitmap: TPdfBitmap; out IsOpaque: Boolean): TBytes; static;
  public
    // Pixels: straight (not premultiplied) RGBA, rows top to bottom, stride Width * 4. ColorType Rgb drops alpha.
    // Raises EArgumentOutOfRangeException for Width/Height < 1 or a Pixels length <> Width * Height * 4.
    class function Encode(const Width, Height: Integer; const Pixels: TBytes; const ColorType: TPdfPngColorType): TBytes; static;
    // Premultiplied TPdfBitmap -> straight RGBA -> Encode; Rgb when every alpha is 255
    class function EncodeBitmap(const Bitmap: TPdfBitmap): TBytes; static;
  end;

implementation

uses
  System.Math,
  System.ZLib;

const
  PngSignature: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
  ColorTypeRgb = 2;
  ColorTypeRgba = 6;
  BitDepth = 8;
  OpaqueAlpha = 255;
  SignedByteLimit = 128;
  ByteRange = 256;

{ TPdfPngEncoder }

class function TPdfPngEncoder.BytesPerPixel(const ColorType: TPdfPngColorType): Integer;
begin
  if ColorType = TPdfPngColorType.Rgba then
  begin
    Result := 4;
  end
  else
  begin
    Result := 3;
  end;
end;

class procedure TPdfPngEncoder.CheckArguments(const Width, Height: Integer; const Pixels: TBytes);
begin
  const IsTooSmall = ((Width < 1) or (Height < 1));
  if IsTooSmall then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Image size %d x %d is not positive', [Width, Height]);
  end;

  const ExpectedLength = Int64(Width) * Int64(Height) * PixelBytes;
  if Length(Pixels) <> ExpectedLength then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The pixel data has %d bytes; an image of %d x %d needs %d', [Length(Pixels), Width, Height, ExpectedLength]);
  end;
end;

class procedure TPdfPngEncoder.CopyRow(const Pixels: TBytes; const Row, Width: Integer; const ColorType: TPdfPngColorType; const Target: PByte);
begin
  const Source = PByte(Pixels) + Int64(Row) * Width * PixelBytes;
  if ColorType = TPdfPngColorType.Rgba then
  begin
    Move(Source^, Target^, Width * PixelBytes);
    Exit;
  end;

  for var X := 0 to Width - 1 do
  begin
    Move(Source[X * PixelBytes], Target[X * 3], 3);
  end;
end;

class function TPdfPngEncoder.Paeth(const Left, Above, UpperLeft: Integer): Integer;
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

// Writes the filtered row to Target and returns the sum of its bytes as signed values
class function TPdfPngEncoder.ApplyFilter(const FilterType: Integer; const Current, Previous, Target: PByte; const RowBytes, Step: Integer): Integer;
begin
  Result := 0;
  for var Index := 0 to RowBytes - 1 do
  begin
    var Left := 0;
    var UpperLeft := 0;
    if Index >= Step then
    begin
      Left := Current[Index - Step];
      UpperLeft := Previous[Index - Step];
    end;
    const Above = Previous[Index];

    var Predicted: Integer;
    case FilterType of
      FilterSub: Predicted := Left;
      FilterUp: Predicted := Above;
      FilterPaeth: Predicted := Paeth(Left, Above, UpperLeft);
    else
      Predicted := 0;
    end;

    const Filtered = Byte(Current[Index] - Predicted);
    Target[Index] := Filtered;
    if Filtered < SignedByteLimit then
    begin
      Inc(Result, Filtered);
    end
    else
    begin
      Inc(Result, ByteRange - Filtered);
    end;
  end;
end;

class function TPdfPngEncoder.FilterRows(const Width, Height: Integer; const Pixels: TBytes; const ColorType: TPdfPngColorType): TBytes;
begin
  const Step = BytesPerPixel(ColorType);
  const RowBytes = Width * Step;

  var Previous: TBytes;
  var Current: TBytes;
  var Candidate: TBytes;
  var Best: TBytes;
  SetLength(Previous, RowBytes);
  SetLength(Current, RowBytes);
  SetLength(Candidate, RowBytes);
  SetLength(Best, RowBytes);
  FillChar(Previous[0], RowBytes, 0);

  Result := nil;
  SetLength(Result, (Int64(RowBytes) + 1) * Height);
  for var Row := 0 to Height - 1 do
  begin
    CopyRow(Pixels, Row, Width, ColorType, PByte(Current));

    var BestType := FilterNone;
    var BestSum := ApplyFilter(FilterNone, PByte(Current), PByte(Previous), PByte(Best), RowBytes, Step);
    for var FilterType in TrialFilters do
    begin
      const Sum = ApplyFilter(FilterType, PByte(Current), PByte(Previous), PByte(Candidate), RowBytes, Step);
      if Sum < BestSum then
      begin
        BestSum := Sum;
        BestType := FilterType;
        var Swap := Best;
        Best := Candidate;
        Candidate := Swap;
      end;
    end;

    const Offset = Int64(Row) * (RowBytes + 1);
    Result[Offset] := Byte(BestType);
    Move(Best[0], Result[Offset + 1], RowBytes);
    var Finished := Current;
    Current := Previous;
    Previous := Finished;
  end;
end;

class function TPdfPngEncoder.Compress(const Data: TBytes): TBytes;
begin
  const Output = TBytesStream.Create;
  try
    const Compressor = TZCompressionStream.Create(Output);
    try
      Compressor.WriteBuffer(Data[0], Length(Data));
    finally
      Compressor.Free;
    end;
    Result := Copy(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
  end;
end;

class procedure TPdfPngEncoder.WriteBigEndian(const Stream: TStream; const Value: Cardinal);
begin
  var Bytes: array[0..3] of Byte;
  Bytes[0] := Byte(Value shr 24);
  Bytes[1] := Byte(Value shr 16);
  Bytes[2] := Byte(Value shr 8);
  Bytes[3] := Byte(Value);
  Stream.WriteBuffer(Bytes[0], SizeOf(Bytes));
end;

class procedure TPdfPngEncoder.WriteChunk(const Stream: TStream; const ChunkType: AnsiString; const Body: PByte; const Size: Integer);
begin
  WriteBigEndian(Stream, Cardinal(Size));
  Stream.WriteBuffer(ChunkType[1], Length(ChunkType));

  var Checksum := crc32(0, PByte(PAnsiChar(ChunkType)), Length(ChunkType));
  if Size > 0 then
  begin
    Stream.WriteBuffer(Body^, Size);
    Checksum := crc32(Checksum, Body, Cardinal(Size));
  end;
  WriteBigEndian(Stream, Checksum);
end;

class procedure TPdfPngEncoder.WriteHeader(const Stream: TStream; const Width, Height: Integer; const ColorType: TPdfPngColorType);
begin
  var Body: array[0..12] of Byte;
  Body[0] := Byte(Width shr 24);
  Body[1] := Byte(Width shr 16);
  Body[2] := Byte(Width shr 8);
  Body[3] := Byte(Width);
  Body[4] := Byte(Height shr 24);
  Body[5] := Byte(Height shr 16);
  Body[6] := Byte(Height shr 8);
  Body[7] := Byte(Height);
  Body[8] := BitDepth;
  if ColorType = TPdfPngColorType.Rgba then
  begin
    Body[9] := ColorTypeRgba;
  end
  else
  begin
    Body[9] := ColorTypeRgb;
  end;
  // Compression method, filter method and interlace method
  Body[10] := 0;
  Body[11] := 0;
  Body[12] := 0;
  WriteChunk(Stream, 'IHDR', @Body[0], SizeOf(Body));
end;

class procedure TPdfPngEncoder.WriteImageData(const Stream: TStream; const Compressed: TBytes);
begin
  var Offset := 0;
  while Offset < Length(Compressed) do
  begin
    const Size = Length(Compressed) - Offset;
    const ChunkSize = Min(Size, MaxIdatBytes);
    WriteChunk(Stream, 'IDAT', @Compressed[Offset], ChunkSize);
    Inc(Offset, ChunkSize);
  end;
end;

class function TPdfPngEncoder.Encode(const Width, Height: Integer; const Pixels: TBytes; const ColorType: TPdfPngColorType): TBytes;
begin
  CheckArguments(Width, Height, Pixels);

  const Compressed = Compress(FilterRows(Width, Height, Pixels, ColorType));

  const Output = TBytesStream.Create;
  try
    Output.WriteBuffer(PngSignature[0], SizeOf(PngSignature));
    WriteHeader(Output, Width, Height, ColorType);
    WriteImageData(Output, Compressed);
    WriteChunk(Output, 'IEND', nil, 0);
    Result := Copy(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
  end;
end;

class function TPdfPngEncoder.ToStraightPixels(const Bitmap: TPdfBitmap; out IsOpaque: Boolean): TBytes;
begin
  const Source = Bitmap.Pixels;
  Result := nil;
  SetLength(Result, Length(Source));
  IsOpaque := True;

  var Offset := 0;
  while Offset < Length(Source) do
  begin
    const Alpha = Source[Offset + 3];
    if Alpha <> OpaqueAlpha then
    begin
      IsOpaque := False;
    end;

    for var Channel := 0 to 2 do
    begin
      if Alpha = 0 then
      begin
        Result[Offset + Channel] := 0;
      end
      else
      begin
        const Straight = (Integer(Source[Offset + Channel]) * OpaqueAlpha + Alpha div 2) div Alpha;
        Result[Offset + Channel] := Byte(Min(Straight, OpaqueAlpha));
      end;
    end;
    Result[Offset + 3] := Alpha;
    Inc(Offset, PixelBytes);
  end;
end;

class function TPdfPngEncoder.EncodeBitmap(const Bitmap: TPdfBitmap): TBytes;
begin
  var IsOpaque: Boolean;
  const Straight = ToStraightPixels(Bitmap, IsOpaque);

  if IsOpaque then
  begin
    Result := Encode(Bitmap.Width, Bitmap.Height, Straight, TPdfPngColorType.Rgb);
  end
  else
  begin
    Result := Encode(Bitmap.Width, Bitmap.Height, Straight, TPdfPngColorType.Rgba);
  end;
end;

end.
