// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 path/src/stroker.rs (inline tests), and of the stroker around them
unit Pdf4D.Render.Native.Stroker.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Dash,
  Pdf4D.Render.Native.Stroker;

type
  [TestFixture]
  TTsStrokerTests = class
  private
    FFloatState: TTsFloatState;

    function BitsToSingle(const Bits: Cardinal): Single;
    function LinePath(const X0, Y0, X1, Y1: Single): TTsPath;
    function StrokeOf(const Path: TTsPath; const Stroke: TTsStroke; out Stroked: TTsPath): Boolean;
    procedure AssertNextSegment(var Iter: TTsPathSegmentsIter; const Expected: TTsPathSegment);
    function ClosedPath: TTsPath;
    function OpenPath: TTsPath;
    function PathHash(const Path: TTsPath): Cardinal;
    procedure AssertRustReference(const Path: TTsPath; const Width, MiterLimit, ResScale: Single; const Join: TTsLineJoin;
                                  const Cap: TTsLineCap; const ExpectedHash: Cardinal);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestAutoClose;

    [Test]
    procedure TestCubic1;

    [Test]
    procedure TestCubic2;

    [Test]
    procedure TestBig;

    [Test]
    procedure TestQuadStrokerOneOff;

    [Test]
    procedure TestCubicStrokerOneOff;

    [Test]
    procedure TestStrokeOfLineHasExpectedBounds;

    [Test]
    procedure TestSquareCapExtendsBounds;

    [Test]
    procedure TestHugeStrokeWidthIsFinite;

    [Test]
    procedure TestQuadOfHugeControlPointsFailsInsteadOfStrokingNaN;

    [Test]
    procedure TestZeroWidthGivesNoPath;

    [Test]
    procedure TestRoundCapOfPointIsCircle;

    [Test]
    procedure TestButtCapOfPointGivesNoPath;

    [Test]
    procedure TestRoundJoinAndMiterClipJoinStrokeAnAngle;

    [Test]
    procedure TestMiterLimitBelowOneBecomesBevel;

    [Test]
    procedure TestStrokerIsReusable;

    [Test]
    procedure TestComputeResolutionScale;

    [Test]
    procedure TestStrokeWithQuadAndCubicIsFinite;

    [Test]
    procedure TestStrokeOfClosedRectHasInnerAndOuterContour;

    // The expected hashes are of the output of tiny-skia v0.12.0 for the same input: every verb and the bits of every point
    [Test]
    procedure TestRustReferenceClosedRoundJoinRoundCap;

    [Test]
    procedure TestRustReferenceClosedScaledMiterClipSquareCap;

    [Test]
    procedure TestRustReferenceOpenMiterSquareCap;

    [Test]
    procedure TestRustReferenceOpenMiterClipRoundCap;

    [Test]
    procedure TestRustReferenceOpenRoundJoinButtCap;

    [Test]
    procedure TestRustReferenceOpenBevelSquareCap;
  end;

implementation

function TTsStrokerTests.BitsToSingle(const Bits: Cardinal): Single;
begin
  var Copy := Bits;
  Move(Copy, Result, SizeOf(Single));
end;

function TTsStrokerTests.LinePath(const X0, Y0, X1, Y1: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(X0, Y0);
  Builder.LineTo(X1, Y1);

  Assert.IsTrue(Builder.TryFinish(Result), 'The line path');
end;

function TTsStrokerTests.StrokeOf(const Path: TTsPath; const Stroke: TTsStroke; out Stroked: TTsPath): Boolean;
begin
  Result := Path.TryStroke(Stroke, 1, Stroked);
end;

procedure TTsStrokerTests.AssertNextSegment(var Iter: TTsPathSegmentsIter; const Expected: TTsPathSegment);
begin
  var Segment: TTsPathSegment;
  Assert.IsTrue(Iter.TryNext(Segment), 'A segment is expected');
  Assert.IsTrue(Expected = Segment, 'The segment differs');
end;

function TTsStrokerTests.ClosedPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.QuadTo(50, 100, 90, 10);
  Builder.CubicTo(120, 80, 150, -60, 190, 10);
  Builder.LineTo(150, 60);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The closed path');
end;

function TTsStrokerTests.OpenPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.QuadTo(50, 100, 90, 10);
  Builder.CubicTo(120, 80, 150, -60, 190, 10);
  Builder.LineTo(150, 60);
  Builder.LineTo(150, 60);
  Builder.MoveTo(5, 5);
  Builder.LineTo(5, 5);
  Builder.MoveTo(30, 30);
  Builder.CubicTo(80, 30, 10, 30, 60, 30);
  Builder.MoveTo(70, 70);
  Builder.CubicTo(120, 120, 20, 120, 70, 70);

  Assert.IsTrue(Builder.TryFinish(Result), 'The open path');
end;

// FNV-1a over the verbs and the bits of the points
function TTsStrokerTests.PathHash(const Path: TTsPath): Cardinal;
begin
  var Hash: UInt64 := 2166136261;

  for var Verb in Path.Verbs do
  begin
    Hash := ((Hash xor Ord(Verb)) * 16777619) and $FFFFFFFF;
  end;

  for var Pt in Path.Points do
  begin
    Hash := ((Hash xor TTsLane.Bits(Pt.X)) * 16777619) and $FFFFFFFF;
    Hash := ((Hash xor TTsLane.Bits(Pt.Y)) * 16777619) and $FFFFFFFF;
  end;

  Result := Cardinal(Hash);
end;

procedure TTsStrokerTests.AssertRustReference(const Path: TTsPath; const Width, MiterLimit, ResScale: Single;
                                              const Join: TTsLineJoin; const Cap: TTsLineCap; const ExpectedHash: Cardinal);
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := Width;
  Stroke.MiterLimit := MiterLimit;
  Stroke.LineJoin := Join;
  Stroke.LineCap := Cap;

  var Stroked: TTsPath;
  Assert.IsTrue(Path.TryStroke(Stroke, ResScale, Stroked), 'Stroke');
  Assert.AreEqual(ExpectedHash, PathHash(Stroked), 'The bits of the stroked path');
end;

procedure TTsStrokerTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsStrokerTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsStrokerTests.TestAutoClose;
begin
  // A triangle.
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.LineTo(20, 50);
  Builder.LineTo(30, 10);
  Builder.Close;
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, TTsStroke.New, Stroked));

  var Iter := Stroked.Segments;
  Iter.SetAutoClose(True);

  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(10.485071, 9.878732)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(20.485071, 49.878731)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(20.0, 50.0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(19.514929, 49.878731)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(29.514929, 9.878732)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(30.0, 10.0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(30.0, 10.5)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(10.0, 10.5)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(10.0, 10.0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(10.485071, 9.878732)));
  AssertNextSegment(Iter, TTsPathSegment.CloseSegment);
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(9.3596115, 9.5)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(30.640388, 9.5)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(20.485071, 50.121269)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(19.514929, 50.121269)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(9.514929, 10.121268)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(9.3596115, 9.5)));
  AssertNextSegment(Iter, TTsPathSegment.CloseSegment);

  var Segment: TTsPathSegment;
  Assert.IsFalse(Iter.TryNext(Segment), 'No more segments');
end;

// From skia/tests/StrokeTest.cpp
procedure TTsStrokerTests.TestCubic1;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(51.0161362, 1511.52478);
  Builder.CubicTo(51.0161362, 1511.52478, 51.0161362, 1511.52478, 51.0161362, 1511.52478);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 0.394537568;

  var Stroked: TTsPath;
  Assert.IsFalse(StrokeOf(Path, Stroke, Stroked));
end;

// From skia/tests/StrokeTest.cpp
procedure TTsStrokerTests.TestCubic2;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(BitsToSingle($424C1086), BitsToSingle($44BCF0CB)); // 51.0161362, 1511.52478
  Builder.CubicTo(
    BitsToSingle($424C107C), BitsToSingle($44BCF0CB), // 51.0160980, 1511.52478
    BitsToSingle($424C10C2), BitsToSingle($44BCF0CB), // 51.0163651, 1511.52478
    BitsToSingle($424C1119), BitsToSingle($44BCF0CA)); // 51.0166969, 1511.52466
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 0.394537568;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
end;

// From skia/tests/StrokeTest.cpp
// From skbug.com/6491. The large stroke width can cause numerical instabilities.
procedure TTsStrokerTests.TestBig;
begin
  // Skia uses kStrokeAndFill_Style here, but we do not support it.
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(BitsToSingle($46380000), BitsToSingle($C6380000)); // 11776, -11776
  Builder.LineTo(BitsToSingle($46A00000), BitsToSingle($C6A00000)); // 20480, -20480
  Builder.LineTo(BitsToSingle($468C0000), BitsToSingle($C68C0000)); // 17920, -17920
  Builder.LineTo(BitsToSingle($46100000), BitsToSingle($C6100000)); // 9216, -9216
  Builder.LineTo(BitsToSingle($46380000), BitsToSingle($C6380000)); // 11776, -11776
  Builder.Close;
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 1.49679073E+10;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
end;

// From skia/tests/StrokerTest.cpp
procedure TTsStrokerTests.TestQuadStrokerOneOff;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(BitsToSingle($43C99223), BitsToSingle($42B7417E));
  Builder.QuadTo(
    BitsToSingle($4285D839), BitsToSingle($43ED6645),
    BitsToSingle($43C941C8), BitsToSingle($42B3ACE3));
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 164.683548;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
end;

// From skia/tests/StrokerTest.cpp
procedure TTsStrokerTests.TestCubicStrokerOneOff;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(BitsToSingle($433F5370), BitsToSingle($43D1F4B3));
  Builder.CubicTo(
    BitsToSingle($4331CB76), BitsToSingle($43EA3340),
    BitsToSingle($4388F498), BitsToSingle($42F7F08D),
    BitsToSingle($43F1CD32), BitsToSingle($42802EC1));
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 42.835968;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
end;

procedure TTsStrokerTests.TestStrokeOfLineHasExpectedBounds;
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := 2;
  Stroke.LineCap := TTsLineCap.Butt;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(LinePath(0, 0, 10, 0), Stroke, Stroked));

  var Bounds := Stroked.Bounds;
  Assert.AreEqual(Single(0), Bounds.Left, 'Left');
  Assert.AreEqual(Single(-1), Bounds.Top, 'Top');
  Assert.AreEqual(Single(10), Bounds.Right, 'Right');
  Assert.AreEqual(Single(1), Bounds.Bottom, 'Bottom');
end;

procedure TTsStrokerTests.TestSquareCapExtendsBounds;
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := 2;
  Stroke.LineCap := TTsLineCap.Square;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(LinePath(0, 0, 10, 0), Stroke, Stroked));

  var Bounds := Stroked.Bounds;
  Assert.AreEqual(Single(-1), Bounds.Left, 'Left');
  Assert.AreEqual(Single(-1), Bounds.Top, 'Top');
  Assert.AreEqual(Single(11), Bounds.Right, 'Right');
  Assert.AreEqual(Single(1), Bounds.Bottom, 'Bottom');
end;

procedure TTsStrokerTests.TestHugeStrokeWidthIsFinite;
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := 1E20;

  var Stroked: TTsPath;
  if StrokeOf(LinePath(0, 0, 10, 0), Stroke, Stroked) then
  begin
    var Bounds := Stroked.Bounds;
    Assert.IsTrue(TTsScalar.IsFinite(Bounds.Left) and TTsScalar.IsFinite(Bounds.Top) and TTsScalar.IsFinite(Bounds.Right) and
                  TTsScalar.IsFinite(Bounds.Bottom), 'The bounds are finite');
  end;
end;

procedure TTsStrokerTests.TestQuadOfHugeControlPointsFailsInsteadOfStrokingNaN;
begin
  // numer of the maximum curvature is inf - inf = NaN, where Rust panics on an unwrap
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.QuadTo(1E30, 1E30, 3E30, 1E30);

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path), 'The quad path');

  var Stroke := TTsStroke.New;
  Stroke.Width := 2;

  var Stroked: TTsPath;
  if StrokeOf(Path, Stroke, Stroked) then
  begin
    var Bounds := Stroked.Bounds;
    Assert.IsTrue(TTsScalar.IsFinite(Bounds.Left) and TTsScalar.IsFinite(Bounds.Top) and TTsScalar.IsFinite(Bounds.Right) and
                  TTsScalar.IsFinite(Bounds.Bottom), 'The bounds are finite');
  end;
end;

procedure TTsStrokerTests.TestZeroWidthGivesNoPath;
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := 0;

  var Stroked: TTsPath;
  Assert.IsFalse(StrokeOf(LinePath(0, 0, 10, 0), Stroke, Stroked));

  Stroke.Width := -1;
  Assert.IsFalse(StrokeOf(LinePath(0, 0, 10, 0), Stroke, Stroked));
end;

procedure TTsStrokerTests.TestRoundCapOfPointIsCircle;
begin
  // A zero-length line with a round cap is a dot
  var Stroke := TTsStroke.New;
  Stroke.Width := 4;
  Stroke.LineCap := TTsLineCap.Round;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(LinePath(5, 5, 5, 5), Stroke, Stroked));

  var Bounds := Stroked.Bounds;
  Assert.AreEqual(Single(3), Bounds.Left, 0.01, 'Left');
  Assert.AreEqual(Single(3), Bounds.Top, 0.01, 'Top');
  Assert.AreEqual(Single(7), Bounds.Right, 0.01, 'Right');
  Assert.AreEqual(Single(7), Bounds.Bottom, 0.01, 'Bottom');
end;

procedure TTsStrokerTests.TestButtCapOfPointGivesNoPath;
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := 4;

  var Stroked: TTsPath;
  Assert.IsFalse(StrokeOf(LinePath(5, 5, 5, 5), Stroke, Stroked));
end;

procedure TTsStrokerTests.TestRoundJoinAndMiterClipJoinStrokeAnAngle;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.LineTo(10, 0);
  Builder.LineTo(10, 10);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 2;
  Stroke.LineJoin := TTsLineJoin.Round;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
  Assert.AreEqual(Single(11), Stroked.Bounds.Right, 0.001, 'Round join right');
  Assert.AreEqual(Single(-1), Stroked.Bounds.Top, 0.001, 'Round join top');

  Stroke.LineJoin := TTsLineJoin.MiterClip;
  Stroke.MiterLimit := 1.2;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
  Assert.IsTrue(Stroked.Bounds.Right >= 11, 'Miter clip right');

  Stroke.LineJoin := TTsLineJoin.Miter;
  Stroke.MiterLimit := 4;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));
  Assert.AreEqual(Single(11), Stroked.Bounds.Right, 0.001, 'Miter join right');
  Assert.AreEqual(Single(-1), Stroked.Bounds.Top, 0.001, 'Miter join top');
end;

procedure TTsStrokerTests.TestMiterLimitBelowOneBecomesBevel;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.LineTo(10, 0);
  Builder.LineTo(10, 10);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Stroke := TTsStroke.New;
  Stroke.Width := 2;
  Stroke.MiterLimit := 1;

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(Path, Stroke, Stroked));

  var Bevel: TTsPath;
  Stroke.LineJoin := TTsLineJoin.Bevel;
  Assert.IsTrue(StrokeOf(Path, Stroke, Bevel));

  Assert.AreEqual(Length(Bevel.Points), Length(Stroked.Points), 'A miter limit of 1 is a bevel');
  for var Index := 0 to High(Bevel.Points) do
  begin
    Assert.IsTrue(Bevel.Points[Index] = Stroked.Points[Index], 'Point ' + Index.ToString);
  end;
end;

procedure TTsStrokerTests.TestStrokerIsReusable;
begin
  var Stroker := TTsPathStroker.Create;
  try
    var Stroke := TTsStroke.New;
    Stroke.Width := 2;

    var First: TTsPath;
    Assert.IsTrue(Stroker.TryStroke(LinePath(0, 0, 10, 0), Stroke, 1, First));

    var Second: TTsPath;
    Assert.IsTrue(Stroker.TryStroke(LinePath(0, 0, 10, 0), Stroke, 1, Second));

    Assert.AreEqual(Length(First.Points), Length(Second.Points), 'Same number of points');
    Assert.AreEqual(Length(First.Verbs), Length(Second.Verbs), 'Same number of verbs');
    Assert.AreEqual(First.Bounds.Right, Second.Bounds.Right);
  finally
    Stroker.Free;
  end;
end;

procedure TTsStrokerTests.TestComputeResolutionScale;
begin
  Assert.AreEqual(Single(1), TTsPathStroker.ComputeResolutionScale(TTsTransform.Identity));
  Assert.AreEqual(Single(3), TTsPathStroker.ComputeResolutionScale(TTsTransform.FromScale(3, 2)));
  Assert.AreEqual(Single(1), TTsPathStroker.ComputeResolutionScale(TTsTransform.FromScale(0, 0)));
end;

procedure TTsStrokerTests.TestStrokeWithQuadAndCubicIsFinite;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.QuadTo(50, 100, 90, 10);
  Builder.CubicTo(120, 80, 150, -60, 190, 10);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  for var Join := Low(TTsLineJoin) to High(TTsLineJoin) do
  begin
    for var Cap := Low(TTsLineCap) to High(TTsLineCap) do
    begin
      var Stroke := TTsStroke.New;
      Stroke.Width := 6;
      Stroke.LineJoin := Join;
      Stroke.LineCap := Cap;

      var Stroked: TTsPath;
      Assert.IsTrue(StrokeOf(Path, Stroke, Stroked), 'Stroke');
      Assert.IsTrue(Stroked.Bounds.Left < 10, 'Wider than the path');
      Assert.IsTrue(Stroked.Bounds.Right > 190, 'Wider than the path');
    end;
  end;
end;

procedure TTsStrokerTests.TestStrokeOfClosedRectHasInnerAndOuterContour;
begin
  var Stroke := TTsStroke.New;
  Stroke.Width := 2;

  var Rect: TTsRect;
  Assert.IsTrue(TTsRect.TryFromLTRB(10, 10, 50, 30, Rect));

  var Stroked: TTsPath;
  Assert.IsTrue(StrokeOf(TTsPathBuilder.FromRect(Rect), Stroke, Stroked));

  var MoveCount := 0;
  for var Verb in Stroked.Verbs do
  begin
    if Verb = TTsPathVerb.Move then
    begin
      Inc(MoveCount);
    end;
  end;

  Assert.AreEqual(2, MoveCount, 'Outer and inner contour');
  Assert.AreEqual(Single(9), Stroked.Bounds.Left, 'Left');
  Assert.AreEqual(Single(51), Stroked.Bounds.Right, 'Right');
  Assert.AreEqual(Single(9), Stroked.Bounds.Top, 'Top');
  Assert.AreEqual(Single(31), Stroked.Bounds.Bottom, 'Bottom');
end;

procedure TTsStrokerTests.TestRustReferenceClosedRoundJoinRoundCap;
begin
  AssertRustReference(ClosedPath, 6, 4, 1, TTsLineJoin.Round, TTsLineCap.Round, $B33489F2);
end;

procedure TTsStrokerTests.TestRustReferenceClosedScaledMiterClipSquareCap;
begin
  AssertRustReference(ClosedPath, 6, 4, 3.5, TTsLineJoin.MiterClip, TTsLineCap.Square, $1659CDFA);
end;

procedure TTsStrokerTests.TestRustReferenceOpenMiterSquareCap;
begin
  AssertRustReference(OpenPath, 9, 2.5, 1, TTsLineJoin.Miter, TTsLineCap.Square, $65C7A748);
end;

procedure TTsStrokerTests.TestRustReferenceOpenMiterClipRoundCap;
begin
  AssertRustReference(OpenPath, 9, 2.5, 1, TTsLineJoin.MiterClip, TTsLineCap.Round, $8A7D9140);
end;

procedure TTsStrokerTests.TestRustReferenceOpenRoundJoinButtCap;
begin
  AssertRustReference(OpenPath, 9, 2.5, 1, TTsLineJoin.Round, TTsLineCap.Butt, $40408ED3);
end;

procedure TTsStrokerTests.TestRustReferenceOpenBevelSquareCap;
begin
  AssertRustReference(OpenPath, 9, 2.5, 1, TTsLineJoin.Bevel, TTsLineCap.Square, $764E3CE6);
end;

end.
