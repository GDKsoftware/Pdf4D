// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 path/src/dash.rs (inline tests), and of the dashing around them
unit Pdf4D.Render.Native.Dash.Tests;

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
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Dash;

type
  [TestFixture]
  TTsDashTests = class
  private
    FFloatState: TTsFloatState;

    function LinePath(const X0, Y0, X1, Y1: Single): TTsPath;
    function Dash(const Intervals: TArray<Single>; const Offset: Single = 0): TTsStrokeDash;
    procedure AssertNextSegment(var Iter: TTsPathSegmentsIter; const Expected: TTsPathSegment);
    function ClosedPath: TTsPath;
    function OpenPath: TTsPath;
    function PathHash(const Path: TTsPath): Cardinal;
    procedure AssertRustReference(const Path: TTsPath; const Intervals: TArray<Single>; const Offset, ResScale: Single;
                                  const ExpectedHash: Cardinal);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestStrokeDashCreate;

    [Test]
    procedure TestBug26;

    [Test]
    procedure TestInvalidDashIntervals;

    [Test]
    procedure TestDashCountLimitGivesNoPath;

    [Test]
    procedure TestDashedLineSegments;

    [Test]
    procedure TestDashOffsetShiftsThePattern;

    [Test]
    procedure TestNegativeDashOffsetIsFlipped;

    [Test]
    procedure TestDashedClosedContourJoinsTheFirstAndLastDash;

    [Test]
    procedure TestDashOfQuadAndCubicKeepsTheCurveEnds;

    [Test]
    procedure TestZeroLengthOnDashGivesZeroLengthLine;

    [Test]
    procedure TestRemainder;

    // The expected hashes are of the output of tiny-skia v0.12.0 for the same input: every verb and the bits of every point
    [Test]
    procedure TestRustReferenceOpenPathWithOffset;

    [Test]
    procedure TestRustReferenceClosedPathWithOffset;

    [Test]
    procedure TestRustReferenceZeroLengthDashesAndNegativeOffset;

    [Test]
    procedure TestRustReferenceClosedPathWithCurves;
  end;

implementation

function TTsDashTests.LinePath(const X0, Y0, X1, Y1: Single): TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(X0, Y0);
  Builder.LineTo(X1, Y1);

  Assert.IsTrue(Builder.TryFinish(Result), 'The line path');
end;

function TTsDashTests.Dash(const Intervals: TArray<Single>; const Offset: Single): TTsStrokeDash;
begin
  Assert.IsTrue(TTsStrokeDash.TryCreate(Intervals, Offset, Result), 'The dash');
end;

procedure TTsDashTests.AssertNextSegment(var Iter: TTsPathSegmentsIter; const Expected: TTsPathSegment);
begin
  var Segment: TTsPathSegment;
  Assert.IsTrue(Iter.TryNext(Segment), 'A segment is expected');
  Assert.IsTrue(Expected = Segment, 'The segment differs');
end;

function TTsDashTests.ClosedPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10, 10);
  Builder.QuadTo(50, 100, 90, 10);
  Builder.CubicTo(120, 80, 150, -60, 190, 10);
  Builder.LineTo(150, 60);
  Builder.Close;

  Assert.IsTrue(Builder.TryFinish(Result), 'The closed path');
end;

function TTsDashTests.OpenPath: TTsPath;
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
function TTsDashTests.PathHash(const Path: TTsPath): Cardinal;
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

procedure TTsDashTests.AssertRustReference(const Path: TTsPath; const Intervals: TArray<Single>; const Offset, ResScale: Single;
                                           const ExpectedHash: Cardinal);
begin
  var Dashed: TTsPath;
  Assert.IsTrue(Path.TryDash(Dash(Intervals, Offset), ResScale, Dashed), 'Dash');
  Assert.AreEqual(ExpectedHash, PathHash(Dashed), 'The bits of the dashed path');
end;

procedure TTsDashTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsDashTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsDashTests.TestStrokeDashCreate;
begin
  var Created: TTsStrokeDash;

  Assert.IsFalse(TTsStrokeDash.TryCreate([], 0, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([1], 0, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([1, 2, 3], 0, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([1, -2], 0, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([0, 0], 0, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([1, -1], 0, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([1, 1], Infinity, Created));
  Assert.IsFalse(TTsStrokeDash.TryCreate([1, Infinity], 0, Created));
  Assert.IsTrue(TTsStrokeDash.TryCreate([1, 1], 0, Created));
end;

procedure TTsDashTests.TestBug26;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(665.54, 287.3);
  Builder.LineTo(675.67, 273.04);
  Builder.LineTo(675.52, 271.32);
  Builder.LineTo(674.79, 269.61);
  Builder.LineTo(674.05, 268.04);
  Builder.LineTo(672.88, 266.47);
  Builder.LineTo(671.27, 264.9);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Dashed: TTsPath;
  Assert.IsTrue(Path.TryDash(Dash([6, 4.5]), 1, Dashed));
end;

procedure TTsDashTests.TestInvalidDashIntervals;
begin
  var Created: TTsStrokeDash;

  Assert.IsFalse(TTsStrokeDash.TryCreate([1], 0, Created), 'One interval');
  Assert.IsFalse(TTsStrokeDash.TryCreate([-1, 1], 0, Created), 'Negative interval');
  Assert.IsFalse(TTsStrokeDash.TryCreate([0, 0], 0, Created), 'Zero sum');
  Assert.IsFalse(TTsStrokeDash.TryCreate([NaN, 1], 0, Created), 'NaN interval');
  Assert.IsFalse(TTsStrokeDash.TryCreate([1, 1], NaN, Created), 'NaN offset');
end;

procedure TTsDashTests.TestDashCountLimitGivesNoPath;
begin
  var Dashed: TTsPath;
  Assert.IsFalse(LinePath(0, 0, 1E7, 0).TryDash(Dash([1, 1]), 1, Dashed), 'More than 1000000 dashes');
  Assert.IsTrue(LinePath(0, 0, 1E6, 0).TryDash(Dash([1, 1]), 1, Dashed), '500000 dashes');
end;

procedure TTsDashTests.TestDashedLineSegments;
begin
  var Dashed: TTsPath;
  Assert.IsTrue(LinePath(0, 0, 10, 0).TryDash(Dash([2, 2]), 1, Dashed));

  var Iter := Dashed.Segments;
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(0, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(2, 0)));
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(4, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(6, 0)));
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(8, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(10, 0)));

  var Segment: TTsPathSegment;
  Assert.IsFalse(Iter.TryNext(Segment), 'No more segments');
end;

procedure TTsDashTests.TestDashOffsetShiftsThePattern;
begin
  var Dashed: TTsPath;
  Assert.IsTrue(LinePath(0, 0, 10, 0).TryDash(Dash([2, 2], 1), 1, Dashed));

  var Iter := Dashed.Segments;
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(0, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(1, 0)));
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(3, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(5, 0)));
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(7, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(9, 0)));
end;

procedure TTsDashTests.TestNegativeDashOffsetIsFlipped;
begin
  // An offset of -1 in a pattern of length 4 is the same as an offset of 3
  var Negative: TTsPath;
  var Positive: TTsPath;
  Assert.IsTrue(LinePath(0, 0, 10, 0).TryDash(Dash([2, 2], -1), 1, Negative));
  Assert.IsTrue(LinePath(0, 0, 10, 0).TryDash(Dash([2, 2], 3), 1, Positive));

  Assert.AreEqual(Length(Positive.Points), Length(Negative.Points));
  for var Index := 0 to High(Positive.Points) do
  begin
    Assert.IsTrue(Positive.Points[Index] = Negative.Points[Index], 'Point ' + Index.ToString);
  end;
end;

procedure TTsDashTests.TestDashedClosedContourJoinsTheFirstAndLastDash;
begin
  var Rect: TTsRect;
  Assert.IsTrue(TTsRect.TryFromLTRB(0, 0, 10, 10, Rect));

  var Dashed: TTsPath;
  Assert.IsTrue(TTsPathBuilder.FromRect(Rect).TryDash(Dash([15, 5]), 1, Dashed));

  Assert.IsTrue(Dashed.Len >= 4, 'Several dashes');
  Assert.AreEqual(Single(0), Dashed.Bounds.Left, 'Left');
  Assert.AreEqual(Single(10), Dashed.Bounds.Right, 'Right');
  Assert.AreEqual(Single(0), Dashed.Bounds.Top, 'Top');
  Assert.AreEqual(Single(10), Dashed.Bounds.Bottom, 'Bottom');
end;

procedure TTsDashTests.TestDashOfQuadAndCubicKeepsTheCurveEnds;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0, 0);
  Builder.QuadTo(50, 50, 100, 0);
  Builder.CubicTo(120, -40, 160, 40, 200, 0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  // One long dash covers the whole contour
  var Dashed: TTsPath;
  Assert.IsTrue(Path.TryDash(Dash([1000, 1]), 1, Dashed));
  Assert.AreEqual(Single(0), Dashed.Points[0].X, 'Start x');
  Assert.AreEqual(Single(200), Dashed.Points[High(Dashed.Points)].X, 0.01, 'End x');

  Assert.IsTrue(Path.TryDash(Dash([20, 10]), 1, Dashed));
  Assert.IsTrue(Dashed.Len > 10, 'Many dashes');
end;

procedure TTsDashTests.TestZeroLengthOnDashGivesZeroLengthLine;
begin
  // A dash with no length is kept as a zero-length line, the stroker draws a cap on it
  var Dashed: TTsPath;
  Assert.IsTrue(LinePath(0, 0, 10, 0).TryDash(Dash([0, 5]), 1, Dashed));

  var Iter := Dashed.Segments;
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(0, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(0, 0)));
  AssertNextSegment(Iter, TTsPathSegment.MoveTo(TTsPoint.FromXY(5, 0)));
  AssertNextSegment(Iter, TTsPathSegment.LineTo(TTsPoint.FromXY(5, 0)));
end;

procedure TTsDashTests.TestRemainder;
begin
  Assert.AreEqual(Single(1), TTsScalar.RemainderF(7, 3));
  Assert.AreEqual(Single(0.5), TTsScalar.RemainderF(10.5, 2));
  Assert.AreEqual(Single(0), TTsScalar.RemainderF(6, 3));
  Assert.AreEqual(Single(2), TTsScalar.RemainderF(2, 3));
  // The exact remainder, where the quotient does not fit in a Single
  Assert.AreEqual(Single(0), TTsScalar.RemainderF(1E30, 2));
  Assert.AreEqual(Single(16), TTsScalar.RemainderF(17179869184.0, 1023));
end;

procedure TTsDashTests.TestRustReferenceOpenPathWithOffset;
begin
  AssertRustReference(OpenPath, [5, 2, 1, 2], 4.5, 1, $710C208A);
end;

procedure TTsDashTests.TestRustReferenceClosedPathWithOffset;
begin
  AssertRustReference(ClosedPath, [5, 2, 1, 2], 4.5, 2, $691AE21E);
end;

procedure TTsDashTests.TestRustReferenceZeroLengthDashesAndNegativeOffset;
begin
  AssertRustReference(OpenPath, [0, 6], -2, 1, $63F1A85E);
end;

procedure TTsDashTests.TestRustReferenceClosedPathWithCurves;
begin
  AssertRustReference(ClosedPath, [7, 3], 0, 2, $F8F74028);
end;

end.
