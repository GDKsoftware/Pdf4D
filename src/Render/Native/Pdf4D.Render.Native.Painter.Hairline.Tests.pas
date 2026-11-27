// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The hairline tests of tiny-skia (tests/integration/hairline.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Hairline.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTinySkiaHairlineTests = class
  private
    FFloatState: TTsFloatState;

    function StrokeOn(const Pixmap: TTsPixmap; const Path: TTsPath; const AntiAlias: Boolean; const Width: Single;
                      const LineCap: TTsLineCap): TTsPixmap;
    function DrawLine(const X0, Y0, X1, Y1: Single; const AntiAlias: Boolean; const Width: Single; const LineCap: TTsLineCap): TTsPixmap;
    function DrawQuad(const AntiAlias: Boolean; const Width: Single; const LineCap: TTsLineCap): TTsPixmap;
    function DrawCubic(const Points: array of Single; const AntiAlias: Boolean; const Width: Single; const LineCap: TTsLineCap): TTsPixmap;
    function SampleCubic(const AntiAlias: Boolean; const Width: Single; const LineCap: TTsLineCap): TTsPixmap;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHline05;

    [Test]
    procedure TestHline05Aa;

    [Test]
    procedure TestHline05AaRound;

    [Test]
    procedure TestVline05;

    [Test]
    procedure TestVline05Aa;

    [Test]
    procedure TestVline05AaRound;

    [Test]
    procedure TestHorish05Aa;

    [Test]
    procedure TestVertish05Aa;

    [Test]
    procedure TestClipLine05Aa;

    [Test]
    procedure TestClipLine00;

    [Test]
    procedure TestClipLine00V2;

    [Test]
    procedure TestClipHlineTopAa;

    [Test]
    procedure TestClipHlineBottomAa;

    [Test]
    procedure TestClipVlineLeftAa;

    [Test]
    procedure TestClipVlineRightAa;

    [Test]
    procedure TestQuadWidth05Aa;

    [Test]
    procedure TestQuadWidth05AaRound;

    [Test]
    procedure TestQuadWidth00;

    [Test]
    procedure TestCubicWidth10Aa;

    [Test]
    procedure TestCubicWidth05Aa;

    [Test]
    procedure TestCubicWidth00Aa;

    [Test]
    procedure TestCubicWidth00;

    [Test]
    procedure TestCubicWidth05AaRound;

    [Test]
    procedure TestCubicWidth00Round;

    [Test]
    procedure TestChopCubic01;

    [Test]
    procedure TestClipCubic05Aa;

    [Test]
    procedure TestClipCubic00;

    [Test]
    procedure TestClippedCircleAa;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaHairlineTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaHairlineTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTinySkiaHairlineTests.StrokeOn(const Pixmap: TTsPixmap; const Path: TTsPath; const AntiAlias: Boolean; const Width: Single;
  const LineCap: TTsLineCap): TTsPixmap;
begin
  Result := Pixmap;

  var Stroke := TTsStroke.New;
  Stroke.Width := Width;
  Stroke.LineCap := LineCap;
  TTsPainter.StrokePath(Result, Path, TTinySkiaFixtures.SolidPaint(AntiAlias), Stroke, TTsTransform.Identity, nil);
end;

function TTinySkiaHairlineTests.DrawLine(const X0, Y0, X1, Y1: Single; const AntiAlias: Boolean; const Width: Single;
  const LineCap: TTsLineCap): TTsPixmap;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(X0, Y0);
  Builder.LineTo(X1, Y1);
  Result := StrokeOn(TTinySkiaFixtures.NewPixmap(100, 100), TTinySkiaFixtures.FinishPath(Builder), AntiAlias, Width, LineCap);
end;

function TTinySkiaHairlineTests.DrawQuad(const AntiAlias: Boolean; const Width: Single; const LineCap: TTsLineCap): TTsPixmap;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(25.0, 80.0);
  Builder.QuadTo(155.0, 75.0, 175.0, 20.0);
  Result := StrokeOn(TTinySkiaFixtures.NewPixmap(200, 100), TTinySkiaFixtures.FinishPath(Builder), AntiAlias, Width, LineCap);
end;

function TTinySkiaHairlineTests.DrawCubic(const Points: array of Single; const AntiAlias: Boolean; const Width: Single;
  const LineCap: TTsLineCap): TTsPixmap;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(Points[0], Points[1]);
  Builder.CubicTo(Points[2], Points[3], Points[4], Points[5], Points[6], Points[7]);
  Result := StrokeOn(TTinySkiaFixtures.NewPixmap(200, 100), TTinySkiaFixtures.FinishPath(Builder), AntiAlias, Width, LineCap);
end;

function TTinySkiaHairlineTests.SampleCubic(const AntiAlias: Boolean; const Width: Single; const LineCap: TTsLineCap): TTsPixmap;
begin
  Result := DrawCubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], AntiAlias, Width, LineCap);
end;

procedure TTinySkiaHairlineTests.TestHline05;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 90.0, 10.0, False, 0.5, TTsLineCap.Butt), 'hairline/hline-05.png');
end;

procedure TTinySkiaHairlineTests.TestHline05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 90.0, 10.0, True, 0.5, TTsLineCap.Butt), 'hairline/hline-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestHline05AaRound;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 90.0, 10.0, True, 0.5, TTsLineCap.Round), 'hairline/hline-05-aa-round.png');
end;

procedure TTinySkiaHairlineTests.TestVline05;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 10.0, 90.0, False, 0.5, TTsLineCap.Butt), 'hairline/vline-05.png');
end;

procedure TTinySkiaHairlineTests.TestVline05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 10.0, 90.0, True, 0.5, TTsLineCap.Butt), 'hairline/vline-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestVline05AaRound;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 10.0, 90.0, True, 0.5, TTsLineCap.Round), 'hairline/vline-05-aa-round.png');
end;

procedure TTinySkiaHairlineTests.TestHorish05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 90.0, 70.0, True, 0.5, TTsLineCap.Butt), 'hairline/horish-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestVertish05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(10.0, 10.0, 70.0, 90.0, True, 0.5, TTsLineCap.Butt), 'hairline/vertish-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestClipLine05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(-10.0, 10.0, 110.0, 70.0, True, 0.5, TTsLineCap.Butt), 'hairline/clip-line-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestClipLine00;
begin
  TTinySkiaImages.AssertMatches(DrawLine(-10.0, 10.0, 110.0, 70.0, False, 0.0, TTsLineCap.Butt), 'hairline/clip-line-00.png');
end;

procedure TTinySkiaHairlineTests.TestClipLine00V2;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(369.26462, 577.8069);
  Builder.LineTo(488.0846, 471.04388);
  const Pixmap = StrokeOn(TTinySkiaFixtures.NewPixmap(512, 512), TTinySkiaFixtures.FinishPath(Builder), False, 0.0, TTsLineCap.Butt);
  TTinySkiaImages.AssertMatches(Pixmap, 'hairline/clip-line-00-v2.png');
end;

procedure TTinySkiaHairlineTests.TestClipHlineTopAa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(-1.0, 0.0, 101.0, 0.0, True, 1.0, TTsLineCap.Butt), 'hairline/clip-hline-top-aa.png');
end;

procedure TTinySkiaHairlineTests.TestClipHlineBottomAa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(-1.0, 100.0, 101.0, 100.0, True, 1.0, TTsLineCap.Butt), 'hairline/clip-hline-bottom-aa.png');
end;

procedure TTinySkiaHairlineTests.TestClipVlineLeftAa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(0.0, -1.0, 0.0, 101.0, True, 1.0, TTsLineCap.Butt), 'hairline/clip-vline-left-aa.png');
end;

procedure TTinySkiaHairlineTests.TestClipVlineRightAa;
begin
  TTinySkiaImages.AssertMatches(DrawLine(100.0, -1.0, 100.0, 101.0, True, 1.0, TTsLineCap.Butt), 'hairline/clip-vline-right-aa.png');
end;

procedure TTinySkiaHairlineTests.TestQuadWidth05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawQuad(True, 0.5, TTsLineCap.Butt), 'hairline/quad-width-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestQuadWidth05AaRound;
begin
  TTinySkiaImages.AssertMatches(DrawQuad(True, 0.5, TTsLineCap.Round), 'hairline/quad-width-05-aa-round.png');
end;

procedure TTinySkiaHairlineTests.TestQuadWidth00;
begin
  TTinySkiaImages.AssertMatches(DrawQuad(False, 0.0, TTsLineCap.Butt), 'hairline/quad-width-00.png');
end;

procedure TTinySkiaHairlineTests.TestCubicWidth10Aa;
begin
  TTinySkiaImages.AssertMatches(SampleCubic(True, 1.0, TTsLineCap.Butt), 'hairline/cubic-width-10-aa.png');
end;

procedure TTinySkiaHairlineTests.TestCubicWidth05Aa;
begin
  TTinySkiaImages.AssertMatches(SampleCubic(True, 0.5, TTsLineCap.Butt), 'hairline/cubic-width-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestCubicWidth00Aa;
begin
  TTinySkiaImages.AssertMatches(SampleCubic(True, 0.0, TTsLineCap.Butt), 'hairline/cubic-width-00-aa.png');
end;

procedure TTinySkiaHairlineTests.TestCubicWidth00;
begin
  TTinySkiaImages.AssertMatches(SampleCubic(False, 0.0, TTsLineCap.Butt), 'hairline/cubic-width-00.png');
end;

procedure TTinySkiaHairlineTests.TestCubicWidth05AaRound;
begin
  TTinySkiaImages.AssertMatches(SampleCubic(True, 0.5, TTsLineCap.Round), 'hairline/cubic-width-05-aa-round.png');
end;

procedure TTinySkiaHairlineTests.TestCubicWidth00Round;
begin
  TTinySkiaImages.AssertMatches(SampleCubic(False, 0.0, TTsLineCap.Round), 'hairline/cubic-width-00-round.png');
end;

procedure TTinySkiaHairlineTests.TestChopCubic01;
begin
  // This curve will invoke the chop at max curvature branch of the cubic hairline
  TTinySkiaImages.AssertMatches(DrawCubic([57.0, 13.0, 17.0, 15.0, 55.0, 97.0, 89.0, 62.0], True, 0.5, TTsLineCap.Butt),
    'hairline/chop-cubic-01.png');
end;

procedure TTinySkiaHairlineTests.TestClipCubic05Aa;
begin
  TTinySkiaImages.AssertMatches(DrawCubic([-25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], True, 0.5, TTsLineCap.Butt),
    'hairline/clip-cubic-05-aa.png');
end;

procedure TTinySkiaHairlineTests.TestClipCubic00;
begin
  TTinySkiaImages.AssertMatches(DrawCubic([-25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], False, 0.0, TTsLineCap.Butt),
    'hairline/clip-cubic-00.png');
end;

procedure TTinySkiaHairlineTests.TestClippedCircleAa;
begin
  var Circle: TTsPath;
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(50.0, 50.0, 55.0, Circle));
  TTinySkiaImages.AssertMatches(StrokeOn(TTinySkiaFixtures.NewPixmap(100, 100), Circle, True, 0.5, TTsLineCap.Butt),
    'hairline/clipped-circle-aa.png');
end;

end.
