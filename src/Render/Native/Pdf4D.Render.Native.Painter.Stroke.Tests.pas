// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The stroke tests of tiny-skia (tests/integration/stroke.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Stroke.Tests;

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
  TTinySkiaStrokeTests = class
  private
    FFloatState: TTsFloatState;

    procedure AssertZeroLengthSubpath(const LineCap: TTsLineCap; const RelativePng: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRoundCapsAndLargeScale;

    [Test]
    procedure TestCircle;

    [Test]
    procedure TestZeroLenSubpathButtCap;

    [Test]
    procedure TestZeroLenSubpathRoundCap;

    [Test]
    procedure TestZeroLenSubpathSquareCap;

    [Test]
    procedure TestRoundCapJoin;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaStrokeTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaStrokeTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTinySkiaStrokeTests.TestRoundCapsAndLargeScale;
begin
  const OneSixteenth: Single = 1 / 16;
  const Sixteen: Single = 16;
  const X0: Single = Single(60) * OneSixteenth;
  const Y: Single = Single(100) * OneSixteenth;
  const X1: Single = Single(140) * OneSixteenth;

  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(X0, Y);
  Builder.LineTo(X1, Y);
  const Path = TTinySkiaFixtures.FinishPath(Builder);

  var Stroke := TTsStroke.New;
  Stroke.Width := 6.0;
  Stroke.LineCap := TTsLineCap.Round;

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.StrokePath(Pixmap, Path, TTinySkiaFixtures.SolidPaint(True), Stroke, TTsTransform.FromScale(Sixteen, Sixteen), nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'stroke/round-caps-and-large-scale.png');
end;

procedure TTinySkiaStrokeTests.TestCircle;
begin
  var Circle: TTsPath;
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(100.0, 100.0, 50.0, Circle));

  var Stroke := TTsStroke.New;
  Stroke.Width := 2.0;

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.StrokePath(Pixmap, Circle, TTinySkiaFixtures.SolidPaint(True), Stroke, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'stroke/circle.png');
end;

procedure TTinySkiaStrokeTests.AssertZeroLengthSubpath(const LineCap: TTsLineCap; const RelativePng: string);
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(50.0, 50.0);
  Builder.LineTo(50.0, 50.0);
  const Path = TTinySkiaFixtures.FinishPath(Builder);

  var Stroke := TTsStroke.New;
  Stroke.Width := 20.0;
  Stroke.LineCap := LineCap;

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.StrokePath(Pixmap, Path, TTinySkiaFixtures.SolidPaint(True), Stroke, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, RelativePng);
end;

procedure TTinySkiaStrokeTests.TestZeroLenSubpathButtCap;
begin
  AssertZeroLengthSubpath(TTsLineCap.Butt, 'stroke/zero-len-subpath-butt-cap.png');
end;

procedure TTinySkiaStrokeTests.TestZeroLenSubpathRoundCap;
begin
  AssertZeroLengthSubpath(TTsLineCap.Round, 'stroke/zero-len-subpath-round-cap.png');
end;

procedure TTinySkiaStrokeTests.TestZeroLenSubpathSquareCap;
begin
  AssertZeroLengthSubpath(TTsLineCap.Square, 'stroke/zero-len-subpath-square-cap.png');
end;

procedure TTinySkiaStrokeTests.TestRoundCapJoin;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(170.0, 30.0);
  Builder.LineTo(30.553378, 99.048418);
  Builder.CubicTo(30.563658, 99.066835, 30.546308, 99.280724, 30.557592, 99.305282);
  const Path = TTinySkiaFixtures.FinishPath(Builder);

  var Stroke := TTsStroke.New;
  Stroke.Width := 30.0;
  Stroke.LineCap := TTsLineCap.Round;
  Stroke.LineJoin := TTsLineJoin.Round;

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.StrokePath(Pixmap, Path, TTinySkiaFixtures.SolidPaint(True), Stroke, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'stroke/round-cap-join.png');
end;

end.
