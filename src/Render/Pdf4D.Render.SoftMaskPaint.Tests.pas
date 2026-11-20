// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the mask that TPdfSoftMaskBuilder makes of the image of a soft mask group (PDFBox 3.0.8, applySoftMaskToPaint) and of the
// transfer function of images (applyTransferFunction)
unit Pdf4D.Render.SoftMaskPaint.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Graphics.&Function,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Functions;

type
  [TestFixture]
  TSoftMaskBuilderTests = class
  private
    const Size = 4;

  private
    FBuilder: TFunctionTestBuilder;

    // Every pixel of the colour, premultiplied as the layers of a group have them
    function FilledBitmap(const Color: TPdfDeviceColor): TPdfBitmap;
    function SquareFunction: TPDFunction;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLuminosityMaskFromWhiteGroupIsOpaque;

    [Test]
    procedure TestLuminosityUsesRec601Weights;

    [Test]
    procedure TestAlphaMaskUsesGroupAlpha;

    [Test]
    procedure TestLuminosityIsOfTheGroupOverBlack;

    [Test]
    procedure TestTransferFunctionApplied;

    [Test]
    procedure TestTransferFunctionNotAppliedToTheValueOutside;

    [Test]
    procedure TestBackdropValueUsesTheWeightsOfPdfBox;

    [Test]
    procedure TestMaskLiesAtTheGivenPosition;

    [Test]
    procedure TestLuminosityOfAColour;
  end;

  [TestFixture]
  TImageTransferTests = class
  private
    FBuilder: TFunctionTestBuilder;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTableOfNoFunctionIsTheIdentity;

    [Test]
    procedure TestTableTruncatesLikeAnInt;

    [Test]
    procedure TestApplyKeepsTheAlphaOfAPremultipliedPixel;
  end;

implementation

uses
  Pdf4D.Render.SoftMaskPaint;

const
  Tolerance = 1;

{ TSoftMaskBuilderTests }

procedure TSoftMaskBuilderTests.Setup;
begin
  FBuilder := TFunctionTestBuilder.Create;
end;

procedure TSoftMaskBuilderTests.TearDown;
begin
  FreeAndNil(FBuilder);
end;

function TSoftMaskBuilderTests.FilledBitmap(const Color: TPdfDeviceColor): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Size, Size);
  const Alpha = Color.A;
  const Premultiplied = TPdfDeviceColor.Create((Color.R * Alpha + 127) div 255, (Color.G * Alpha + 127) div 255, (Color.B * Alpha + 127) div 255, Alpha);
  for var Y := 0 to Size - 1 do
  begin
    for var X := 0 to Size - 1 do
    begin
      Result.SetPixel(X, Y, Premultiplied);
    end;
  end;
end;

// x squared
function TSoftMaskBuilderTests.SquareFunction: TPDFunction;
begin
  Result := TPDFunction.Create(FBuilder.NewType2('0 1', '0', '1', 2), FBuilder.Context);
end;

procedure TSoftMaskBuilderTests.TestLuminosityMaskFromWhiteGroupIsOpaque;
begin
  const Image = FilledBitmap(TPdfDeviceColor.White);
  try
    const Mask = TPdfSoftMaskBuilder.MaskFromImage(Image, 0, 0, False, 0, nil);
    try
      for var Value in Mask.Values do
      begin
        Assert.AreEqual<Integer>(255, Value);
      end;
    finally
      Mask.Free;
    end;
  finally
    Image.Free;
  end;
end;

procedure TSoftMaskBuilderTests.TestLuminosityUsesRec601Weights;
begin
  const Gray = FilledBitmap(TPdfDeviceColor.Create(128, 128, 128));
  const Red = FilledBitmap(TPdfDeviceColor.Create(255, 0, 0));
  const Green = FilledBitmap(TPdfDeviceColor.Create(0, 255, 0));
  const Blue = FilledBitmap(TPdfDeviceColor.Create(0, 0, 255));
  try
    const GrayMask = TPdfSoftMaskBuilder.MaskFromImage(Gray, 0, 0, False, 0, nil);
    const RedMask = TPdfSoftMaskBuilder.MaskFromImage(Red, 0, 0, False, 0, nil);
    const GreenMask = TPdfSoftMaskBuilder.MaskFromImage(Green, 0, 0, False, 0, nil);
    const BlueMask = TPdfSoftMaskBuilder.MaskFromImage(Blue, 0, 0, False, 0, nil);
    try
      Assert.AreEqual(Double(128), Double(GrayMask.ValueAt(1, 1)), Tolerance);
      Assert.AreEqual(Double(0.299 * 255), Double(RedMask.ValueAt(1, 1)), Tolerance);
      Assert.AreEqual(Double(0.587 * 255), Double(GreenMask.ValueAt(1, 1)), Tolerance);
      Assert.AreEqual(Double(0.114 * 255), Double(BlueMask.ValueAt(1, 1)), Tolerance);
    finally
      BlueMask.Free;
      GreenMask.Free;
      RedMask.Free;
      GrayMask.Free;
    end;
  finally
    Blue.Free;
    Green.Free;
    Red.Free;
    Gray.Free;
  end;
end;

procedure TSoftMaskBuilderTests.TestAlphaMaskUsesGroupAlpha;
begin
  const Image = FilledBitmap(TPdfDeviceColor.Create(255, 0, 0, 100));
  try
    const Mask = TPdfSoftMaskBuilder.MaskFromImage(Image, 0, 0, True, 0, nil);
    try
      Assert.AreEqual<Integer>(100, Mask.ValueAt(2, 2));
    finally
      Mask.Free;
    end;
  finally
    Image.Free;
  end;
end;

// A luminosity group is drawn over black: a half transparent white shows as gray
procedure TSoftMaskBuilderTests.TestLuminosityIsOfTheGroupOverBlack;
begin
  const Image = FilledBitmap(TPdfDeviceColor.Create(255, 255, 255, 128));
  try
    const Mask = TPdfSoftMaskBuilder.MaskFromImage(Image, 0, 0, False, 0, nil);
    try
      Assert.AreEqual(Double(128), Double(Mask.ValueAt(0, 0)), Tolerance);
    finally
      Mask.Free;
    end;
  finally
    Image.Free;
  end;
end;

procedure TSoftMaskBuilderTests.TestTransferFunctionApplied;
begin
  const Image = FilledBitmap(TPdfDeviceColor.Create(128, 128, 128));
  const Transfer = SquareFunction;
  try
    const Mask = TPdfSoftMaskBuilder.MaskFromImage(Image, 0, 0, False, 0, Transfer);
    try
      // 0.5 becomes 0.25
      Assert.AreEqual(Double(0.25 * 255), Double(Mask.ValueAt(1, 1)), Tolerance);
    finally
      Mask.Free;
    end;
  finally
    Transfer.Free;
    Image.Free;
  end;
end;

// SoftPaintContext.getRaster: the value outside the mask image is bc / 255, the transfer function maps the values inside the image only
procedure TSoftMaskBuilderTests.TestTransferFunctionNotAppliedToTheValueOutside;
begin
  const Image = FilledBitmap(TPdfDeviceColor.White);
  const Transfer = SquareFunction;
  try
    const Mask = TPdfSoftMaskBuilder.MaskFromImage(Image, 0, 0, False, 128, Transfer);
    try
      Assert.AreEqual<Integer>(128, Mask.OutsideValue);
      Assert.AreEqual<Integer>(255, Mask.ValueAt(1, 1));
    finally
      Mask.Free;
    end;
  finally
    Transfer.Free;
    Image.Free;
  end;
end;

// SoftMask: bc = (299 * red + 587 * green + 114 * blue) / 1000 with an integer division
procedure TSoftMaskBuilderTests.TestBackdropValueUsesTheWeightsOfPdfBox;
begin
  Assert.AreEqual<Integer>(76, TPdfSoftMaskBuilder.BackdropValue(TPdfDeviceColor.Create(255, 0, 0)));
  Assert.AreEqual<Integer>(255, TPdfSoftMaskBuilder.BackdropValue(TPdfDeviceColor.White));
  Assert.AreEqual<Integer>(0, TPdfSoftMaskBuilder.BackdropValue(TPdfDeviceColor.Create(0, 0, 0)));
end;

procedure TSoftMaskBuilderTests.TestMaskLiesAtTheGivenPosition;
begin
  const Image = FilledBitmap(TPdfDeviceColor.White);
  try
    const Mask = TPdfSoftMaskBuilder.MaskFromImage(Image, 10, 20, False, 7, nil);
    try
      Assert.AreEqual<Integer>(10, Mask.Left);
      Assert.AreEqual<Integer>(20, Mask.Top);
      Assert.AreEqual<Integer>(Size, Mask.Width);
      Assert.AreEqual<Integer>(255, Mask.ValueAt(10, 20));
      Assert.AreEqual<Integer>(255, Mask.ValueAt(13, 23));
      Assert.AreEqual<Integer>(7, Mask.ValueAt(9, 20));
      Assert.AreEqual<Integer>(7, Mask.ValueAt(10, 24));
    finally
      Mask.Free;
    end;
  finally
    Image.Free;
  end;
end;

procedure TSoftMaskBuilderTests.TestLuminosityOfAColour;
begin
  Assert.AreEqual<Integer>(255, TPdfSoftMaskBuilder.Luminosity(TPdfDeviceColor.White));
  Assert.AreEqual<Integer>(0, TPdfSoftMaskBuilder.Luminosity(TPdfDeviceColor.Create(0, 0, 0)));
  Assert.AreEqual<Integer>(128, TPdfSoftMaskBuilder.Luminosity(TPdfDeviceColor.Create(128, 128, 128)));
end;

{ TImageTransferTests }

procedure TImageTransferTests.Setup;
begin
  FBuilder := TFunctionTestBuilder.Create;
end;

procedure TImageTransferTests.TearDown;
begin
  FreeAndNil(FBuilder);
end;

procedure TImageTransferTests.TestTableOfNoFunctionIsTheIdentity;
begin
  const Table = TPdfImageTransfer.Table(nil);

  Assert.AreEqual<Integer>(256, Length(Table));
  Assert.AreEqual<Integer>(0, Table[0]);
  Assert.AreEqual<Integer>(77, Table[77]);
  Assert.AreEqual<Integer>(255, Table[255]);
end;

// (int) (x * 255) of 1 - x for 1 is 0, and the table is limited to 0..255
procedure TImageTransferTests.TestTableTruncatesLikeAnInt;
begin
  const Transfer = TPDFunction.Create(FBuilder.NewType2('0 1', '1', '0', 1), FBuilder.Context);
  try
    const Table = TPdfImageTransfer.Table(Transfer);

    Assert.AreEqual<Integer>(255, Table[0]);
    Assert.AreEqual<Integer>(0, Table[255]);
    Assert.IsTrue(Table[128] in [126, 127]);
  finally
    Transfer.Free;
  end;
end;

// A half transparent pixel: the colour is unpremultiplied for the function, and premultiplied again
procedure TImageTransferTests.TestApplyKeepsTheAlphaOfAPremultipliedPixel;
begin
  const Bitmap = TPdfBitmap.Create(1, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(0, 0, 0, 128));
    const Transfer = FBuilder.NewType2('0 1', '1', '0', 1);

    TPdfImageTransfer.Apply(Bitmap, Transfer, FBuilder.Context);

    // black becomes white of alpha 128: premultiplied (128, 128, 128, 128)
    const Pixel = Bitmap.GetPixel(0, 0);
    Assert.AreEqual<Integer>(128, Pixel.A);
    Assert.AreEqual(Double(128), Double(Pixel.R), Tolerance);
    Assert.AreEqual(Double(128), Double(Pixel.G), Tolerance);
    Assert.AreEqual(Double(128), Double(Pixel.B), Tolerance);
  finally
    Bitmap.Free;
  end;
end;

end.
