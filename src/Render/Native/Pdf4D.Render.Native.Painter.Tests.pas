// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the draw tiler (the inline tests of src/painter.rs) and of the painter on a pixmap that needs tiles
unit Pdf4D.Render.Native.Painter.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Mask,
  Pdf4D.Render.Native.Painter;

type
  [TestFixture]
  TTsPainterTests = class
  private
    FFloatState: TTsFloatState;

    procedure AssertTile(var Tiler: TTsDrawTiler; const X, Y, Width, Height: Cardinal);
    procedure AssertNoTile(var Tiler: TTsDrawTiler);
    function IsFilled(const Pixmap: TTsPixmap; const X, Y: Cardinal): Boolean;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSkip;

    [Test]
    procedure TestHorizontal;

    [Test]
    procedure TestVertical;

    [Test]
    procedure TestRect;

    [Test]
    procedure TestWidePixmapUsesTiler;

    [Test]
    procedure TestTallPixmapUsesTilerForStrokes;

    [Test]
    procedure TestMaskIsClippedToTheTile;

    [Test]
    procedure TestHugePathIsRejected;

    [Test]
    procedure TestApplyMaskRequiresTheSameSize;
  end;

implementation

uses
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Tests.TinySkiaImages;

const
  MaxDimension = TTsDrawTiler.MaxDimensions;

procedure TTsPainterTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsPainterTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsPainterTests.AssertTile(var Tiler: TTsDrawTiler; const X, Y, Width, Height: Cardinal);
begin
  var Tile: TTsScreenIntRect;
  Assert.IsTrue(Tiler.TryNext(Tile), 'a tile is expected');

  var Expected: TTsScreenIntRect;
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(X, Y, Width, Height, Expected));
  Assert.IsTrue(Tile = Expected, Format('the tile is (%d, %d, %d, %d), expected (%d, %d, %d, %d)',
    [Tile.X, Tile.Y, Tile.Width, Tile.Height, X, Y, Width, Height]));
end;

procedure TTsPainterTests.AssertNoTile(var Tiler: TTsDrawTiler);
begin
  var Tile: TTsScreenIntRect;
  Assert.IsFalse(Tiler.TryNext(Tile), 'no tile is expected');
end;

function TTsPainterTests.IsFilled(const Pixmap: TTsPixmap; const X, Y: Cardinal): Boolean;
begin
  var Color: TTsPremultipliedColorU8;
  Assert.IsTrue(Pixmap.TryPixel(X, Y, Color));
  Result := (Color.Alpha <> 0);
end;

procedure TTsPainterTests.TestSkip;
begin
  var Tiler: TTsDrawTiler;
  Assert.IsFalse(TTsDrawTiler.TryCreate(100, 500, Tiler));
end;

procedure TTsPainterTests.TestHorizontal;
begin
  var Tiler: TTsDrawTiler;
  Assert.IsTrue(TTsDrawTiler.TryCreate(10000, 500, Tiler));
  AssertTile(Tiler, 0, 0, MaxDimension, 500);
  AssertTile(Tiler, MaxDimension, 0, 10000 - MaxDimension, 500);
  AssertNoTile(Tiler);
end;

procedure TTsPainterTests.TestVertical;
begin
  var Tiler: TTsDrawTiler;
  Assert.IsTrue(TTsDrawTiler.TryCreate(500, 10000, Tiler));
  AssertTile(Tiler, 0, 0, 500, MaxDimension);
  AssertTile(Tiler, 0, MaxDimension, 500, 10000 - MaxDimension);
  AssertNoTile(Tiler);
end;

procedure TTsPainterTests.TestRect;
begin
  var Tiler: TTsDrawTiler;
  Assert.IsTrue(TTsDrawTiler.TryCreate(10000, 10000, Tiler));
  // Row 1
  AssertTile(Tiler, 0, 0, MaxDimension, MaxDimension);
  AssertTile(Tiler, MaxDimension, 0, 10000 - MaxDimension, MaxDimension);
  // Row 2
  AssertTile(Tiler, 0, MaxDimension, MaxDimension, 10000 - MaxDimension);
  AssertTile(Tiler, MaxDimension, MaxDimension, 10000 - MaxDimension, 10000 - MaxDimension);
  AssertNoTile(Tiler);
end;

procedure TTsPainterTests.TestWidePixmapUsesTiler;
begin
  // The anti-aliased fill draws nothing when the clip is wider than 32767 pixels in supersampled units: the tiler must split the pixmap
  var Pixmap := TTinySkiaFixtures.NewPixmap(9000, 4);
  TTsPainter.FillPath(Pixmap, TTsPathBuilder.FromRect(TTinySkiaFixtures.RectXYWH(8000, 0, 400, 4)), TTinySkiaFixtures.SolidPaint(True),
    TTsFillRule.Winding, TTsTransform.Identity, nil);

  Assert.IsTrue(IsFilled(Pixmap, 8190, 1), '(8190, 1) is filled');
  Assert.IsTrue(IsFilled(Pixmap, 8195, 1), '(8195, 1) is filled');
  Assert.IsFalse(IsFilled(Pixmap, 7999, 1), '(7999, 1) is empty');
  Assert.IsFalse(IsFilled(Pixmap, 8400, 1), '(8400, 1) is empty');

  var Rect := TTinySkiaFixtures.NewPixmap(9000, 4);
  TTsPainter.FillRect(Rect, TTinySkiaFixtures.RectXYWH(8000, 0, 400, 4), TTinySkiaFixtures.SolidPaint(True), TTsTransform.Identity, nil);
  Assert.IsTrue(IsFilled(Rect, 8190, 1), 'the rectangle (8190, 1) is filled');
  Assert.IsTrue(IsFilled(Rect, 8195, 1), 'the rectangle (8195, 1) is filled');
  Assert.IsFalse(IsFilled(Rect, 7999, 1), 'the rectangle (7999, 1) is empty');
  Assert.IsFalse(IsFilled(Rect, 8400, 1), 'the rectangle (8400, 1) is empty');
end;

procedure TTsPainterTests.TestTallPixmapUsesTilerForStrokes;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(4, 9000);
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(1.5, 8000);
  Builder.LineTo(1.5, 8400);
  const Path = TTinySkiaFixtures.FinishPath(Builder);

  var Paint := TTinySkiaFixtures.SolidPaint(True);
  var Stroke := TTsStroke.New;
  Stroke.Width := 0.5;
  TTsPainter.StrokePath(Pixmap, Path, Paint, Stroke, TTsTransform.Identity, nil);

  Assert.IsTrue(IsFilled(Pixmap, 1, 8190), '(1, 8190) is drawn');
  Assert.IsTrue(IsFilled(Pixmap, 1, 8195), '(1, 8195) is drawn');
  Assert.IsFalse(IsFilled(Pixmap, 1, 7990), '(1, 7990) is empty');
  Assert.IsFalse(IsFilled(Pixmap, 1, 8410), '(1, 8410) is empty');
end;

procedure TTsPainterTests.TestMaskIsClippedToTheTile;
begin
  // The mask of a tiled draw is cut for every tile: a mask that is white on the right half only
  var Pixmap := TTinySkiaFixtures.NewPixmap(9000, 2);
  var Mask: TTsMask;
  Assert.IsTrue(TTsMask.TryCreate(9000, 2, Mask));
  for var Y := 0 to 1 do
  begin
    for var X := 8195 to 8999 do
    begin
      Mask.Data[Y * 9000 + X] := 255;
    end;
  end;

  TTsPainter.FillPath(Pixmap, TTsPathBuilder.FromRect(TTinySkiaFixtures.RectXYWH(8000, 0, 400, 2)), TTinySkiaFixtures.SolidPaint(False),
    TTsFillRule.Winding, TTsTransform.Identity, @Mask);

  Assert.IsFalse(IsFilled(Pixmap, 8190, 0), '(8190, 0) is masked out');
  Assert.IsTrue(IsFilled(Pixmap, 8200, 0), '(8200, 0) is drawn');
  Assert.IsFalse(IsFilled(Pixmap, 8400, 0), '(8400, 0) is outside the rectangle');
end;

procedure TTsPainterTests.TestHugePathIsRejected;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(10, 10);
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.LineTo(2E38, 0);
  Builder.LineTo(0, 10);
  const Path = TTinySkiaFixtures.FinishPath(Builder);
  Assert.IsTrue(TTsPainter.IsTooBigForMath(Path));

  TTsPainter.FillPath(Pixmap, Path, TTinySkiaFixtures.SolidPaint(True), TTsFillRule.Winding, TTsTransform.Identity, nil);
  Assert.IsFalse(IsFilled(Pixmap, 0, 0));
end;

procedure TTsPainterTests.TestApplyMaskRequiresTheSameSize;
begin
  var Pixmap := TTinySkiaFixtures.NewPixmap(4, 4);
  Pixmap.Fill(TTsColor.FromRgba8(50, 127, 150, 255));

  var Mask: TTsMask;
  Assert.IsTrue(TTsMask.TryCreate(5, 4, Mask));
  TTsPainter.ApplyMask(Pixmap, Mask);
  Assert.IsTrue(IsFilled(Pixmap, 0, 0), 'a mask of another size changes nothing');

  Assert.IsTrue(TTsMask.TryCreate(4, 4, Mask));
  TTsPainter.ApplyMask(Pixmap, Mask);
  Assert.IsFalse(IsFilled(Pixmap, 0, 0), 'an empty mask of the same size removes the content');
end;

end.
