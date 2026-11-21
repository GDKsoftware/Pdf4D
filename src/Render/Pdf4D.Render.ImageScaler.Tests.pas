// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the area-averaging scaler; the expected values follow from the algorithm (the weights
// are the areas that the destination pixel covers of each source pixel)
unit Pdf4D.Render.ImageScaler.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap;

type
  [TestFixture]
  TImageScalerTests = class
  private
    FOwned: TArray<TPdfBitmap>;

    function Track(const Bitmap: TPdfBitmap): TPdfBitmap;
    // Opaque gray pixels, one row
    function GrayRow(const Values: array of Byte): TPdfBitmap;
    procedure AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const R, G, B, A: Byte);

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTwoByTwoAveragesToOnePixel;

    [Test]
    procedure TestThreeToTwoWeighsByCoveredArea;

    [Test]
    procedure TestRowsAreAveragedToo;

    [Test]
    procedure TestAlphaWeighsTheColour;

    [Test]
    procedure TestFlatImageStaysFlat;

    [Test]
    procedure TestSizeOfTheResult;

    [Test]
    procedure TestScalingUpRepeatsPixels;

    [Test]
    procedure TestInvalidSizeRaises;
  end;

implementation

uses
  Pdf4D.Render.ImageScaler;

{ TImageScalerTests }

procedure TImageScalerTests.TearDown;
begin
  for var Bitmap in FOwned do
  begin
    Bitmap.Free;
  end;
  FOwned := nil;
end;

function TImageScalerTests.Track(const Bitmap: TPdfBitmap): TPdfBitmap;
begin
  FOwned := FOwned + [Bitmap];
  Result := Bitmap;
end;

function TImageScalerTests.GrayRow(const Values: array of Byte): TPdfBitmap;
begin
  Result := Track(TPdfBitmap.Create(Length(Values), 1));
  for var Index := 0 to High(Values) do
  begin
    Result.SetPixel(Index, 0, TPdfDeviceColor.Create(Values[Index], Values[Index], Values[Index]));
  end;
end;

procedure TImageScalerTests.AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const R, G, B, A: Byte);
begin
  const Pixel = Bitmap.GetPixel(X, Y);
  Assert.AreEqual<Integer>(R, Pixel.R, Format('R of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(G, Pixel.G, Format('G of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(B, Pixel.B, Format('B of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(A, Pixel.A, Format('A of (%d, %d)', [X, Y]));
end;

procedure TImageScalerTests.TestTwoByTwoAveragesToOnePixel;
begin
  const Source = Track(TPdfBitmap.Create(2, 2));
  Source.SetPixel(0, 0, TPdfDeviceColor.Create(0, 0, 0));
  Source.SetPixel(1, 0, TPdfDeviceColor.Create(100, 100, 100));
  Source.SetPixel(0, 1, TPdfDeviceColor.Create(200, 200, 200));
  Source.SetPixel(1, 1, TPdfDeviceColor.Create(40, 40, 40));

  const Scaled = Track(TPdfImageScaler.ScaleSmooth(Source, 1, 1));

  AssertPixel(Scaled, 0, 0, 85, 85, 85, 255);
end;

// 3 source pixels on 2: every destination pixel covers 1.5 source pixels, so the middle one is shared half and half
procedure TImageScalerTests.TestThreeToTwoWeighsByCoveredArea;
begin
  const Scaled = Track(TPdfImageScaler.ScaleSmooth(GrayRow([0, 90, 0]), 2, 1));

  AssertPixel(Scaled, 0, 0, 30, 30, 30, 255);
  AssertPixel(Scaled, 1, 0, 30, 30, 30, 255);
end;

procedure TImageScalerTests.TestRowsAreAveragedToo;
begin
  const Source = Track(TPdfBitmap.Create(1, 3));
  Source.SetPixel(0, 0, TPdfDeviceColor.Create(0, 0, 0));
  Source.SetPixel(0, 1, TPdfDeviceColor.Create(150, 150, 150));
  Source.SetPixel(0, 2, TPdfDeviceColor.Create(60, 60, 60));

  const Scaled = Track(TPdfImageScaler.ScaleSmooth(Source, 1, 2));

  // (0 + 150 / 2) / 1.5 and (150 / 2 + 60) / 1.5
  AssertPixel(Scaled, 0, 0, 50, 50, 50, 255);
  AssertPixel(Scaled, 0, 1, 90, 90, 90, 255);
end;

// An opaque red pixel and a transparent one: the alpha is 128, the colour stays red (the transparent pixel has no weight)
procedure TImageScalerTests.TestAlphaWeighsTheColour;
begin
  const Source = Track(TPdfBitmap.Create(2, 1));
  Source.SetPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0, 255));
  Source.SetPixel(1, 0, TPdfDeviceColor.Create(0, 0, 0, 0));

  const Scaled = Track(TPdfImageScaler.ScaleSmooth(Source, 1, 1));

  // straight (255, 0, 0, 128), stored premultiplied
  AssertPixel(Scaled, 0, 0, 128, 0, 0, 128);
end;

procedure TImageScalerTests.TestFlatImageStaysFlat;
begin
  const Source = Track(TPdfBitmap.Create(7, 5));
  for var Y := 0 to 4 do
  begin
    for var X := 0 to 6 do
    begin
      Source.SetPixel(X, Y, TPdfDeviceColor.Create(77, 133, 201));
    end;
  end;

  const Scaled = Track(TPdfImageScaler.ScaleSmooth(Source, 3, 2));

  for var Y := 0 to 1 do
  begin
    for var X := 0 to 2 do
    begin
      AssertPixel(Scaled, X, Y, 77, 133, 201, 255);
    end;
  end;
end;

procedure TImageScalerTests.TestSizeOfTheResult;
begin
  const Scaled = Track(TPdfImageScaler.ScaleSmooth(Track(TPdfBitmap.Create(10, 8)), 4, 3));

  Assert.AreEqual(4, Scaled.Width);
  Assert.AreEqual(3, Scaled.Height);
end;

procedure TImageScalerTests.TestScalingUpRepeatsPixels;
begin
  const Scaled = Track(TPdfImageScaler.ScaleSmooth(GrayRow([10, 200]), 4, 2));

  AssertPixel(Scaled, 0, 0, 10, 10, 10, 255);
  AssertPixel(Scaled, 1, 0, 10, 10, 10, 255);
  AssertPixel(Scaled, 2, 0, 200, 200, 200, 255);
  AssertPixel(Scaled, 3, 1, 200, 200, 200, 255);
end;

procedure TImageScalerTests.TestInvalidSizeRaises;
begin
  const Source = GrayRow([1, 2]);

  Assert.WillRaise(
    procedure
    begin
      TPdfImageScaler.ScaleSmooth(Source, 0, 1).Free;
    end,
    EArgumentOutOfRangeException);
end;

end.
