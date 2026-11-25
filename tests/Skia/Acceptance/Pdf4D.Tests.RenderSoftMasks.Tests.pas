// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Pixel tests of the soft masks on the Skia backend: the mask follows from the group of the soft mask (ISO 32000-1 11.6.5.2), as
// PDFBox 3.0.8 draws it
unit Pdf4D.Tests.RenderSoftMasks.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.GraphicsDocuments;

type
  [TestFixture]
  TRenderSoftMaskTests = class
  private
    const Resources = '/ExtGState << /GsMask 6 0 R /GsHalf << /ca 0.5 >> /GsNone << /SMask /None >> >>';
    const GroupEntries = '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >> /Resources << /ExtGState << /GsHalf << /ca 0.5 >> >> >>';
    const BlueEverywhere = '/GsMask gs 0 0 1 rg 0 0 200 200 re f';
    const Inverse = '/TR << /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;

    // The soft mask is the state of object 6 with MaskEntries, and its group object 5 draws GroupContent
    function Render(const PageContent, MaskEntries, GroupContent: string): TPdfBitmap;
    procedure AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const Expected: TPdfDeviceColor);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestWhiteGroupShowsTheFillInsideItsBox;

    [Test]
    procedure TestOutsideTheBoxTheLuminosityMaskHidesTheFill;

    [Test]
    procedure TestGrayGroupGivesHalfOfTheFill;

    [Test]
    procedure TestAlphaMaskFollowsTheAlphaOfTheGroup;

    [Test]
    procedure TestTransferFunctionInvertsTheMask;

    [Test]
    procedure TestBackdropColorShowsTheFillOutsideTheBox;

    [Test]
    procedure TestSoftMaskNoneShowsTheWholeFill;
  end;

implementation

uses
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.ReferenceBackends;

const
  PageSize = 200;
  Tolerance = 2;

{ TRenderSoftMaskTests }

procedure TRenderSoftMaskTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
end;

procedure TRenderSoftMaskTests.TearDown;
begin
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

function TRenderSoftMaskTests.Render(const PageContent, MaskEntries, GroupContent: string): TPdfBitmap;
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), Resources);
  try
    Builder.AddObject(6, Format('<< /Type /ExtGState /SMask << /Type /Mask %s /G 5 0 R >> >>', [MaskEntries]));
    Builder.AddStreamObject(5, GroupEntries, TEncoding.ASCII.GetBytes(GroupContent));
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;

  const Renderer: IPdfRenderer = TPdfRenderer.Create(FDocument, TReferenceBackends.Create);
  Assert.AreEqual(TPdfRenderStatus.Completed, Renderer.RenderToBitmap(0, TPdfRenderParams.Create(1), Result));
end;

// The page row of a point is PageSize - Y
procedure TRenderSoftMaskTests.AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const Expected: TPdfDeviceColor);
begin
  const Actual = Bitmap.GetPixel(X, PageSize - Y);
  Assert.AreEqual(Double(Expected.R), Double(Actual.R), Tolerance, Format('R at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.G), Double(Actual.G), Tolerance, Format('G at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.B), Double(Actual.B), Tolerance, Format('B at (%d, %d)', [X, Y]));
end;

procedure TRenderSoftMaskTests.TestWhiteGroupShowsTheFillInsideItsBox;
begin
  const Bitmap = Render(BlueEverywhere, '/S /Luminosity', '1 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.Create(0, 0, 255));
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderSoftMaskTests.TestOutsideTheBoxTheLuminosityMaskHidesTheFill;
begin
  const Bitmap = Render(BlueEverywhere, '/S /Luminosity', '1 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 150, 150, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderSoftMaskTests.TestGrayGroupGivesHalfOfTheFill;
begin
  const Bitmap = Render(BlueEverywhere, '/S /Luminosity', '0.5 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.Create(127, 127, 255));
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderSoftMaskTests.TestAlphaMaskFollowsTheAlphaOfTheGroup;
begin
  const Bitmap = Render(BlueEverywhere, '/S /Alpha', '/GsHalf gs 0 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.Create(127, 127, 255));
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderSoftMaskTests.TestTransferFunctionInvertsTheMask;
begin
  const Bitmap = Render(BlueEverywhere, '/S /Luminosity ' + Inverse, '1 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.White);
    // Outside the box the mask is black, and the function does not map that value (SoftPaintContext.getRaster): the fill stays hidden
    AssertPixel(Bitmap, 150, 150, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderSoftMaskTests.TestBackdropColorShowsTheFillOutsideTheBox;
begin
  const Bitmap = Render(BlueEverywhere, '/S /Luminosity /BC [1]', '0 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.White);
    AssertPixel(Bitmap, 150, 150, TPdfDeviceColor.Create(0, 0, 255));
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderSoftMaskTests.TestSoftMaskNoneShowsTheWholeFill;
begin
  const Bitmap = Render('/GsMask gs /GsNone gs 0 0 1 rg 0 0 200 200 re f', '/S /Luminosity', '0 g 0 0 100 100 re f');
  try
    AssertPixel(Bitmap, 150, 150, TPdfDeviceColor.Create(0, 0, 255));
  finally
    Bitmap.Free;
  end;
end;

end.
