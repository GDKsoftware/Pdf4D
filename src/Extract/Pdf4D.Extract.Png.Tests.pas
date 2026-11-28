// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.Png.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TPdfPngEncoderTests = class
  private
    function Gradient(const Width, Height: Integer): TBytes;
    function Noise(const Width, Height: Integer): TBytes;
    function ReadChunkCount(const Png: TBytes; const ChunkType: string): Integer;
    function LargestChunk(const Png: TBytes; const ChunkType: string): Integer;
    procedure CheckPixelsEqual(const Expected, Actual: TBytes; const ColorType: Integer);
    procedure EncodeZeroWidth;
    procedure EncodeZeroHeight;
    procedure EncodeShortPixels;
    procedure EncodeLongPixels;

  public
    [Test]
    procedure TestSignatureAndIhdr;

    [Test]
    procedure TestChunkCrcsAreValid;

    [Test]
    procedure TestRoundTripRgb;

    [Test]
    procedure TestRoundTripRgba;

    [Test]
    procedure TestEncodeBitmapUnpremultiplies;

    [Test]
    procedure TestOpaqueBitmapGivesRgb;

    [Test]
    procedure TestLargeImageSplitsIdat;

    [Test]
    procedure TestInvalidSizeRaises;
  end;

implementation

uses
  System.Math,
  System.ZLib,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Png,
  Pdf4D.Extract.Png;

const
  SignatureLength = 8;
  ChunkOverhead = 12;
  ColorTypeRgb = 2;
  ColorTypeRgba = 6;
  MaxIdatBytes = 1024 * 1024;

function ReadBigEndian(const Data: TBytes; const Offset: Integer): Cardinal;
begin
  Result := (Cardinal(Data[Offset]) shl 24) or (Cardinal(Data[Offset + 1]) shl 16) or (Cardinal(Data[Offset + 2]) shl 8) or Data[Offset + 3];
end;

function ChunkTypeAt(const Data: TBytes; const Offset: Integer): string;
begin
  Result := Chr(Data[Offset]) + Chr(Data[Offset + 1]) + Chr(Data[Offset + 2]) + Chr(Data[Offset + 3]);
end;

function TPdfPngEncoderTests.Gradient(const Width, Height: Integer): TBytes;
begin
  Result := nil;
  SetLength(Result, Width * Height * 4);
  for var Y := 0 to Height - 1 do
  begin
    for var X := 0 to Width - 1 do
    begin
      const Offset = (Y * Width + X) * 4;
      Result[Offset] := Byte(X * 7 + Y);
      Result[Offset + 1] := Byte(Y * 13);
      Result[Offset + 2] := Byte(X * X + Y * 3);
      Result[Offset + 3] := Byte(255 - (X + Y) * 5);
    end;
  end;
end;

function TPdfPngEncoderTests.Noise(const Width, Height: Integer): TBytes;
begin
  Result := nil;
  SetLength(Result, Width * Height * 4);
  var State: Cardinal := 12345;
  for var Index := 0 to High(Result) do
  begin
    State := State * 1664525 + 1013904223;
    Result[Index] := Byte(State shr 24);
  end;
end;

function TPdfPngEncoderTests.ReadChunkCount(const Png: TBytes; const ChunkType: string): Integer;
begin
  Result := 0;
  var Offset: Integer := SignatureLength;
  while Offset + ChunkOverhead <= Length(Png) do
  begin
    const Size = ReadBigEndian(Png, Offset);
    if ChunkTypeAt(Png, Offset + 4) = ChunkType then
    begin
      Inc(Result);
    end;
    Offset := Offset + ChunkOverhead + Integer(Size);
  end;
end;

function TPdfPngEncoderTests.LargestChunk(const Png: TBytes; const ChunkType: string): Integer;
begin
  Result := 0;
  var Offset: Integer := SignatureLength;
  while Offset + ChunkOverhead <= Length(Png) do
  begin
    const Size = Integer(ReadBigEndian(Png, Offset));
    if (ChunkTypeAt(Png, Offset + 4) = ChunkType) and (Size > Result) then
    begin
      Result := Size;
    end;
    Offset := Offset + ChunkOverhead + Size;
  end;
end;

procedure TPdfPngEncoderTests.CheckPixelsEqual(const Expected, Actual: TBytes; const ColorType: Integer);
begin
  Assert.AreEqual(Length(Expected), Length(Actual));
  for var Index := 0 to High(Expected) do
  begin
    const IsDroppedAlpha = (ColorType = ColorTypeRgb) and (Index mod 4 = 3);
    const ExpectedValue = IfThen(IsDroppedAlpha, 255, Expected[Index]);
    if Actual[Index] <> ExpectedValue then
    begin
      Assert.Fail(Format('Byte %d differs: expected %d, got %d', [Index, ExpectedValue, Actual[Index]]));
    end;
  end;
end;

procedure TPdfPngEncoderTests.TestSignatureAndIhdr;
begin
  const Png = TPdfPngEncoder.Encode(5, 3, Gradient(5, 3), TPdfPngColorType.Rgba);

  Assert.AreEqual<Byte>(137, Png[0]);
  Assert.AreEqual<Byte>(80, Png[1]);
  Assert.AreEqual<Byte>(78, Png[2]);
  Assert.AreEqual<Byte>(71, Png[3]);
  Assert.AreEqual<Byte>(13, Png[4]);
  Assert.AreEqual<Byte>(10, Png[5]);
  Assert.AreEqual<Byte>(26, Png[6]);
  Assert.AreEqual<Byte>(10, Png[7]);
  Assert.AreEqual<Cardinal>(13, ReadBigEndian(Png, 8));
  Assert.AreEqual('IHDR', ChunkTypeAt(Png, 12));
  Assert.AreEqual<Cardinal>(5, ReadBigEndian(Png, 16));
  Assert.AreEqual<Cardinal>(3, ReadBigEndian(Png, 20));
  Assert.AreEqual<Byte>(8, Png[24]);
  Assert.AreEqual<Byte>(ColorTypeRgba, Png[25]);
  Assert.AreEqual<Byte>(0, Png[26]);
  Assert.AreEqual<Byte>(0, Png[27]);
  Assert.AreEqual<Byte>(0, Png[28]);

  const RgbPng = TPdfPngEncoder.Encode(5, 3, Gradient(5, 3), TPdfPngColorType.Rgb);
  Assert.AreEqual<Byte>(ColorTypeRgb, RgbPng[25]);
  Assert.AreEqual('IEND', ChunkTypeAt(RgbPng, Length(RgbPng) - 8));
end;

procedure TPdfPngEncoderTests.TestChunkCrcsAreValid;
begin
  const Png = TPdfPngEncoder.Encode(40, 30, Gradient(40, 30), TPdfPngColorType.Rgba);

  var Offset: Integer := SignatureLength;
  var Count: Integer := 0;
  while Offset < Length(Png) do
  begin
    const Size = Integer(ReadBigEndian(Png, Offset));
    const Expected = ReadBigEndian(Png, Offset + 8 + Size);
    const Actual = crc32(0, @Png[Offset + 4], Cardinal(Size + 4));
    Assert.AreEqual(Expected, Actual, 'CRC of chunk ' + ChunkTypeAt(Png, Offset + 4));
    Offset := Offset + ChunkOverhead + Size;
    Inc(Count);
  end;

  Assert.AreEqual<Integer>(Length(Png), Offset);
  Assert.IsTrue(Count >= 3);
end;

procedure TPdfPngEncoderTests.TestRoundTripRgb;
begin
  const Pixels = Gradient(37, 23);
  const Png = TPdfPngEncoder.Encode(37, 23, Pixels, TPdfPngColorType.Rgb);

  var Width, Height: Integer;
  const Decoded = TPng.DecodeStraight(Png, Width, Height);

  Assert.AreEqual(37, Width);
  Assert.AreEqual(23, Height);
  CheckPixelsEqual(Pixels, Decoded, ColorTypeRgb);
end;

procedure TPdfPngEncoderTests.TestRoundTripRgba;
begin
  const Pixels = Gradient(37, 23);
  const Png = TPdfPngEncoder.Encode(37, 23, Pixels, TPdfPngColorType.Rgba);

  var Width, Height: Integer;
  const Decoded = TPng.DecodeStraight(Png, Width, Height);

  Assert.AreEqual(37, Width);
  Assert.AreEqual(23, Height);
  CheckPixelsEqual(Pixels, Decoded, ColorTypeRgba);
end;

procedure TPdfPngEncoderTests.TestEncodeBitmapUnpremultiplies;
begin
  const Bitmap = TPdfBitmap.Create(2, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(64, 0, 0, 128));
    Bitmap.SetPixel(1, 0, TPdfDeviceColor.Create(0, 0, 0, 0));

    const Png = TPdfPngEncoder.EncodeBitmap(Bitmap);

    Assert.AreEqual<Byte>(ColorTypeRgba, Png[25]);
    var Width, Height: Integer;
    const Decoded = TPng.DecodeStraight(Png, Width, Height);
    Assert.AreEqual<Byte>(128, Decoded[0]);
    Assert.AreEqual<Byte>(0, Decoded[1]);
    Assert.AreEqual<Byte>(0, Decoded[2]);
    Assert.AreEqual<Byte>(128, Decoded[3]);
    Assert.AreEqual<Byte>(0, Decoded[7]);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfPngEncoderTests.TestOpaqueBitmapGivesRgb;
begin
  const Bitmap = TPdfBitmap.Create(3, 2);
  try
    for var Y := 0 to 1 do
    begin
      for var X := 0 to 2 do
      begin
        Bitmap.SetPixel(X, Y, TPdfDeviceColor.Create(Byte(X * 50), Byte(Y * 90), 200, 255));
      end;
    end;

    const Png = TPdfPngEncoder.EncodeBitmap(Bitmap);

    Assert.AreEqual<Byte>(ColorTypeRgb, Png[25]);
    var Width, Height: Integer;
    const Decoded = TPng.DecodeStraight(Png, Width, Height);
    Assert.AreEqual<Byte>(100, Decoded[(1 * 3 + 2) * 4]);
    Assert.AreEqual<Byte>(90, Decoded[(1 * 3 + 2) * 4 + 1]);
    Assert.AreEqual<Byte>(200, Decoded[(1 * 3 + 2) * 4 + 2]);
    Assert.AreEqual<Byte>(255, Decoded[(1 * 3 + 2) * 4 + 3]);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfPngEncoderTests.TestLargeImageSplitsIdat;
begin
  const Pixels = Noise(4000, 3000);

  const Png = TPdfPngEncoder.Encode(4000, 3000, Pixels, TPdfPngColorType.Rgba);

  Assert.IsTrue(ReadChunkCount(Png, 'IDAT') > 1, 'IDAT is split');
  Assert.IsTrue(LargestChunk(Png, 'IDAT') <= MaxIdatBytes, 'IDAT chunks are at most 1 MB');
  var Width, Height: Integer;
  const Decoded = TPng.DecodeStraight(Png, Width, Height);
  Assert.AreEqual(4000, Width);
  Assert.AreEqual(3000, Height);
  CheckPixelsEqual(Pixels, Decoded, ColorTypeRgba);
end;

procedure TPdfPngEncoderTests.EncodeZeroWidth;
begin
  TPdfPngEncoder.Encode(0, 1, nil, TPdfPngColorType.Rgba);
end;

procedure TPdfPngEncoderTests.EncodeZeroHeight;
begin
  TPdfPngEncoder.Encode(1, 0, nil, TPdfPngColorType.Rgba);
end;

procedure TPdfPngEncoderTests.EncodeShortPixels;
begin
  TPdfPngEncoder.Encode(2, 2, Gradient(2, 1), TPdfPngColorType.Rgba);
end;

procedure TPdfPngEncoderTests.EncodeLongPixels;
begin
  TPdfPngEncoder.Encode(2, 1, Gradient(2, 2), TPdfPngColorType.Rgb);
end;

procedure TPdfPngEncoderTests.TestInvalidSizeRaises;
begin
  Assert.WillRaise(EncodeZeroWidth, EArgumentOutOfRangeException);
  Assert.WillRaise(EncodeZeroHeight, EArgumentOutOfRangeException);
  Assert.WillRaise(EncodeShortPixels, EArgumentOutOfRangeException);
  Assert.WillRaise(EncodeLongPixels, EArgumentOutOfRangeException);
end;

end.
