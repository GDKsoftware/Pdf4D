// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Bitmap.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap;

type
  [TestFixture]
  TPdfBitmapTests = class
  public
    [Test]
    procedure TestNewBitmapIsTransparent;

    [Test]
    procedure TestSetAndGetPixel;

    [Test]
    procedure TestFlattenOnWhite;

    [Test]
    procedure TestFlattenOnColorKeepsOpaquePixelsAndFillsTransparentOnes;

    [Test]
    procedure TestTooLargeBitmapRaises;

    [Test]
    procedure TestPixelOutsideTheBitmapRaises;

    [Test]
    procedure TestCloneIsIndependent;

    [Test]
    procedure TestScanLineStartsAtTheRow;
  end;

  [TestFixture]
  TPdfAlphaMaskTests = class
  public
    [Test]
    procedure TestAlphaMaskOutsideValue;

    [Test]
    procedure TestEmptyMaskReturnsOutsideValue;

    [Test]
    procedure TestNegativeSizeRaises;
  end;

implementation

{ TPdfBitmapTests }

procedure TPdfBitmapTests.TestNewBitmapIsTransparent;
begin
  const Bitmap = TPdfBitmap.Create(3, 2);
  try
    Assert.AreEqual(3, Bitmap.Width);
    Assert.AreEqual(2, Bitmap.Height);
    Assert.AreEqual(12, Bitmap.Stride);
    Assert.AreEqual(24, Integer(Length(Bitmap.Pixels)));
    for var Value in Bitmap.Pixels do
    begin
      Assert.AreEqual(Byte(0), Value);
    end;
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfBitmapTests.TestSetAndGetPixel;
begin
  const Bitmap = TPdfBitmap.Create(3, 2);
  try
    Bitmap.SetPixel(2, 1, TPdfDeviceColor.Create(10, 20, 30, 40));

    Assert.AreEqual(Byte(10), Bitmap.Pixels[20]);
    Assert.AreEqual(Byte(20), Bitmap.Pixels[21]);
    Assert.AreEqual(Byte(30), Bitmap.Pixels[22]);
    Assert.AreEqual(Byte(40), Bitmap.Pixels[23]);

    const Pixel = Bitmap.GetPixel(2, 1);
    Assert.AreEqual(Byte(10), Pixel.R);
    Assert.AreEqual(Byte(20), Pixel.G);
    Assert.AreEqual(Byte(30), Pixel.B);
    Assert.AreEqual(Byte(40), Pixel.A);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfBitmapTests.TestFlattenOnWhite;
begin
  const Bitmap = TPdfBitmap.Create(2, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(128, 0, 0, 128));

    Bitmap.FlattenOn(TPdfDeviceColor.White);

    const Flattened = Bitmap.GetPixel(0, 0);
    Assert.AreEqual(255, Integer(Flattened.R), 1);
    Assert.AreEqual(127, Integer(Flattened.G), 1);
    Assert.AreEqual(127, Integer(Flattened.B), 1);
    Assert.AreEqual(Byte(255), Flattened.A);

    const Untouched = Bitmap.GetPixel(1, 0);
    Assert.AreEqual(Byte(255), Untouched.R);
    Assert.AreEqual(Byte(255), Untouched.A);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfBitmapTests.TestFlattenOnColorKeepsOpaquePixelsAndFillsTransparentOnes;
begin
  const Bitmap = TPdfBitmap.Create(2, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(1, 2, 3, 255));

    Bitmap.FlattenOn(TPdfDeviceColor.Create(10, 20, 30));

    const Opaque = Bitmap.GetPixel(0, 0);
    Assert.AreEqual(Byte(1), Opaque.R);
    Assert.AreEqual(Byte(2), Opaque.G);
    Assert.AreEqual(Byte(3), Opaque.B);

    const Filled = Bitmap.GetPixel(1, 0);
    Assert.AreEqual(Byte(10), Filled.R);
    Assert.AreEqual(Byte(20), Filled.G);
    Assert.AreEqual(Byte(30), Filled.B);
    Assert.AreEqual(Byte(255), Filled.A);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfBitmapTests.TestTooLargeBitmapRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfBitmap.Create(65536, 65536).Free;
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      TPdfBitmap.Create(0, 5).Free;
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      TPdfBitmap.Create(5, -1).Free;
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfBitmapTests.TestPixelOutsideTheBitmapRaises;
begin
  const Bitmap = TPdfBitmap.Create(3, 2);
  try
    Assert.WillRaise(
      procedure
      begin
        Bitmap.GetPixel(3, 0);
      end,
      EArgumentOutOfRangeException);
    Assert.WillRaise(
      procedure
      begin
        Bitmap.SetPixel(0, -1, TPdfDeviceColor.White);
      end,
      EArgumentOutOfRangeException);
    Assert.WillRaise(
      procedure
      begin
        Bitmap.ScanLine(2);
      end,
      EArgumentOutOfRangeException);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfBitmapTests.TestCloneIsIndependent;
begin
  const Bitmap = TPdfBitmap.Create(2, 2);
  try
    Bitmap.SetPixel(1, 1, TPdfDeviceColor.Create(1, 2, 3, 4));

    const Copy = Bitmap.Clone;
    try
      Bitmap.SetPixel(1, 1, TPdfDeviceColor.Create(9, 9, 9, 9));

      Assert.AreEqual(Byte(1), Copy.GetPixel(1, 1).R);
      Assert.AreEqual(Byte(4), Copy.GetPixel(1, 1).A);
      Assert.AreEqual(2, Copy.Width);
      Assert.AreEqual(2, Copy.Height);
    finally
      Copy.Free;
    end;
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfBitmapTests.TestScanLineStartsAtTheRow;
begin
  const Bitmap = TPdfBitmap.Create(3, 2);
  try
    Bitmap.SetPixel(0, 1, TPdfDeviceColor.Create(7, 8, 9, 10));

    const Row = Bitmap.ScanLine(1);

    Assert.AreEqual(Byte(7), Row^);
    Assert.AreEqual(NativeUInt(Bitmap.Stride), NativeUInt(Row) - NativeUInt(Bitmap.ScanLine(0)));
  finally
    Bitmap.Free;
  end;
end;

{ TPdfAlphaMaskTests }

procedure TPdfAlphaMaskTests.TestAlphaMaskOutsideValue;
begin
  const Mask = TPdfAlphaMask.Create(10, 10, 2, 2, 7);
  try
    Mask.Values[3] := 200;

    Assert.AreEqual(Byte(7), Mask.ValueAt(0, 0));
    Assert.AreEqual(Byte(7), Mask.ValueAt(12, 10));
    Assert.AreEqual(Byte(200), Mask.ValueAt(11, 11));
    Assert.AreEqual(Byte(0), Mask.ValueAt(10, 10));
    Assert.AreEqual(Byte(7), Mask.OutsideValue);
    Assert.AreEqual(4, Integer(Length(Mask.Values)));
  finally
    Mask.Free;
  end;
end;

procedure TPdfAlphaMaskTests.TestEmptyMaskReturnsOutsideValue;
begin
  const Mask = TPdfAlphaMask.Create(0, 0, 0, 0, 255);
  try
    Assert.AreEqual(Byte(255), Mask.ValueAt(0, 0));
    Assert.AreEqual(0, Integer(Length(Mask.Values)));
  finally
    Mask.Free;
  end;
end;

procedure TPdfAlphaMaskTests.TestNegativeSizeRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfAlphaMask.Create(0, 0, -1, 4, 0).Free;
    end,
    EArgumentOutOfRangeException);
end;

end.
