// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/edge_clipper.rs, src/line_clipper.rs and src/path64
unit Pdf4D.Render.Native.EdgeClipper.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.PathGeometry,
  Pdf4D.Render.Native.Path64,
  Pdf4D.Render.Native.EdgeClipper;

type
  [TestFixture]
  TTsEdgeClipperTests = class
  private
    FFloatState: TTsFloatState;

    function Pt(const X, Y: Single): TTsPoint;
    function ClipRect: TTsRect;
    function Segment(const X0, Y0, X1, Y1: Single): TTsPoints2;
    procedure AssertPoint(const Expected: TTsPoint; const Actual: TTsPoint; const Description: string);
    procedure AssertEdgesInside(const Edges: TTsClippedEdges);
    procedure AssertSame(const Expected, Actual: Single; const Description: string);
    procedure AssertLineEdge(const Edges: TTsClippedEdges; const Index: Integer; const X0, Y0, X1, Y1: Single);
    procedure AssertQuadEdge(const Edges: TTsClippedEdges; const Index: Integer; const X0, Y0, X1, Y1, X2, Y2: Single);
    procedure AssertCubicEdge(const Edges: TTsClippedEdges; const Index: Integer; const X0, Y0, X1, Y1, X2, Y2, X3, Y3: Single);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLineAboveOrBelowTheClipIsDropped;

    [Test]
    procedure TestLineInsideTheClipIsKept;

    [Test]
    procedure TestLineCrossingTheTopIsCutAtTheTop;

    [Test]
    procedure TestLineLeftOfTheClipGetsAVerticalPart;

    [Test]
    procedure TestLineRunningRightToLeftKeepsItsDirection;

    [Test]
    procedure TestLineRightOfTheClipIsVerticalOrCulled;

    [Test]
    procedure TestLineThroughBothSidesGivesThreeSegments;

    [Test]
    procedure TestIntersectKeepsInsideAndRejectsOutside;

    [Test]
    procedure TestIntersectCutsAtTheBorders;

    [Test]
    procedure TestClipperLineOutsideGivesNoEdges;

    [Test]
    procedure TestQuadInsideIsKept;

    [Test]
    procedure TestQuadLeftOfTheClipStartsWithAVerticalLine;

    [Test]
    procedure TestQuadAboveTheClipIsDropped;

    [Test]
    procedure TestQuadWithExtremaIsCutIntoMonotonicPieces;

    [Test]
    procedure TestCubicInsideIsKept;

    [Test]
    procedure TestCubicCrossingTheTopStaysInsideTheClip;

    [Test]
    procedure TestCubicTooBigForFloatMathBecomesALine;

    [Test]
    procedure TestCubicCrossingBothSidesStaysInsideTheClip;

    [Test]
    procedure TestChopMonoCubicAtYFindsTheCrossing;

    [Test]
    procedure TestChopMonoCubicAtXFindsTheCrossing;

    [Test]
    procedure TestChopMonoCubicAtYWithoutACrossingFails;

    [Test]
    procedure TestHugeSegmentsGiveTheEdgesOfTinySkia;

    [Test]
    procedure TestClipperIterGivesTheEdgesOfEverySegment;
  end;

  [TestFixture]
  TTsPath64Tests = class
  private
    FFloatState: TTsFloatState;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestBoundReturnsMaxForNan;

    [Test]
    procedure TestApproximateComparisons;

    [Test]
    procedure TestCubeRoot;

    [Test]
    procedure TestQuadRootsReal;

    [Test]
    procedure TestQuadRootsValidTKeepsTheRootsInZeroToOne;

    [Test]
    procedure TestQuadDegenerateToALine;

    [Test]
    procedure TestPointAtT;

    [Test]
    procedure TestChopAtHalfAndAtT;

    [Test]
    procedure TestVerticalIntersect;

    [Test]
    procedure TestSearchGivesUpWhereRustDoes;

    [Test]
    procedure TestHorizontalIntersect;

    [Test]
    procedure TestIntersectWithNoCrossing;

    [Test]
    procedure TestNanPointsDoNotHang;
  end;

implementation

{ TTsEdgeClipperTests }

function TTsEdgeClipperTests.Pt(const X, Y: Single): TTsPoint;
begin
  Result := TTsPoint.FromXY(X, Y);
end;

function TTsEdgeClipperTests.ClipRect: TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromLTRB(0, 0, 100, 100, Result), 'The clip rect');
end;

function TTsEdgeClipperTests.Segment(const X0, Y0, X1, Y1: Single): TTsPoints2;
begin
  Result[0] := Pt(X0, Y0);
  Result[1] := Pt(X1, Y1);
end;

procedure TTsEdgeClipperTests.AssertPoint(const Expected: TTsPoint; const Actual: TTsPoint; const Description: string);
begin
  Assert.AreEqual(Expected.X, Actual.X, 0.001, Description + ' x');
  Assert.AreEqual(Expected.Y, Actual.Y, 0.001, Description + ' y');
end;

procedure TTsEdgeClipperTests.AssertSame(const Expected, Actual: Single; const Description: string);
begin
  Assert.AreEqual(Expected, Actual, 0.0, Description);
end;

procedure TTsEdgeClipperTests.AssertLineEdge(const Edges: TTsClippedEdges; const Index: Integer; const X0, Y0, X1, Y1: Single);
begin
  Assert.IsTrue(Index < Edges.Count, Format('Edge %d exists', [Index]));

  const Edge = Edges.Items[Index];
  Assert.IsTrue(Edge.Kind = TTsPathEdgeKind.LineTo, Format('Edge %d is a line', [Index]));
  AssertSame(X0, Edge.P0.X, Format('Edge %d x0', [Index]));
  AssertSame(Y0, Edge.P0.Y, Format('Edge %d y0', [Index]));
  AssertSame(X1, Edge.P1.X, Format('Edge %d x1', [Index]));
  AssertSame(Y1, Edge.P1.Y, Format('Edge %d y1', [Index]));
end;

procedure TTsEdgeClipperTests.AssertQuadEdge(const Edges: TTsClippedEdges; const Index: Integer; const X0, Y0, X1, Y1, X2, Y2: Single);
begin
  Assert.IsTrue(Index < Edges.Count, Format('Edge %d exists', [Index]));

  const Edge = Edges.Items[Index];
  Assert.IsTrue(Edge.Kind = TTsPathEdgeKind.QuadTo, Format('Edge %d is a quad', [Index]));
  AssertSame(X0, Edge.P0.X, Format('Edge %d x0', [Index]));
  AssertSame(Y0, Edge.P0.Y, Format('Edge %d y0', [Index]));
  AssertSame(X1, Edge.P1.X, Format('Edge %d x1', [Index]));
  AssertSame(Y1, Edge.P1.Y, Format('Edge %d y1', [Index]));
  AssertSame(X2, Edge.P2.X, Format('Edge %d x2', [Index]));
  AssertSame(Y2, Edge.P2.Y, Format('Edge %d y2', [Index]));
end;

procedure TTsEdgeClipperTests.AssertCubicEdge(const Edges: TTsClippedEdges; const Index: Integer;
                                              const X0, Y0, X1, Y1, X2, Y2, X3, Y3: Single);
begin
  Assert.IsTrue(Index < Edges.Count, Format('Edge %d exists', [Index]));

  const Edge = Edges.Items[Index];
  Assert.IsTrue(Edge.Kind = TTsPathEdgeKind.CubicTo, Format('Edge %d is a cubic', [Index]));
  AssertSame(X0, Edge.P0.X, Format('Edge %d x0', [Index]));
  AssertSame(Y0, Edge.P0.Y, Format('Edge %d y0', [Index]));
  AssertSame(X1, Edge.P1.X, Format('Edge %d x1', [Index]));
  AssertSame(Y1, Edge.P1.Y, Format('Edge %d y1', [Index]));
  AssertSame(X2, Edge.P2.X, Format('Edge %d x2', [Index]));
  AssertSame(Y2, Edge.P2.Y, Format('Edge %d y2', [Index]));
  AssertSame(X3, Edge.P3.X, Format('Edge %d x3', [Index]));
  AssertSame(Y3, Edge.P3.Y, Format('Edge %d y3', [Index]));
end;

procedure TTsEdgeClipperTests.AssertEdgesInside(const Edges: TTsClippedEdges);
begin
  for var Index := 0 to Edges.Count - 1 do
  begin
    const Edge = Edges.Items[Index];

    var Count := 2;
    if Edge.Kind = TTsPathEdgeKind.QuadTo then
    begin
      Count := 3;
    end
    else if Edge.Kind = TTsPathEdgeKind.CubicTo then
    begin
      Count := 4;
    end;

    var Points: TTsPoints4;
    Points[0] := Edge.P0;
    Points[1] := Edge.P1;
    Points[2] := Edge.P2;
    Points[3] := Edge.P3;

    for var PointIndex := 0 to Count - 1 do
    begin
      Assert.IsTrue((Points[PointIndex].X >= 0) and (Points[PointIndex].X <= 100), Format('Edge %d point %d: x %f', [Index, PointIndex, Points[PointIndex].X]));
      Assert.IsTrue((Points[PointIndex].Y >= 0) and (Points[PointIndex].Y <= 100), Format('Edge %d point %d: y %f', [Index, PointIndex, Points[PointIndex].Y]));
    end;
  end;
end;

procedure TTsEdgeClipperTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsEdgeClipperTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsEdgeClipperTests.TestLineAboveOrBelowTheClipIsDropped;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(0, TTsLineClipper.Clip(Segment(0, -10, 50, -5), ClipRect, False, Points), 'Above');
  Assert.AreEqual(0, TTsLineClipper.Clip(Segment(0, 100, 50, 150), ClipRect, False, Points), 'Below, touching the bottom');
  Assert.AreEqual(0, TTsLineClipper.Clip(Segment(0, 0, 50, 0), ClipRect, False, Points), 'A horizontal line on the top has no height');
end;

procedure TTsEdgeClipperTests.TestLineInsideTheClipIsKept;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(2, TTsLineClipper.Clip(Segment(10, 10, 50, 60), ClipRect, False, Points));
  AssertPoint(Pt(10, 10), Points[0], 'First');
  AssertPoint(Pt(50, 60), Points[1], 'Second');
end;

procedure TTsEdgeClipperTests.TestLineCrossingTheTopIsCutAtTheTop;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(2, TTsLineClipper.Clip(Segment(10, -10, 10, 40), ClipRect, False, Points));
  AssertPoint(Pt(10, 0), Points[0], 'First');
  AssertPoint(Pt(10, 40), Points[1], 'Second');

  Assert.AreEqual(2, TTsLineClipper.Clip(Segment(0, -50, 50, 50), ClipRect, False, Points));
  AssertPoint(Pt(25, 0), Points[0], 'Slanted first');
  AssertPoint(Pt(50, 50), Points[1], 'Slanted second');
end;

procedure TTsEdgeClipperTests.TestLineLeftOfTheClipGetsAVerticalPart;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(3, TTsLineClipper.Clip(Segment(-50, 10, 50, 60), ClipRect, False, Points));
  AssertPoint(Pt(0, 10), Points[0], 'Vertical start');
  AssertPoint(Pt(0, 35), Points[1], 'Vertical end');
  AssertPoint(Pt(50, 60), Points[2], 'End');

  Assert.AreEqual(2, TTsLineClipper.Clip(Segment(-50, 10, -10, 60), ClipRect, False, Points), 'Wholly to the left');
  AssertPoint(Pt(0, 10), Points[0], 'Wholly left first');
  AssertPoint(Pt(0, 60), Points[1], 'Wholly left second');
end;

procedure TTsEdgeClipperTests.TestLineRunningRightToLeftKeepsItsDirection;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(3, TTsLineClipper.Clip(Segment(50, 60, -50, 10), ClipRect, False, Points));
  AssertPoint(Pt(50, 60), Points[0], 'Start');
  AssertPoint(Pt(0, 35), Points[1], 'Vertical start');
  AssertPoint(Pt(0, 10), Points[2], 'Vertical end');
end;

procedure TTsEdgeClipperTests.TestLineRightOfTheClipIsVerticalOrCulled;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(2, TTsLineClipper.Clip(Segment(150, 10, 200, 60), ClipRect, False, Points));
  AssertPoint(Pt(100, 10), Points[0], 'First');
  AssertPoint(Pt(100, 60), Points[1], 'Second');

  Assert.AreEqual(0, TTsLineClipper.Clip(Segment(150, 10, 200, 60), ClipRect, True, Points), 'Culled to the right');
end;

procedure TTsEdgeClipperTests.TestLineThroughBothSidesGivesThreeSegments;
begin
  var Points: TTsPoints4;
  Assert.AreEqual(4, TTsLineClipper.Clip(Segment(-100, 20, 200, 80), ClipRect, False, Points));

  // vertical on the left, the part inside, vertical on the right
  Assert.AreEqual(Single(0), Points[0].X);
  Assert.AreEqual(Single(0), Points[1].X);
  Assert.AreEqual(Single(100), Points[2].X);
  Assert.AreEqual(Single(100), Points[3].X);
  Assert.AreEqual(Single(20), Points[0].Y, 0.001);
  Assert.AreEqual(Single(40), Points[1].Y, 0.001);
  Assert.AreEqual(Single(60), Points[2].Y, 0.001);
  Assert.AreEqual(Single(80), Points[3].Y, 0.001);
end;

procedure TTsEdgeClipperTests.TestIntersectKeepsInsideAndRejectsOutside;
begin
  var Dst: TTsPoints2;
  Assert.IsTrue(TTsLineClipper.Intersect(Segment(10, 10, 50, 60), ClipRect, Dst));
  AssertPoint(Pt(10, 10), Dst[0], 'First');
  AssertPoint(Pt(50, 60), Dst[1], 'Second');

  Assert.IsFalse(TTsLineClipper.Intersect(Segment(-50, 10, -10, 60), ClipRect, Dst), 'Left');
  Assert.IsFalse(TTsLineClipper.Intersect(Segment(10, 150, 50, 160), ClipRect, Dst), 'Below');
end;

procedure TTsEdgeClipperTests.TestIntersectCutsAtTheBorders;
begin
  var Dst: TTsPoints2;
  Assert.IsTrue(TTsLineClipper.Intersect(Segment(-50, 50, 150, 50), ClipRect, Dst));
  AssertPoint(Pt(0, 50), Dst[0], 'Left border');
  AssertPoint(Pt(100, 50), Dst[1], 'Right border');
end;

procedure TTsEdgeClipperTests.TestClipperLineOutsideGivesNoEdges;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsFalse(Clipper.TryClipLine(Pt(0, -10), Pt(50, -5), Edges));
  Assert.AreEqual(0, Edges.Count);

  Clipper := TTsEdgeClipper.Create(ClipRect, False);
  Assert.IsTrue(Clipper.TryClipLine(Pt(-100, 20), Pt(200, 80), Edges));
  Assert.AreEqual(3, Edges.Count, 'Vertical, inside, vertical');
  AssertEdgesInside(Edges);
end;

procedure TTsEdgeClipperTests.TestQuadInsideIsKept;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipQuad(Pt(10, 10), Pt(30, 20), Pt(50, 60), Edges));
  Assert.AreEqual(1, Edges.Count);
  Assert.IsTrue(Edges.Items[0].Kind = TTsPathEdgeKind.QuadTo);
  AssertPoint(Pt(10, 10), Edges.Items[0].P0, 'P0');
  AssertPoint(Pt(30, 20), Edges.Items[0].P1, 'P1');
  AssertPoint(Pt(50, 60), Edges.Items[0].P2, 'P2');
end;

procedure TTsEdgeClipperTests.TestQuadLeftOfTheClipStartsWithAVerticalLine;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipQuad(Pt(-50, 10), Pt(-10, 30), Pt(50, 60), Edges));
  Assert.AreEqual(2, Edges.Count);

  Assert.IsTrue(Edges.Items[0].Kind = TTsPathEdgeKind.LineTo);
  Assert.AreEqual(Single(0), Edges.Items[0].P0.X);
  Assert.AreEqual(Single(0), Edges.Items[0].P1.X);

  Assert.IsTrue(Edges.Items[1].Kind = TTsPathEdgeKind.QuadTo);
  Assert.AreEqual(Single(0), Edges.Items[1].P0.X, 'The quad starts on the clip border');
  Assert.AreEqual(Edges.Items[0].P1.Y, Edges.Items[1].P0.Y, 0.001, 'The quad continues where the vertical line ends');
  AssertEdgesInside(Edges);

  // The edges of tiny-skia v0.12.0
  AssertLineEdge(Edges, 0, 0, 10, 0, 35);
  AssertQuadEdge(Edges, 1, 0, 35, 22.970585, 46.48529, 50, 60);
end;

procedure TTsEdgeClipperTests.TestQuadAboveTheClipIsDropped;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsFalse(Clipper.TryClipQuad(Pt(10, -50), Pt(30, -20), Pt(50, -10), Edges));
end;

procedure TTsEdgeClipperTests.TestQuadWithExtremaIsCutIntoMonotonicPieces;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  // x and y both turn
  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipQuad(Pt(10, 10), Pt(90, 50), Pt(10, 10), Edges));
  AssertEdgesInside(Edges);

  // The pieces of tiny-skia v0.12.0, cut where x and y turn (50, 30)
  Assert.AreEqual(2, Edges.Count);
  AssertQuadEdge(Edges, 0, 10, 10, 50, 30, 50, 30);
  AssertQuadEdge(Edges, 1, 50, 30, 50, 30, 10, 10);
end;

procedure TTsEdgeClipperTests.TestCubicInsideIsKept;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipCubic(Pt(10, 10), Pt(20, 30), Pt(40, 50), Pt(50, 90), Edges));
  Assert.AreEqual(1, Edges.Count);
  Assert.IsTrue(Edges.Items[0].Kind = TTsPathEdgeKind.CubicTo);
  AssertPoint(Pt(10, 10), Edges.Items[0].P0, 'P0');
  AssertPoint(Pt(50, 90), Edges.Items[0].P3, 'P3');
end;

procedure TTsEdgeClipperTests.TestCubicCrossingTheTopStaysInsideTheClip;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipCubic(Pt(10, -50), Pt(30, -50), Pt(30, 50), Pt(10, 50), Edges));
  AssertEdgesInside(Edges);

  // The part below the top, as tiny-skia v0.12.0 chops it
  Assert.AreEqual(1, Edges.Count);
  AssertCubicEdge(Edges, 0, 25, 0, 25, 25, 20, 50, 10, 50);
end;

procedure TTsEdgeClipperTests.TestCubicTooBigForFloatMathBecomesALine;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipCubic(Pt(10, -5E6), Pt(30, 20), Pt(30, 50), Pt(60, 5E6), Edges));
  AssertEdgesInside(Edges);

  // One line from the top to the bottom, as tiny-skia v0.12.0 gives
  Assert.AreEqual(1, Edges.Count, 'Only one line is left');
  AssertLineEdge(Edges, 0, 35, 0, 35.0005, 100);
end;

procedure TTsEdgeClipperTests.TestCubicCrossingBothSidesStaysInsideTheClip;
begin
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);

  var Edges: TTsClippedEdges;
  Assert.IsTrue(Clipper.TryClipCubic(Pt(-60, 10), Pt(-20, 40), Pt(120, 60), Pt(160, 90), Edges));
  AssertEdgesInside(Edges);

  // Left vertical, the cubic, right vertical, as tiny-skia v0.12.0 gives
  Assert.AreEqual(3, Edges.Count);
  AssertLineEdge(Edges, 0, 0, 10, 0, 35.655018);
  AssertCubicEdge(Edges, 1, 0, 35.655018, 31.564827, 45.42106, 68.53052, 54.640713, 100, 64.40915);
  AssertLineEdge(Edges, 2, 100, 64.40915, 100, 90);
end;

procedure TTsEdgeClipperTests.TestChopMonoCubicAtYFindsTheCrossing;
begin
  // a cubic that is a straight line with even steps: y(t) = 90 t
  var Src: TTsPoints4;
  Src[0] := Pt(0, 0);
  Src[1] := Pt(10, 30);
  Src[2] := Pt(20, 60);
  Src[3] := Pt(30, 90);

  var Dst: TTsPoints7;
  Assert.IsTrue(TTsPathGeometry.ChopMonoCubicAtY(Src, 45, Dst));
  AssertPoint(Pt(0, 0), Dst[0], 'Start');
  AssertPoint(Pt(15, 45), Dst[3], 'The chop point');
  AssertPoint(Pt(30, 90), Dst[6], 'End');
end;

procedure TTsEdgeClipperTests.TestChopMonoCubicAtXFindsTheCrossing;
begin
  // x(t) = 30 t
  var Src: TTsPoints4;
  Src[0] := Pt(0, 0);
  Src[1] := Pt(10, 0);
  Src[2] := Pt(20, 10);
  Src[3] := Pt(30, 10);

  var Dst: TTsPoints7;
  Assert.IsTrue(TTsPathGeometry.ChopMonoCubicAtX(Src, 15, Dst));
  AssertPoint(Pt(15, 5), Dst[3], 'The chop point');
end;

procedure TTsEdgeClipperTests.TestChopMonoCubicAtYWithoutACrossingFails;
begin
  var Src: TTsPoints4;
  Src[0] := Pt(0, 0);
  Src[1] := Pt(10, 30);
  Src[2] := Pt(20, 60);
  Src[3] := Pt(30, 90);

  var Dst: TTsPoints7;
  Assert.IsFalse(TTsPathGeometry.ChopMonoCubicAtY(Src, 500, Dst));
end;

procedure TTsEdgeClipperTests.TestHugeSegmentsGiveTheEdgesOfTinySkia;
begin
  const Big: Single = 1.5E38;
  var Edges: TTsClippedEdges;

  // The edges of tiny-skia v0.12.0 for the same segments
  var Clipper := TTsEdgeClipper.Create(ClipRect, False);
  Assert.IsTrue(Clipper.TryClipLine(Pt(-Big, -Big), Pt(Big, Big), Edges));
  Assert.AreEqual(1, Edges.Count, 'Line');
  AssertLineEdge(Edges, 0, 0, 0, 0, 100);

  Clipper := TTsEdgeClipper.Create(ClipRect, False);
  Assert.IsTrue(Clipper.TryClipQuad(Pt(-Big, 10), Pt(Big, Big), Pt(Big, 50), Edges));
  Assert.AreEqual(2, Edges.Count, 'Quad');
  AssertLineEdge(Edges, 0, 0, 10, 0, 100);
  AssertLineEdge(Edges, 1, 100, 100, 100, 50);

  Clipper := TTsEdgeClipper.Create(ClipRect, False);
  Assert.IsTrue(Clipper.TryClipCubic(Pt(-Big, 10), Pt(Big, Big), Pt(-Big, 70), Pt(Big, 50), Edges));
  Assert.AreEqual(3, Edges.Count, 'Cubic');
  AssertLineEdge(Edges, 0, 0, 10, 0, 30);
  AssertLineEdge(Edges, 1, 0, 30, 100, 30);
  AssertLineEdge(Edges, 2, 100, 30, 100, 50);

  // just below the limit of what float math can still handle: a cubic is left
  Clipper := TTsEdgeClipper.Create(ClipRect, False);
  Assert.IsTrue(Clipper.TryClipCubic(Pt(-4E6, 10), Pt(4E6, 20), Pt(-4E6, 70), Pt(4E6, 50), Edges));
  Assert.AreEqual(6, Edges.Count, 'Cubic of 4e6');
  AssertLineEdge(Edges, 0, 0, 10, 0, 41.247395);
  AssertLineEdge(Edges, 1, 0, 41.247395, 0, 41.2526);
  AssertLineEdge(Edges, 2, 0, 41.2526, 0, 41.30439);
  AssertCubicEdge(Edges, 3, 0, 41.30439, 0.28660193, 41.614784, 5.4937034, 41.9223, 100, 42.226646);
  AssertLineEdge(Edges, 4, 100, 42.226646, 100, 54.677044);
  AssertLineEdge(Edges, 5, 100, 54.677044, 100, 50);
end;

procedure TTsEdgeClipperTests.TestClipperIterGivesTheEdgesOfEverySegment;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.LineTo(50, 10);
  Builder.LineTo(50, 50);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Iter := TTsEdgeClipperIter.Create(Path, ClipRect, False);
  var Results := 0;
  var Total := 0;

  var Edges: TTsClippedEdges;
  while Iter.TryNext(Edges) do
  begin
    Inc(Results);
    Inc(Total, Edges.Count);
    AssertEdgesInside(Edges);
  end;

  Assert.AreEqual(3, Results, 'Two lines and the closing line');
  Assert.AreEqual(3, Total);
end;

{ TTsPath64Tests }

procedure TTsPath64Tests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsPath64Tests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsPath64Tests.TestBoundReturnsMaxForNan;
begin
  Assert.AreEqual(Double(1.0), TTsScalar64.Bound(NaN, 0.0, 1.0));
  Assert.AreEqual(Double(1.0), TTsScalar64.Bound(Infinity, 0.0, 1.0));
  Assert.AreEqual(Double(0.0), TTsScalar64.Bound(-5.0, 0.0, 1.0));
  Assert.AreEqual(Double(0.25), TTsScalar64.Bound(0.25, 0.0, 1.0));
end;

procedure TTsPath64Tests.TestApproximateComparisons;
begin
  Assert.IsTrue(TTsScalar64.ApproximatelyZero(1E-17));
  Assert.IsFalse(TTsScalar64.ApproximatelyZero(1E-15));
  Assert.IsTrue(TTsScalar64.ApproximatelyEqual(0.5, 0.5 + 1E-17));
  Assert.IsTrue(TTsScalar64.ApproximatelyZeroOrMore(-1E-17));
  Assert.IsFalse(TTsScalar64.ApproximatelyZeroOrMore(-1E-10));
  Assert.IsTrue(TTsScalar64.ApproximatelyOneOrLess(1.0 + 1E-17));
  Assert.IsFalse(TTsScalar64.ApproximatelyOneOrLess(1.001));
  Assert.IsTrue(TTsScalar64.ApproximatelyEqualHalf(1.0, 1.0 + 1E-9));
  Assert.IsTrue(TTsScalar64.Between(0.5, 0.0, 1.0));
  Assert.IsTrue(TTsScalar64.Between(0.5, 1.0, 0.0));
  Assert.IsFalse(TTsScalar64.Between(1.5, 0.0, 1.0));
  Assert.IsTrue(TTsScalar64.AlmostDequalUlps(1.0, 1.0 + 1E-9));
  Assert.IsFalse(TTsScalar64.AlmostDequalUlps(1.0, 1.001));
  Assert.IsTrue(TTsScalar64.AlmostDequalUlps(1E300, 1E300 * (1.0 + 1E-9)), 'Beyond the range of f32 the relative difference counts');
end;

procedure TTsPath64Tests.TestCubeRoot;
begin
  Assert.AreEqual(3.0, TTsPath64.CubeRoot(27.0), 1E-9);
  Assert.AreEqual(-2.0, TTsPath64.CubeRoot(-8.0), 1E-9);
  Assert.AreEqual(0.5, TTsPath64.CubeRoot(0.125), 1E-9);
  Assert.AreEqual(Double(0.0), TTsPath64.CubeRoot(1E-30), 'Too small to matter');
end;

procedure TTsPath64Tests.TestQuadRootsReal;
begin
  var S: TTsDoubles3;
  S[0] := 0.0;
  S[1] := 0.0;
  S[2] := 0.0;

  // x^2 - 3x + 2
  Assert.AreEqual(2, TTsQuad64.RootsReal(1.0, -3.0, 2.0, S));
  Assert.AreEqual(2.0, S[0], 1E-12);
  Assert.AreEqual(1.0, S[1], 1E-12);

  // x^2 + 1 has no real root
  Assert.AreEqual(0, TTsQuad64.RootsReal(1.0, 0.0, 1.0, S));

  // x^2 - 2x + 1 has a double root
  Assert.AreEqual(1, TTsQuad64.RootsReal(1.0, -2.0, 1.0, S));
  Assert.AreEqual(1.0, S[0], 1E-12);
end;

procedure TTsPath64Tests.TestQuadRootsValidTKeepsTheRootsInZeroToOne;
begin
  var T: TTsDoubles3;
  T[0] := 0.0;
  T[1] := 0.0;
  T[2] := 0.0;

  // roots 0.25 and 3
  Assert.AreEqual(1, TTsQuad64.RootsValidT(1.0, -3.25, 0.75, T));
  Assert.AreEqual(0.25, T[0], 1E-12);
end;

procedure TTsPath64Tests.TestQuadDegenerateToALine;
begin
  var S: TTsDoubles3;
  S[0] := 0.0;
  S[1] := 0.0;
  S[2] := 0.0;

  // 2x - 1 = 0
  Assert.AreEqual(1, TTsQuad64.RootsReal(0.0, 2.0, -1.0, S));
  Assert.AreEqual(0.5, S[0], 1E-12);

  // 0 = 0 has the root 0 only for c = 0
  Assert.AreEqual(1, TTsQuad64.RootsReal(0.0, 0.0, 0.0, S));
  Assert.AreEqual(0, TTsQuad64.RootsReal(0.0, 0.0, 1.0, S));
end;

procedure TTsPath64Tests.TestPointAtT;
begin
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(0, 0), TTsPoint64.FromXY(0, 10), TTsPoint64.FromXY(10, 20), TTsPoint64.FromXY(10, 30)]);

  Assert.AreEqual(0.0, Cubic.PointAtT(0.0).X, 0.0);
  Assert.AreEqual(30.0, Cubic.PointAtT(1.0).Y, 0.0);
  Assert.AreEqual(5.0, Cubic.PointAtT(0.5).X, 1E-12);
  Assert.AreEqual(15.0, Cubic.PointAtT(0.5).Y, 1E-12);
end;

procedure TTsPath64Tests.TestChopAtHalfAndAtT;
begin
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(0, 0), TTsPoint64.FromXY(0, 10), TTsPoint64.FromXY(10, 20), TTsPoint64.FromXY(10, 30)]);

  const Half = Cubic.ChopAt(0.5);
  Assert.AreEqual(5.0, Half.Points[3].X, 1E-12);
  Assert.AreEqual(15.0, Half.Points[3].Y, 1E-12);

  // the t interpolation agrees with the t = 0.5 formulas
  const Quarter = Cubic.ChopAt(0.25);
  const Expected = Cubic.PointAtT(0.25);
  Assert.AreEqual(Expected.X, Quarter.Points[3].X, 1E-12);
  Assert.AreEqual(Expected.Y, Quarter.Points[3].Y, 1E-12);
  Assert.AreEqual(0.0, Quarter.Points[0].X, 0.0);
  Assert.AreEqual(10.0, Quarter.Points[6].X, 0.0);
end;

procedure TTsPath64Tests.TestVerticalIntersect;
begin
  // x(t) = 30 t
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(0, 0), TTsPoint64.FromXY(10, 0), TTsPoint64.FromXY(20, 10), TTsPoint64.FromXY(30, 10)]);

  var Roots: TTsDoubles3;
  Roots[0] := 0.0;
  Roots[1] := 0.0;
  Roots[2] := 0.0;

  Assert.AreEqual(1, TTsLineCubicIntersections.VerticalIntersect(Cubic, 15.0, Roots));
  Assert.AreEqual(0.5, Roots[0], 1E-9);
end;

procedure TTsPath64Tests.TestSearchGivesUpWhereRustDoes;
begin
  // x(t) = 30 t^2 - 20 t^3 gives x(0.5) = 5, but the root of the cubic equation is not exact, so the binary search takes over. The
  // approximately_equal_half of the source has no abs: for a rising curve the point below always counts as equal and the search ends
  // without a root. This is what Rust does as well.
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(0, 0), TTsPoint64.FromXY(0, 10), TTsPoint64.FromXY(10, 20), TTsPoint64.FromXY(10, 30)]);

  var Roots: TTsDoubles3;
  Roots[0] := 0.0;
  Roots[1] := 0.0;
  Roots[2] := 0.0;

  Assert.AreEqual(0, TTsLineCubicIntersections.VerticalIntersect(Cubic, 5.0, Roots));

  // The results of tiny-skia v0.12.0 for the same cubic at other x: only the intercept 9 gives a root
  Assert.AreEqual(0, TTsLineCubicIntersections.VerticalIntersect(Cubic, 2.0, Roots));
  Assert.AreEqual(0, TTsLineCubicIntersections.VerticalIntersect(Cubic, 7.5, Roots));
  Assert.AreEqual(0, TTsLineCubicIntersections.VerticalIntersect(Cubic, 1.0, Roots));
  Assert.AreEqual(1, TTsLineCubicIntersections.VerticalIntersect(Cubic, 9.0, Roots));
  Assert.AreEqual(0.8041998943409083, Roots[0], 1E-15, 'The root, up to the last bits of the RTL cosine');

  Assert.AreEqual(1, TTsLineCubicIntersections.HorizontalIntersect(Cubic, 22.5, Roots));
  Assert.AreEqual(0.75, Roots[0], 1E-15);
  Assert.AreEqual(1, TTsLineCubicIntersections.HorizontalIntersect(Cubic, 3.0, Roots));
  Assert.AreEqual(0.1, Roots[0], 1E-15);
  Assert.AreEqual(0, TTsLineCubicIntersections.HorizontalIntersect(Cubic, 6.0, Roots));
  Assert.AreEqual(0, TTsLineCubicIntersections.HorizontalIntersect(Cubic, 27.0, Roots));
end;

procedure TTsPath64Tests.TestHorizontalIntersect;
begin
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(0, 0), TTsPoint64.FromXY(0, 10), TTsPoint64.FromXY(10, 20), TTsPoint64.FromXY(10, 30)]);

  var Roots: TTsDoubles3;
  Roots[0] := 0.0;
  Roots[1] := 0.0;
  Roots[2] := 0.0;

  Assert.AreEqual(1, TTsLineCubicIntersections.HorizontalIntersect(Cubic, 15.0, Roots));
  Assert.AreEqual(0.5, Roots[0], 1E-9);
end;

procedure TTsPath64Tests.TestIntersectWithNoCrossing;
begin
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(0, 0), TTsPoint64.FromXY(0, 10), TTsPoint64.FromXY(10, 20), TTsPoint64.FromXY(10, 30)]);

  var Roots: TTsDoubles3;
  Roots[0] := 0.0;
  Roots[1] := 0.0;
  Roots[2] := 0.0;

  Assert.AreEqual(0, TTsLineCubicIntersections.VerticalIntersect(Cubic, 50.0, Roots));
  Assert.AreEqual(0, TTsLineCubicIntersections.HorizontalIntersect(Cubic, -20.0, Roots));
end;

procedure TTsPath64Tests.TestNanPointsDoNotHang;
begin
  const Cubic = TTsCubic64.Create([TTsPoint64.FromXY(NaN, 0), TTsPoint64.FromXY(0, NaN), TTsPoint64.FromXY(10, 20), TTsPoint64.FromXY(NaN, NaN)]);

  var ExtremeTs: TTsDoubles6;
  FillChar(ExtremeTs, SizeOf(ExtremeTs), 0);

  var Roots: TTsDoubles3;
  Roots[0] := 0.0;
  Roots[1] := 0.0;
  Roots[2] := 0.0;

  // the result does not matter, the search has to end
  Cubic.SearchRoots(0, 5.0, TTsSearchAxis.X, ExtremeTs, Roots);
  TTsLineCubicIntersections.VerticalIntersect(Cubic, 5.0, Roots);
  TTsLineCubicIntersections.HorizontalIntersect(Cubic, 5.0, Roots);
  Assert.Pass;
end;

end.
