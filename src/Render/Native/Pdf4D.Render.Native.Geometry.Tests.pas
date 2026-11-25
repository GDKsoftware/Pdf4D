// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Geometry.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry;

type
  [TestFixture]
  TTsGeometryTests = class
  private
    function MakeRect(const Left, Top, Right, Bottom: Single): TTsRect;
    function MakeNonZeroRect(const Left, Top, Right, Bottom: Single): TTsNonZeroRect;
    function MakeIntRect(const X, Y: Integer; const Width, Height: Cardinal): TTsIntRect;
    function MakeIntSize(const Width, Height: Cardinal): TTsIntSize;
    function MakeSize(const Width, Height: Single): TTsSize;
    procedure AssertRect(const Left, Top, Right, Bottom: Single; const Actual: TTsRect);
    procedure AssertIntRect(const X, Y: Integer; const Width, Height: Cardinal; const Actual: TTsIntRect);
    procedure ConvertWideScreenRectToIntRect;

  public
    [Test]
    procedure TestPointBasics;

    [Test]
    procedure TestPointNormalize;

    [Test]
    procedure TestPointNormalizeOfAHugeVector;

    [Test]
    procedure TestPointNonFiniteChecks;

    [Test]
    procedure TestPointOperators;

    [Test]
    procedure TestIntSizeTests;

    [Test]
    procedure TestIntSizeScaling;

    [Test]
    procedure TestSizeTryFromWHRejectsInvalid;

    [Test]
    procedure TestSizeScaling;

    [Test]
    procedure TestSizeConversions;

    [Test]
    procedure TestIntRectTests;

    [Test]
    procedure TestIntRectContainsInsetOutsetTranslate;

    [Test]
    procedure TestIntRectOverflowIsRejected;

    [Test]
    procedure TestRectTests;

    [Test]
    procedure TestRectRejectsNonFiniteAndInverted;

    [Test]
    procedure TestRectRejectsOverflowingSize;

    [Test]
    procedure TestRectEmptyRoundIntersectJoinInset;

    [Test]
    procedure TestRectFromPoints;

    [Test]
    procedure TestRectFromPointsRejectsNonFinite;

    [Test]
    procedure TestNonZeroRectTests;

    [Test]
    procedure TestNonZeroRectConversions;

    [Test]
    procedure TestScreenIntRectTests;

    [Test]
    procedure TestScreenIntRectRejectsOverflow;

    [Test]
    procedure TestScreenIntRectConversions;

    [Test]
    procedure TestScreenIntRectToIntRectRaisesWhenTheRightEdgeExceedsInt32;
  end;

implementation

{ TTsGeometryTests }

function TTsGeometryTests.MakeRect(const Left, Top, Right, Bottom: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromLTRB(Left, Top, Right, Bottom, Result), 'a valid rect');
end;

function TTsGeometryTests.MakeNonZeroRect(const Left, Top, Right, Bottom: Single): TTsNonZeroRect;
begin
  Assert.IsTrue(TTsNonZeroRect.TryFromLTRB(Left, Top, Right, Bottom, Result), 'a valid non-zero rect');
end;

function TTsGeometryTests.MakeIntRect(const X, Y: Integer; const Width, Height: Cardinal): TTsIntRect;
begin
  Assert.IsTrue(TTsIntRect.TryFromXYWH(X, Y, Width, Height, Result), 'a valid int rect');
end;

function TTsGeometryTests.MakeIntSize(const Width, Height: Cardinal): TTsIntSize;
begin
  Assert.IsTrue(TTsIntSize.TryFromWH(Width, Height, Result), 'a valid int size');
end;

function TTsGeometryTests.MakeSize(const Width, Height: Single): TTsSize;
begin
  Assert.IsTrue(TTsSize.TryFromWH(Width, Height, Result), 'a valid size');
end;

procedure TTsGeometryTests.AssertRect(const Left, Top, Right, Bottom: Single; const Actual: TTsRect);
begin
  Assert.IsTrue(Actual = MakeRect(Left, Top, Right, Bottom),
    Format('expected (%g, %g, %g, %g), got (%g, %g, %g, %g)', [Left, Top, Right, Bottom, Actual.Left, Actual.Top, Actual.Right, Actual.Bottom]));
end;

procedure TTsGeometryTests.AssertIntRect(const X, Y: Integer; const Width, Height: Cardinal; const Actual: TTsIntRect);
begin
  Assert.IsTrue(Actual = MakeIntRect(X, Y, Width, Height),
    Format('expected (%d, %d, %d, %d), got (%d, %d, %d, %d)', [X, Y, Width, Height, Actual.X, Actual.Y, Actual.Width, Actual.Height]));
end;

procedure TTsGeometryTests.ConvertWideScreenRectToIntRect;
begin
  var Rect: TTsScreenIntRect;

  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(2147483000, 0, 1000, 1, Rect));
  Rect.ToIntRect;
end;

procedure TTsGeometryTests.TestPointBasics;
begin
  const P = TTsPoint.FromXY(3, 4);

  Assert.AreEqual<Single>(5, P.Length);
  Assert.AreEqual<Single>(25, P.LengthSqd);
  Assert.AreEqual<Single>(11, P.Dot(TTsPoint.FromXY(1, 2)));
  Assert.AreEqual<Single>(2, P.Cross(TTsPoint.FromXY(1, 2)));
  Assert.AreEqual<Single>(5, P.Distance(TTsPoint.Zero));
  Assert.AreEqual<Single>(25, P.DistanceToSqd(TTsPoint.Zero));
  Assert.IsTrue(TTsPoint.Zero.IsZero);
  Assert.IsFalse(P.IsZero);
  Assert.IsTrue(P.EqualsWithinTolerance(TTsPoint.FromXY(3.0001, 4), 0.001));
  Assert.IsFalse(P.EqualsWithinTolerance(TTsPoint.FromXY(3.1, 4), 0.001));
  Assert.IsTrue(P.AlmostEqual(P));
  Assert.IsFalse(P.AlmostEqual(TTsPoint.FromXY(3, 5)));

  var Moved := P;
  Moved.RotateCw;
  Assert.IsTrue(Moved = TTsPoint.FromXY(-4, 3));

  Moved := P;
  Moved.RotateCcw;
  Assert.IsTrue(Moved = TTsPoint.FromXY(4, -3));

  Moved := P;
  Moved.Scale(2);
  Assert.IsTrue(Moved = TTsPoint.FromXY(6, 8));
  Assert.IsTrue(P.Scaled(0.5) = TTsPoint.FromXY(1.5, 2));

  const FromTuple = TTsPoint.FromF32x2(P.ToF32x2);
  Assert.IsTrue(FromTuple = P);
end;

procedure TTsGeometryTests.TestPointNormalize;
begin
  var P := TTsPoint.FromXY(3, 4);

  Assert.IsTrue(P.Normalize);
  Assert.AreEqual(0.6, P.X, 1E-6);
  Assert.AreEqual(0.8, P.Y, 1E-6);

  var Q := TTsPoint.FromXY(3, 4);

  Assert.IsTrue(Q.SetLength(10));
  Assert.AreEqual(6.0, Q.X, 1E-5);
  Assert.AreEqual(8.0, Q.Y, 1E-5);

  var Zero := TTsPoint.FromXY(0, 0);
  const State = TTsFloatMode.Enter;
  try
    Assert.IsFalse(Zero.Normalize, 'a vector of length zero cannot be normalized');
  finally
    TTsFloatMode.Leave(State);
  end;
  Assert.IsTrue(Zero = TTsPoint.Zero);

  var Set1 := TTsPoint.FromXY(9, 9);

  Assert.IsTrue(Set1.SetNormalize(0, 5));
  Assert.IsTrue(Set1 = TTsPoint.FromXY(0, 1));
end;

procedure TTsGeometryTests.TestPointNormalizeOfAHugeVector;
begin
  // x * x overflows an f32, the f64 path keeps the direction
  var P := TTsPoint.FromXY(2E38, 1.5E38);

  const State = TTsFloatMode.Enter;
  try
    Assert.AreEqual(2.5E38, Double(P.Length), 1E32, 'length');
    Assert.IsTrue(P.Normalize, 'normalize');
    Assert.AreEqual(0.8, P.X, 1E-6);
    Assert.AreEqual(0.6, P.Y, 1E-6);
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsGeometryTests.TestPointNonFiniteChecks;
begin
  const State = TTsFloatMode.Enter;
  try
    Assert.IsTrue(TTsPoint.FromXY(1, 2).IsFinite);
    Assert.IsFalse(TTsPoint.FromXY(Single.NaN, 2).IsFinite);
    Assert.IsFalse(TTsPoint.FromXY(Single.PositiveInfinity, 2).IsFinite);
    Assert.IsFalse(TTsPoint.FromXY(Single.PositiveInfinity, 0).IsFinite, 'inf * 0 is NaN');

    Assert.IsFalse(TTsPoint.FromXY(Single.NaN, 2).CanNormalize);
    Assert.IsFalse(TTsPoint.FromXY(0, 0).CanNormalize);
    Assert.IsTrue(TTsPoint.FromXY(0, 1).CanNormalize);

    Assert.IsFalse(TTsPoint.FromXY(Single.NaN, 1) = TTsPoint.FromXY(Single.NaN, 1), 'a NaN is not equal to itself');
    Assert.IsTrue(TTsPoint.FromXY(Single.NaN, 1) <> TTsPoint.FromXY(Single.NaN, 1));
    Assert.IsFalse(TTsPoint.FromXY(Single.NaN, 0).IsZero);
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsGeometryTests.TestPointOperators;
begin
  const A = TTsPoint.FromXY(1, 2);
  const B = TTsPoint.FromXY(3, 5);

  Assert.IsTrue((A + B) = TTsPoint.FromXY(4, 7));
  Assert.IsTrue((B - A) = TTsPoint.FromXY(2, 3));
  Assert.IsTrue((A * B) = TTsPoint.FromXY(3, 10));
  Assert.IsTrue((-A) = TTsPoint.FromXY(-1, -2));
  Assert.IsTrue(A <> B);
end;

procedure TTsGeometryTests.TestIntSizeTests;
begin
  var Size: TTsIntSize;

  Assert.IsFalse(TTsIntSize.TryFromWH(0, 0, Size));
  Assert.IsFalse(TTsIntSize.TryFromWH(1, 0, Size));
  Assert.IsFalse(TTsIntSize.TryFromWH(0, 1, Size));

  Size := MakeIntSize(3, 4);
  Assert.AreEqual<Cardinal>(3, Size.Width);
  Assert.AreEqual<Cardinal>(4, Size.Height);
  AssertIntRect(1, 2, 3, 4, Size.ToIntRect(1, 2));

  var Width, Height: Cardinal;
  Size.Dimensions(Width, Height);
  Assert.AreEqual<Cardinal>(3, Width);
  Assert.AreEqual<Cardinal>(4, Height);
end;

procedure TTsGeometryTests.TestIntSizeScaling;
begin
  var Scaled: TTsIntSize;

  Assert.IsTrue(MakeIntSize(3, 4).TryScaleBy(1.5, Scaled), 'half way rounds away from zero');
  Assert.IsTrue(Scaled = MakeIntSize(5, 6));
  Assert.IsFalse(MakeIntSize(3, 4).TryScaleBy(0.1, Scaled), 'the scaled width is 0');

  Assert.IsTrue(MakeIntSize(3, 4).TryScaleToWidth(6, Scaled));
  Assert.IsTrue(Scaled = MakeIntSize(6, 8));
  Assert.IsTrue(MakeIntSize(3, 4).TryScaleToHeight(8, Scaled));
  Assert.IsTrue(Scaled = MakeIntSize(6, 8));
  Assert.IsTrue(MakeIntSize(3, 4).TryScaleToWidth(1, Scaled));
  Assert.IsTrue(Scaled = MakeIntSize(1, 2), 'the height is rounded up');

  Assert.IsTrue(MakeIntSize(100, 50).ScaleTo(MakeIntSize(200, 200)) = MakeIntSize(200, 100));
  Assert.IsTrue(MakeIntSize(50, 100).ScaleTo(MakeIntSize(200, 200)) = MakeIntSize(100, 200));
end;

procedure TTsGeometryTests.TestSizeTryFromWHRejectsInvalid;
begin
  var Size: TTsSize;

  Assert.IsFalse(TTsSize.TryFromWH(0, 1, Size));
  Assert.IsFalse(TTsSize.TryFromWH(1, 0, Size));
  Assert.IsFalse(TTsSize.TryFromWH(-1, 1, Size));
  Assert.IsFalse(TTsSize.TryFromWH(Single.NaN, 1, Size));
  Assert.IsFalse(TTsSize.TryFromWH(1, Single.PositiveInfinity, Size));
  Assert.IsTrue(TTsSize.TryFromWH(2, 3, Size));
  Assert.AreEqual<Single>(2, Size.Width);
  Assert.AreEqual<Single>(3, Size.Height);
end;

procedure TTsGeometryTests.TestSizeScaling;
begin
  var Scaled: TTsSize;

  Assert.IsTrue(MakeSize(100, 50).ScaleTo(MakeSize(200, 200)) = MakeSize(200, 100));
  Assert.IsTrue(MakeSize(100, 50).ExpandTo(MakeSize(200, 200)) = MakeSize(400, 200));
  Assert.IsTrue(MakeSize(2, 3).TryScaleBy(2, Scaled));
  Assert.IsTrue(Scaled = MakeSize(4, 6));
  Assert.IsFalse(MakeSize(2, 3).TryScaleBy(0, Scaled));
  Assert.IsTrue(MakeSize(2, 4).TryScaleToWidth(1, Scaled));
  Assert.IsTrue(Scaled = MakeSize(1, 2));
  Assert.IsTrue(MakeSize(2, 4).TryScaleToHeight(8, Scaled));
  Assert.IsTrue(Scaled = MakeSize(4, 8));
end;

procedure TTsGeometryTests.TestSizeConversions;
begin
  Assert.IsTrue(MakeSize(2.5, 0.2).ToIntSize = MakeIntSize(3, 1), 'rounds half away from zero, at least 1');
  Assert.IsTrue(MakeIntSize(3, 4).ToSize = MakeSize(3, 4));

  var Rect: TTsRect;
  Assert.IsTrue(MakeSize(3, 4).TryToRect(1, 2, Rect));
  AssertRect(1, 2, 4, 6, Rect);

  Assert.IsTrue(MakeSize(3, 4).ToNonZeroRect(1, 2) = MakeNonZeroRect(1, 2, 4, 6));
end;

procedure TTsGeometryTests.TestIntRectTests;
begin
  var Rect: TTsIntRect;

  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, 0, 0, 0, Rect));
  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, 0, 1, 0, Rect));
  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, 0, 0, 1, Rect));

  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, 0, High(Cardinal), High(Cardinal), Rect));
  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, 0, 1, High(Cardinal), Rect));
  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, 0, High(Cardinal), 1, Rect));

  Assert.IsFalse(TTsIntRect.TryFromXYWH(High(Integer), 0, 1, 1, Rect));
  Assert.IsFalse(TTsIntRect.TryFromXYWH(0, High(Integer), 1, 1, Rect));

  // No intersection.
  var Intersection: TTsIntRect;
  Assert.IsFalse(MakeIntRect(1, 2, 3, 4).TryIntersect(MakeIntRect(11, 12, 13, 14), Intersection));

  // Second inside the first one.
  Assert.IsTrue(MakeIntRect(1, 2, 30, 40).TryIntersect(MakeIntRect(11, 12, 13, 14), Intersection));
  AssertIntRect(11, 12, 13, 14, Intersection);

  // Partial overlap.
  Assert.IsTrue(MakeIntRect(1, 2, 30, 40).TryIntersect(MakeIntRect(11, 12, 50, 60), Intersection));
  AssertIntRect(11, 12, 20, 30, Intersection);

  Rect := MakeIntRect(1, 2, 3, 4);
  Assert.AreEqual(1, Rect.Left);
  Assert.AreEqual(2, Rect.Top);
  Assert.AreEqual(4, Rect.Right);
  Assert.AreEqual(6, Rect.Bottom);
  Assert.IsTrue(Rect.Size = MakeIntSize(3, 4));
end;

procedure TTsGeometryTests.TestIntRectContainsInsetOutsetTranslate;
begin
  var Result: TTsIntRect;

  Assert.IsTrue(MakeIntRect(0, 0, 10, 10).Contains(MakeIntRect(2, 2, 3, 3)));
  Assert.IsTrue(MakeIntRect(0, 0, 10, 10).Contains(MakeIntRect(0, 0, 10, 10)));
  Assert.IsFalse(MakeIntRect(0, 0, 10, 10).Contains(MakeIntRect(8, 8, 3, 3)));

  Assert.IsTrue(MakeIntRect(1, 2, 30, 40).TryInset(1, 1, Result));
  AssertIntRect(2, 3, 28, 38, Result);
  Assert.IsFalse(MakeIntRect(1, 2, 3, 4).TryInset(2, 2, Result), 'the width would be negative');
  Assert.IsFalse(MakeIntRect(1, 2, 2, 4).TryInset(1, 0, Result), 'the width would be zero');

  Assert.IsTrue(MakeIntRect(1, 2, 3, 4).TryMakeOutset(1, 1, Result));
  AssertIntRect(0, 1, 5, 6, Result);
  Assert.IsTrue(MakeIntRect(Low(Integer) + 1, 0, 2, 2).TryMakeOutset(10, 0, Result), 'the left edge saturates at i32::MIN');
  AssertIntRect(Low(Integer), 0, 13, 2, Result);

  Assert.IsTrue(MakeIntRect(1, 2, 3, 4).TryTranslate(10, -2, Result));
  AssertIntRect(11, 0, 3, 4, Result);
  Assert.IsTrue(MakeIntRect(1, 2, 3, 4).TryTranslateTo(7, 8, Result));
  AssertIntRect(7, 8, 3, 4, Result);
  Assert.IsFalse(MakeIntRect(1, 2, 3, 4).TryTranslateTo(High(Integer), 0, Result));
end;

procedure TTsGeometryTests.TestIntRectOverflowIsRejected;
begin
  var Rect: TTsIntRect;

  Assert.IsFalse(TTsIntRect.TryFromLTRB(Low(Integer), 0, High(Integer), 1, Rect), 'the width does not fit in an i32');
  Assert.IsFalse(TTsIntRect.TryFromLTRB(5, 0, 1, 1, Rect));
  Assert.IsTrue(TTsIntRect.TryFromLTRB(1, 2, 4, 6, Rect));
  AssertIntRect(1, 2, 3, 4, Rect);
  Assert.IsFalse(TTsIntRect.TryFromXYWH(Low(Integer), 0, 2147483648, 1, Rect), 'the width does not fit in an i32');
end;

procedure TTsGeometryTests.TestRectTests;
begin
  var Rect: TTsRect;

  Assert.IsFalse(TTsRect.TryFromLTRB(10, 10, 5, 10, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(10, 10, 10, 5, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(Single.NaN, 10, 10, 10, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(10, Single.NaN, 10, 10, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(10, 10, Single.NaN, 10, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(10, 10, 10, Single.NaN, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(10, 10, 10, Single.PositiveInfinity, Rect));

  Rect := MakeRect(10, 20, 30, 40);
  Assert.AreEqual<Single>(10, Rect.Left);
  Assert.AreEqual<Single>(20, Rect.Top);
  Assert.AreEqual<Single>(30, Rect.Right);
  Assert.AreEqual<Single>(40, Rect.Bottom);
  Assert.AreEqual<Single>(20, Rect.Width);
  Assert.AreEqual<Single>(20, Rect.Height);

  Rect := MakeRect(-30, 20, -10, 40);
  Assert.AreEqual<Single>(20, Rect.Width);
  Assert.AreEqual<Single>(20, Rect.Height);

  Assert.IsTrue(TTsRect.TryFromXYWH(1, 2, 3, 4, Rect));
  AssertRect(1, 2, 4, 6, Rect);
end;

procedure TTsGeometryTests.TestRectRejectsNonFiniteAndInverted;
begin
  var Rect: TTsRect;

  Assert.IsFalse(TTsRect.TryFromLTRB(0, 0, Single.NaN, 1, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(5, 0, 1, 1, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(Single.NaN, Single.NaN, Single.NaN, Single.NaN, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(0, 0, Single.PositiveInfinity, 1, Rect));
  Assert.IsFalse(TTsRect.TryFromLTRB(Single.NegativeInfinity, 0, 1, 1, Rect));
end;

procedure TTsGeometryTests.TestRectRejectsOverflowingSize;
begin
  var Rect: TTsRect;

  Assert.IsFalse(TTsRect.TryFromLTRB(-3E38, 0, 3E38, 1, Rect), 'the width is larger than f32::MAX');
  Assert.IsFalse(TTsRect.TryFromLTRB(0, -3E38, 1, 3E38, Rect), 'the height is larger than f32::MAX');
  Assert.IsTrue(TTsRect.TryFromLTRB(-1E38, 0, 1E38, 1, Rect));
end;

procedure TTsGeometryTests.TestRectEmptyRoundIntersectJoinInset;
begin
  var Result: TTsRect;
  var IntResult: TTsIntRect;

  Assert.IsTrue(MakeRect(1, 1, 1, 5).IsEmpty);
  Assert.IsTrue(MakeRect(1, 1, 5, 1).IsEmpty);
  Assert.IsFalse(MakeRect(1, 1, 5, 5).IsEmpty);

  Assert.IsTrue(MakeRect(1.2, 2.7, 4.2, 6.1).TryRound(IntResult));
  AssertIntRect(1, 2, 3, 4, IntResult);
  Assert.IsTrue(MakeRect(1.2, 2.7, 4.2, 6.1).TryRoundOut(IntResult));
  AssertIntRect(1, 2, 4, 5, IntResult);
  Assert.IsTrue(MakeRect(1, 1, 1, 1).TryRound(IntResult), 'width and height are at least 1');
  AssertIntRect(1, 1, 1, 1, IntResult);
  Assert.IsTrue(MakeRect(1, 1, 1, 1).TryRoundOut(IntResult));
  AssertIntRect(1, 1, 1, 1, IntResult);

  Assert.IsTrue(MakeRect(0, 0, 2, 2).TryIntersect(MakeRect(1, 1, 3, 3), Result));
  AssertRect(1, 1, 2, 2, Result);
  Assert.IsFalse(MakeRect(0, 0, 1, 1).TryIntersect(MakeRect(2, 2, 3, 3), Result));
  Assert.IsTrue(MakeRect(0, 0, 2, 2).TryIntersect(MakeRect(2, 2, 3, 3), Result), 'a touching corner is an empty rect');
  Assert.IsTrue(Result.IsEmpty);

  Assert.IsTrue(MakeRect(0, 0, 1, 1).TryJoin(MakeRect(2, 2, 3, 3), Result));
  AssertRect(0, 0, 3, 3, Result);
  Assert.IsTrue(MakeRect(0, 0, 1, 1).TryJoin(MakeRect(5, 5, 5, 9), Result), 'an empty other rect is ignored');
  AssertRect(0, 0, 1, 1, Result);
  Assert.IsTrue(MakeRect(5, 5, 5, 9).TryJoin(MakeRect(0, 0, 1, 1), Result), 'an empty rect is ignored');
  AssertRect(0, 0, 1, 1, Result);
  Assert.IsFalse(MakeRect(-3E38, 0, -2E38, 1).TryJoin(MakeRect(2E38, 0, 3E38, 1), Result), 'the width would overflow');

  Assert.IsTrue(MakeRect(0, 0, 4, 4).TryInset(1, 1, Result));
  AssertRect(1, 1, 3, 3, Result);
  Assert.IsFalse(MakeRect(0, 0, 4, 4).TryInset(3, 3, Result));
  Assert.IsTrue(MakeRect(0, 0, 4, 4).TryOutset(1, 1, Result));
  AssertRect(-1, -1, 5, 5, Result);
end;

procedure TTsGeometryTests.TestRectFromPoints;
begin
  var Rect: TTsRect;

  Assert.IsFalse(TTsRect.TryFromPoints([], Rect), 'no points');

  Assert.IsTrue(TTsRect.TryFromPoints([TTsPoint.FromXY(1, 2)], Rect));
  AssertRect(1, 2, 1, 2, Rect);

  Assert.IsTrue(TTsRect.TryFromPoints([TTsPoint.FromXY(3, 4), TTsPoint.FromXY(1, 0)], Rect));
  AssertRect(1, 0, 3, 4, Rect);

  Assert.IsTrue(TTsRect.TryFromPoints([TTsPoint.FromXY(0, 0), TTsPoint.FromXY(5, 1), TTsPoint.FromXY(2, -3)], Rect));
  AssertRect(0, -3, 5, 1, Rect);

  Assert.IsTrue(TTsRect.TryFromPoints([TTsPoint.FromXY(0, 0), TTsPoint.FromXY(5, 1), TTsPoint.FromXY(2, -3), TTsPoint.FromXY(-1, 7)], Rect));
  AssertRect(-1, -3, 5, 7, Rect);

  Assert.IsTrue(TTsRect.TryFromPoints([TTsPoint.FromXY(0, 0), TTsPoint.FromXY(5, 1), TTsPoint.FromXY(2, -3), TTsPoint.FromXY(-1, 7),
    TTsPoint.FromXY(9, 9)], Rect));
  AssertRect(-1, -3, 9, 9, Rect);
end;

procedure TTsGeometryTests.TestRectFromPointsRejectsNonFinite;
begin
  var Rect: TTsRect;

  const State = TTsFloatMode.Enter;
  try
    Assert.IsFalse(TTsRect.TryFromPoints([TTsPoint.FromXY(Single.NaN, 2)], Rect));
    Assert.IsFalse(TTsRect.TryFromPoints([TTsPoint.FromXY(Single.NaN, 2), TTsPoint.FromXY(1, 1)], Rect));
    Assert.IsFalse(TTsRect.TryFromPoints([TTsPoint.FromXY(1, 1), TTsPoint.FromXY(Single.PositiveInfinity, 1)], Rect));
    Assert.IsFalse(TTsRect.TryFromPoints([TTsPoint.FromXY(0, 0), TTsPoint.FromXY(1, 1), TTsPoint.FromXY(Single.NaN, 3)], Rect));
    Assert.IsFalse(TTsRect.TryFromPoints([TTsPoint.FromXY(0, 0), TTsPoint.FromXY(1, 1), TTsPoint.FromXY(2, 3),
      TTsPoint.FromXY(4, Single.PositiveInfinity)], Rect));
    Assert.IsFalse(TTsRect.TryFromPoints([TTsPoint.FromXY(0, 0), TTsPoint.FromXY(1, 1), TTsPoint.FromXY(2, 3),
      TTsPoint.FromXY(Single.NegativeInfinity, 4), TTsPoint.FromXY(5, 5)], Rect));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsGeometryTests.TestNonZeroRectTests;
begin
  var Rect: TTsNonZeroRect;

  Assert.IsFalse(TTsNonZeroRect.TryFromLTRB(1, 1, 1, 2, Rect), 'zero width');
  Assert.IsFalse(TTsNonZeroRect.TryFromLTRB(1, 1, 2, 1, Rect), 'zero height');
  Assert.IsFalse(TTsNonZeroRect.TryFromLTRB(2, 1, 1, 2, Rect));
  Assert.IsFalse(TTsNonZeroRect.TryFromLTRB(Single.NaN, 1, 2, 2, Rect));
  Assert.IsFalse(TTsNonZeroRect.TryFromLTRB(-3E38, 0, 3E38, 1, Rect));

  Assert.IsTrue(TTsNonZeroRect.TryFromXYWH(1, 2, 3, 4, Rect));
  Assert.AreEqual<Single>(1, Rect.X);
  Assert.AreEqual<Single>(2, Rect.Y);
  Assert.AreEqual<Single>(3, Rect.Width);
  Assert.AreEqual<Single>(4, Rect.Height);
  Assert.AreEqual<Single>(4, Rect.Right);
  Assert.AreEqual<Single>(6, Rect.Bottom);
  Assert.IsTrue(Rect.Size = MakeSize(3, 4));
end;

procedure TTsGeometryTests.TestNonZeroRectConversions;
begin
  var Moved: TTsNonZeroRect;
  const Rect = MakeNonZeroRect(1.5, 2.5, 4.7, 3.6);

  AssertRect(1.5, 2.5, 4.7, 3.6, MakeNonZeroRect(1.5, 2.5, 4.7, 3.6).ToRect);
  AssertIntRect(1, 2, 4, 2, Rect.ToIntRect);

  Assert.IsTrue(Rect.TryTranslateTo(10, 20, Moved));
  Assert.AreEqual<Single>(10, Moved.X);
  Assert.AreEqual<Single>(20, Moved.Y);
  Assert.AreEqual<Single>(Rect.Width, Moved.Width);
end;

procedure TTsGeometryTests.TestScreenIntRectTests;
begin
  var Rect: TTsScreenIntRect;

  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, 0, 0, Rect));
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, 1, 0, Rect));
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, 0, 1, Rect));

  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, High(Cardinal), High(Cardinal), Rect));
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, 1, High(Cardinal), Rect));
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, High(Cardinal), 1, Rect));

  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(High(Cardinal), 0, 1, 1, Rect));
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, High(Cardinal), 1, 1, Rect));

  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(High(Cardinal), High(Cardinal), High(Cardinal), High(Cardinal), Rect));

  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(1, 2, 3, 4, Rect));
  Assert.AreEqual<Cardinal>(1, Rect.X);
  Assert.AreEqual<Cardinal>(2, Rect.Y);
  Assert.AreEqual<Cardinal>(3, Rect.Width);
  Assert.AreEqual<Cardinal>(4, Rect.Height);
  Assert.AreEqual<Cardinal>(4, Rect.Right);
  Assert.AreEqual<Cardinal>(6, Rect.Bottom);
  Assert.IsTrue(Rect.Size = MakeIntSize(3, 4));
end;

// The brief of this port expected TryFromXYWH(2147483000, 0, 1000, 1) to fail. The Rust code accepts it: every value fits an i32 and the
// u32 sums cannot overflow when all four values are at most i32::MAX. The cases that fail are a value above i32::MAX and a zero length.
procedure TTsGeometryTests.TestScreenIntRectRejectsOverflow;
begin
  var Rect: TTsScreenIntRect;

  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(2147483000, 0, 1000, 1, Rect), 'the sums fit in a u32, as in the Rust code');
  Assert.AreEqual<Cardinal>(2147484000, Rect.Right);

  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(2147483648, 0, 1, 1, Rect), 'x is above i32::MAX');
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 2147483648, 1, 1, Rect), 'y is above i32::MAX');
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, 2147483648, 1, Rect), 'the width is above i32::MAX');
  Assert.IsFalse(TTsScreenIntRect.TryFromXYWH(0, 0, 1, 2147483648, Rect), 'the height is above i32::MAX');
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(2147483647, 2147483647, 2147483647, 2147483647, Rect));
  Assert.AreEqual<Cardinal>(4294967294, Rect.Right);
end;

procedure TTsGeometryTests.TestScreenIntRectConversions;
begin
  var Rect: TTsScreenIntRect;

  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(1, 2, 3, 4, Rect));
  AssertIntRect(1, 2, 3, 4, Rect.ToIntRect);
  AssertRect(1, 2, 4, 6, Rect.ToRect);
  Assert.IsTrue(MakeIntSize(3, 4).ToScreenIntRect(1, 2) = Rect);

  var FromInt: TTsScreenIntRect;
  Assert.IsTrue(MakeIntRect(1, 2, 3, 4).TryToScreenIntRect(FromInt));
  Assert.IsTrue(FromInt = Rect);
  Assert.IsFalse(MakeIntRect(-1, 2, 3, 4).TryToScreenIntRect(FromInt));
  Assert.IsFalse(MakeIntRect(1, -2, 3, 4).TryToScreenIntRect(FromInt));

  AssertRect(1, 2, 4, 6, MakeIntRect(1, 2, 3, 4).ToRect);

  Assert.IsTrue(Rect.Contains(Rect));
  Assert.IsTrue(MakeIntRect(1, 2, 3, 4).Contains(MakeIntRect(2, 3, 1, 1)));

  var Inner: TTsScreenIntRect;
  Assert.IsTrue(TTsScreenIntRect.TryFromXYWH(2, 3, 1, 1, Inner));
  Assert.IsTrue(Rect.Contains(Inner));
  Assert.IsFalse(Inner.Contains(Rect));
end;

procedure TTsGeometryTests.TestScreenIntRectToIntRectRaisesWhenTheRightEdgeExceedsInt32;
begin
  Assert.WillRaise(ConvertWideScreenRectToIntRect, ETsGeometryError);
end;

end.
