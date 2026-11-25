// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/edge.rs and src/edge_builder.rs
unit Pdf4D.Render.Native.EdgeBuilder.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Edge,
  Pdf4D.Render.Native.EdgeClipper,
  Pdf4D.Render.Native.EdgeBuilder;

type
  [TestFixture]
  TTsEdgeBuilderTests = class
  private
    FFloatState: TTsFloatState;

    function Pt(const X, Y: Single): TTsPoint;
    function RectPath(const Left, Top, Right, Bottom: Single): TTsPath;
    function ClipOf(const Width, Height: Cardinal; const Shift: Integer): TTsShiftedIntRect;
    function Build(const Path: TTsPath; const Shift: Integer; out Edges: TArray<TTsEdge>): Boolean;
    procedure AssertEdgesInsideClip(const Edges: TArray<TTsEdge>; const Width, Height: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRectGivesTwoLineEdges;

    [Test]
    procedure TestEdgeLeftOfClipBecomesVerticalAtBorder;

    [Test]
    procedure TestHugeCoordinatesAreClipped;

    [Test]
    procedure TestCubicIsChoppedAtClipTop;

    [Test]
    procedure TestAntiAliasShiftScalesRows;

    [Test]
    procedure TestEmptyOrDegeneratePathGivesNoEdges;

    [Test]
    procedure TestLineEdgeValues;

    [Test]
    procedure TestLineEdgeOfZeroHeightFails;

    [Test]
    procedure TestVerticalLinesWithTheSameWindingMerge;

    [Test]
    procedure TestOppositeVerticalLinesCancel;

    [Test]
    procedure TestQuadraticEdgeIsBuiltAndSteppedToTheEnd;

    [Test]
    procedure TestCubicEdgeIsBuiltAndSteppedToTheEnd;

    [Test]
    procedure TestUnclippedBuildChopsAtYExtrema;

    [Test]
    procedure TestUnclippedBuildOfARect;

    [Test]
    procedure TestShiftOutOfRangeGivesNoEdges;

    [Test]
    procedure TestShiftedIntRectShiftsAndRecovers;

    [Test]
    procedure TestShiftedIntRectRejectsWhatDoesNotFit;

    [Test]
    procedure TestPathEdgeIterAutoClosesEveryContour;

    [Test]
    procedure TestHugeFiniteCoordinatesDoNotRaise;

    [Test]
    procedure TestHugeCubicDoesNotRaise;

    [Test]
    procedure TestMillionsOfSegmentsStayLinear;
  end;

implementation

{ TTsEdgeBuilderTests }

function TTsEdgeBuilderTests.Pt(const X, Y: Single): TTsPoint;
begin
  Result := TTsPoint.FromXY(X, Y);
end;

function TTsEdgeBuilderTests.RectPath(const Left, Top, Right, Bottom: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(Left, Top);
  Builder.LineTo(Right, Top);
  Builder.LineTo(Right, Bottom);
  Builder.LineTo(Left, Bottom);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The rect path');
end;

function TTsEdgeBuilderTests.ClipOf(const Width, Height: Cardinal; const Shift: Integer): TTsShiftedIntRect;
begin
  var Rect: TTsScreenIntRect;
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(0, 0, Width, Height, Rect), 'The clip rect');
  Assert.IsTrue(TTsShiftedIntRect.TryCreate(Rect, Shift, Result), 'The shifted clip rect');
end;

function TTsEdgeBuilderTests.Build(const Path: TTsPath; const Shift: Integer; out Edges: TArray<TTsEdge>): Boolean;
begin
  Result := TTsBasicEdgeBuilder.TryBuildEdges(Path, ClipOf(100, 100, Shift), Shift, Edges);
end;

procedure TTsEdgeBuilderTests.AssertEdgesInsideClip(const Edges: TArray<TTsEdge>; const Width, Height: Integer);
begin
  const MaxX = Width * 65536;

  for var Index := 0 to High(Edges) do
  begin
    const Line = Edges[Index].Line;
    Assert.IsTrue((Line.X >= 0) and (Line.X <= MaxX), Format('Edge %d: x %d inside the clip', [Index, Line.X]));
    Assert.IsTrue((Line.FirstY >= 0) and (Line.FirstY < Height), Format('Edge %d: first y %d inside the clip', [Index, Line.FirstY]));
    Assert.IsTrue((Line.LastY >= Line.FirstY) and (Line.LastY < Height), Format('Edge %d: last y %d inside the clip', [Index, Line.LastY]));
    Assert.IsTrue(Abs(Line.Winding) = 1, 'The winding is 1 or -1');
  end;
end;

procedure TTsEdgeBuilderTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsEdgeBuilderTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsEdgeBuilderTests.TestRectGivesTwoLineEdges;
begin
  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(RectPath(10, 10, 20, 20), 0, Edges));

  Assert.AreEqual(2, Integer(Length(Edges)), 'The horizontal edges have no height');
  Assert.IsTrue(Edges[0].Kind = TTsEdgeKind.Line);
  Assert.IsTrue(Edges[1].Kind = TTsEdgeKind.Line);

  // the right edge goes down, the left edge goes up
  Assert.AreEqual(1, Integer(Edges[0].Line.Winding));
  Assert.AreEqual(20 * 65536, Edges[0].Line.X);
  Assert.AreEqual(0, Edges[0].Line.Dx);
  Assert.AreEqual(10, Edges[0].Line.FirstY);
  Assert.AreEqual(19, Edges[0].Line.LastY);

  Assert.AreEqual(-1, Integer(Edges[1].Line.Winding));
  Assert.AreEqual(10 * 65536, Edges[1].Line.X);
  Assert.AreEqual(10, Edges[1].Line.FirstY);
  Assert.AreEqual(19, Edges[1].Line.LastY);
end;

procedure TTsEdgeBuilderTests.TestEdgeLeftOfClipBecomesVerticalAtBorder;
begin
  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(RectPath(-50, 10, 20, 20), 0, Edges));

  Assert.AreEqual(2, Integer(Length(Edges)));
  Assert.AreEqual(20 * 65536, Edges[0].Line.X);
  Assert.AreEqual(0, Edges[1].Line.X, 'The left edge sits on the clip border');
  Assert.AreEqual(0, Edges[1].Line.Dx);
  Assert.AreEqual(10, Edges[1].Line.FirstY);
  Assert.AreEqual(19, Edges[1].Line.LastY);
  Assert.AreEqual(-1, Integer(Edges[1].Line.Winding));
end;

procedure TTsEdgeBuilderTests.TestHugeCoordinatesAreClipped;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(-1E30, 5);
  Builder.LineTo(1E30, 50);
  Builder.LineTo(0, 90);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(Path, 0, Edges));
  Assert.IsTrue(Length(Edges) >= 2);
  AssertEdgesInsideClip(Edges, 100, 100);
end;

procedure TTsEdgeBuilderTests.TestCubicIsChoppedAtClipTop;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, -50);
  Builder.CubicTo(30, -50, 30, 50, 10, 50);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(Path, 0, Edges));

  var CubicCount := 0;
  for var Index := 0 to High(Edges) do
  begin
    if Edges[Index].Kind = TTsEdgeKind.Cubic then
    begin
      Inc(CubicCount);
    end;
  end;

  Assert.IsTrue(CubicCount >= 1, 'The part of the cubic inside the clip is kept');
  AssertEdgesInsideClip(Edges, 100, 100);
end;

procedure TTsEdgeBuilderTests.TestAntiAliasShiftScalesRows;
begin
  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(RectPath(10, 10, 20, 20), 2, Edges));

  Assert.AreEqual(2, Integer(Length(Edges)));
  Assert.AreEqual(40, Edges[0].Line.FirstY);
  Assert.AreEqual(79, Edges[0].Line.LastY);
  Assert.AreEqual(40, Edges[1].Line.FirstY);
  Assert.AreEqual(79, Edges[1].Line.LastY);
  Assert.AreEqual(80 * 65536, Edges[0].Line.X, 'The x is in the supersampled units too');
end;

procedure TTsEdgeBuilderTests.TestEmptyOrDegeneratePathGivesNoEdges;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 5);
  Builder.LineTo(50, 5);

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsFalse(Build(Path, 0, Edges));
  Assert.AreEqual(0, Integer(Length(Edges)));
end;

procedure TTsEdgeBuilderTests.TestLineEdgeValues;
begin
  var Edge: TTsLineEdge;
  Assert.IsTrue(TTsLineEdge.TryCreate(Pt(0, 0), Pt(10, 20), 0, Edge));

  // x at the center of the first row (y = 0.5) is 0.25 pixels
  Assert.AreEqual(16384, Edge.X);
  Assert.AreEqual(32768, Edge.Dx);
  Assert.AreEqual(0, Edge.FirstY);
  Assert.AreEqual(19, Edge.LastY);
  Assert.AreEqual(1, Integer(Edge.Winding));
  Assert.IsFalse(Edge.IsVertical);
  Assert.AreEqual(TTsLineEdge.NoLink, Edge.Prev);
  Assert.AreEqual(TTsLineEdge.NoLink, Edge.Next);

  // the same line upwards is the same edge with the other winding
  var Up: TTsLineEdge;
  Assert.IsTrue(TTsLineEdge.TryCreate(Pt(10, 20), Pt(0, 0), 0, Up));
  Assert.AreEqual(-1, Integer(Up.Winding));
  Assert.AreEqual(Edge.X, Up.X);
  Assert.AreEqual(Edge.Dx, Up.Dx);
end;

procedure TTsEdgeBuilderTests.TestLineEdgeOfZeroHeightFails;
begin
  var Edge: TTsLineEdge;
  Assert.IsFalse(TTsLineEdge.TryCreate(Pt(0, 5), Pt(10, 5), 0, Edge));
  Assert.IsFalse(TTsLineEdge.TryCreate(Pt(0, 5.1), Pt(10, 5.3), 0, Edge), 'Both ends round to the same row');
  Assert.IsFalse(TTsLineEdge.TryCreate(Pt(0, 0), Pt(10, 20), -1, Edge), 'A negative shift');
  Assert.IsFalse(TTsLineEdge.TryCreate(Pt(0, 0), Pt(10, 20), TTsLineEdge.MaxShift + 1, Edge), 'A shift that is too large');
end;

procedure TTsEdgeBuilderTests.TestVerticalLinesWithTheSameWindingMerge;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.LineTo(10, 20);
  Builder.LineTo(10, 30);
  Builder.LineTo(30, 30);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(Path, 0, Edges));

  Assert.AreEqual(2, Integer(Length(Edges)), 'The two vertical lines are one edge, the diagonal is the other');
  Assert.AreEqual(10, Edges[0].Line.FirstY);
  Assert.AreEqual(29, Edges[0].Line.LastY);
  Assert.AreEqual(1, Integer(Edges[0].Line.Winding));
  Assert.AreEqual(-1, Integer(Edges[1].Line.Winding));
end;

procedure TTsEdgeBuilderTests.TestOppositeVerticalLinesCancel;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.LineTo(10, 20);
  Builder.LineTo(10, 10);
  Builder.Close;
  Builder.MoveTo(30, 10);
  Builder.LineTo(30, 20);
  Builder.LineTo(50, 15);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(Path, 0, Edges));

  Assert.AreEqual(3, Integer(Length(Edges)), 'Down and up on the same x cancel each other');
  for var Index := 0 to High(Edges) do
  begin
    Assert.AreNotEqual(10 * 65536, Edges[Index].Line.X, 'Nothing is left of the first contour');
  end;
end;

procedure TTsEdgeBuilderTests.TestQuadraticEdgeIsBuiltAndSteppedToTheEnd;
begin
  var Quad: TTsQuadraticEdge;
  Assert.IsTrue(TTsQuadraticEdge.TryCreate([Pt(10, 10), Pt(30, 30), Pt(10, 50)], 0, 0, Quad));
  Assert.IsTrue(Quad.CurveCount > 0);
  Assert.AreEqual(1, Integer(Quad.Line.Winding));

  // every segment of the curve lies below the one before and the last row is the last row of the curve
  var PreviousLast := Quad.Line.LastY;
  Assert.AreEqual(10, Quad.Line.FirstY);
  while Quad.CurveCount > 0 do
  begin
    if not Quad.Update then
    begin
      Break;
    end;

    Assert.IsTrue(Quad.Line.FirstY > PreviousLast, 'The next segment starts below the last one');
    PreviousLast := Quad.Line.LastY;
  end;

  Assert.AreEqual(49, PreviousLast);
  Assert.IsFalse(Quad.Update, 'No segment is left');
end;

procedure TTsEdgeBuilderTests.TestCubicEdgeIsBuiltAndSteppedToTheEnd;
begin
  var Cubic: TTsCubicEdge;
  Assert.IsTrue(TTsCubicEdge.TryCreate([Pt(10, 10), Pt(40, 20), Pt(0, 40), Pt(30, 70)], 0, 0, Cubic));
  Assert.IsTrue(Cubic.CurveCount < 0);
  Assert.AreEqual(1, Integer(Cubic.Line.Winding));
  Assert.AreEqual(10, Cubic.Line.FirstY);

  var PreviousLast := Cubic.Line.LastY;
  while Cubic.CurveCount < 0 do
  begin
    if not Cubic.Update then
    begin
      Break;
    end;

    Assert.IsTrue(Cubic.Line.FirstY > PreviousLast, 'The next segment starts below the last one');
    PreviousLast := Cubic.Line.LastY;
  end;

  Assert.AreEqual(69, PreviousLast);
  Assert.IsFalse(Cubic.Update, 'No segment is left');
end;

procedure TTsEdgeBuilderTests.TestUnclippedBuildChopsAtYExtrema;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.CubicTo(10, 30, 20, -10, 30, 40);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(Path, 0, Edges));

  var CubicCount := 0;
  for var Index := 0 to High(Edges) do
  begin
    if Edges[Index].Kind = TTsEdgeKind.Cubic then
    begin
      Inc(CubicCount);
    end;
  end;

  Assert.IsTrue(CubicCount >= 2, 'A cubic with two y extrema is cut into monotonic pieces');
end;

procedure TTsEdgeBuilderTests.TestUnclippedBuildOfARect;
begin
  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(RectPath(10, 10, 20, 20), 0, Edges));

  Assert.AreEqual(2, Integer(Length(Edges)));
  Assert.AreEqual(20 * 65536, Edges[0].Line.X);
  Assert.AreEqual(10 * 65536, Edges[1].Line.X);
end;

procedure TTsEdgeBuilderTests.TestShiftOutOfRangeGivesNoEdges;
begin
  var Edges: TArray<TTsEdge>;
  Assert.IsFalse(TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(RectPath(10, 10, 20, 20), -1, Edges));
  Assert.IsFalse(TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(RectPath(10, 10, 20, 20), 99, Edges));
end;

procedure TTsEdgeBuilderTests.TestShiftedIntRectShiftsAndRecovers;
begin
  var Rect: TTsScreenIntRect;
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(3, 5, 100, 200, Rect));

  var Shifted: TTsShiftedIntRect;
  Assert.IsTrue(TTsShiftedIntRect.TryCreate(Rect, 2, Shifted));
  Assert.AreEqual(Cardinal(12), Shifted.Shifted.X);
  Assert.AreEqual(Cardinal(20), Shifted.Shifted.Y);
  Assert.AreEqual(Cardinal(400), Shifted.Shifted.Width);
  Assert.AreEqual(Cardinal(800), Shifted.Shifted.Height);
  Assert.IsTrue(Rect = Shifted.Recover);
end;

procedure TTsEdgeBuilderTests.TestShiftedIntRectRejectsWhatDoesNotFit;
begin
  var Rect: TTsScreenIntRect;
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(0, 0, 1 shl 30, 10, Rect));

  var Shifted: TTsShiftedIntRect;
  Assert.IsFalse(TTsShiftedIntRect.TryCreate(Rect, 2, Shifted), 'The width does not fit in 31 bits after the shift');
  Assert.IsFalse(TTsShiftedIntRect.TryCreate(Rect, -1, Shifted));
  Assert.IsFalse(TTsShiftedIntRect.TryCreate(Rect, TTsLineEdge.MaxShift + 1, Shifted));
end;

procedure TTsEdgeBuilderTests.TestPathEdgeIterAutoClosesEveryContour;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.LineTo(10, 0);
  Builder.MoveTo(20, 20);
  Builder.LineTo(30, 20);

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Iter := TTsPathEdgeIter.Create(Path);
  var Edge: TTsPathEdge;

  Assert.IsTrue(Iter.TryNext(Edge));
  Assert.IsTrue(Edge.Kind = TTsPathEdgeKind.LineTo);
  Assert.IsTrue((Edge.P0 = Pt(0, 0)) and (Edge.P1 = Pt(10, 0)));

  Assert.IsTrue(Iter.TryNext(Edge), 'The first contour is closed before the next one starts');
  Assert.IsTrue((Edge.P0 = Pt(10, 0)) and (Edge.P1 = Pt(0, 0)));

  Assert.IsTrue(Iter.TryNext(Edge));
  Assert.IsTrue((Edge.P0 = Pt(20, 20)) and (Edge.P1 = Pt(30, 20)));

  Assert.IsTrue(Iter.TryNext(Edge), 'The last contour is closed at the end');
  Assert.IsTrue((Edge.P0 = Pt(30, 20)) and (Edge.P1 = Pt(20, 20)));

  Assert.IsFalse(Iter.TryNext(Edge));
end;

procedure TTsEdgeBuilderTests.TestHugeFiniteCoordinatesDoNotRaise;
begin
  const Big: Single = 1.5E38;

  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(-Big, -Big);
  Builder.LineTo(Big, -Big);
  Builder.QuadTo(Big, Big, 0, Big);
  Builder.LineTo(-Big, 50);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  if Build(Path, 0, Edges) then
  begin
    AssertEdgesInsideClip(Edges, 100, 100);
  end;

  if TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(Path, 2, Edges) then
  begin
    Assert.IsTrue(Length(Edges) >= 2);
  end;
end;

procedure TTsEdgeBuilderTests.TestHugeCubicDoesNotRaise;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.CubicTo(1.5E38, 1E38, -1.5E38, 1E38, 5, 5);
  Builder.CubicTo(1E7, 20, -1E7, 40, 50, 60);
  Builder.Close;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  if Build(Path, 2, Edges) then
  begin
    AssertEdgesInsideClip(Edges, 100 shl 2, 100 shl 2);
  end;
end;

procedure TTsEdgeBuilderTests.TestMillionsOfSegmentsStayLinear;
begin
  const SegmentCount = 1000000;

  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 0);
  for var Index := 1 to SegmentCount do
  begin
    if Odd(Index) then
    begin
      Builder.LineTo(90, Index mod 97);
    end
    else
    begin
      Builder.LineTo(10, Index mod 89);
    end;
  end;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Edges: TArray<TTsEdge>;
  Assert.IsTrue(Build(Path, 0, Edges));
  Assert.IsTrue(Length(Edges) <= SegmentCount + 1, 'At most one edge per segment');
  Assert.IsTrue(Length(Edges) > SegmentCount div 2);
  AssertEdgesInsideClip(Edges, 100, 100);
end;

end.
