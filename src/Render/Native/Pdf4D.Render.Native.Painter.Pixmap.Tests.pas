// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The pixmap tests of tiny-skia (tests/integration/pixmap.rs), compared with the reference images
unit Pdf4D.Render.Native.Painter.Pixmap.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTinySkiaPixmapTests = class
  private
    FFloatState: TTsFloatState;

    function CircleOnPixmap: TTsPixmap;
    function Triangle: TTsPixmap;
    procedure AssertCloneRect(const Pixmap: TTsPixmap; const X, Y: Integer; const Width, Height: Cardinal; const RelativePng: string);
    procedure AssertNoClone(const Pixmap: TTsPixmap; const X, Y: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCloneRect1;

    [Test]
    procedure TestCloneRect2;

    [Test]
    procedure TestCloneRectOutOfBound;

    [Test]
    procedure TestFill;

    [Test]
    procedure TestDrawPixmap;

    [Test]
    procedure TestDrawPixmapTs;

    [Test]
    procedure TestDrawPixmapOpacity;
  end;

implementation

uses
  Pdf4D.Tests.TinySkiaImages;

procedure TTinySkiaPixmapTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTinySkiaPixmapTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTinySkiaPixmapTests.CircleOnPixmap: TTsPixmap;
begin
  Result := TTinySkiaFixtures.NewPixmap(200, 200);

  var Circle: TTsPath;
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(100.0, 100.0, 80.0, Circle));
  TTsPainter.FillPath(Result, Circle, TTinySkiaFixtures.SolidPaint(True), TTsFillRule.Winding, TTsTransform.Identity, nil);
end;

function TTinySkiaPixmapTests.Triangle: TTsPixmap;
begin
  Result := TTinySkiaFixtures.NewPixmap(100, 100);

  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0.0, 100.0);
  Builder.LineTo(100.0, 100.0);
  Builder.LineTo(50.0, 0.0);
  Builder.Close;
  TTsPainter.FillPath(Result, TTinySkiaFixtures.FinishPath(Builder), TTinySkiaFixtures.SolidPaint(True), TTsFillRule.Winding,
    TTsTransform.Identity, nil);
end;

procedure TTinySkiaPixmapTests.AssertCloneRect(const Pixmap: TTsPixmap; const X, Y: Integer; const Width, Height: Cardinal;
  const RelativePng: string);
begin
  var Rect: TTsIntRect;
  Assert.IsTrue(TTsIntRect.TryFromXYWH(X, Y, Width, Height, Rect));

  var Part: TTsPixmap;
  Assert.IsTrue(Pixmap.TryCloneRect(Rect, Part), 'the rectangle intersects the pixmap');
  TTinySkiaImages.AssertMatches(Part, RelativePng);
end;

procedure TTinySkiaPixmapTests.AssertNoClone(const Pixmap: TTsPixmap; const X, Y: Integer);
begin
  var Rect: TTsIntRect;
  Assert.IsTrue(TTsIntRect.TryFromXYWH(X, Y, 80, 90, Rect));

  var Part: TTsPixmap;
  Assert.IsFalse(Pixmap.TryCloneRect(Rect, Part), Format('the rectangle at (%d, %d) is outside the pixmap', [X, Y]));
end;

procedure TTinySkiaPixmapTests.TestCloneRect1;
begin
  AssertCloneRect(CircleOnPixmap, 10, 15, 80, 90, 'pixmap/clone-rect-1.png');
end;

procedure TTinySkiaPixmapTests.TestCloneRect2;
begin
  AssertCloneRect(CircleOnPixmap, 130, 120, 80, 90, 'pixmap/clone-rect-2.png');
end;

procedure TTinySkiaPixmapTests.TestCloneRectOutOfBound;
begin
  const Pixmap = CircleOnPixmap;
  AssertNoClone(Pixmap, 250, 15);
  AssertNoClone(Pixmap, 10, 250);
  AssertNoClone(Pixmap, 10, -250);
end;

procedure TTinySkiaPixmapTests.TestFill;
begin
  const Color = TTsColor.FromRgba8(50, 100, 150, 200);
  var Pixmap := TTinySkiaFixtures.NewPixmap(10, 10);
  Pixmap.Fill(Color);

  var Actual: TTsPremultipliedColorU8;
  Assert.IsTrue(Pixmap.TryPixel(1, 1, Actual));
  Assert.IsTrue(Actual = Color.Premultiply.ToColorU8);
end;

procedure TTinySkiaPixmapTests.TestDrawPixmap;
begin
  // Tests that painting algorithm will switch Bicubic/Bilinear to Nearest. Otherwise we will get a blurry image.

  // A pixmap with the bottom half filled with solid color
  var SubPixmap := TTinySkiaFixtures.NewPixmap(100, 100);
  TTsPainter.FillRect(SubPixmap, TTinySkiaFixtures.RectXYWH(0.0, 50.0, 100.0, 50.0), TTinySkiaFixtures.SolidPaint(False),
    TTsTransform.Identity, nil);

  var Paint := TTsPixmapPaint.Default;
  Paint.Quality := TTsFilterQuality.Bicubic;

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.DrawPixmap(Pixmap, 20, 20, SubPixmap.AsRef, Paint, TTsTransform.Identity, nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'canvas/draw-pixmap.png');
end;

procedure TTinySkiaPixmapTests.TestDrawPixmapTs;
begin
  var Paint := TTsPixmapPaint.Default;
  Paint.Quality := TTsFilterQuality.Bicubic;

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.DrawPixmap(Pixmap, 5, 10, Triangle.AsRef, Paint, TTsTransform.FromRow(1.2, 0.5, 0.5, 1.2, 0.0, 0.0), nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'canvas/draw-pixmap-ts.png');
end;

procedure TTinySkiaPixmapTests.TestDrawPixmapOpacity;
begin
  var Paint := TTsPixmapPaint.Default;
  Paint.Quality := TTsFilterQuality.Bicubic;
  Paint.Opacity := 0.5;

  var Pixmap := TTinySkiaFixtures.NewPixmap(200, 200);
  TTsPainter.DrawPixmap(Pixmap, 5, 10, Triangle.AsRef, Paint, TTsTransform.FromRow(1.2, 0.5, 0.5, 1.2, 0.0, 0.0), nil);
  TTinySkiaImages.AssertMatches(Pixmap, 'canvas/draw-pixmap-opacity.png');
end;

end.
