// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The pattern tests of tiny-skia (tests/integration/pattern.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Pattern.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTinySkiaPatternTests = class
  private
    FFloatState: TTsFloatState;

    function CrateTriangle: TTsPixmap;
    procedure AssertPattern(const SpreadMode: TTsSpreadMode; const Quality: TTsFilterQuality; const Ts: TTsTransform;
                            const RelativePng: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPadNearest;

    [Test]
    procedure TestRepeatNearest;

    [Test]
    procedure TestReflectNearest;

    [Test]
    procedure TestPadBicubic;

    [Test]
    procedure TestRepeatBicubic;

    [Test]
    procedure TestReflectBicubic;

    [Test]
    procedure TestFilterNearestNoTs;

    [Test]
    procedure TestFilterNearest;

    [Test]
    procedure TestFilterBilinear;

    [Test]
    procedure TestFilterBicubic;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaPatternTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaPatternTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTinySkiaPatternTests.CrateTriangle: TTsPixmap;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0.0, 20.0);
  Builder.LineTo(20.0, 20.0);
  Builder.LineTo(10.0, 0.0);
  Builder.Close;

  Result := TTinySkiaFixtures.NewPixmap(20, 20);
  TTsPainter.FillPath(Result, TTinySkiaFixtures.FinishPath(Builder), TTinySkiaFixtures.SolidPaint(True), TTsFillRule.Winding,
    TTsTransform.Identity, nil);
end;

procedure TTinySkiaPatternTests.AssertPattern(const SpreadMode: TTsSpreadMode; const Quality: TTsFilterQuality; const Ts: TTsTransform;
  const RelativePng: string);
begin
  const Triangle = CrateTriangle;

  var Paint := TTsPaint.Default;
  Paint.AntiAlias := False;
  Paint.Shader := TTsShader.NewPattern(Triangle.AsRef, SpreadMode, Quality, 1.0, Ts);

  const Path = TTsPathBuilder.FromRect(TTinySkiaFixtures.RectLTRB(10.0, 10.0, 190.0, 190.0));

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.FillPath(Pixmap, Path, Paint, TTsFillRule.Winding, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, RelativePng);
end;

procedure TTinySkiaPatternTests.TestPadNearest;
begin
  AssertPattern(TTsSpreadMode.Pad, TTsFilterQuality.Nearest, TTsTransform.Identity, 'pattern/pad-nearest.png');
end;

procedure TTinySkiaPatternTests.TestRepeatNearest;
begin
  AssertPattern(TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, TTsTransform.Identity, 'pattern/repeat-nearest.png');
end;

procedure TTinySkiaPatternTests.TestReflectNearest;
begin
  AssertPattern(TTsSpreadMode.Reflect, TTsFilterQuality.Nearest, TTsTransform.Identity, 'pattern/reflect-nearest.png');
end;

procedure TTinySkiaPatternTests.TestPadBicubic;
begin
  // Transform must be set, otherwise we will fallback to Nearest
  AssertPattern(TTsSpreadMode.Pad, TTsFilterQuality.Bicubic, TTsTransform.FromRow(1.1, 0.3, 0.0, 1.4, 0.0, 0.0), 'pattern/pad-bicubic.png');
end;

procedure TTinySkiaPatternTests.TestRepeatBicubic;
begin
  AssertPattern(TTsSpreadMode.&Repeat, TTsFilterQuality.Bicubic, TTsTransform.FromRow(1.1, 0.3, 0.0, 1.4, 0.0, 0.0),
    'pattern/repeat-bicubic.png');
end;

procedure TTinySkiaPatternTests.TestReflectBicubic;
begin
  AssertPattern(TTsSpreadMode.Reflect, TTsFilterQuality.Bicubic, TTsTransform.FromRow(1.1, 0.3, 0.0, 1.4, 0.0, 0.0),
    'pattern/reflect-bicubic.png');
end;

procedure TTinySkiaPatternTests.TestFilterNearestNoTs;
begin
  AssertPattern(TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, TTsTransform.Identity, 'pattern/filter-nearest-no-ts.png');
end;

procedure TTinySkiaPatternTests.TestFilterNearest;
begin
  AssertPattern(TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, TTsTransform.FromRow(1.5, 0.0, -0.4, -0.8, 5.0, 1.0),
    'pattern/filter-nearest.png');
end;

procedure TTinySkiaPatternTests.TestFilterBilinear;
begin
  AssertPattern(TTsSpreadMode.&Repeat, TTsFilterQuality.Bilinear, TTsTransform.FromRow(1.5, 0.0, -0.4, -0.8, 5.0, 1.0),
    'pattern/filter-bilinear.png');
end;

procedure TTinySkiaPatternTests.TestFilterBicubic;
begin
  AssertPattern(TTsSpreadMode.&Repeat, TTsFilterQuality.Bicubic, TTsTransform.FromRow(1.5, 0.0, -0.4, -0.8, 5.0, 1.0),
    'pattern/filter-bicubic.png');
end;

end.
