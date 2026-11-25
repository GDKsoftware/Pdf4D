// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 tests/integration/path.rs
unit Pdf4D.Render.Native.Path.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path;

type
  [TestFixture]
  TTsPathTests = class
  private
    function Pt(const X, Y: Single): TTsPoint;
    function MakeRect(const Left, Top, Right, Bottom: Single): TTsRect;
    function MakeRectXYWH(const X, Y, Width, Height: Single): TTsRect;
    procedure AssertBounds(const Expected, Actual: TTsRect);
    procedure AssertSegments(const Path: TTsPath; const Expected: array of TTsPathSegment);
    function TwoPointPath: TTsPath;

  public
    [Test]
    procedure TestEmpty;

    [Test]
    procedure TestLine;

    [Test]
    procedure TestNoMoveBeforeLine;

    [Test]
    procedure TestNoMoveBeforeQuad;

    [Test]
    procedure TestNoMoveBeforeCubic;

    [Test]
    procedure TestNoMoveBeforeClose;

    [Test]
    procedure TestDoubleClose;

    [Test]
    procedure TestDoubleMoveTo1;

    [Test]
    procedure TestDoubleMoveTo2;

    [Test]
    procedure TestTwoContours;

    [Test]
    procedure TestTwoClosedContours;

    [Test]
    procedure TestLineAfterClose;

    [Test]
    procedure TestHorLine;

    [Test]
    procedure TestVerLine;

    [Test]
    procedure TestTranslate;

    [Test]
    procedure TestScale;

    [Test]
    procedure TestTransform;

    [Test]
    procedure TestInvalidTransform;

    [Test]
    procedure TestCircle;

    [Test]
    procedure TestLargeCircle;

    [Test]
    procedure TestTightBounds1;

    [Test]
    procedure TestTightBounds2;

    [Test]
    procedure TestBuilderWithNaNGivesNoPath;

    [Test]
    procedure TestTransformToInfinityFails;

    [Test]
    procedure TestIteratorAutoClose;

    [Test]
    procedure TestFromRectAndPushRect;

    [Test]
    procedure TestPushOvalGivesQuads;

    [Test]
    procedure TestConicToBranches;

    [Test]
    procedure TestReversePathTo;

    [Test]
    procedure TestPushPathAndPushPathBuilder;

    [Test]
    procedure TestZeroFilledBuilderIsNew;
  end;

implementation

{ TTsPathTests }

function TTsPathTests.Pt(const X, Y: Single): TTsPoint;
begin
  Result := TTsPoint.FromXY(X, Y);
end;

function TTsPathTests.MakeRect(const Left, Top, Right, Bottom: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromLTRB(Left, Top, Right, Bottom, Result), 'a valid rect');
end;

function TTsPathTests.MakeRectXYWH(const X, Y, Width, Height: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromXYWH(X, Y, Width, Height, Result), 'a valid rect');
end;

procedure TTsPathTests.AssertBounds(const Expected, Actual: TTsRect);
begin
  const Message = Format('expected (%g, %g, %g, %g), got (%g, %g, %g, %g)',
    [Expected.Left, Expected.Top, Expected.Right, Expected.Bottom, Actual.Left, Actual.Top, Actual.Right, Actual.Bottom]);

  Assert.IsTrue((Expected.Left = Actual.Left) and (Expected.Top = Actual.Top) and (Expected.Right = Actual.Right) and
                (Expected.Bottom = Actual.Bottom), Message);
end;

procedure TTsPathTests.AssertSegments(const Path: TTsPath; const Expected: array of TTsPathSegment);
begin
  var Iter := Path.Segments;
  var Segment: TTsPathSegment;
  var Index := 0;
  while Iter.TryNext(Segment) do
  begin
    Assert.IsTrue(Index <= High(Expected), 'more segments than expected');
    Assert.IsTrue(Segment = Expected[Index], Format('segment %d differs', [Index]));
    Inc(Index);
  end;

  Assert.AreEqual(Integer(Length(Expected)), Index, 'segment count');
end;

function TTsPathTests.TwoPointPath: TTsPath;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.LineTo(30.0, 40.0);
  Assert.IsTrue(Builder.TryFinish(Result));
end;

procedure TTsPathTests.TestEmpty;
begin
  var Builder := TTsPathBuilder.New;
  var Path: TTsPath;

  Assert.IsFalse(Builder.TryFinish(Path));
end;

procedure TTsPathTests.TestLine;
begin
  var Path := TwoPointPath;

  AssertBounds(MakeRect(10.0, 20.0, 30.0, 40.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 20.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0))]);
end;

procedure TTsPathTests.TestNoMoveBeforeLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.LineTo(30.0, 40.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(0.0, 0.0, 30.0, 40.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(0.0, 0.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0))]);
end;

procedure TTsPathTests.TestNoMoveBeforeQuad;
begin
  var Builder := TTsPathBuilder.New;
  Builder.QuadTo(40.0, 30.0, 60.0, 75.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(0.0, 0.0, 60.0, 75.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(0.0, 0.0)), TTsPathSegment.QuadTo(Pt(40.0, 30.0), Pt(60.0, 75.0))]);
end;

procedure TTsPathTests.TestNoMoveBeforeCubic;
begin
  var Builder := TTsPathBuilder.New;
  Builder.CubicTo(40.0, 30.0, 60.0, 75.0, 33.0, 66.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(0.0, 0.0, 60.0, 75.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(0.0, 0.0)),
                        TTsPathSegment.CubicTo(Pt(40.0, 30.0), Pt(60.0, 75.0), Pt(33.0, 66.0))]);
end;

procedure TTsPathTests.TestNoMoveBeforeClose;
begin
  var Builder := TTsPathBuilder.New;
  Builder.Close;
  var Path: TTsPath;

  Assert.IsFalse(Builder.TryFinish(Path));
end;

procedure TTsPathTests.TestDoubleClose;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(20.0, 10.0);
  Builder.LineTo(20.0, 20.0);
  Builder.Close;
  Builder.Close;
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(10.0, 10.0, 20.0, 20.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 10.0)), TTsPathSegment.LineTo(Pt(20.0, 10.0)),
                        TTsPathSegment.LineTo(Pt(20.0, 20.0)), TTsPathSegment.CloseSegment]);
end;

procedure TTsPathTests.TestDoubleMoveTo1;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.MoveTo(30.0, 40.0);
  var Path: TTsPath;

  Assert.IsFalse(Builder.TryFinish(Path));
end;

procedure TTsPathTests.TestDoubleMoveTo2;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.MoveTo(20.0, 10.0);
  Builder.LineTo(30.0, 40.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(20.0, 10.0, 30.0, 40.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(20.0, 10.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0))]);
end;

procedure TTsPathTests.TestTwoContours;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.LineTo(30.0, 40.0);
  Builder.MoveTo(100.0, 200.0);
  Builder.LineTo(300.0, 400.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(10.0, 20.0, 300.0, 400.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 20.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0)),
                        TTsPathSegment.MoveTo(Pt(100.0, 200.0)), TTsPathSegment.LineTo(Pt(300.0, 400.0))]);
end;

procedure TTsPathTests.TestTwoClosedContours;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.LineTo(30.0, 40.0);
  Builder.Close;
  Builder.MoveTo(100.0, 200.0);
  Builder.LineTo(300.0, 400.0);
  Builder.Close;
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(10.0, 20.0, 300.0, 400.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 20.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0)), TTsPathSegment.CloseSegment,
                        TTsPathSegment.MoveTo(Pt(100.0, 200.0)), TTsPathSegment.LineTo(Pt(300.0, 400.0)), TTsPathSegment.CloseSegment]);
end;

procedure TTsPathTests.TestLineAfterClose;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 20.0);
  Builder.LineTo(30.0, 40.0);
  Builder.Close;
  Builder.LineTo(20.0, 20.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(10.0, 20.0, 30.0, 40.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 20.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0)), TTsPathSegment.CloseSegment,
                        TTsPathSegment.MoveTo(Pt(10.0, 20.0)), TTsPathSegment.LineTo(Pt(20.0, 20.0))]);
end;

procedure TTsPathTests.TestHorLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(20.0, 10.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(10.0, 10.0, 20.0, 10.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 10.0)), TTsPathSegment.LineTo(Pt(20.0, 10.0))]);
end;

procedure TTsPathTests.TestVerLine;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(10.0, 20.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertBounds(MakeRect(10.0, 10.0, 10.0, 20.0), Path.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 10.0)), TTsPathSegment.LineTo(Pt(10.0, 20.0))]);
end;

procedure TTsPathTests.TestTranslate;
begin
  var Path := TwoPointPath;
  var Moved: TTsPath;

  Assert.IsTrue(Path.TryTransform(TTsTransform.FromTranslate(10.0, 20.0), Moved));
  AssertSegments(Moved, [TTsPathSegment.MoveTo(Pt(20.0, 40.0)), TTsPathSegment.LineTo(Pt(40.0, 60.0))]);
  AssertBounds(MakeRect(20.0, 40.0, 40.0, 60.0), Moved.Bounds);
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(10.0, 20.0)), TTsPathSegment.LineTo(Pt(30.0, 40.0))]);
end;

procedure TTsPathTests.TestScale;
begin
  var Path := TwoPointPath;
  var Scaled: TTsPath;

  Assert.IsTrue(Path.TryTransform(TTsTransform.FromScale(2.0, 0.5), Scaled));
  AssertSegments(Scaled, [TTsPathSegment.MoveTo(Pt(20.0, 10.0)), TTsPathSegment.LineTo(Pt(60.0, 20.0))]);
end;

procedure TTsPathTests.TestTransform;
begin
  var Path := TwoPointPath;
  var Transformed: TTsPath;

  Assert.IsTrue(Path.TryTransform(TTsTransform.FromRow(2.0, 0.7, -0.3, 0.5, 10.0, 20.0), Transformed));
  AssertSegments(Transformed, [TTsPathSegment.MoveTo(Pt(24.0, 37.0)), TTsPathSegment.LineTo(Pt(58.0, 61.0))]);
end;

procedure TTsPathTests.TestInvalidTransform;
begin
  var Path := TwoPointPath;
  var Transformed: TTsPath;

  // will produce infinity
  const State = TTsFloatMode.Enter;
  try
    Assert.IsFalse(Path.TryTransform(TTsTransform.FromScale(TTsScalar.ScalarMax, TTsScalar.ScalarMax), Transformed));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsPathTests.TestCircle;
begin
  var Path: TTsPath;

  // Must not fail
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(250.0, 250.0, 300.0, Path));
end;

procedure TTsPathTests.TestLargeCircle;
begin
  var Path: TTsPath;

  // Must not fail
  Assert.IsTrue(TTsPathBuilder.TryFromCircle(250.0, 250.0, 2000.0, Path));
end;

procedure TTsPathTests.TestTightBounds1;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(50.0, 85.0);
  Builder.LineTo(65.0, 135.0);
  Builder.LineTo(150.0, 135.0);
  Builder.LineTo(85.0, 135.0);
  Builder.QuadTo(100.0, 45.0, 50.0, 85.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var TightBounds: TTsRect;
  Assert.IsTrue(Path.TryComputeTightBounds(TightBounds));
  AssertBounds(MakeRectXYWH(50.0, 45.0, 100.0, 90.0), Path.Bounds);
  AssertBounds(MakeRectXYWH(50.0, 72.692307, 100.0, 62.307693), TightBounds);
end;

procedure TTsPathTests.TestTightBounds2;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(-19.309214, 72.11173);
  Builder.CubicTo(-24.832062, 67.477516, -20.490944, 62.16584, -9.61306, 60.247776);
  Builder.CubicTo(1.2648277, 58.329712, 14.560249, 60.53159, 20.083096, 65.16581);
  Builder.CubicTo(14.560249, 60.53159, 18.901363, 55.219913, 29.779247, 53.30185);
  Builder.CubicTo(40.65713, 51.383785, 53.952557, 53.585663, 59.475407, 58.21988);
  Builder.QuadTo(74.4754, 70.80637, 50.083096, 90.3388);
  Builder.QuadTo(-4.3092155, 84.69823, -19.309214, 72.11173);
  Builder.Close;
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var TightBounds: TTsRect;
  Assert.IsTrue(Path.TryComputeTightBounds(TightBounds));
  AssertBounds(MakeRectXYWH(-21.707121, 52.609154, 86.894302, 37.729645), TightBounds);
end;

procedure TTsPathTests.TestBuilderWithNaNGivesNoPath;
begin
  const State = TTsFloatMode.Enter;
  try
    var Builder := TTsPathBuilder.New;
    Builder.MoveTo(0.0, 0.0);
    Builder.LineTo(NaN, 1.0);
    var Path: TTsPath;

    Assert.IsFalse(Builder.TryFinish(Path));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsPathTests.TestTransformToInfinityFails;
begin
  const State = TTsFloatMode.Enter;
  try
    var Builder := TTsPathBuilder.New;
    Builder.MoveTo(0.0, 0.0);
    Builder.LineTo(1e30, 1e30);
    var Path: TTsPath;
    Assert.IsTrue(Builder.TryFinish(Path));

    var Transformed: TTsPath;
    Assert.IsFalse(Path.TryTransform(TTsTransform.FromScale(1e10, 1e10), Transformed));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsPathTests.TestIteratorAutoClose;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(10.0, 10.0);
  Builder.LineTo(20.0, 10.0);
  Builder.LineTo(20.0, 20.0);
  Builder.Close;
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  var Iter := Path.Segments;
  Iter.SetAutoClose(True);
  var Segment: TTsPathSegment;
  var Segments: TArray<TTsPathSegment>;
  while Iter.TryNext(Segment) do
  begin
    Segments := Segments + [Segment];
  end;

  Assert.AreEqual(5, Integer(Length(Segments)));
  Assert.IsTrue(Segments[3] = TTsPathSegment.LineTo(Pt(10.0, 10.0)), 'the line back to the start');
  Assert.IsTrue(Segments[4] = TTsPathSegment.CloseSegment);

  var Plain := Path.Segments;
  var Verb: TTsPathVerb;
  Assert.IsTrue(Plain.TryNextVerb(Verb));
  Assert.IsTrue(Verb = TTsPathVerb.Move);
  Assert.IsTrue(Plain.TryNext(Segment));
  Assert.IsTrue(Plain.CurrVerb = TTsPathVerb.Move);

  // The Rust code compares the end of a line with the last point of the iterator, which next() has set to that end already; every line is
  // skipped and the close ends the search
  Assert.IsFalse(Plain.HasValidTangent);
end;

procedure TTsPathTests.TestFromRectAndPushRect;
begin
  const Rect = MakeRect(1.0, 2.0, 3.0, 4.0);
  const FromRect = TTsPathBuilder.FromRect(Rect);

  var Builder := TTsPathBuilder.New;
  Builder.PushRect(Rect);
  var Pushed: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Pushed));

  AssertBounds(Rect, FromRect.Bounds);
  AssertBounds(Rect, Pushed.Bounds);
  AssertSegments(FromRect, [TTsPathSegment.MoveTo(Pt(1.0, 2.0)), TTsPathSegment.LineTo(Pt(3.0, 2.0)), TTsPathSegment.LineTo(Pt(3.0, 4.0)),
                            TTsPathSegment.LineTo(Pt(1.0, 4.0)), TTsPathSegment.CloseSegment]);
  AssertSegments(Pushed, [TTsPathSegment.MoveTo(Pt(1.0, 2.0)), TTsPathSegment.LineTo(Pt(3.0, 2.0)), TTsPathSegment.LineTo(Pt(3.0, 4.0)),
                          TTsPathSegment.LineTo(Pt(1.0, 4.0)), TTsPathSegment.CloseSegment]);
end;

procedure TTsPathTests.TestPushOvalGivesQuads;
begin
  var Path: TTsPath;
  Assert.IsTrue(TTsPathBuilder.TryFromOval(MakeRect(0.0, 0.0, 100.0, 100.0), Path));

  AssertBounds(MakeRect(0.0, 0.0, 100.0, 100.0), Path.Bounds);
  Assert.AreEqual(Path.Verbs[0], TTsPathVerb.Move);
  Assert.AreEqual(Path.Verbs[Path.Len - 1], TTsPathVerb.Close);
  for var Index := 1 to Path.Len - 2 do
  begin
    Assert.AreEqual(Path.Verbs[Index], TTsPathVerb.Quad);
  end;

  // Four conics of at least one quad each, two points per quad, the start point and the close
  Assert.IsTrue(Path.Len >= 6);
  Assert.AreEqual(1 + 2 * (Path.Len - 2), Integer(Length(Path.Points)));
  Assert.IsTrue(Path.Points[0] = Pt(100.0, 50.0), 'starts at the right-hand end of the oval');
end;

procedure TTsPathTests.TestConicToBranches;
begin
  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0.0, 0.0);
  Builder.ConicTo(5.0, 5.0, 10.0, 0.0, -1.0);
  Builder.ConicTo(5.0, 5.0, 20.0, 0.0, 1.0);

  const State = TTsFloatMode.Enter;
  try
    Builder.ConicTo(5.0, 5.0, 30.0, 0.0, Infinity);
    Builder.ConicTo(5.0, 5.0, 40.0, 0.0, NaN);
  finally
    TTsFloatMode.Leave(State);
  end;

  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));
  AssertSegments(Path, [
    TTsPathSegment.MoveTo(Pt(0.0, 0.0)),
    TTsPathSegment.LineTo(Pt(10.0, 0.0)),
    TTsPathSegment.QuadTo(Pt(5.0, 5.0), Pt(20.0, 0.0)),
    TTsPathSegment.LineTo(Pt(5.0, 5.0)),
    TTsPathSegment.LineTo(Pt(30.0, 0.0)),
    TTsPathSegment.LineTo(Pt(40.0, 0.0))]);
end;

procedure TTsPathTests.TestReversePathTo;
begin
  var Source := TTsPathBuilder.New;
  Source.MoveTo(0.0, 0.0);
  Source.LineTo(10.0, 0.0);
  Source.QuadTo(15.0, 5.0, 10.0, 10.0);
  Source.CubicTo(8.0, 12.0, 4.0, 12.0, 0.0, 10.0);

  var Builder := TTsPathBuilder.New;
  Builder.MoveTo(0.0, 10.0);
  Builder.ReversePathTo(Source);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));

  AssertSegments(Path, [
    TTsPathSegment.MoveTo(Pt(0.0, 10.0)),
    TTsPathSegment.CubicTo(Pt(4.0, 12.0), Pt(8.0, 12.0), Pt(10.0, 10.0)),
    TTsPathSegment.QuadTo(Pt(15.0, 5.0), Pt(10.0, 0.0)),
    TTsPathSegment.LineTo(Pt(0.0, 0.0))]);
end;

procedure TTsPathTests.TestPushPathAndPushPathBuilder;
begin
  var Path := TwoPointPath;

  var Builder := TTsPathBuilder.New;
  Builder.PushPath(Path);
  Builder.PushPath(Path);
  Assert.AreEqual(4, Builder.Len);

  var Other := TTsPathBuilder.New;
  Other.MoveTo(1.0, 1.0);
  Other.LineTo(2.0, 2.0);
  Builder.PushPathBuilder(Other);
  Assert.AreEqual(6, Builder.Len);

  var Last: TTsPoint;
  Assert.IsTrue(Builder.TryLastPoint(Last));
  Assert.IsTrue(Last = Pt(2.0, 2.0));
  Assert.IsFalse(Builder.IsZeroLengthSincePoint(0));
  Builder.SetLastPoint(Pt(1.0, 1.0));
  Assert.IsTrue(Builder.IsZeroLengthSincePoint(4));
end;

procedure TTsPathTests.TestZeroFilledBuilderIsNew;
begin
  var Builder: TTsPathBuilder := Default(TTsPathBuilder);
  Builder.LineTo(1.0, 1.0);
  var Path: TTsPath;
  Assert.IsTrue(Builder.TryFinish(Path));
  AssertSegments(Path, [TTsPathSegment.MoveTo(Pt(0.0, 0.0)), TTsPathSegment.LineTo(Pt(1.0, 1.0))]);
end;

end.
