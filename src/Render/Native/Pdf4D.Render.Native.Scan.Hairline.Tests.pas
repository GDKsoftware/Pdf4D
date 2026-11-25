// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/scan/hairline.rs and src/scan/hairline_aa.rs
unit Pdf4D.Render.Native.Scan.Hairline.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Scan.Hairline,
  Pdf4D.Render.Native.Scan.HairlineAntiAlias,
  Pdf4D.Tests.RecordingBlitter;

type
  [TestFixture]
  TTsScanHairlineTests = class
  private
    FFloatState: TTsFloatState;
    FBlitter: TRecordingBlitter;

    function ClipOf(const Width, Height: Cardinal): TTsScreenIntRect;
    function LinePath(const X0, Y0, X1, Y1: Single): TTsPath;
    function QuadPath: TTsPath;
    function CubicPath: TTsPath;
    function LoopingCubicPath: TTsPath;
    function HugeCubicPath(const Big: Single): TTsPath;
    function PolylinePath: TTsPath;
    procedure UseBlitter(const Width, Height: Integer);
    function RowSum(const Y: Integer): Integer;
    procedure StrokeAll(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect);

    // The alpha that the stroke leaves in a clip of Size by Size pixels, summed
    function StrokeTotal(const Path: TTsPath; const LineCap: TTsLineCap; const AntiAlias: Boolean; const Size: Integer): Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHairlineHorizontal;

    [Test]
    procedure TestHairlineVertical;

    [Test]
    procedure TestHairlineDiagonalHasOnePixelPerColumn;

    [Test]
    procedure TestSquareCapExtendsTheLine;

    [Test]
    procedure TestHairlineOutsideTheClipDrawsNothing;

    [Test]
    procedure TestHairlineIsClippedToTheClip;

    [Test]
    procedure TestAaHairlineSplitsOverTwoRows;

    [Test]
    procedure TestAaHairlineAtHalfPixelUsesOneRow;

    [Test]
    procedure TestAaHairlineDiagonalSumsToFullCoveragePerRow;

    [Test]
    procedure TestAaHairlineIsClippedToTheClip;

    [Test]
    procedure TestAaHairlineVerticalSplitsOverTwoColumns;

    [Test]
    procedure TestHairlineTotalsMatchTinySkia;

    [Test]
    procedure TestPolylineAndClosedPathAreDrawn;

    [Test]
    procedure TestZeroLengthContourWithRoundCapGivesADot;

    [Test]
    procedure TestHugeLineIsClipped;

    [Test]
    procedure TestHugeCurvesDoNotRaise;

    [Test]
    procedure TestPathBeyondTheClipIsRejectedByItsBounds;
  end;

implementation

{ TTsScanHairlineTests }

function TTsScanHairlineTests.ClipOf(const Width, Height: Cardinal): TTsScreenIntRect;
begin
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(0, 0, Width, Height, Result), 'The clip rect');
end;

function TTsScanHairlineTests.LinePath(const X0, Y0, X1, Y1: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(X0, Y0);
  Builder.LineTo(X1, Y1);

  Assert.IsTrue(Builder.TryFinish(Result), 'The line');
end;

function TTsScanHairlineTests.QuadPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(2, 2);
  Builder.QuadTo(18, 2, 18, 18);

  Assert.IsTrue(Builder.TryFinish(Result), 'The quad');
end;

function TTsScanHairlineTests.CubicPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(2, 18);
  Builder.CubicTo(2, 2, 18, 2, 18, 18);

  Assert.IsTrue(Builder.TryFinish(Result), 'The cubic');
end;

// The control points lie outside of the limits of the end points, so the cubic is chopped at its maximum curvature
function TTsScanHairlineTests.LoopingCubicPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(2, 2);
  Builder.CubicTo(28, 28, -8, 28, 18, 2);

  Assert.IsTrue(Builder.TryFinish(Result), 'The looping cubic');
end;

function TTsScanHairlineTests.HugeCubicPath(const Big: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(-Big, 5);
  Builder.CubicTo(Big, -Big, -Big, Big, Big, 15);
  Builder.QuadTo(Big, Big, 0, 0);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The huge curves');
end;

function TTsScanHairlineTests.PolylinePath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(3, 3);
  Builder.LineTo(16, 5);
  Builder.LineTo(10, 17);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The triangle');
end;

procedure TTsScanHairlineTests.UseBlitter(const Width, Height: Integer);
begin
  FBlitter.Free;
  FBlitter := TRecordingBlitter.Create(Width, Height);
end;

function TTsScanHairlineTests.RowSum(const Y: Integer): Integer;
begin
  Result := 0;
  for var X := 0 to FBlitter.Width - 1 do
  begin
    Inc(Result, FBlitter.CoverageAt(X, Y));
  end;
end;

procedure TTsScanHairlineTests.StrokeAll(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect);
begin
  TTsScanHairline.StrokePath(Path, LineCap, Clip, FBlitter);
  TTsScanHairlineAntiAlias.StrokePath(Path, LineCap, Clip, FBlitter);
end;

function TTsScanHairlineTests.StrokeTotal(const Path: TTsPath; const LineCap: TTsLineCap; const AntiAlias: Boolean;
                                          const Size: Integer): Integer;
begin
  UseBlitter(Size, Size);

  if AntiAlias then
  begin
    TTsScanHairlineAntiAlias.StrokePath(Path, LineCap, ClipOf(Size, Size), FBlitter);
  end
  else
  begin
    TTsScanHairline.StrokePath(Path, LineCap, ClipOf(Size, Size), FBlitter);
  end;

  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside the buffer');
  Result := Integer(FBlitter.CompositedTotal);
end;

procedure TTsScanHairlineTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
  UseBlitter(20, 20);
end;

procedure TTsScanHairlineTests.TearDown;
begin
  FreeAndNil(FBlitter);
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsScanHairlineTests.TestHairlineHorizontal;
begin
  TTsScanHairline.StrokePath(LinePath(1, 5.5, 9, 5.5), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var Y := 0 to 19 do
  begin
    for var X := 0 to 19 do
    begin
      const Expected = Ord((Y = 5) and (X >= 1) and (X <= 8)) * 255;
      Assert.AreEqual(Expected, FBlitter.CoverageAt(X, Y), Format('Coverage at (%d, %d)', [X, Y]));
    end;
  end;

  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanHairlineTests.TestHairlineVertical;
begin
  TTsScanHairline.StrokePath(LinePath(5.5, 1, 5.5, 9), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var Y := 0 to 19 do
  begin
    for var X := 0 to 19 do
    begin
      const Expected = Ord((X = 5) and (Y >= 1) and (Y <= 8)) * 255;
      Assert.AreEqual(Expected, FBlitter.CoverageAt(X, Y), Format('Coverage at (%d, %d)', [X, Y]));
    end;
  end;
end;

procedure TTsScanHairlineTests.TestHairlineDiagonalHasOnePixelPerColumn;
begin
  TTsScanHairline.StrokePath(LinePath(2, 3, 12, 8), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  // A mostly horizontal line has one pixel per column
  for var X := 2 to 11 do
  begin
    var Count := 0;
    for var Y := 0 to 19 do
    begin
      if FBlitter.CoverageAt(X, Y) <> 0 then
      begin
        Inc(Count);
      end;
    end;

    Assert.AreEqual(1, Count, Format('Pixels in column %d', [X]));
  end;
end;

procedure TTsScanHairlineTests.TestSquareCapExtendsTheLine;
begin
  TTsScanHairline.StrokePath(LinePath(5.5, 5.5, 10.5, 5.5), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);
  Assert.AreEqual(5, FBlitter.CountPixelsWithCoverage, 'The butt cap has the pixels 6 to 10');

  UseBlitter(20, 20);
  TTsScanHairline.StrokePath(LinePath(5.5, 5.5, 10.5, 5.5), TTsLineCap.Square, ClipOf(20, 20), FBlitter);
  Assert.AreEqual(6, FBlitter.CountPixelsWithCoverage, 'The square cap adds half a pixel at each end');
  Assert.AreEqual(255, FBlitter.CoverageAt(5, 5), 'The pixel of the cap');
end;

procedure TTsScanHairlineTests.TestHairlineOutsideTheClipDrawsNothing;
begin
  StrokeAll(LinePath(30, 30, 40, 40), TTsLineCap.Butt, ClipOf(20, 20));
  StrokeAll(LinePath(-30, 5, -10, 5), TTsLineCap.Square, ClipOf(20, 20));

  Assert.AreEqual(0, FBlitter.CallCount, 'Not a single blit');
end;

procedure TTsScanHairlineTests.TestHairlineIsClippedToTheClip;
begin
  TTsScanHairline.StrokePath(LinePath(-10, 5.5, 30, 5.5), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var X := 0 to 19 do
  begin
    Assert.AreEqual(255, FBlitter.CoverageAt(X, 5), Format('Coverage at x %d', [X]));
  end;

  Assert.AreEqual(20, FBlitter.CountPixelsWithCoverage, 'One row of the clip');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanHairlineTests.TestAaHairlineSplitsOverTwoRows;
begin
  TTsScanHairlineAntiAlias.StrokePath(LinePath(1, 5, 9, 5), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var X := 2 to 8 do
  begin
    Assert.AreEqual(128, FBlitter.CoverageAt(X, 5), Format('Row 5 at x %d', [X]));
    Assert.AreEqual(127, FBlitter.CoverageAt(X, 4), Format('Row 4 at x %d', [X]));
    Assert.AreEqual(255, FBlitter.CoverageAt(X, 4) + FBlitter.CoverageAt(X, 5), 'The line has the coverage of one pixel');
  end;

  Assert.AreEqual(0, FBlitter.CoverageAt(10, 5), 'Nothing right of the line');
  Assert.AreEqual(0, FBlitter.CoverageAt(5, 6), 'Nothing below the line');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanHairlineTests.TestAaHairlineAtHalfPixelUsesOneRow;
begin
  TTsScanHairlineAntiAlias.StrokePath(LinePath(1, 5.5, 9, 5.5), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var X := 2 to 8 do
  begin
    Assert.AreEqual(255, FBlitter.CoverageAt(X, 5), Format('Row 5 at x %d', [X]));
    Assert.AreEqual(0, FBlitter.CoverageAt(X, 4), Format('Row 4 at x %d', [X]));
    Assert.AreEqual(0, FBlitter.CoverageAt(X, 6), Format('Row 6 at x %d', [X]));
  end;
end;

procedure TTsScanHairlineTests.TestAaHairlineDiagonalSumsToFullCoveragePerRow;
begin
  TTsScanHairlineAntiAlias.StrokePath(LinePath(2, 2, 12, 12), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var Y := 4 to 9 do
  begin
    Assert.AreEqual(255, RowSum(Y), Format('Coverage of row %d', [Y]));
  end;

  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanHairlineTests.TestAaHairlineIsClippedToTheClip;
begin
  TTsScanHairlineAntiAlias.StrokePath(LinePath(-10, 5.5, 30, 5.5), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var X := 0 to 19 do
  begin
    Assert.AreEqual(255, FBlitter.CoverageAt(X, 5), Format('Coverage at x %d', [X]));
  end;

  Assert.AreEqual(0, FBlitter.OutsideCount);
  Assert.AreEqual(20 * 255, Integer(FBlitter.TotalCoverage), 'One row of the clip');

  UseBlitter(20, 20);
  TTsScanHairlineAntiAlias.StrokePath(LinePath(-5, -5, 25, 22), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);
  Assert.AreEqual(0, FBlitter.OutsideCount, 'A slanted line through the clip');
  Assert.IsTrue(FBlitter.CountPixelsWithCoverage > 20);
end;

procedure TTsScanHairlineTests.TestAaHairlineVerticalSplitsOverTwoColumns;
begin
  TTsScanHairlineAntiAlias.StrokePath(LinePath(5, 1, 5, 9), TTsLineCap.Butt, ClipOf(20, 20), FBlitter);

  for var Y := 2 to 8 do
  begin
    Assert.AreEqual(255, FBlitter.CoverageAt(4, Y) + FBlitter.CoverageAt(5, Y), Format('The two columns of row %d', [Y]));
  end;

  Assert.AreEqual(0, FBlitter.OutsideCount);
end;


// The totals of tiny-skia v0.12.0 (its hairline strokes of the same paths, into a pixmap of 20 and of 10 pixels square, black at full
// alpha, so the alpha is the coverage): per path, per cap (butt, round, square), per mode (not anti-aliased, anti-aliased), per size (20, 10)
procedure TTsScanHairlineTests.TestHairlineTotalsMatchTinySkia;
const
  Expected: array[0..3, 0..11] of Integer = (
    (6120, 2040, 6110, 2040, 6120, 2040, 6193, 2118, 6375, 2040, 6225, 2141),
    (7140, 1530, 7057, 1592, 7140, 1530, 7227, 1531, 7650, 1530, 7221, 1509),
    (9180, 2040, 8255, 1913, 9180, 2040, 8447, 2013, 9180, 2040, 8520, 2049),
    (9690, 3315, 9657, 3459, 9945, 3570, 9878, 3596, 9945, 3570, 9936, 3629));
begin
  var Paths: array[0..3] of TTsPath;
  Paths[0] := QuadPath;
  Paths[1] := CubicPath;
  Paths[2] := LoopingCubicPath;
  Paths[3] := PolylinePath;

  var Caps: array[0..2] of TTsLineCap;
  Caps[0] := TTsLineCap.Butt;
  Caps[1] := TTsLineCap.Round;
  Caps[2] := TTsLineCap.Square;

  for var PathIndex := 0 to High(Paths) do
  begin
    for var CapIndex := 0 to High(Caps) do
    begin
      for var Mode := 0 to 1 do
      begin
        for var SizeIndex := 0 to 1 do
        begin
          const Size = 20 - SizeIndex * 10;
          const Total = StrokeTotal(Paths[PathIndex], Caps[CapIndex], Mode = 1, Size);

          Assert.AreEqual(Expected[PathIndex, CapIndex * 4 + Mode * 2 + SizeIndex], Total,
                          Format('Path %d, cap %d, anti-aliased %d, size %d', [PathIndex, CapIndex, Mode, Size]));
        end;
      end;
    end;
  end;
end;

procedure TTsScanHairlineTests.TestPolylineAndClosedPathAreDrawn;
begin
  TTsScanHairline.StrokePath(PolylinePath, TTsLineCap.Butt, ClipOf(20, 20), FBlitter);
  Assert.IsTrue(FBlitter.CountPixelsWithCoverage >= 30, 'The three sides of the triangle');
  Assert.IsTrue(FBlitter.CoverageAt(3, 3) >= 255, 'The first corner, where two sides begin and end');
  Assert.AreEqual(0, FBlitter.OutsideCount);

  UseBlitter(20, 20);
  TTsScanHairlineAntiAlias.StrokePath(PolylinePath, TTsLineCap.Round, ClipOf(20, 20), FBlitter);
  Assert.IsTrue(FBlitter.CountPixelsWithCoverage >= 30, 'The three sides of the triangle, anti-aliased');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanHairlineTests.TestZeroLengthContourWithRoundCapGivesADot;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(5.5, 5.5);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The zero length contour');

  // The totals of tiny-skia v0.12.0
  Assert.AreEqual(203, StrokeTotal(Path, TTsLineCap.Round, True, 20), 'The round cap of a point, anti-aliased');
  Assert.AreEqual(255, StrokeTotal(Path, TTsLineCap.Round, False, 20), 'The round cap of a point');
  Assert.AreEqual(255, StrokeTotal(Path, TTsLineCap.Square, True, 20), 'The square cap of a point, anti-aliased');
  Assert.AreEqual(0, StrokeTotal(Path, TTsLineCap.Butt, False, 20), 'A butt cap of a point has no length');
  Assert.AreEqual(0, StrokeTotal(Path, TTsLineCap.Butt, True, 20), 'A butt cap of a point has no length, anti-aliased');
end;

procedure TTsScanHairlineTests.TestHugeLineIsClipped;
begin
  // The totals of tiny-skia v0.12.0 for a line from corner to corner of an enormous square, and for a row, into 20 by 20 pixels
  for var Big in [1.0E30, 1.5E38] do
  begin
    const Value: Single = Big;

    Assert.AreEqual(5100, StrokeTotal(LinePath(-Value, -Value, Value, Value), TTsLineCap.Butt, False, 20), 'The diagonal');
    Assert.AreEqual(3820, StrokeTotal(LinePath(-Value, -Value, Value, Value), TTsLineCap.Butt, True, 20), 'The anti-aliased diagonal');
  end;

  Assert.AreEqual(5100, StrokeTotal(LinePath(-1.0E30, 5.5, 1.0E30, 5.5), TTsLineCap.Square, False, 20), 'The row');
  Assert.AreEqual(5100, StrokeTotal(LinePath(-1.0E30, 5.5, 1.0E30, 5.5), TTsLineCap.Square, True, 20), 'The anti-aliased row');

  // The column and the other caps stay inside the buffer
  Assert.IsTrue(StrokeTotal(LinePath(7.5, -1.0E30, 7.5, 1.0E30), TTsLineCap.Round, False, 20) > 0, 'The column');
  Assert.IsTrue(StrokeTotal(LinePath(7.5, -1.0E30, 7.5, 1.0E30), TTsLineCap.Round, True, 20) > 0, 'The anti-aliased column');
end;

procedure TTsScanHairlineTests.TestHugeCurvesDoNotRaise;
begin
  // The totals of tiny-skia v0.12.0 for the cubic and the quad of enormous control points
  Assert.AreEqual(5100, StrokeTotal(HugeCubicPath(1.0E30), TTsLineCap.Butt, False, 20), 'The huge curves');
  Assert.AreEqual(3820, StrokeTotal(HugeCubicPath(1.0E30), TTsLineCap.Butt, True, 20), 'The anti-aliased huge curves');

  StrokeTotal(HugeCubicPath(1.0E30), TTsLineCap.Square, False, 20);
  StrokeTotal(HugeCubicPath(1.0E30), TTsLineCap.Round, True, 20);
  StrokeTotal(HugeCubicPath(1.5E38), TTsLineCap.Round, False, 20);
  StrokeTotal(HugeCubicPath(1.5E38), TTsLineCap.Square, True, 20);
  StrokeTotal(HugeCubicPath(1.0E7), TTsLineCap.Butt, False, 20);
  StrokeTotal(HugeCubicPath(1.0E7), TTsLineCap.Butt, True, 20);
end;

procedure TTsScanHairlineTests.TestPathBeyondTheClipIsRejectedByItsBounds;
begin
  // Entirely outside, with and without the 1 or 2 pixels of margin of the caps
  StrokeAll(LinePath(21.5, 5, 40, 5), TTsLineCap.Butt, ClipOf(20, 20));
  StrokeAll(LinePath(5, -40, 5, -2.5), TTsLineCap.Square, ClipOf(20, 20));

  Assert.AreEqual(0, FBlitter.CallCount);
end;

end.
