// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Png.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TPngTests = class
  private
    class procedure Append(var Target: TBytes; const Addition: TBytes); static;
    class function Chunk(const ChunkType: string; const Body: TBytes): TBytes; static;
    class function Handmade(const ColorType: Byte; const Width, Height: Integer; const Rows: TBytes; const Palette: TBytes = nil;
                            const Transparency: TBytes = nil): TBytes; static;

  public
    [Test]
    procedure TestRoundTripRgba;

    [Test]
    procedure TestReadsGrayAndPalette;

    [Test]
    procedure TestReadsFilteredRows;
  end;

implementation

uses
  System.ZLib,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Png;

const
  SignatureBytes: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);

class procedure TPngTests.Append(var Target: TBytes; const Addition: TBytes);
begin
  const OldLength = Length(Target);
  SetLength(Target, OldLength + Length(Addition));
  if Length(Addition) > 0 then
  begin
    Move(Addition[0], Target[OldLength], Length(Addition));
  end;
end;

// The CRC is not checked by the reader, so the chunk gets zeros
class function TPngTests.Chunk(const ChunkType: string; const Body: TBytes): TBytes;
begin
  Result := [0, 0, Byte(Length(Body) shr 8), Byte(Length(Body))];
  Append(Result, TEncoding.ASCII.GetBytes(ChunkType));
  Append(Result, Body);
  Append(Result, [0, 0, 0, 0]);
end;

// Rows: for every row a filter byte and the data
class function TPngTests.Handmade(const ColorType: Byte; const Width, Height: Integer; const Rows: TBytes; const Palette, Transparency: TBytes): TBytes;
begin
  SetLength(Result, Length(SignatureBytes));
  Move(SignatureBytes[0], Result[0], Length(SignatureBytes));
  Append(Result, Chunk('IHDR', [0, 0, 0, Byte(Width), 0, 0, 0, Byte(Height), 8, ColorType, 0, 0, 0]));
  if Length(Palette) > 0 then
  begin
    Append(Result, Chunk('PLTE', Palette));
  end;
  if Length(Transparency) > 0 then
  begin
    Append(Result, Chunk('tRNS', Transparency));
  end;
  var Compressed: TBytes;
  ZCompress(Rows, Compressed);
  Append(Result, Chunk('IDAT', Compressed));
  Append(Result, Chunk('IEND', nil));
end;

procedure TPngTests.TestRoundTripRgba;
begin
  const Source = TPdfBitmap.Create(3, 2);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0, 255));
    Source.SetPixel(1, 0, TPdfDeviceColor.Create(0, 128, 0, 128));
    Source.SetPixel(2, 0, TPdfDeviceColor.Transparent);
    Source.SetPixel(0, 1, TPdfDeviceColor.Create(10, 20, 30, 255));
    Source.SetPixel(1, 1, TPdfDeviceColor.Create(1, 2, 3, 255));
    Source.SetPixel(2, 1, TPdfDeviceColor.White);

    const Copy = TPng.FromBytes(TPng.ToBytes(Source));
    try
      Assert.AreEqual(3, Copy.Width);
      Assert.AreEqual(2, Copy.Height);
      Assert.AreEqual<TBytes>(Source.Pixels, Copy.Pixels);
    finally
      Copy.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TPngTests.TestReadsGrayAndPalette;
begin
  const Gray = TPng.FromBytes(Handmade(0, 2, 1, [0, 10, 200]));
  const GrayAlpha = TPng.FromBytes(Handmade(4, 1, 1, [0, 100, 255]));
  const Palette = TPng.FromBytes(Handmade(3, 2, 1, [0, 1, 0], [1, 2, 3, 40, 50, 60], [128, 255]));
  try
    Assert.AreEqual<Byte>(10, Gray.GetPixel(0, 0).G);
    Assert.AreEqual<Byte>(200, Gray.GetPixel(1, 0).B);
    Assert.AreEqual<Byte>(255, Gray.GetPixel(1, 0).A);
    Assert.AreEqual<Byte>(100, GrayAlpha.GetPixel(0, 0).R);
    Assert.AreEqual<Byte>(40, Palette.GetPixel(0, 0).R);
    Assert.AreEqual<Byte>(255, Palette.GetPixel(0, 0).A);
    Assert.AreEqual<Byte>(128, Palette.GetPixel(1, 0).A);
    Assert.AreEqual<Byte>(1, Palette.GetPixel(1, 0).R);
  finally
    Palette.Free;
    GrayAlpha.Free;
    Gray.Free;
  end;
end;

// Sub, Up, Average and Paeth on a gray image of 2 x 4
procedure TPngTests.TestReadsFilteredRows;
begin
  const Image = TPng.FromBytes(Handmade(0, 2, 4, [1, 10, 5,   2, 1, 1,   3, 1, 1,   4, 1, 1]));
  try
    Assert.AreEqual<Byte>(10, Image.GetPixel(0, 0).R);
    Assert.AreEqual<Byte>(15, Image.GetPixel(1, 0).R);
    Assert.AreEqual<Byte>(11, Image.GetPixel(0, 1).R);
    Assert.AreEqual<Byte>(16, Image.GetPixel(1, 1).R);
    // Average: 1 + (0 + 11) div 2 = 6 and 1 + (6 + 16) div 2 = 12
    Assert.AreEqual<Byte>(6, Image.GetPixel(0, 2).R);
    Assert.AreEqual<Byte>(12, Image.GetPixel(1, 2).R);
    // Paeth: left 0, above 6, upper left 0 gives 6, so 7; then left 7, above 12, upper left 6: estimate 13 gives 12, so 13
    Assert.AreEqual<Byte>(7, Image.GetPixel(0, 3).R);
    Assert.AreEqual<Byte>(13, Image.GetPixel(1, 3).R);
  finally
    Image.Free;
  end;
end;

end.
