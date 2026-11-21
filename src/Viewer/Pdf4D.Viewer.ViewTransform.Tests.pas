// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ViewTransform.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Quad,
  Pdf4D.Model.Rectangle,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.ViewTransform;

type
  [TestFixture]
  TPdfViewTransformTests = class
  private
    class function PageInfo(const CropBox: TPdfRectangle; const Rotation: Integer): TPdfPageInfo; static;
    class function Box(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TPdfRectangle; static;
    procedure AssertPointNear(const Expected, Actual: TPointF; const Context: string);
    procedure AssertCreateRaises(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single; const Context: string);
    procedure AssertCorpusPageMatchesRenderer(const FileName: string; const ViewRotation: Integer);

  public
    [Test]
    procedure TestActualSizeAt72Dpi;
    [Test]
    procedure TestScaleCombinesZoomAndDpi;
    [Test]
    procedure TestSizeEqualsPageTransform;
    [Test]
    procedure TestPageRotationPlusViewRotation;
    [Test]
    procedure TestCropBoxOffset;
    [Test]
    [TestCase('Rotation0', '0')]
    [TestCase('Rotation90', '90')]
    [TestCase('Rotation180', '180')]
    [TestCase('Rotation270', '270')]
    procedure TestViewToPageInverts(const ViewRotation: Integer);
    [Test]
    procedure TestQuadToViewKeepsOrder;
    [Test]
    procedure TestInvalidArgumentsRaise;
    [Test]
    procedure TestTransformEqualsRendererForCorpus;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.PageTransform,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.RecordingDevice;

const
  PointTolerance = 0.01;
  RelativeTolerance = 0.00001;
  CorpusScale = 96 / 72;

{ TPdfViewTransformTests }

class function TPdfViewTransformTests.Box(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TPdfRectangle;
begin
  Result.LowerLeftX := LowerLeftX;
  Result.LowerLeftY := LowerLeftY;
  Result.UpperRightX := UpperRightX;
  Result.UpperRightY := UpperRightY;
end;

class function TPdfViewTransformTests.PageInfo(const CropBox: TPdfRectangle; const Rotation: Integer): TPdfPageInfo;
begin
  Result.CropBox := CropBox;
  Result.Rotation := Rotation;
  Result.Label_ := '';
end;

procedure TPdfViewTransformTests.AssertPointNear(const Expected, Actual: TPointF; const Context: string);
begin
  const ToleranceX = PointTolerance + RelativeTolerance * Abs(Expected.X);
  const ToleranceY = PointTolerance + RelativeTolerance * Abs(Expected.Y);
  Assert.AreEqual(Double(Expected.X), Double(Actual.X), ToleranceX, Context + ' x');
  Assert.AreEqual(Double(Expected.Y), Double(Actual.Y), ToleranceY, Context + ' y');
end;

procedure TPdfViewTransformTests.TestActualSizeAt72Dpi;
begin
  const Transform = TPdfViewTransform.Create(PageInfo(TPdfRectangle.Letter, 0), 0, 1, 72);

  Assert.AreEqual(Double(1), Double(Transform.Scale), 0.0001);
  Assert.AreEqual<Integer>(612, Transform.Size.cx);
  Assert.AreEqual<Integer>(792, Transform.Size.cy);
  AssertPointNear(TPointF.Create(0, 792), Transform.PageToView(TPointF.Create(0, 0)), 'lower left');
  AssertPointNear(TPointF.Create(612, 0), Transform.PageToView(TPointF.Create(612, 792)), 'upper right');
end;

procedure TPdfViewTransformTests.TestScaleCombinesZoomAndDpi;
begin
  const Transform = TPdfViewTransform.Create(PageInfo(TPdfRectangle.Letter, 0), 0, 1.5, 144);

  Assert.AreEqual(Double(3), Double(Transform.Scale), 0.0001);
end;

procedure TPdfViewTransformTests.TestSizeEqualsPageTransform;
begin
  const Transform = TPdfViewTransform.Create(PageInfo(TPdfRectangle.Letter, 0), 0, 1, 96);

  const Expected = TPdfPageTransform.Create(TPdfRectangle.Letter, 0, 96 / 72).Size;

  Assert.AreEqual<Integer>(Expected.cx, Transform.Size.cx);
  Assert.AreEqual<Integer>(Expected.cy, Transform.Size.cy);
end;

procedure TPdfViewTransformTests.TestPageRotationPlusViewRotation;
begin
  const CropBox = Box(0, 0, 200, 100);
  const Transform = TPdfViewTransform.Create(PageInfo(CropBox, 90), 90, 1, 72);
  const Reference = TPdfPageTransform.Create(CropBox, 180, 1);

  for var Point in [TPointF.Create(0, 0), TPointF.Create(200, 100), TPointF.Create(30, 70)] do
  begin
    const Expected = Reference.PageToDevice.TransformPoint(Point.X, Point.Y);
    AssertPointNear(Expected, Transform.PageToView(Point), Format('%g,%g', [Double(Point.X), Double(Point.Y)]));
  end;
end;

procedure TPdfViewTransformTests.TestCropBoxOffset;
begin
  const Transform = TPdfViewTransform.Create(PageInfo(Box(50, 50, 562, 742), 0), 0, 1, 72);

  AssertPointNear(TPointF.Create(0, 0), Transform.PageToView(TPointF.Create(50, 742)), 'upper left of the crop box');
end;

procedure TPdfViewTransformTests.TestViewToPageInverts(const ViewRotation: Integer);
begin
  const Transform = TPdfViewTransform.Create(PageInfo(Box(10, 20, 410, 320), 90), ViewRotation, 1.25, 110);

  for var Original in [TPointF.Create(10, 20), TPointF.Create(410, 320), TPointF.Create(123.5, 77.25)] do
  begin
    const Restored = Transform.ViewToPage(Transform.PageToView(Original));
    AssertPointNear(Original, Restored, Format('rotation %d', [ViewRotation]));
  end;
end;

procedure TPdfViewTransformTests.TestQuadToViewKeepsOrder;
begin
  const Transform = TPdfViewTransform.Create(PageInfo(TPdfRectangle.Letter, 0), 0, 1, 72);
  const Quad = TPdfQuad.Create(TPointF.Create(10, 20), TPointF.Create(110, 20), TPointF.Create(110, 40), TPointF.Create(10, 40));

  const Corners = Transform.QuadToView(Quad);

  Assert.AreEqual<Integer>(4, Length(Corners));
  AssertPointNear(Transform.PageToView(Quad.P1), Corners[0], 'P1');
  AssertPointNear(Transform.PageToView(Quad.P2), Corners[1], 'P2');
  AssertPointNear(Transform.PageToView(Quad.P3), Corners[2], 'P3');
  AssertPointNear(Transform.PageToView(Quad.P4), Corners[3], 'P4');
  AssertPointNear(TPointF.Create(10, 772), Corners[0], 'P1 value');
  AssertPointNear(TPointF.Create(10, 752), Corners[3], 'P4 value');
end;

procedure TPdfViewTransformTests.TestInvalidArgumentsRaise;
begin
  AssertCreateRaises(45, 1, 72, 'view rotation 45');
  AssertCreateRaises(360, 1, 72, 'view rotation 360');
  AssertCreateRaises(-90, 1, 72, 'view rotation -90');
  AssertCreateRaises(0, 0, 72, 'zoom 0');
  AssertCreateRaises(0, 1, 0, 'pixels per inch 0');
end;

procedure TPdfViewTransformTests.AssertCreateRaises(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single; const Context: string);
begin
  const Page = PageInfo(TPdfRectangle.Letter, 0);

  Assert.WillRaise(
    procedure
    begin
      TPdfViewTransform.Create(Page, ViewRotation, Zoom, PixelsPerInch);
    end,
    EArgumentException,
    Context);
end;

procedure TPdfViewTransformTests.AssertCorpusPageMatchesRenderer(const FileName: string; const ViewRotation: Integer);
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(FileName);
  var Document: IPdfDocument;
  try
    Document := TPdfDocument.Load(TCorpus.PdfPath(FileName), Options);
  except
    on Exception do
    begin
      Exit;
    end;
  end;
  if Document.PageCount = 0 then
  begin
    Exit;
  end;

  const Page = Document.Page(0);
  const Info = PageInfo(Page.CropBox, Page.Rotation);
  const Backend: IPdfRenderBackend = TRecordingBackend.Create;
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, Backend);
  const Expected = Renderer.PageTransform(0, CorpusScale, ViewRotation);

  const Transform = TPdfViewTransform.Create(Info, ViewRotation, 1, 96);

  const Context = Format('%s rotation %d', [FileName, ViewRotation]);
  Assert.AreEqual<Integer>(Expected.Size.cx, Transform.Size.cx, Context + ' width');
  Assert.AreEqual<Integer>(Expected.Size.cy, Transform.Size.cy, Context + ' height');
  for var Point in [TPointF.Create(Info.CropBox.LowerLeftX, Info.CropBox.LowerLeftY),
                    TPointF.Create(Info.CropBox.UpperRightX, Info.CropBox.UpperRightY),
                    TPointF.Create((Info.CropBox.LowerLeftX + Info.CropBox.UpperRightX) / 2, (Info.CropBox.LowerLeftY + Info.CropBox.UpperRightY) / 2)] do
  begin
    const ExpectedPoint = Expected.PageToDevice.TransformPoint(Point.X, Point.Y);
    AssertPointNear(ExpectedPoint, Transform.PageToView(Point), Context);
  end;
end;

procedure TPdfViewTransformTests.TestTransformEqualsRendererForCorpus;
begin
  const Files = TCorpus.Files;
  if Length(Files) = 0 then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  for var FileName in Files do
  begin
    AssertCorpusPageMatchesRenderer(FileName, 0);
    AssertCorpusPageMatchesRenderer(FileName, 90);
  end;
end;

end.
