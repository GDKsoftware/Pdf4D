// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the function-based shading (type 1), PDFBox 3.0.8: Type1ShadingContext
unit Pdf4D.Render.Shading.&Function.Tests;

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
  TFunctionShadingTests = class
  private
    // The function of the shading S1 of generated/render/shadings.pdf: (x, y) gives the colour (x, y, x * y)
    const FunctionEntries = '/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1]';
    const FunctionProgram = '{ 2 copy mul }';

  private
    FDocument: TShadingTestDocument;
    FShading: TPDShading;
    FBitmap: TPdfBitmap;

    procedure Make(const ShadingEntries: string);
    procedure Rasterize(const Area: TRect; const ShadingToDevice: TPdfMatrix);

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFunctionBasedShadingUsesMatrixAndDomain;

    [Test]
    procedure TestFunctionBasedShadingOutsideTheDomainIsTransparent;

    [Test]
    procedure TestFunctionBasedShadingOutsideTheDomainUsesTheBackground;

    [Test]
    procedure TestFunctionBasedShadingWithoutMatrixAndDomainUsesTheUnitSquare;

    [Test]
    procedure TestFunctionBasedShadingFollowsTheMatrixToDevice;

    [Test]
    procedure TestShadingDictionaryKeepsTheEntries;
  end;

implementation

uses
  Pdf4D.Model.Rectangle;

{ TFunctionShadingTests }

procedure TFunctionShadingTests.TearDown;
begin
  FreeAndNil(FBitmap);
  FreeAndNil(FShading);
  FreeAndNil(FDocument);
end;

procedure TFunctionShadingTests.Make(const ShadingEntries: string);
begin
  FDocument := TShadingTestDocument.Create('/ShadingType 1 /ColorSpace /DeviceRGB /Function 5 0 R ' + ShadingEntries, FunctionEntries, FunctionProgram);
  FShading := FDocument.NewShading;
end;

procedure TFunctionShadingTests.Rasterize(const Area: TRect; const ShadingToDevice: TPdfMatrix);
begin
  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, ShadingToDevice, Area, nil);
end;

procedure TFunctionShadingTests.TestFunctionBasedShadingUsesMatrixAndDomain;
begin
  Make('/Domain [0 1 0 1] /Matrix [100 0 0 100 10 20]');

  Rasterize(TRect.Create(0, 0, 150, 150), TPdfMatrix.Identity);

  const Origin = TShadingPixels.At(FBitmap, 10, 20);
  const Middle = TShadingPixels.At(FBitmap, 60, 70);
  const NearCorner = TShadingPixels.At(FBitmap, 109, 119);
  const BeforeOrigin = TShadingPixels.At(FBitmap, 5, 5);
  const BeyondCorner = TShadingPixels.At(FBitmap, 120, 130);
  Assert.IsTrue(TShadingPixels.AreNear(Origin, 0, 0, 0, 255, 0), TShadingPixels.Describe(Origin));
  Assert.IsTrue(TShadingPixels.AreNear(Middle, 127, 127, 63, 255, 1), TShadingPixels.Describe(Middle));
  Assert.IsTrue(TShadingPixels.AreNear(NearCorner, 252, 252, 249, 255, 1), TShadingPixels.Describe(NearCorner));
  Assert.AreEqual<Integer>(0, BeforeOrigin.A);
  Assert.AreEqual<Integer>(0, BeyondCorner.A);
end;

// The domain is a part of what the function takes: the square 0.25..0.75 of its input
procedure TFunctionShadingTests.TestFunctionBasedShadingOutsideTheDomainIsTransparent;
begin
  Make('/Domain [0.25 0.75 0.25 0.75] /Matrix [100 0 0 100 0 0]');

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 10, 50).A);
  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, 50, 50).A);
  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 90, 50).A);
end;

procedure TFunctionShadingTests.TestFunctionBasedShadingOutsideTheDomainUsesTheBackground;
begin
  Make('/Domain [0 1 0 1] /Matrix [50 0 0 50 0 0] /Background [0 0 1]');

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.Identity);

  const Outside = TShadingPixels.At(FBitmap, 80, 80);
  Assert.IsTrue(TShadingPixels.AreNear(Outside, 0, 0, 255, 255, 0), TShadingPixels.Describe(Outside));
end;

procedure TFunctionShadingTests.TestFunctionBasedShadingWithoutMatrixAndDomainUsesTheUnitSquare;
begin
  Make('');

  Rasterize(TRect.Create(0, 0, 6, 6), TPdfMatrix.GetScaleInstance(3, 3));

  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, 2, 2).A, 'the pixel at (2, 2) is at (0.67, 0.67)');
  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 4, 4).A, 'the pixel at (4, 4) is at (1.33, 1.33)');
end;

procedure TFunctionShadingTests.TestFunctionBasedShadingFollowsTheMatrixToDevice;
begin
  Make('/Domain [0 1 0 1] /Matrix [100 0 0 100 0 0]');

  Rasterize(TRect.Create(0, 0, 100, 100), TPdfMatrix.GetTranslateInstance(50, 50));

  const Origin = TShadingPixels.At(FBitmap, 50, 50);
  Assert.IsTrue(TShadingPixels.AreNear(Origin, 0, 0, 0, 255, 0), TShadingPixels.Describe(Origin));
  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 49, 49).A);
end;

procedure TFunctionShadingTests.TestShadingDictionaryKeepsTheEntries;
begin
  Make('/Domain [0 2 0 2] /BBox [1 2 30 40] /AntiAlias true');

  Assert.AreEqual<Integer>(1, FShading.ShadingType);
  Assert.AreEqual('DeviceRGB', FShading.ColorSpace.Name);
  Assert.IsTrue(FShading.AntiAlias);
  var BBox: TPdfRectangle;
  Assert.IsTrue(FShading.TryGetBBox(BBox));
  Assert.AreEqual<Single>(30, BBox.UpperRightX);
  var Background: TArray<Single>;
  Assert.IsFalse(FShading.TryGetBackground(Background));
  Assert.AreEqual<Single>(2, TPDShadingType1(FShading).Domain[1]);
end;

end.
