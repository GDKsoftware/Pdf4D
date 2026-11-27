// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The dash tests of tiny-skia (tests/integration/dash.rs and skia_dash.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Dash.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Dash,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTinySkiaDashTests = class
  private
    FFloatState: TTsFloatState;

    function DashedStroke(const First, Second, Offset, Width: Single): TTsStroke;
    procedure AssertDashed(var Builder: TTsPathBuilder; const AntiAlias: Boolean; const Stroke: TTsStroke; const Size: Cardinal;
                           const RelativePng: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLine;

    [Test]
    procedure TestQuad;

    [Test]
    procedure TestCubic;

    [Test]
    procedure TestHairline;

    [Test]
    procedure TestComplex;

    [Test]
    procedure TestMultiSubpaths;

    [Test]
    procedure TestClosed;

    [Test]
    procedure TestCrbug140642;

    [Test]
    procedure TestCrbug124652;

    [Test]
    procedure TestInfiniteDash;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaDashTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaDashTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTinySkiaDashTests.DashedStroke(const First, Second, Offset, Width: Single): TTsStroke;
begin
  Result := TTsStroke.New;
  Assert.IsTrue(TTsStrokeDash.TryCreate([First, Second], Offset, Result.Dash));
  Result.HasDash := True;
  Result.Width := Width;
end;

procedure TTinySkiaDashTests.AssertDashed(var Builder: TTsPathBuilder; const AntiAlias: Boolean; const Stroke: TTsStroke;
  const Size: Cardinal; const RelativePng: string);
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(Size, Size);
  TTsPainter.StrokePath(Pixmap, TTinySkiaFixtures.FinishPath(Builder), TTinySkiaFixtures.SolidPaint(AntiAlias), Stroke,
    TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, RelativePng);
end;

procedure TTinySkiaDashTests.TestLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.LineTo(90.0, 80.0);
  AssertDashed(Builder, False, DashedStroke(5.0, 10.0, 0.0, 2.0), 100, 'dash/line.png');
end;

procedure TTinySkiaDashTests.TestQuad;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.QuadTo(35.0, 75.0, 90.0, 80.0);
  AssertDashed(Builder, False, DashedStroke(5.0, 10.0, 0.0, 2.0), 100, 'dash/quad.png');
end;

procedure TTinySkiaDashTests.TestCubic;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.CubicTo(95.0, 35.0, 0.0, 75.0, 75.0, 90.0);
  AssertDashed(Builder, False, DashedStroke(5.0, 10.0, 0.0, 2.0), 100, 'dash/cubic.png');
end;

procedure TTinySkiaDashTests.TestHairline;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.CubicTo(95.0, 35.0, 0.0, 75.0, 75.0, 90.0);
  AssertDashed(Builder, True, DashedStroke(5.0, 10.0, 0.0, 0.5), 100, 'dash/hairline.png');
end;

procedure TTinySkiaDashTests.TestComplex;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(28.7, 23.9);
  Builder.LineTo(177.4, 35.2);
  Builder.LineTo(177.4, 68.0);
  Builder.LineTo(129.7, 68.0);
  Builder.CubicTo(81.6, 59.3, 41.8, 63.3, 33.4, 115.2);
  Builder.CubicTo(56.8, 128.7, 77.3, 143.8, 53.3, 183.8);
  Builder.CubicTo(113.8, 185.7, 91.0, 109.7, 167.3, 111.8);
  Builder.CubicTo(-56.2, 90.3, 177.3, 68.0, 110.2, 95.5);
  AssertDashed(Builder, True, DashedStroke(10.0, 5.0, 2.0, 2.0), 200, 'dash/complex.png');
end;

procedure TTinySkiaDashTests.TestMultiSubpaths;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(49.0, 76.0);
  Builder.CubicTo(22.0, 150.0, 11.0, 213.0, 186.0, 151.0);
  Builder.CubicTo(194.0, 106.0, 195.0, 64.0, 169.0, 26.0);
  Builder.MoveTo(124.0, 41.0);
  Builder.LineTo(162.0, 105.0);
  Builder.CubicTo(135.0, 175.0, 97.0, 166.0, 53.0, 128.0);
  Builder.LineTo(93.0, 71.0);
  Builder.MoveTo(24.0, 52.0);
  Builder.LineTo(108.0, 20.0);
  AssertDashed(Builder, True, DashedStroke(10.0, 5.0, 2.0, 2.0), 200, 'dash/multi_subpaths.png');
end;

procedure TTinySkiaDashTests.TestClosed;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(22.0, 22.0);
  Builder.CubicTo(63.0, 16.0, 82.0, 24.0, 84.0, 46.0);
  Builder.CubicTo(86.0, 73.0, 15.0, 58.0, 16.0, 89.0);
  Builder.Close;
  AssertDashed(Builder, True, DashedStroke(10.0, 5.0, 2.0, 2.0), 100, 'dash/closed.png');
end;

procedure TTinySkiaDashTests.TestCrbug140642;
begin
  // We used to see this construct, and due to rounding as we accumulated our length, the loop where we apply the phase would run off the
  // end of the array
  var Dash: TTsStrokeDash;
  Assert.IsTrue(TTsStrokeDash.TryCreate([27734.0, 35660.0, 2157846850.0, 247.0], -248.135982067, Dash));
end;

procedure TTinySkiaDashTests.TestCrbug124652;
begin
  // This particular test only applies to the float case, where large values can "swamp" small ones
  var Dash: TTsStrokeDash;
  Assert.IsTrue(TTsStrokeDash.TryCreate([837099584.0, 33450.0], -10.0, Dash));
end;

procedure TTinySkiaDashTests.TestInfiniteDash;
begin
  // Extremely large path_length/dash_length ratios may cause infinite looping due to single precision rounding
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0.0, 5.0);
  Builder.LineTo(5000000.0, 5.0);
  const Path = TTinySkiaFixtures.FinishPath(Builder);

  var Stroke := TTsStroke.New;
  Assert.IsTrue(TTsStrokeDash.TryCreate([0.2, 0.2], 0.0, Stroke.Dash));
  Stroke.HasDash := True;

  // Doesn't draw anything
  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.StrokePath(Pixmap, Path, TTinySkiaFixtures.SolidPaint(True), Stroke, TTsTransform.Identity, nil);
  TTinySkiaFixtures.AssertTotals(Pixmap, 0, 0);
end;

end.
