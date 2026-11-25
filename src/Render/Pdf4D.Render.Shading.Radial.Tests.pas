// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the radial shading (type 3), PDFBox 3.0.8: RadialShadingContext
unit Pdf4D.Render.Shading.Radial.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Shading.Context,
  Pdf4D.Tests.ShadingBuilder;

type
  [TestFixture]
  TRadialShadingTests = class
  private
    const RedToBlue = '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>';
    // The shading of the cell S3x of generated/render/shadings.pdf: the stitching function and the extension at both ends
    const YellowGreenBlue = '/Function << /FunctionType 3 /Domain [0 1] /Functions [<< /FunctionType 2 /Domain [0 1] /C0 [1 1 0] /C1 [0 0.6 0] /N 1 >> ' +
      '<< /FunctionType 2 /Domain [0 1] /C0 [0 0.6 0] /C1 [0 0 0.6] /N 1 >>] /Bounds [0.4] /Encode [0 1 0 1] >>';

  private
    FDocument: TShadingTestDocument;
    FShading: TPDShading;
    FBitmap: TPdfBitmap;

    procedure Make(const ShadingEntries: string);
    procedure Rasterize(const Area: TRect; const ShadingToDevice: TPdfMatrix);
    // The cell of the reference: page x 140..240, y 145..245 of a page 400 points high, device pixels x 140..240, y 155..255
    procedure RasterizeReferenceCell;
    procedure AssertReferencePixel(const X, Y, Red, Green, Blue: Integer);

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRadialConcentric;

    [Test]
    procedure TestRadialOutsideTheLastCircleIsTransparent;

    [Test]
    procedure TestRadialBackgroundFillsOutside;

    // The values are the pixels that PDFBox renders in the reference of shadings.pdf (page 1, the cell with the circles (35, 50, 10) and
    // (65, 50, 25) and /Extend [true true]): the circles with a negative radius are painted too
    [Test]
    procedure TestRadialFocusOutsideCircle;

    [Test]
    procedure TestRadialFocusOutsideCircleLeavesTheOtherSideTransparent;

    [Test]
    procedure TestRadialWithoutQuadraticTermIsLinear;

    [Test]
    procedure TestRadialStartExtensionNeedsAStartRadius;

    [Test]
    procedure TestRadialEndExtensionNeedsAnEndRadius;
  end;

implementation

{ TRadialShadingTests }

procedure TRadialShadingTests.TearDown;
begin
  FreeAndNil(FBitmap);
  FreeAndNil(FShading);
  FreeAndNil(FDocument);
end;

procedure TRadialShadingTests.Make(const ShadingEntries: string);
begin
  FDocument := TShadingTestDocument.Create(ShadingEntries);
  FShading := FDocument.NewShading;
end;

procedure TRadialShadingTests.Rasterize(const Area: TRect; const ShadingToDevice: TPdfMatrix);
begin
  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, ShadingToDevice, Area, nil);
end;

procedure TRadialShadingTests.RasterizeReferenceCell;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [35 50 10 65 50 25] /Extend [true true] ' + YellowGreenBlue);

  const ShadingToDevice = TPdfMatrix.Create(1, 0, 0, -1, 140, 255);
  Rasterize(TRect.Create(140, 155, 240, 255), ShadingToDevice);
end;

procedure TRadialShadingTests.AssertReferencePixel(const X, Y, Red, Green, Blue: Integer);
begin
  const Pixel = TShadingPixels.At(FBitmap, X - 140, Y - 155);

  Assert.IsTrue(TShadingPixels.AreNear(Pixel, Red, Green, Blue, 255, 3), Format('(%d, %d): %s', [X, Y, TShadingPixels.Describe(Pixel)]));
end;

procedure TRadialShadingTests.TestRadialConcentric;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 0 50 50 50] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  const Center = TShadingPixels.At(FBitmap, 50, 50);
  const Edge = TShadingPixels.At(FBitmap, 50, 1);
  Assert.IsTrue(TShadingPixels.AreNear(Center, 255, 0, 0, 255, 0), TShadingPixels.Describe(Center));
  Assert.IsTrue(TShadingPixels.AreNear(Edge, 7, 0, 247, 255, 8), TShadingPixels.Describe(Edge));
end;

procedure TRadialShadingTests.TestRadialOutsideTheLastCircleIsTransparent;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 0 50 50 30] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 5, 5).A);
  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, 60, 50).A);
end;

procedure TRadialShadingTests.TestRadialBackgroundFillsOutside;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 10 50 50 30] /Background [1 1 0] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  const Corner = TShadingPixels.At(FBitmap, 5, 5);
  const Inside = TShadingPixels.At(FBitmap, 70, 50);
  Assert.IsTrue(TShadingPixels.AreNear(Corner, 255, 255, 0, 255, 0), TShadingPixels.Describe(Corner));
  Assert.AreEqual<Integer>(255, Inside.A);
  Assert.IsFalse(TShadingPixels.AreNear(Inside, 255, 255, 0, 255, 0), 'the pixel is inside the circles, not the background');
end;

procedure TRadialShadingTests.TestRadialFocusOutsideCircle;
begin
  RasterizeReferenceCell;

  AssertReferencePixel(150, 205, 255, 255, 0);
  AssertReferencePixel(165, 200, 255, 255, 0);
  AssertReferencePixel(170, 205, 43, 170, 0);
  AssertReferencePixel(182, 205, 0, 0, 153);
  AssertReferencePixel(186, 205, 241, 249, 0);
  AssertReferencePixel(210, 215, 0, 98, 54);
  AssertReferencePixel(230, 190, 0, 0, 153);
end;

procedure TRadialShadingTests.TestRadialFocusOutsideCircleLeavesTheOtherSideTransparent;
begin
  RasterizeReferenceCell;

  for var Point in [TPoint.Create(160, 190), TPoint.Create(178, 190), TPoint.Create(166, 215), TPoint.Create(200, 170), TPoint.Create(200, 240)] do
  begin
    const Pixel = TShadingPixels.At(FBitmap, Point.X - 140, Point.Y - 155);
    Assert.AreEqual<Integer>(0, Pixel.A, Format('(%d, %d): %s', [Point.X, Point.Y, TShadingPixels.Describe(Pixel)]));
  end;
end;

// The radii differ by exactly the distance of the centers, so there is no quadratic term (PDFBox divides by zero there). The point at the
// center of the first circle has s = -0.25, which the extension turns into the start; the point at x = 90 has s = 1.5, the end.
procedure TRadialShadingTests.TestRadialWithoutQuadraticTermIsLinear;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [20 50 10 40 50 30] /Extend [true true] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  const OnFirstCircle = TShadingPixels.At(FBitmap, 20, 50);
  const Beyond = TShadingPixels.At(FBitmap, 90, 50);
  Assert.AreEqual<Integer>(255, OnFirstCircle.A);
  Assert.IsTrue(TShadingPixels.AreNear(Beyond, 0, 0, 255, 255, 2), TShadingPixels.Describe(Beyond));
end;

// RadialShadingContext: the start is extended only for extend[0] and coords[2] > 0. From a point (r0 = 0) the pixels beyond the end circle
// are not painted with the start colour, where the smaller root (below 0) would be extended.
procedure TRadialShadingTests.TestRadialStartExtensionNeedsAStartRadius;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 0 50 50 30] /Extend [true false] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 5, 5).A);
  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, 60, 50).A);
end;

// With both ends extended the larger root decides, and an end that has no radius does not extend: the pixels outside the circle that
// shrinks to a point stay empty
procedure TRadialShadingTests.TestRadialEndExtensionNeedsAnEndRadius;
begin
  Make('/ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 30 50 50 0] /Extend [true true] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 5, 5).A);
  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, 60, 50).A);
end;

end.
