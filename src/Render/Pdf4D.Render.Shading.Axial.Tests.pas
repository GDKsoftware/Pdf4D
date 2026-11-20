// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the axial shading (type 2) and of TPdfShadingRasterizer (PDFBox 3.0.8: AxialShadingContext, ShadingContext)
unit Pdf4D.Render.Shading.Axial.Tests;

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
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.ShadingBuilder;

type
  // A cancel token that says yes, and counts how often it was asked
  TCancelledToken = class(TInterfacedObject, IPdfCancelToken)
  private
    FAsked: Integer;

  public
    function IsCancelled: Boolean;

    property Asked: Integer read FAsked;
  end;

  [TestFixture]
  TAxialShadingTests = class
  private
    const RedToBlue = '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>';
    const Prefix = '/ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] ';

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
    procedure TestAxialTwoStops;

    [Test]
    procedure TestAxialExtendFalseIsTransparentOutside;

    [Test]
    procedure TestAxialExtendTrueRepeatsEdgeColor;

    [Test]
    procedure TestAxialBackgroundFillsOutside;

    [Test]
    procedure TestAxialFollowsTheMatrixToDevice;

    [Test]
    procedure TestAxialWithEqualEndsPaintsNothingWithoutBackground;

    [Test]
    procedure TestAxialWithEqualEndsPaintsTheBackground;

    [Test]
    procedure TestAxialDomainChoosesTheFunctionInput;

    [Test]
    procedure TestSingularMatrixPaintsNothing;

    [Test]
    procedure TestCancelStopsRasterizing;

    [Test]
    procedure TestRasterizeWithEmptyAreaRaises;

    [Test]
    procedure TestMeshShadingGivesTransparentBitmap;

    [Test]
    procedure TestMissingFunctionRaisesParseException;

    [Test]
    procedure TestMissingCoordsRaisesParseException;

    [Test]
    procedure TestUnknownShadingTypeRaisesParseException;

    [Test]
    procedure TestArrayOfFunctionsGivesOneComponentEach;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TCancelledToken }

function TCancelledToken.IsCancelled: Boolean;
begin
  Inc(FAsked);
  Result := True;
end;

{ TAxialShadingTests }

procedure TAxialShadingTests.TearDown;
begin
  FreeAndNil(FBitmap);
  FreeAndNil(FShading);
  FreeAndNil(FDocument);
end;

procedure TAxialShadingTests.Make(const ShadingEntries: string);
begin
  FDocument := TShadingTestDocument.Create(ShadingEntries);
  FShading := FDocument.NewShading;
end;

procedure TAxialShadingTests.Rasterize(const Area: TRect; const ShadingToDevice: TPdfMatrix);
begin
  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, ShadingToDevice, Area, nil);
end;

procedure TAxialShadingTests.TestAxialTwoStops;
begin
  Make(Prefix + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 1), TPdfMatrix.Identity);

  const First = TShadingPixels.At(FBitmap, 0, 0);
  const Middle = TShadingPixels.At(FBitmap, 50, 0);
  const Last = TShadingPixels.At(FBitmap, 99, 0);
  Assert.IsTrue(TShadingPixels.AreNear(First, 255, 0, 0, 255, 0), TShadingPixels.Describe(First));
  Assert.IsTrue(TShadingPixels.AreNear(Middle, 127, 0, 128, 255, 2), TShadingPixels.Describe(Middle));
  // The last pixel has the step below the end of the table, like PDFBox: 101 steps for a diagonal of 100.005 pixels
  Assert.IsTrue(TShadingPixels.AreNear(Last, 5, 0, 249, 255, 1), TShadingPixels.Describe(Last));
end;

procedure TAxialShadingTests.TestAxialExtendFalseIsTransparentOutside;
begin
  Make(Prefix + RedToBlue);

  Rasterize(TRect.Create(-50, 0, 150, 1), TPdfMatrix.Identity);

  const Before = TShadingPixels.At(FBitmap, 10, 0);
  const Inside = TShadingPixels.At(FBitmap, 100, 0);
  const After = TShadingPixels.At(FBitmap, 180, 0);
  Assert.IsTrue(TShadingPixels.AreNear(Before, 0, 0, 0, 0, 0), TShadingPixels.Describe(Before));
  Assert.AreEqual<Integer>(255, Inside.A);
  Assert.IsTrue(TShadingPixels.AreNear(After, 0, 0, 0, 0, 0), TShadingPixels.Describe(After));
end;

procedure TAxialShadingTests.TestAxialExtendTrueRepeatsEdgeColor;
begin
  Make(Prefix + RedToBlue + ' /Extend [true true]');

  Rasterize(TRect.Create(-50, 0, 150, 1), TPdfMatrix.Identity);

  const Before = TShadingPixels.At(FBitmap, 10, 0);
  const After = TShadingPixels.At(FBitmap, 180, 0);
  Assert.IsTrue(TShadingPixels.AreNear(Before, 255, 0, 0, 255, 0), TShadingPixels.Describe(Before));
  Assert.IsTrue(TShadingPixels.AreNear(After, 0, 0, 255, 255, 0), TShadingPixels.Describe(After));
end;

procedure TAxialShadingTests.TestAxialBackgroundFillsOutside;
begin
  Make(Prefix + RedToBlue + ' /Background [0 1 0]');

  Rasterize(TRect.Create(-50, 0, 150, 1), TPdfMatrix.Identity);

  const Before = TShadingPixels.At(FBitmap, 10, 0);
  Assert.IsTrue(TShadingPixels.AreNear(Before, 0, 255, 0, 255, 0), TShadingPixels.Describe(Before));
end;

procedure TAxialShadingTests.TestAxialFollowsTheMatrixToDevice;
begin
  Make('/ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 50 0] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 1), TPdfMatrix.GetScaleInstance(2, 2));

  const First = TShadingPixels.At(FBitmap, 0, 0);
  const Last = TShadingPixels.At(FBitmap, 99, 0);
  Assert.IsTrue(TShadingPixels.AreNear(First, 255, 0, 0, 255, 0), TShadingPixels.Describe(First));
  Assert.IsTrue(TShadingPixels.AreNear(Last, 5, 0, 249, 255, 1), TShadingPixels.Describe(Last));
end;

procedure TAxialShadingTests.TestAxialWithEqualEndsPaintsNothingWithoutBackground;
begin
  Make('/ShadingType 2 /ColorSpace /DeviceRGB /Coords [10 10 10 10] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 20, 20), TPdfMatrix.Identity);

  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 10, 10).A);
end;

procedure TAxialShadingTests.TestAxialWithEqualEndsPaintsTheBackground;
begin
  Make('/ShadingType 2 /ColorSpace /DeviceRGB /Coords [10 10 10 10] /Background [0 0 1] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 20, 20), TPdfMatrix.Identity);

  const Pixel = TShadingPixels.At(FBitmap, 10, 10);
  Assert.IsTrue(TShadingPixels.AreNear(Pixel, 0, 0, 255, 255, 0), TShadingPixels.Describe(Pixel));
end;

// The Domain [0.5 1] makes the function see 0.5 at the start of the axis and 1 at its end
procedure TAxialShadingTests.TestAxialDomainChoosesTheFunctionInput;
begin
  Make(Prefix + '/Domain [0.5 1] ' + RedToBlue);

  Rasterize(TRect.Create(0, 0, 100, 1), TPdfMatrix.Identity);

  const First = TShadingPixels.At(FBitmap, 0, 0);
  Assert.IsTrue(TShadingPixels.AreNear(First, 127, 0, 127, 255, 1), TShadingPixels.Describe(First));
end;

procedure TAxialShadingTests.TestSingularMatrixPaintsNothing;
begin
  Make(Prefix + RedToBlue);

  Rasterize(TRect.Create(0, 0, 10, 10), TPdfMatrix.GetScaleInstance(0, 1));

  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 5, 5).A);
end;

procedure TAxialShadingTests.TestCancelStopsRasterizing;
begin
  Make(Prefix + RedToBlue + ' /Extend [true true]');
  const Token = TCancelledToken.Create;
  const TokenReference: IPdfCancelToken = Token;

  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, TPdfMatrix.Identity, TRect.Create(0, 0, 100, 50), TokenReference);

  Assert.IsTrue(Token.Asked <= 1, 'the token is asked once, before the first row');
  var PaintedRows := 0;
  for var Row := 0 to FBitmap.Height - 1 do
  begin
    if TShadingPixels.At(FBitmap, 0, Row).A <> 0 then
    begin
      Inc(PaintedRows);
    end;
  end;
  Assert.IsTrue(PaintedRows <= 1, 'at most one row is painted');
end;

procedure TAxialShadingTests.TestRasterizeWithEmptyAreaRaises;
begin
  Make(Prefix + RedToBlue);

  Assert.WillRaise(
    procedure
    begin
      TPdfShadingRasterizer.Rasterize(FShading, TPdfMatrix.Identity, TRect.Create(0, 0, 0, 5), nil).Free;
    end,
    EArgumentOutOfRangeException);
end;

procedure TAxialShadingTests.TestMeshShadingGivesTransparentBitmap;
begin
  Make('/ShadingType 4 /ColorSpace /DeviceRGB');

  Rasterize(TRect.Create(0, 0, 5, 5), TPdfMatrix.Identity);

  Assert.AreEqual<Integer>(4, FShading.ShadingType);
  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, 2, 2).A);
end;

procedure TAxialShadingTests.TestMissingFunctionRaisesParseException;
begin
  FDocument := TShadingTestDocument.Create(Prefix);

  Assert.WillRaise(
    procedure
    begin
      FDocument.NewShading.Free;
    end,
    EPdfParseException);
end;

procedure TAxialShadingTests.TestMissingCoordsRaisesParseException;
begin
  FDocument := TShadingTestDocument.Create('/ShadingType 2 /ColorSpace /DeviceRGB ' + RedToBlue);

  Assert.WillRaise(
    procedure
    begin
      FDocument.NewShading.Free;
    end,
    EPdfParseException);
end;

procedure TAxialShadingTests.TestUnknownShadingTypeRaisesParseException;
begin
  FDocument := TShadingTestDocument.Create('/ShadingType 9 /ColorSpace /DeviceRGB');

  Assert.WillRaise(
    procedure
    begin
      FDocument.NewShading.Free;
    end,
    EPdfParseException);
end;

// One function for each component: the red from the first, the green from the second and the blue from the third
procedure TAxialShadingTests.TestArrayOfFunctionsGivesOneComponentEach;
begin
  Make(Prefix + '/Function [<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >> << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [0] /N 1 >> ' +
       '<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>]');

  Rasterize(TRect.Create(0, 0, 100, 1), TPdfMatrix.Identity);

  const Last = TShadingPixels.At(FBitmap, 99, 0);
  Assert.IsTrue(TShadingPixels.AreNear(Last, 5, 0, 249, 255, 1), TShadingPixels.Describe(Last));
end;

end.
