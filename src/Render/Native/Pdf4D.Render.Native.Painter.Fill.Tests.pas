// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The fill tests of tiny-skia (tests/integration/fill.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Fill.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTinySkiaFillTests = class
  private
    FFloatState: TTsFloatState;

    function FillPathOn(const Pixmap: TTsPixmap; const Path: TTsPath; const Paint: TTsPaint; const FillRule: TTsFillRule): TTsPixmap;
    function Star: TTsPath;
    function Polygon(const Closed: Boolean): TTsPath;
    procedure AssertFilledPath(const Path: TTsPath; const FillRule: TTsFillRule; const RelativePng: string);
    procedure AssertFilledRect(const Rect: TTsRect; const AntiAlias: Boolean; const RelativePng: string);
    procedure AssertNineCells(const Pixmap: TTsPixmap; const R, G, B, A: Byte);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHorizontalLine;

    [Test]
    procedure TestVerticalLine;

    [Test]
    procedure TestSingleLine;

    [Test]
    procedure TestIntRect;

    [Test]
    procedure TestFloatRect;

    [Test]
    procedure TestIntRectAa;

    [Test]
    procedure TestFloatRectAa;

    [Test]
    procedure TestFloatRectAaHighp;

    [Test]
    procedure TestTinyFloatRect;

    [Test]
    procedure TestTinyFloatRectAa;

    [Test]
    procedure TestTinyRectAa;

    [Test]
    procedure TestFloatRectClipTopLeftAa;

    [Test]
    procedure TestFloatRectClipTopRightAa;

    [Test]
    procedure TestFloatRectClipBottomRightAa;

    [Test]
    procedure TestIntRectWithTsClipRight;

    [Test]
    procedure TestOpenPolygon;

    [Test]
    procedure TestClosedPolygon;

    [Test]
    procedure TestWindingStar;

    [Test]
    procedure TestEvenOddStar;

    [Test]
    procedure TestQuadCurve;

    [Test]
    procedure TestCubicCurve;

    [Test]
    procedure TestMemset2d;

    [Test]
    procedure TestMemset2dOutOfBounds;

    [Test]
    procedure TestFillAa;

    [Test]
    procedure TestOverflowInWalkEdges1;

    [Test]
    procedure TestClipLine1;

    [Test]
    procedure TestClipLine2;

    [Test]
    procedure TestClipQuad;

    [Test]
    procedure TestClipCubic1;

    [Test]
    procedure TestClipCubic2;

    [Test]
    procedure TestAaEndlessLoop;

    [Test]
    procedure TestClearAa;

    [Test]
    procedure TestLineCurve;

    [Test]
    procedure TestVerticalLinesMergingBug;

    [Test]
    procedure TestFillRect;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaFillTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaFillTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTinySkiaFillTests.FillPathOn(const Pixmap: TTsPixmap; const Path: TTsPath; const Paint: TTsPaint;
  const FillRule: TTsFillRule): TTsPixmap;
begin
  Result := Pixmap;
  TTsPainter.FillPath(Result, Path, Paint, FillRule, TTsTransform.Identity, nil);
end;

function TTinySkiaFillTests.Star: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(50.0, 7.5);
  Builder.LineTo(75.0, 87.5);
  Builder.LineTo(10.0, 37.5);
  Builder.LineTo(90.0, 37.5);
  Builder.LineTo(25.0, 87.5);
  Result := TTinySkiaFixtures.FinishPath(Builder);
end;

function TTinySkiaFillTests.Polygon(const Closed: Boolean): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(75.160671, 88.756136);
  Builder.LineTo(24.797274, 88.734053);
  Builder.LineTo(9.255130, 40.828792);
  Builder.LineTo(50.012955, 11.243795);
  Builder.LineTo(90.744819, 40.864522);
  if Closed then
  begin
    Builder.Close;
  end;
  Result := TTinySkiaFixtures.FinishPath(Builder);
end;

procedure TTinySkiaFillTests.AssertFilledPath(const Path: TTsPath; const FillRule: TTsFillRule; const RelativePng: string);
begin
  const Pixmap = FillPathOn(TTinySkiaFixtures.NewPixmap(100, 100), Path, TTinySkiaFixtures.SolidPaint(False), FillRule);
  TTinySkiaImages.AssertMatches(Pixmap, RelativePng);
end;

procedure TTinySkiaFillTests.AssertFilledRect(const Rect: TTsRect; const AntiAlias: Boolean; const RelativePng: string);
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillRect(Pixmap, Rect, TTinySkiaFixtures.SolidPaint(AntiAlias), TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, RelativePng);
end;

procedure TTinySkiaFillTests.AssertNineCells(const Pixmap: TTsPixmap; const R, G, B, A: Byte);
begin
  for var Y := 0 to 2 do
  begin
    for var X := 0 to 2 do
    begin
      if (X = 1) and (Y = 1) then
      begin
        TTinySkiaFixtures.AssertPixel(Pixmap, X, Y, R, G, B, A);
      end
      else
      begin
        TTinySkiaFixtures.AssertPixel(Pixmap, X, Y, 0, 0, 0, 0);
      end;
    end;
  end;
end;

procedure TTinySkiaFillTests.TestHorizontalLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(90.0, 10.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/empty.png');
end;

procedure TTinySkiaFillTests.TestVerticalLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(10.0, 90.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/empty.png');
end;

procedure TTinySkiaFillTests.TestSingleLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(90.0, 90.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/empty.png');
end;

procedure TTinySkiaFillTests.TestIntRect;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(10.0, 15.0, 80.0, 70.0), False, 'fill/int-rect.png');
end;

procedure TTinySkiaFillTests.TestFloatRect;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(10.3, 15.4, 80.5, 70.6), False, 'fill/float-rect.png');
end;

procedure TTinySkiaFillTests.TestIntRectAa;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(10.0, 15.0, 80.0, 70.0), True, 'fill/int-rect-aa.png');
end;

procedure TTinySkiaFillTests.TestFloatRectAa;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(10.3, 15.4, 80.5, 70.6), True, 'fill/float-rect-aa.png');
end;

procedure TTinySkiaFillTests.TestFloatRectAaHighp;
begin
  var Paint := TTinySkiaFixtures.SolidPaint(True);
  Paint.ForceHqPipeline := True;

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(10.3, 15.4, 80.5, 70.6), Paint, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/float-rect-aa-highp.png');
end;

procedure TTinySkiaFillTests.TestTinyFloatRect;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(3, 3);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(1.3, 1.4, 0.5, 0.6), TTinySkiaFixtures.SolidPaint(False), TTsTransform.Identity,
    nil);
  AssertNineCells(Pixmap, 50, 127, 150, 200);
end;

procedure TTinySkiaFillTests.TestTinyFloatRectAa;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(3, 3);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(1.3, 1.4, 0.5, 0.6), TTinySkiaFixtures.SolidPaint(True), TTsTransform.Identity,
    nil);
  AssertNineCells(Pixmap, 51, 128, 153, 60);
end;

procedure TTinySkiaFillTests.TestTinyRectAa;
begin
  var Paint := TTinySkiaFixtures.SolidPaint(True);
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(0, 0, 0, 0));

  // Must not panic; a transparent paint leaves the pixmap empty
  var Pixmap := TTinySkiaFixtures.NewPixmap(10, 10);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(0.7, 0.0, 1.0, 2.0), Paint, TTsTransform.Identity, nil);
  TTinySkiaFixtures.AssertTotals(Pixmap, 0, 0);
end;

procedure TTinySkiaFillTests.TestFloatRectClipTopLeftAa;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(-10.3, -20.4, 100.5, 70.2), True, 'fill/float-rect-clip-top-left-aa.png');
end;

procedure TTinySkiaFillTests.TestFloatRectClipTopRightAa;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(60.3, -20.4, 100.5, 70.2), True, 'fill/float-rect-clip-top-right-aa.png');
end;

procedure TTinySkiaFillTests.TestFloatRectClipBottomRightAa;
begin
  AssertFilledRect(TTinySkiaFixtures.RectXYWH(60.3, 40.4, 100.5, 70.2), True, 'fill/float-rect-clip-bottom-right-aa.png');
end;

procedure TTinySkiaFillTests.TestIntRectWithTsClipRight;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(0.0, 0.0, 100.0, 100.0), TTinySkiaFixtures.SolidPaint(False),
    TTsTransform.FromRow(1.0, 0.0, 0.0, 1.0, 0.5, 0.5), nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/int-rect-with-ts-clip-right.png');
end;

procedure TTinySkiaFillTests.TestOpenPolygon;
begin
  AssertFilledPath(Polygon(False), TTsFillRule.Winding, 'fill/polygon.png');
end;

procedure TTinySkiaFillTests.TestClosedPolygon;
begin
  // Must be the same as open
  AssertFilledPath(Polygon(True), TTsFillRule.Winding, 'fill/polygon.png');
end;

procedure TTinySkiaFillTests.TestWindingStar;
begin
  AssertFilledPath(Star, TTsFillRule.Winding, 'fill/winding-star.png');
end;

procedure TTinySkiaFillTests.TestEvenOddStar;
begin
  AssertFilledPath(Star, TTsFillRule.EvenOdd, 'fill/even-odd-star.png');
end;

procedure TTinySkiaFillTests.TestQuadCurve;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 15.0);
  Builder.QuadTo(95.0, 35.0, 75.0, 90.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.EvenOdd, 'fill/quad.png');
end;

procedure TTinySkiaFillTests.TestCubicCurve;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 15.0);
  Builder.CubicTo(95.0, 35.0, 0.0, 75.0, 75.0, 90.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.EvenOdd, 'fill/cubic.png');
end;

procedure TTinySkiaFillTests.TestMemset2d;
begin
  // Must be opaque to trigger memset2d
  var Paint := TTinySkiaFixtures.SolidPaint(False);
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(50, 127, 150, 255));

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillPath(Pixmap, TTsPathBuilder.FromRect(TTinySkiaFixtures.RectLTRB(10.0, 10.0, 90.0, 90.0)), Paint, TTsFillRule.Winding,
    TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/memset2d.png');
end;

procedure TTinySkiaFillTests.TestMemset2dOutOfBounds;
begin
  // Make sure we do not write past pixmap memory
  var Paint := TTinySkiaFixtures.SolidPaint(False);
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(50, 127, 150, 255));

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillPath(Pixmap, TTsPathBuilder.FromRect(TTinySkiaFixtures.RectLTRB(50.0, 50.0, 120.0, 120.0)), Paint, TTsFillRule.Winding,
    TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/memset2d-2.png');
end;

procedure TTinySkiaFillTests.TestFillAa;
begin
  const Pixmap = FillPathOn(TTinySkiaFixtures.NewPixmap(100, 100), Star, TTinySkiaFixtures.SolidPaint(True), TTsFillRule.EvenOdd);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/star-aa.png');
end;

procedure TTinySkiaFillTests.TestOverflowInWalkEdges1;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.CubicTo(39.0, 163.0, 117.0, 61.0, 130.0, 70.0);

  // Must not panic. The totals come from a run of tiny-skia 0.12.0.
  const Pixmap = FillPathOn(TTinySkiaFixtures.NewPixmap(100, 100), TTinySkiaFixtures.FinishPath(Builder), TTinySkiaFixtures.SolidPaint(False),
    TTsFillRule.Winding);
  TTinySkiaFixtures.AssertTotals(Pixmap, 1813376, 3968);
end;

procedure TTinySkiaFillTests.TestClipLine1;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(50.0, -15.0);
  Builder.LineTo(-15.0, 50.0);
  Builder.LineTo(50.0, 115.0);
  Builder.LineTo(115.0, 50.0);
  Builder.Close;
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/clip-line-1.png');
end;

procedure TTinySkiaFillTests.TestClipLine2;
begin
  // This strange path forces the line clipper to return an empty array. And we're checking that this case is handled correctly.
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0.0, -1.0);
  Builder.LineTo(50.0, 0.0);
  Builder.LineTo(0.0, 50.0);
  Builder.Close;
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/clip-line-2.png');
end;

procedure TTinySkiaFillTests.TestClipQuad;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 85.0);
  Builder.QuadTo(150.0, 150.0, 85.0, 15.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/clip-quad.png');
end;

procedure TTinySkiaFillTests.TestClipCubic1;
begin
  // The line clipper produces 2 points for this path
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 50.0);
  Builder.CubicTo(0.0, 175.0, 195.0, 70.0, 75.0, 20.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/clip-cubic-1.png');
end;

procedure TTinySkiaFillTests.TestClipCubic2;
begin
  // The line clipper produces 3 points for this path
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 50.0);
  Builder.CubicTo(10.0, 40.0, 90.0, 120.0, 125.0, 20.0);
  AssertFilledPath(TTinySkiaFixtures.FinishPath(Builder), TTsFillRule.Winding, 'fill/clip-cubic-2.png');
end;

procedure TTinySkiaFillTests.TestAaEndlessLoop;
begin
  var Paint := TTsPaint.Default;
  Paint.AntiAlias := True;

  // This path was causing an endless loop before
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(2.1537175, 11.560721);
  Builder.QuadTo(1.9999998, 10.787931, 2.0, 10.0);

  // Must not loop. The totals come from a run of tiny-skia 0.12.0: one pixel of the sliver is drawn.
  const Pixmap = FillPathOn(TTinySkiaFixtures.NewPixmap(100, 100), TTinySkiaFixtures.FinishPath(Builder), Paint, TTsFillRule.Winding);
  TTinySkiaFixtures.AssertTotals(Pixmap, 16, 1);
end;

procedure TTinySkiaFillTests.TestClearAa;
begin
  // Make sure that Clear with AA doesn't fallback to memset
  var Paint := TTsPaint.Default;
  Paint.AntiAlias := True;
  Paint.BlendMode := TTsBlendMode.Clear;

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  Pixmap.Fill(TTsColor.FromRgba8(50, 127, 150, 200));

  var Circle: TTsPath;
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(50.0, 50.0, 40.0, Circle));
  TTsPainter.FillPath(Pixmap, Circle, Paint, TTsFillRule.Winding, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/clear-aa.png');
end;

procedure TTinySkiaFillTests.TestLineCurve;
begin
  var Paint := TTsPaint.Default;
  Paint.AntiAlias := True;

  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(100.0, 20.0);
  // Just a line
  Builder.CubicTo(100.0, 40.0, 100.0, 160.0, 100.0, 180.0);

  // Must not panic; a vertical line has no area, so nothing is drawn
  const Pixmap = FillPathOn(TTinySkiaFixtures.NewPixmap(200, 200), TTinySkiaFixtures.FinishPath(Builder), Paint, TTsFillRule.Winding);
  TTinySkiaFixtures.AssertTotals(Pixmap, 0, 0);
end;

procedure TTinySkiaFillTests.TestVerticalLinesMergingBug;
begin
  // This path must not trigger the combining of vertical edges, otherwise the alpha runs would crash later
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(765.56, 158.56);
  Builder.LineTo(754.4, 168.28);
  Builder.CubicTo(754.4, 168.28, 754.4, 168.24, 754.4, 168.17);
  Builder.CubicTo(754.4, 168.09, 754.4, 168.02, 754.4, 167.95);
  Builder.LineTo(754.4, 168.06);
  const Path = TTinySkiaFixtures.FinishPath(Builder);

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillPath(Pixmap, Path, TTinySkiaFixtures.SolidPaint(True), TTsFillRule.Winding,
    TTsTransform.FromRow(5.4, 0.0, 0.0, 5.4, -4050.0, -840.0), nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'fill/vertical-lines-merging-bug.png');
end;

procedure TTinySkiaFillTests.TestFillRect;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(20.3, 10.4, 50.5, 30.2), TTinySkiaFixtures.SolidPaint(True),
    TTsTransform.FromRow(1.2, 0.3, -0.7, 0.8, 12.0, 15.3), nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'canvas/fill-rect.png');
end;

end.
