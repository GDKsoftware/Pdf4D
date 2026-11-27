// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The mask tests of tiny-skia (tests/integration/mask.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Mask.Tests;

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
  Pdf4D.Render.Native.Mask,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTinySkiaMaskTests = class
  private
    FFloatState: TTsFloatState;

    function NewMask(const Width, Height: Cardinal): TTsMask;
    function RectPath(const X, Y, Width, Height: Single): TTsPath;
    function CirclePath(const Cx, Cy, Radius: Single): TTsPath;
    function MaskOfRect(const AntiAlias: Boolean; const X, Y, Width, Height: Single): TTsMask;
    procedure AssertMaskedFill(const Mask: TTsMask; const Paint: TTsPaint; const RelativePng: string);
    function CircleFilledPixmap: TTsPixmap;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRect;

    [Test]
    procedure TestRectAa;

    [Test]
    procedure TestRectTs;

    [Test]
    procedure TestCircleBottomRightAa;

    [Test]
    procedure TestStroke;

    [Test]
    procedure TestSkipDest;

    [Test]
    procedure TestIntersectAa;

    [Test]
    procedure TestIgnoreMemset;

    [Test]
    procedure TestIgnoreSource;

    [Test]
    procedure TestApplyMask;

    [Test]
    procedure TestMaskFromAlpha;

    [Test]
    procedure TestMaskFromLuma;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaMaskTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaMaskTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTinySkiaMaskTests.NewMask(const Width, Height: Cardinal): TTsMask;
begin
  Assert.IsTrue(TTsMask.TryCreate(Width, Height, Result));
end;

function TTinySkiaMaskTests.RectPath(const X, Y, Width, Height: Single): TTsPath;
begin
  Result := TTsPathBuilder.FromRect(TTinySkiaFixtures.RectXYWH(X, Y, Width, Height));
end;

function TTinySkiaMaskTests.CirclePath(const Cx, Cy, Radius: Single): TTsPath;
begin
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(Cx, Cy, Radius, Result));
end;

function TTinySkiaMaskTests.MaskOfRect(const AntiAlias: Boolean; const X, Y, Width, Height: Single): TTsMask;
begin
  Result := NewMask(100, 100);
  Result.FillPath(RectPath(X, Y, Width, Height), TTsFillRule.Winding, AntiAlias, TTsTransform.Identity);
end;

procedure TTinySkiaMaskTests.AssertMaskedFill(const Mask: TTsMask; const Paint: TTsPaint; const RelativePng: string);
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(Mask.Width, Mask.Height);
  var MaskCopy := Mask;
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(0.0, 0.0, Mask.Width, Mask.Height), Paint, TTsTransform.Identity, @MaskCopy);
  TTinySkiaImages.AssertMatches(Pixmap, RelativePng);
end;

function TTinySkiaMaskTests.CircleFilledPixmap: TTsPixmap;
begin
  Result := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillPath(Result, CirclePath(100.0, 100.0, 50.0), TTinySkiaFixtures.SolidPaint(True), TTsFillRule.Winding,
    TTsTransform.Identity, nil);
end;

procedure TTinySkiaMaskTests.TestRect;
begin
  AssertMaskedFill(MaskOfRect(False, 10.0, 10.0, 80.0, 80.0), TTinySkiaFixtures.SolidPaint(False), 'mask/rect.png');
end;

procedure TTinySkiaMaskTests.TestRectAa;
begin
  AssertMaskedFill(MaskOfRect(True, 10.5, 10.0, 80.0, 80.5), TTinySkiaFixtures.SolidPaint(False), 'mask/rect-aa.png');
end;

procedure TTinySkiaMaskTests.TestRectTs;
begin
  var ClipPath: TTsPath;
  Assert.IsTrue(RectPath(10.0, 10.0, 80.0, 80.0).TryTransform(TTsTransform.FromRow(1.0, -0.3, 0.0, 1.0, 0.0, 15.0), ClipPath));

  var Mask := NewMask(100, 100);
  Mask.FillPath(ClipPath, TTsFillRule.Winding, False, TTsTransform.Identity);
  AssertMaskedFill(Mask, TTinySkiaFixtures.SolidPaint(False), 'mask/rect-ts.png');
end;

procedure TTinySkiaMaskTests.TestCircleBottomRightAa;
begin
  var Mask := NewMask(100, 100);
  Mask.FillPath(CirclePath(100.0, 100.0, 50.0), TTsFillRule.Winding, True, TTsTransform.Identity);
  AssertMaskedFill(Mask, TTinySkiaFixtures.SolidPaint(False), 'mask/circle-bottom-right-aa.png');
end;

procedure TTinySkiaMaskTests.TestStroke;
begin
  var Mask := MaskOfRect(False, 10.0, 10.0, 80.0, 80.0);

  var Stroke := TTsStroke.New;
  Stroke.Width := 10.0;

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.StrokePath(Pixmap, RectPath(10.0, 10.0, 80.0, 80.0), TTinySkiaFixtures.SolidPaint(False), Stroke, TTsTransform.Identity,
    @Mask);
  TTinySkiaImages.AssertMatches(Pixmap, 'mask/stroke.png');
end;

procedure TTinySkiaMaskTests.TestSkipDest;
begin
  // Make sure we're clipping only source and not source and destination
  var Paint := TTinySkiaFixtures.SolidPaint(False);

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillPath(Pixmap, RectPath(5.0, 5.0, 60.0, 60.0), Paint, TTsFillRule.Winding, TTsTransform.Identity, nil);

  var Pixmap2 := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.FillPath(Pixmap2, RectPath(35.0, 35.0, 60.0, 60.0), Paint, TTsFillRule.Winding, TTsTransform.Identity, nil);

  var Mask := NewMask(100, 100);
  Mask.FillPath(RectPath(40.0, 40.0, 40.0, 40.0), TTsFillRule.Winding, True, TTsTransform.Identity);

  TTsPainter.DrawPixmap(Pixmap, 0, 0, Pixmap2.AsRef, TTsPixmapPaint.Default, TTsTransform.Identity, @Mask);
  TTinySkiaImages.AssertMatches(Pixmap, 'mask/skip-dest.png');
end;

procedure TTinySkiaMaskTests.TestIntersectAa;
begin
  var Mask := NewMask(200, 200);
  Mask.FillPath(CirclePath(75.0, 75.0, 50.0), TTsFillRule.Winding, True, TTsTransform.Identity);
  Mask.IntersectPath(CirclePath(125.0, 125.0, 50.0), TTsFillRule.Winding, True, TTsTransform.Identity);
  AssertMaskedFill(Mask, TTinySkiaFixtures.SolidPaint(False), 'mask/intersect-aa.png');
end;

procedure TTinySkiaMaskTests.TestIgnoreMemset;
begin
  var Paint := TTinySkiaFixtures.SolidPaint(False);
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(50, 127, 150, 255));
  AssertMaskedFill(MaskOfRect(False, 10.0, 10.0, 80.0, 80.0), Paint, 'mask/ignore-memset.png');
end;

procedure TTinySkiaMaskTests.TestIgnoreSource;
begin
  var Mask := MaskOfRect(False, 10.0, 10.0, 80.0, 80.0);

  // Must be opaque
  var Paint := TTinySkiaFixtures.SolidPaint(False);
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(50, 127, 150, 255));
  Paint.BlendMode := TTsBlendMode.SourceOver;

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  Pixmap.Fill(TTsColor.White);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(0.0, 0.0, 100.0, 100.0), Paint, TTsTransform.Identity, @Mask);
  TTinySkiaImages.AssertMatches(Pixmap, 'mask/ignore-source.png');
end;

procedure TTinySkiaMaskTests.TestApplyMask;
begin
  var Mask := NewMask(100, 100);
  Mask.FillPath(CirclePath(100.0, 100.0, 50.0), TTsFillRule.Winding, True, TTsTransform.Identity);

  var Pixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillRect(Pixmap, TTinySkiaFixtures.RectXYWH(0.0, 0.0, 100.0, 100.0), TTinySkiaFixtures.SolidPaint(False),
    TTsTransform.Identity, nil);
  TTsPainter.ApplyMask(Pixmap, Mask);
  TTinySkiaImages.AssertMatches(Pixmap, 'mask/apply-mask.png');
end;

procedure TTinySkiaMaskTests.TestMaskFromAlpha;
begin
  const Pixmap = CircleFilledPixmap;
  TTinySkiaImages.AssertMaskMatches(TTsMask.FromPixmap(Pixmap.AsRef, TTsMaskType.Alpha), 'mask/mask-from-alpha.png');
end;

procedure TTinySkiaMaskTests.TestMaskFromLuma;
begin
  const Pixmap = CircleFilledPixmap;
  TTinySkiaImages.AssertMaskMatches(TTsMask.FromPixmap(Pixmap.AsRef, TTsMaskType.Luminosity), 'mask/mask-from-luma.png');
end;

end.
