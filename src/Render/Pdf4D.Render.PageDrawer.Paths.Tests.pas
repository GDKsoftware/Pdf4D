// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the path, clip and solid colour part of PageDrawer (PDFBox 3.0.8), through the recording device
unit Pdf4D.Render.PageDrawer.Paths.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TPageDrawerPathTests = class
  private
    const Tolerance: Single = 0.001;
    const StateResources = '/ExtGState << /GS1 << /ca 0.5 /CA 0.25 >> >>';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure Render(const Content: string; const Resources: string = '');
    function HasLogLine(const Fragment: string): Boolean;
    function CallsOf(const Kind: TRecordedCallKind): TArray<TRecordedCall>;
    procedure AssertNear(const Expected, Actual: Single);
    procedure AssertBounds(const Left, Top, Right, Bottom: Single; const Actual: TRectF);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestBlueRectangle;

    [Test]
    procedure TestStrokeWidthFollowsCtm;

    [Test]
    procedure TestZeroLineWidthBecomesQuarterPoint;

    [Test]
    procedure TestAllZeroDashDrawsNothing;

    [Test]
    procedure TestOddDashArrayIsDoubled;

    [Test]
    procedure TestDashesFollowTheCtm;

    [Test]
    procedure TestClipBeforeFill;

    [Test]
    procedure TestEvenOddFillAndClip;

    [Test]
    procedure TestFillAndStrokeOrder;

    [Test]
    procedure TestCaAlphaGoesIntoComposite;

    [Test]
    procedure TestSingularCtmDrawsNothing;

    [Test]
    procedure TestEmptyClipDrawsNothing;

    [Test]
    procedure TestHugeCoordinatesDoNotRaise;

    [Test]
    procedure TestColorSpaceNameCycleDoesNotHang;

    [Test]
    procedure TestRestoreGoesBackToTheEarlierClip;

    [Test]
    procedure TestSameClipIsSetOnce;

    [Test]
    procedure TestRectangularFillIsNotAntiAliased;

    [Test]
    procedure TestCurvedFillIsAntiAliased;

    [Test]
    procedure TestStrokeColorAndLineStyle;

    [Test]
    procedure TestTinyClipIsWidenedAtSmallScale;

    [Test]
    procedure TestFormBBoxClipsTheForm;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Path,
  Pdf4D.Render.Renderer,
  Pdf4D.Tests.PdfBuilder;

{ TPageDrawerPathTests }

procedure TPageDrawerPathTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.AreEqual(Double(Expected), Double(Actual), Double(Tolerance));
end;

procedure TPageDrawerPathTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerPathTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerPathTests.Render(const Content: string; const Resources: string);
begin
  FDocument := FDocuments.Open(Content, Resources);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

function TPageDrawerPathTests.CallsOf(const Kind: TRecordedCallKind): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in FDevice.Calls do
    begin
      if Call.Kind = Kind then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

procedure TPageDrawerPathTests.AssertBounds(const Left, Top, Right, Bottom: Single; const Actual: TRectF);
begin
  AssertNear(Left, Actual.Left);
  AssertNear(Top, Actual.Top);
  AssertNear(Right, Actual.Right);
  AssertNear(Bottom, Actual.Bottom);
end;

procedure TPageDrawerPathTests.TestBlueRectangle;
begin
  Render('0 0 1 rg 10 10 100 50 re f');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(TPdfPaintKind.Solid, Fills[0].Paint.Kind);
  Assert.AreEqual(Byte(0), Fills[0].Paint.Color.R);
  Assert.AreEqual(Byte(0), Fills[0].Paint.Color.G);
  Assert.AreEqual(Byte(255), Fills[0].Paint.Color.B);
  Assert.AreEqual(Byte(255), Fills[0].Paint.Color.A);
  Assert.AreEqual(TPdfFillRule.NonZero, Fills[0].FillRule);
  AssertBounds(10, 140, 110, 190, Fills[0].DeviceBounds);
end;

procedure TPageDrawerPathTests.TestStrokeWidthFollowsCtm;
begin
  Render('2 0 0 2 0 0 cm 3 w 0 0 m 50 0 l S');

  const Strokes = CallsOf(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  AssertNear(6, Strokes[0].Stroke.Width);
  // Java2D moves the end points of a stroke to the centre of their pixel
  AssertBounds(0.5, 200.5, 100.5, 200.5, Strokes[0].DeviceBounds);
end;

procedure TPageDrawerPathTests.TestZeroLineWidthBecomesQuarterPoint;
begin
  Render('0 w 0 0 m 50 0 l S');

  const Strokes = CallsOf(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  AssertNear(0.25, Strokes[0].Stroke.Width);
end;

procedure TPageDrawerPathTests.TestAllZeroDashDrawsNothing;
begin
  Render('[0 0] 0 d 0 0 m 50 0 l S');

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Stroke)));
end;

procedure TPageDrawerPathTests.TestOddDashArrayIsDoubled;
begin
  Render('[3] 0 d 0 0 m 50 0 l S');

  const Strokes = CallsOf(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  Assert.AreEqual<Integer>(2, Length(Strokes[0].Stroke.Dashes));
  AssertNear(3, Strokes[0].Stroke.Dashes[0]);
  AssertNear(3, Strokes[0].Stroke.Dashes[1]);
end;

procedure TPageDrawerPathTests.TestDashesFollowTheCtm;
begin
  Render('2 0 0 2 0 0 cm [3 1] 1 d 0 0 m 50 0 l S');

  const Strokes = CallsOf(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  Assert.AreEqual<Integer>(2, Length(Strokes[0].Stroke.Dashes));
  AssertNear(6, Strokes[0].Stroke.Dashes[0]);
  AssertNear(2, Strokes[0].Stroke.Dashes[1]);
  AssertNear(2, Strokes[0].Stroke.DashPhase);
end;

procedure TPageDrawerPathTests.TestClipBeforeFill;
begin
  Render('0 0 50 50 re W n 0 0 100 100 re f');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(2, Fills[0].ClipDepth);
  Assert.AreEqual(TRecordedCallKind.SetClip, FDevice.Calls[FDevice.Calls.Count - 2].Kind);
  Assert.AreEqual<Integer>(2, FDevice.Calls[FDevice.Calls.Count - 2].ClipDepth);
  Assert.AreEqual(TRecordedCallKind.Fill, FDevice.Calls[FDevice.Calls.Count - 1].Kind);
end;

procedure TPageDrawerPathTests.TestEvenOddFillAndClip;
begin
  Render('0 0 50 50 re W* n 0 0 100 100 re f*');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(TPdfFillRule.EvenOdd, Fills[0].FillRule);
  Assert.IsNotNull(FDevice.Clip);
  Assert.AreEqual(TPdfFillRule.EvenOdd, FDevice.Clip.FillRule);
end;

procedure TPageDrawerPathTests.TestFillAndStrokeOrder;
begin
  Render('0 0 50 50 re B');

  Assert.AreEqual(TRecordedCallKind.Fill, FDevice.Calls[FDevice.Calls.Count - 2].Kind);
  Assert.AreEqual(TRecordedCallKind.Stroke, FDevice.Calls[FDevice.Calls.Count - 1].Kind);
end;

procedure TPageDrawerPathTests.TestCaAlphaGoesIntoComposite;
begin
  Render('/GS1 gs 0 0 50 50 re f 0 0 m 10 10 l S', StateResources);

  const Fills = CallsOf(TRecordedCallKind.Fill);
  const Strokes = CallsOf(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(1, Length(Strokes));
  AssertNear(0.5, Fills[0].Composite.Alpha);
  AssertNear(0.25, Strokes[0].Composite.Alpha);
  Assert.AreEqual(TPdfBlendMode.Normal, Fills[0].Composite.BlendMode);
end;

procedure TPageDrawerPathTests.TestSingularCtmDrawsNothing;
begin
  Render('0 0 0 0 0 0 cm 0 0 10 10 re f 0 0 m 10 10 l f');

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Fill)));
end;

procedure TPageDrawerPathTests.TestEmptyClipDrawsNothing;
begin
  Render('0 0 0 0 re W n 0 0 100 100 re f');

  // A fill is either not made or made inside a clip of no area
  for var Fill in CallsOf(TRecordedCallKind.Fill) do
  begin
    Assert.AreEqual<Integer>(2, Fill.ClipDepth);
  end;
  Assert.IsNotNull(FDevice.Clip);
  AssertNear(0, FDevice.Clip.Path.Bounds.Width);
  AssertNear(0, FDevice.Clip.Path.Bounds.Height);
end;

procedure TPageDrawerPathTests.TestHugeCoordinatesDoNotRaise;
begin
  // 3e38 is the largest Single that a number gives; after the CTM the points are beyond the range of a Single
  const Scale = '3' + StringOfChar('0', 38) + '.0';

  Render(Format('%s 0 0 %s 0 0 cm 100 100 m 200 0 l S 100 100 m 200 0 l f', [Scale, Scale]));

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Stroke)), 'no stroke');
  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Fill)), 'no fill');
  Assert.IsTrue(HasLogLine('does not give a finite coordinate'), string.Join('|', FDocuments.LogLines.ToArray));
end;

procedure TPageDrawerPathTests.TestColorSpaceNameCycleDoesNotHang;
begin
  const Cycle = '/ColorSpace << /A /B /B /A /S /S >>';

  Render('/A cs 0 0 10 10 re f', Cycle);
  Render('/S cs 0 0 10 10 re f', Cycle);

  Assert.IsTrue(HasLogLine('Colour spaces are nested deeper'), string.Join('|', FDocuments.LogLines.ToArray));
end;

function TPageDrawerPathTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FDocuments.LogLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

procedure TPageDrawerPathTests.TestRestoreGoesBackToTheEarlierClip;
begin
  Render('q 0 0 50 50 re W n Q 0 0 100 100 re f');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(1, Fills[0].ClipDepth);
end;

procedure TPageDrawerPathTests.TestSameClipIsSetOnce;
begin
  Render('0 0 10 10 re f 0 0 20 20 re f 0 0 30 30 re f');

  Assert.AreEqual<Integer>(1, Length(CallsOf(TRecordedCallKind.SetClip)));
  Assert.AreEqual<Integer>(3, Length(CallsOf(TRecordedCallKind.Fill)));
end;

procedure TPageDrawerPathTests.TestRectangularFillIsNotAntiAliased;
begin
  Render('10 10 100 50 re f 10 10 100 0.5 re f');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(2, Length(Fills));
  Assert.IsFalse(Fills[0].Composite.AntiAlias);
  // A path that is no wider than a pixel stands for a line, see PDFBOX-1658
  Assert.IsTrue(Fills[1].Composite.AntiAlias);
end;

procedure TPageDrawerPathTests.TestCurvedFillIsAntiAliased;
begin
  Render('10 10 m 100 10 100 100 10 100 c f');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsTrue(Fills[0].Composite.AntiAlias);
end;

procedure TPageDrawerPathTests.TestStrokeColorAndLineStyle;
begin
  Render('1 0 0 RG 4 w 1 J 2 j 3 M 0 0 m 50 0 l S');

  const Strokes = CallsOf(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  Assert.AreEqual(Byte(255), Strokes[0].Paint.Color.R);
  Assert.AreEqual(Byte(0), Strokes[0].Paint.Color.G);
  Assert.AreEqual(TPdfLineCap.Round, Strokes[0].Stroke.Cap);
  Assert.AreEqual(TPdfLineJoin.Bevel, Strokes[0].Stroke.Join);
  AssertNear(3, Strokes[0].Stroke.MiterLimit);
  AssertNear(4, Strokes[0].Stroke.Width);
  Assert.AreEqual<Integer>(0, Length(Strokes[0].Stroke.Dashes));
end;

// adjustClip of PageDrawer (PDFBOX-5715): below a scale of one a clip that is thinner than two pixels is made two pixels wide
procedure TPageDrawerPathTests.TestTinyClipIsWidenedAtSmallScale;
begin
  FDocument := FDocuments.Open('0 0 10 0.1 re W n 0 0 100 100 re f', '');
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);
  const Device = TRecordingDevice.Create(100, 100);
  const DeviceReference: IPdfRasterDevice = Device;

  FRenderer.RenderPage(0, DeviceReference, TPdfRenderParams.Create(0.5));

  Assert.IsNotNull(Device.Clip);
  // 0.1 pt high at scale 0.5 is 0.05 pixel: the clip becomes 2 / 0.5 = 4 pt high around its centre
  AssertNear(4, Device.Clip.Path.Bounds.Height);
end;

procedure TPageDrawerPathTests.TestFormBBoxClipsTheForm;
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/F1 Do'), '/XObject << /F1 5 0 R >>');
  try
    Builder.AddStreamObject(5, '/Type /XObject /Subtype /Form /BBox [0 0 50 50]', TEncoding.ASCII.GetBytes('0 0 100 100 re f'));
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(2, Fills[0].ClipDepth);
  const ClipPath = FDevice.Clip.Path.Clone;
  try
    ClipPath.Transform(FDevice.Clip.Transform);
    AssertBounds(0, 150, 50, 200, ClipPath.Bounds);
  finally
    ClipPath.Free;
  end;
end;

end.
