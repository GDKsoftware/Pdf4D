// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/scan/mod.rs, src/scan/path.rs and src/scan/path_aa.rs
unit Pdf4D.Render.Native.Scan.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Scan.AntiAlias,
  Pdf4D.Tests.RecordingBlitter;

type
  [TestFixture]
  TTsScanTests = class
  private
    FFloatState: TTsFloatState;
    FBlitter: TRecordingBlitter;

    function RectPath(const Left, Top, Right, Bottom: Single): TTsPath;
    function ClipOf(const Width, Height: Cardinal): TTsScreenIntRect;
    function RectOf(const Left, Top, Right, Bottom: Single): TTsRect;
    function HugeTrianglePath(const Big: Single): TTsPath;
    function HugeCubicPath(const Big: Single): TTsPath;
    procedure UseBlitter(const Width, Height: Integer);
    procedure AssertCoverageOfRows(const FirstRow, LastRow, FirstColumn, LastColumn, Expected: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNonAaFillsPixelCenters;

    [Test]
    procedure TestNonAaEvenOddLeavesHole;

    [Test]
    procedure TestNonAaWindingFillsHole;

    [Test]
    procedure TestNonAaRespectsClipRect;

    [Test]
    procedure TestNonAaTriangleCoversHalfTheSquare;

    [Test]
    procedure TestNonAaPathOutsideTheClipDrawsNothing;

    [Test]
    procedure TestNonAaFillRectRoundsToPixels;

    [Test]
    procedure TestAaHalfPixelColumn;

    [Test]
    procedure TestAaRespectsClipRect;

    [Test]
    procedure TestAaFillOfTinyRectDoesNotRaise;

    [Test]
    procedure TestAaFillRectBlitsFractionalEdges;

    [Test]
    procedure TestAaEvenOddLeavesHole;

    [Test]
    procedure TestAaCircleCoverageIsAboutItsArea;

    [Test]
    procedure TestAaClipWiderThanTheLimitDrawsNothing;

    [Test]
    procedure TestHugeRectFillsTheClip;

    [Test]
    procedure TestHugeTriangleFillsHalfTheClip;

    [Test]
    procedure TestRectBeyondTheIntegerRangeDrawsNothingOrStaysInside;

    [Test]
    procedure TestMaxFloatTriangleDoesNotRaise;

    [Test]
    procedure TestHugeCubicDoesNotRaise;

    [Test]
    procedure TestManyEdgesAreSortedStably;
  end;

implementation

{ TTsScanTests }

function TTsScanTests.RectPath(const Left, Top, Right, Bottom: Single): TTsPath;
begin
  Result := TTsPathBuilder.FromRect(RectOf(Left, Top, Right, Bottom));
end;

function TTsScanTests.RectOf(const Left, Top, Right, Bottom: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromLTRB(Left, Top, Right, Bottom, Result), 'The rect');
end;

function TTsScanTests.ClipOf(const Width, Height: Cardinal): TTsScreenIntRect;
begin
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(0, 0, Width, Height, Result), 'The clip rect');
end;

function TTsScanTests.HugeTrianglePath(const Big: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.LineTo(Big, Big);
  Builder.LineTo(0, Big);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The huge triangle');
end;

function TTsScanTests.HugeCubicPath(const Big: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(-Big, 5);
  Builder.CubicTo(Big, -Big, -Big, Big, Big, 15);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The huge cubic');
end;

procedure TTsScanTests.UseBlitter(const Width, Height: Integer);
begin
  FBlitter.Free;
  FBlitter := TRecordingBlitter.Create(Width, Height);
end;

procedure TTsScanTests.AssertCoverageOfRows(const FirstRow, LastRow, FirstColumn, LastColumn, Expected: Integer);
begin
  for var Y := FirstRow to LastRow do
  begin
    for var X := FirstColumn to LastColumn do
    begin
      Assert.AreEqual(Expected, FBlitter.CoverageAt(X, Y), Format('Coverage at (%d, %d)', [X, Y]));
    end;
  end;
end;

procedure TTsScanTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
  UseBlitter(30, 30);
end;

procedure TTsScanTests.TearDown;
begin
  FreeAndNil(FBlitter);
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsScanTests.TestNonAaFillsPixelCenters;
begin
  TTsScan.FillPath(RectPath(10.4, 10.4, 19.6, 19.6), TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  AssertCoverageOfRows(10, 19, 10, 19, 255);
  Assert.AreEqual(100, FBlitter.CountPixelsWithCoverage, 'Only the 100 pixels are covered');
  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside');
end;

procedure TTsScanTests.TestNonAaEvenOddLeavesHole;
begin
  var Builder := TTsPathBuilder.New;
  Builder.PushRect(RectOf(0, 0, 20, 20));
  Builder.PushRect(RectOf(5, 5, 15, 15));

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The two squares');

  TTsScan.FillPath(Path, TTsFillRule.EvenOdd, ClipOf(30, 30), FBlitter);

  Assert.AreEqual(0, FBlitter.CoverageAt(10, 10), 'The hole');
  Assert.AreEqual(255, FBlitter.CoverageAt(2, 2), 'The ring');
  Assert.AreEqual(255, FBlitter.CoverageAt(17, 17), 'The ring');
  Assert.AreEqual(400 - 100, FBlitter.CountPixelsWithCoverage, 'The ring has 300 pixels');
end;

procedure TTsScanTests.TestNonAaWindingFillsHole;
begin
  var Builder := TTsPathBuilder.New;
  Builder.PushRect(RectOf(0, 0, 20, 20));
  Builder.PushRect(RectOf(5, 5, 15, 15));

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The two squares');

  TTsScan.FillPath(Path, TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  Assert.AreEqual(255, FBlitter.CoverageAt(10, 10), 'Both are clockwise, so the hole is filled');
  Assert.AreEqual(400, FBlitter.CountPixelsWithCoverage, 'The square has 400 pixels');
end;

procedure TTsScanTests.TestNonAaRespectsClipRect;
begin
  TTsScan.FillPath(RectPath(5, 5, 25, 25), TTsFillRule.Winding, ClipOf(15, 15), FBlitter);

  AssertCoverageOfRows(5, 14, 5, 14, 255);
  Assert.AreEqual(100, FBlitter.CountPixelsWithCoverage, 'Only the part inside the clip');
  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside the buffer');
end;

procedure TTsScanTests.TestNonAaTriangleCoversHalfTheSquare;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.LineTo(20, 0);
  Builder.LineTo(0, 20);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The triangle');

  TTsScan.FillPath(Path, TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  // Row y has the pixels whose center lies left of the diagonal: x + y + 1 <= 20
  Assert.AreEqual(255, FBlitter.CoverageAt(0, 0), 'Top left');
  Assert.AreEqual(0, FBlitter.CoverageAt(19, 19), 'Bottom right');
  Assert.AreEqual(0, FBlitter.CoverageAt(10, 10), 'The diagonal pixel center lies outside');
  Assert.IsTrue((FBlitter.CountPixelsWithCoverage >= 190) and (FBlitter.CountPixelsWithCoverage <= 210), 'About half of 400');
end;

procedure TTsScanTests.TestNonAaPathOutsideTheClipDrawsNothing;
begin
  TTsScan.FillPath(RectPath(40, 40, 50, 50), TTsFillRule.Winding, ClipOf(30, 30), FBlitter);
  TTsScan.FillPath(RectPath(-20, -20, -5, -5), TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  Assert.AreEqual(0, FBlitter.CountPixelsWithCoverage);
  Assert.AreEqual(0, FBlitter.CallCount, 'Not a single blit');
end;

procedure TTsScanTests.TestNonAaFillRectRoundsToPixels;
begin
  // Rect.round of tiny-skia adds 0.5 to the floor of the value, which gives the floor: 10.4 to 19.6 is 10 to 19, nine pixels wide
  TTsScan.FillRect(RectOf(10.4, 10.4, 19.6, 19.6), ClipOf(30, 30), FBlitter);

  AssertCoverageOfRows(10, 18, 10, 18, 255);
  Assert.AreEqual(81, FBlitter.CountPixelsWithCoverage);

  UseBlitter(30, 30);
  TTsScan.FillRect(RectOf(-5, -5, 100, 3.4), ClipOf(30, 30), FBlitter);

  AssertCoverageOfRows(0, 2, 0, 29, 255);
  Assert.AreEqual(90, FBlitter.CountPixelsWithCoverage, 'The part inside the clip');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestAaHalfPixelColumn;
begin
  TTsScanAntiAlias.FillPath(RectPath(10, 10, 20.5, 20), TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  AssertCoverageOfRows(10, 19, 10, 19, 255);
  for var Y := 10 to 19 do
  begin
    const Value = FBlitter.CoverageAt(20, Y);
    Assert.IsTrue((Value >= 120) and (Value <= 136), Format('Half coverage at row %d: %d', [Y, Value]));
  end;

  Assert.AreEqual(0, FBlitter.CoverageAt(21, 15), 'Nothing right of the edge');
  Assert.AreEqual(0, FBlitter.CoverageAt(9, 15), 'Nothing left of the edge');
  Assert.AreEqual(0, FBlitter.CoverageAt(15, 9), 'Nothing above');
  Assert.AreEqual(0, FBlitter.CoverageAt(15, 20), 'Nothing below');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestAaRespectsClipRect;
begin
  TTsScanAntiAlias.FillPath(RectPath(5, 5, 25, 25), TTsFillRule.Winding, ClipOf(15, 15), FBlitter);

  AssertCoverageOfRows(5, 14, 5, 14, 255);
  for var Y := 0 to 29 do
  begin
    for var X := 0 to 29 do
    begin
      if (X >= 15) or (Y >= 15) then
      begin
        Assert.AreEqual(0, FBlitter.CoverageAt(X, Y), Format('Outside the clip at (%d, %d)', [X, Y]));
      end;
    end;
  end;

  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestAaFillOfTinyRectDoesNotRaise;
begin
  // The panic that v0.12.0 fixes: a rectangle of a tenth of a pixel
  TTsScanAntiAlias.FillPath(RectPath(1.1, 1.1, 1.2, 1.2), TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside');
  Assert.IsTrue(FBlitter.TotalCoverage <= 255, 'A hundredth of a pixel is at most one pixel');

  for var Index := 0 to 99 do
  begin
    UseBlitter(30, 30);
    const Left: Single = 1.0 + Index / 97.0;
    const Top: Single = 2.0 + Index / 89.0;
    TTsScanAntiAlias.FillPath(RectPath(Left, Top, Left + 0.01, Top + 0.01), TTsFillRule.Winding, ClipOf(30, 30), FBlitter);
    TTsScanAntiAlias.FillPath(RectPath(Left, Top, Left + 0.3, Top + 0.001), TTsFillRule.EvenOdd, ClipOf(30, 30), FBlitter);
    Assert.AreEqual(0, FBlitter.OutsideCount, Format('Nothing outside for the rect %d', [Index]));
  end;
end;

procedure TTsScanTests.TestAaFillRectBlitsFractionalEdges;
begin
  TTsScan.FillRectAntiAlias(RectOf(10.5, 10.5, 12.5, 12.5), ClipOf(30, 30), FBlitter);

  Assert.AreEqual(64, FBlitter.CoverageAt(10, 10), 'Corner');
  Assert.AreEqual(128, FBlitter.CoverageAt(11, 10), 'Top edge');
  Assert.AreEqual(64, FBlitter.CoverageAt(12, 10), 'Corner');
  Assert.AreEqual(128, FBlitter.CoverageAt(10, 11), 'Left edge');
  Assert.AreEqual(255, FBlitter.CoverageAt(11, 11), 'Inside');
  Assert.AreEqual(128, FBlitter.CoverageAt(12, 11), 'Right edge');
  Assert.AreEqual(64, FBlitter.CoverageAt(12, 12), 'Corner');
  Assert.AreEqual(0, FBlitter.CoverageAt(13, 11), 'Outside');
  Assert.AreEqual(0, FBlitter.OutsideCount);

  UseBlitter(30, 30);
  TTsScan.FillRectAntiAlias(RectOf(-5, -5, 3, 3), ClipOf(30, 30), FBlitter);
  AssertCoverageOfRows(0, 2, 0, 2, 255);
  Assert.AreEqual(9, FBlitter.CountPixelsWithCoverage, 'Clipped to the clip');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestAaEvenOddLeavesHole;
begin
  var Builder := TTsPathBuilder.New;
  Builder.PushRect(RectOf(0, 0, 20, 20));
  Builder.PushRect(RectOf(5, 5, 15, 15));

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The two squares');

  TTsScanAntiAlias.FillPath(Path, TTsFillRule.EvenOdd, ClipOf(30, 30), FBlitter);

  Assert.AreEqual(0, FBlitter.CoverageAt(10, 10), 'The hole');
  Assert.AreEqual(255, FBlitter.CoverageAt(2, 2), 'The ring');
  Assert.AreEqual(300 * 255, Integer(FBlitter.TotalCoverage), 'The ring has 300 pixels');
end;

procedure TTsScanTests.TestAaCircleCoverageIsAboutItsArea;
begin
  var Path: TTsPath;
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(15, 15, 10, Path), 'The circle');

  TTsScanAntiAlias.FillPath(Path, TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  // The total of tiny-skia v0.12.0 for this circle (an area of 307.87: the supersampling of 4 by 4 gives a little less than the 314.16 of
  // the circle)
  Assert.AreEqual(78508, Integer(FBlitter.TotalCoverage), 'The summed coverage of the circle');
  Assert.AreEqual(255, FBlitter.CoverageAt(15, 15), 'The center');
  Assert.AreEqual(0, FBlitter.CoverageAt(1, 1), 'The corner');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestAaClipWiderThanTheLimitDrawsNothing;
begin
  UseBlitter(40000, 2);

  // The anti-aliasing cannot handle a clip right of 32767
  TTsScanAntiAlias.FillPath(RectPath(5, 0, 25, 2), TTsFillRule.Winding, ClipOf(40000, 2), FBlitter);

  Assert.AreEqual(0, FBlitter.CallCount);
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestHugeRectFillsTheClip;
begin
  const Big: Single = 1.0E9;

  UseBlitter(20, 20);
  TTsScan.FillPath(RectPath(-Big, -Big, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  AssertCoverageOfRows(0, 19, 0, 19, 255);
  Assert.AreEqual(0, FBlitter.OutsideCount, 'Non anti-aliased: nothing outside');

  // One side of the rect inside the clip: the part that is visible
  UseBlitter(20, 20);
  TTsScan.FillPath(RectPath(5, 5, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  AssertCoverageOfRows(5, 19, 5, 19, 255);
  Assert.AreEqual(225, FBlitter.CountPixelsWithCoverage, 'The 15 by 15 pixels inside the clip');
  Assert.AreEqual(0, FBlitter.OutsideCount);

  // tiny-skia draws nothing at all of such a path with anti-aliasing: the edges, shifted left by two, overflow the rows
  UseBlitter(20, 20);
  TTsScanAntiAlias.FillPath(RectPath(-Big, -Big, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  Assert.AreEqual(0, FBlitter.CallCount, 'Anti-aliased: nothing drawn');
  TTsScanAntiAlias.FillPath(RectPath(5, 5, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  Assert.AreEqual(0, FBlitter.CallCount, 'Anti-aliased: nothing drawn');
end;

procedure TTsScanTests.TestHugeTriangleFillsHalfTheClip;
begin
  UseBlitter(20, 20);
  TTsScan.FillPath(HugeTrianglePath(1.0E15), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);

  // The pixels at or left of the diagonal: 210 of the 400 (the total of tiny-skia v0.12.0 is 210 * 255)
  Assert.AreEqual(210 * 255, Integer(FBlitter.TotalCoverage));
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;

procedure TTsScanTests.TestRectBeyondTheIntegerRangeDrawsNothingOrStaysInside;
begin
  const Big: Single = 1.0E30;

  UseBlitter(20, 20);
  TTsScan.FillPath(RectPath(-Big, -Big, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  TTsScanAntiAlias.FillPath(RectPath(-Big, -Big, Big, Big), TTsFillRule.EvenOdd, ClipOf(20, 20), FBlitter);
  TTsScan.FillPath(RectPath(5, 5, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  TTsScanAntiAlias.FillPath(RectPath(5, 5, Big, Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);

  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside the buffer');
end;

procedure TTsScanTests.TestMaxFloatTriangleDoesNotRaise;
begin
  const Big: Single = 3.4E38;

  UseBlitter(20, 20);
  TTsScan.FillPath(HugeTrianglePath(Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  TTsScanAntiAlias.FillPath(HugeTrianglePath(Big), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  TTsScan.FillPath(HugeTrianglePath(1.0E15), TTsFillRule.EvenOdd, ClipOf(20, 20), FBlitter);
  TTsScanAntiAlias.FillPath(HugeTrianglePath(1.0E15), TTsFillRule.EvenOdd, ClipOf(20, 20), FBlitter);

  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside the buffer');
end;

procedure TTsScanTests.TestHugeCubicDoesNotRaise;
begin
  UseBlitter(20, 20);
  TTsScan.FillPath(HugeCubicPath(1.0E30), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  TTsScanAntiAlias.FillPath(HugeCubicPath(1.0E30), TTsFillRule.Winding, ClipOf(20, 20), FBlitter);
  TTsScan.FillPath(HugeCubicPath(1.0E7), TTsFillRule.EvenOdd, ClipOf(20, 20), FBlitter);
  TTsScanAntiAlias.FillPath(HugeCubicPath(1.0E7), TTsFillRule.EvenOdd, ClipOf(20, 20), FBlitter);

  Assert.AreEqual(0, FBlitter.OutsideCount, 'Nothing outside the buffer');
end;

procedure TTsScanTests.TestManyEdgesAreSortedStably;
begin
  // Hundreds of squares in a row and a column: the edge list is sorted and the walk gives each of them its pixels
  var Builder := TTsPathBuilder.New;
  for var Index := 0 to 99 do
  begin
    const Column: Single = (Index mod 10) * 3;
    const Row: Single = (Index div 10) * 3;
    Builder.PushRect(RectOf(Column, Row, Column + 2, Row + 2));
  end;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The squares');

  UseBlitter(30, 30);
  TTsScan.FillPath(Path, TTsFillRule.Winding, ClipOf(30, 30), FBlitter);

  Assert.AreEqual(400, FBlitter.CountPixelsWithCoverage, '100 squares of 4 pixels');
  Assert.AreEqual(255, FBlitter.CoverageAt(0, 0));
  Assert.AreEqual(0, FBlitter.CoverageAt(2, 2), 'The gap between the squares');

  UseBlitter(30, 30);
  TTsScanAntiAlias.FillPath(Path, TTsFillRule.Winding, ClipOf(30, 30), FBlitter);
  Assert.AreEqual(400 * 255, Integer(FBlitter.TotalCoverage), 'The same with anti-aliasing');
  Assert.AreEqual(0, FBlitter.OutsideCount);
end;


end.
