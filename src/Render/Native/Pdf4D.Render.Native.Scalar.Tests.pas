// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Scalar.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar;

type
  [TestFixture]
  TTsScalarTests = class
  private
    FZero: Single;
    FStep: Single;
    FBig: Single;
    FSum: Single;

  public
    [Test]
    procedure TestSaturateToInt32;

    [Test]
    procedure TestSaturateFromKeepsTheRustRange;

    [Test]
    procedure TestRoundHalfAwayFromZero;

    [Test]
    procedure TestMinMaxIgnoreNaN;

    [Test]
    procedure TestFloorCeilTruncKeepSingle;

    [Test]
    procedure TestFloorCeilTruncKeepTheSignOfZero;

    [Test]
    procedure TestBoundReturnsMaxForNaN;

    [Test]
    procedure TestIsNearlyZero;

    [Test]
    procedure TestIsFinite;

    [Test]
    procedure TestWrappingAndSaturatingIntegers;

    [Test]
    procedure TestLeftShiftWraps;

    [Test]
    procedure TestShiftRightKeepsTheSign;

    [Test]
    procedure TestAlmostDequalUlps;

    [Test]
    procedure TestNormalizedF32Clamps;

    [Test]
    procedure TestNormalizedF32TryCreateRejectsOutOfRange;

    [Test]
    procedure TestNormalizedF32ExclusiveBounds;

    [Test]
    procedure TestFiniteAndNonZeroPositiveTryCreate;

    [Test]
    procedure TestRemainderKeepsTheSignOfTheDividend;

    [Test]
    procedure TestFloatModeMasksAndRestores;

    [Test]
    procedure TestSingleStepsRoundPerOperation;
  end;

implementation

{ TTsScalarTests }

procedure TTsScalarTests.TestSaturateToInt32;
begin
  Assert.AreEqual(2147483647, TTsScalar.SaturateToInt32(3E9));
  Assert.AreEqual(-2147483648, TTsScalar.SaturateToInt32(-3E9));
  Assert.AreEqual(0, TTsScalar.SaturateToInt32(Single.NaN));
  Assert.AreEqual(1, TTsScalar.SaturateToInt32(1.9));
  Assert.AreEqual(-1, TTsScalar.SaturateToInt32(-1.9));
  Assert.AreEqual(2147483647, TTsScalar.SaturateToInt32(Single.PositiveInfinity));
end;

procedure TTsScalarTests.TestSaturateFromKeepsTheRustRange;
begin
  Assert.AreEqual(2147483520, TTsScalar.SaturateFrom(3E9));
  Assert.AreEqual(-2147483520, TTsScalar.SaturateFrom(-3E9));
  Assert.AreEqual(2147483520, TTsScalar.SaturateFrom(Single.NaN));
  Assert.AreEqual(2, TTsScalar.SaturateRound(2.6), 'saturate_round is floor(x) + 0.5 as in the Rust source');
  Assert.AreEqual(3, TTsScalar.SaturateRound(3.0));
  Assert.AreEqual(-2, TTsScalar.SaturateFloor(-1.5));
  Assert.AreEqual(-1, TTsScalar.SaturateCeil(-1.5));
  Assert.AreEqual(2147483647, TTsScalar.SaturateFromF64(1E12));
  Assert.AreEqual(2147483647, TTsScalar.SaturateFromF64(Double.NaN));
end;

procedure TTsScalarTests.TestRoundHalfAwayFromZero;
begin
  Assert.AreEqual<Single>(1, TTsScalar.RoundHalfAwayFromZero(0.5));
  Assert.AreEqual<Single>(-1, TTsScalar.RoundHalfAwayFromZero(-0.5));
  Assert.AreEqual<Single>(3, TTsScalar.RoundHalfAwayFromZero(2.5));
  Assert.AreEqual<Single>(2, TTsScalar.RoundHalfAwayFromZero(2.4));
  Assert.AreEqual<Single>(-3, TTsScalar.RoundHalfAwayFromZero(-2.5));
  Assert.AreEqual<Single>(1E20, TTsScalar.RoundHalfAwayFromZero(1E20));
end;

procedure TTsScalarTests.TestMinMaxIgnoreNaN;
begin
  Assert.AreEqual<Single>(1, TTsScalar.MinF(Single.NaN, 1));
  Assert.AreEqual<Single>(1, TTsScalar.MinF(1, Single.NaN));
  Assert.AreEqual<Single>(-1, TTsScalar.MaxF(Single.NaN, -1));
  Assert.AreEqual<Single>(-1, TTsScalar.MaxF(-1, Single.NaN));
  Assert.AreEqual<Single>(1, TTsScalar.MinF(2, 1));
  Assert.AreEqual<Single>(2, TTsScalar.MaxF(2, 1));
end;

procedure TTsScalarTests.TestFloorCeilTruncKeepSingle;
begin
  Assert.AreEqual<Single>(-2, TTsScalar.FloorF(-1.5));
  Assert.AreEqual<Single>(-1, TTsScalar.CeilF(-1.5));
  Assert.AreEqual<Single>(-1, TTsScalar.TruncF(-1.5));
  Assert.AreEqual<Single>(1, TTsScalar.FloorF(1.5));
  Assert.AreEqual<Single>(2, TTsScalar.CeilF(1.5));
  Assert.AreEqual<Single>(1, TTsScalar.TruncF(1.5));
  Assert.AreEqual<Single>(1E20, TTsScalar.FloorF(1E20));
  Assert.AreEqual<Single>(-1E20, TTsScalar.CeilF(-1E20));
  Assert.IsTrue(IsNan(TTsScalar.FloorF(Single.NaN)));
end;

procedure TTsScalarTests.TestFloorCeilTruncKeepTheSignOfZero;
begin
  Assert.IsTrue(TTsScalar.IsSignNegative(TTsScalar.CeilF(-0.5)), 'ceil(-0.5) is -0');
  Assert.IsTrue(TTsScalar.IsSignNegative(TTsScalar.TruncF(-0.5)), 'trunc(-0.5) is -0');
  Assert.IsFalse(TTsScalar.IsSignNegative(TTsScalar.FloorF(0.5)), 'floor(0.5) is +0');
  Assert.IsTrue(TTsScalar.IsSignNegative(TTsScalar.RoundHalfAwayFromZero(-0.25)), 'round(-0.25) is -0');
end;

procedure TTsScalarTests.TestBoundReturnsMaxForNaN;
begin
  Assert.AreEqual<Single>(1, TTsScalar.Bound(Single.NaN, 0, 1));
  Assert.AreEqual<Single>(1, TTsScalar.Bound(Single.PositiveInfinity, 0, 1));
  Assert.AreEqual<Single>(0, TTsScalar.Bound(Single.NegativeInfinity, 0, 1));
  Assert.AreEqual<Single>(0.5, TTsScalar.Bound(0.5, 0, 1));
  Assert.AreEqual<Single>(0, TTsScalar.Bound(-1, 0, 1));
  Assert.AreEqual<Single>(1, TTsScalar.Bound(2, 0, 1));
  Assert.AreEqual(5, TTsScalar.BoundInt(0, 5, 9));
  Assert.AreEqual(9, TTsScalar.BoundInt(0, 12, 9));
end;

procedure TTsScalarTests.TestIsNearlyZero;
begin
  Assert.IsTrue(TTsScalar.IsNearlyZero(0.0002));
  Assert.IsFalse(TTsScalar.IsNearlyZero(0.0003));
  Assert.IsTrue(TTsScalar.IsNearlyZero(-0.0002));
  Assert.IsTrue(TTsScalar.IsNearlyEqual(1, 1.0002));
  Assert.IsFalse(TTsScalar.IsNearlyEqual(1, 1.001));
  Assert.IsTrue(TTsScalar.IsNearlyEqualWithinTolerance(1, 1.05, 0.1));
  Assert.IsTrue(TTsScalar.IsNearlyZeroWithinTolerance(0.05, 0.1));
end;

procedure TTsScalarTests.TestIsFinite;
begin
  Assert.IsTrue(TTsScalar.IsFinite(1));
  Assert.IsTrue(TTsScalar.IsFinite(0));
  Assert.IsFalse(TTsScalar.IsFinite(Single.NaN));
  Assert.IsFalse(TTsScalar.IsFinite(Single.PositiveInfinity));
  Assert.IsFalse(TTsScalar.IsFinite(Single.NegativeInfinity));
end;

procedure TTsScalarTests.TestWrappingAndSaturatingIntegers;
begin
  Assert.AreEqual<Cardinal>(1, TTsScalar.WrappingAddU32($FFFFFFFF, 2));
  Assert.AreEqual<Cardinal>($FFFFFFFF, TTsScalar.WrappingSubU32(0, 1));
  Assert.AreEqual(High(Integer), TTsScalar.WrappingSubI32(Low(Integer), 1));
  Assert.AreEqual(Low(Integer), TTsScalar.WrappingAddI32(High(Integer), 1));
  Assert.AreEqual(-5, TTsScalar.WrappingSubI32(5, 10));
  Assert.AreEqual<Cardinal>(0, TTsScalar.SaturatingSubU32(3, 5));
  Assert.AreEqual<Cardinal>(2, TTsScalar.SaturatingSubU32(5, 3));
end;

procedure TTsScalarTests.TestShiftRightKeepsTheSign;
begin
  Assert.AreEqual(-1, TTsScalar.ShiftRightI32(-1, 6));
  Assert.AreEqual(-2, TTsScalar.ShiftRightI32(-3, 1));
  Assert.AreEqual(-4, TTsScalar.ShiftRightI32(Low(Integer), 29));
  Assert.AreEqual(Low(Integer), TTsScalar.ShiftRightI32(Low(Integer), 0));
  Assert.AreEqual(5, TTsScalar.ShiftRightI32(40, 3));
  Assert.AreEqual(Int64(-1), TTsScalar.ShiftRightI64(-1, 16));
  Assert.AreEqual(Int64(-2), TTsScalar.ShiftRightI64(-65537, 16));
  Assert.AreEqual(Int64(3), TTsScalar.ShiftRightI64(Int64(3) shl 16 + 5, 16));
end;

procedure TTsScalarTests.TestLeftShiftWraps;
begin
  Assert.AreEqual(Low(Integer), TTsScalar.LeftShift(1, 31));
  Assert.AreEqual(-2, TTsScalar.LeftShift(-1, 1));
  Assert.AreEqual(Int64(1) shl 62, TTsScalar.LeftShift64(1, 62));
  Assert.AreEqual(Low(Int64), TTsScalar.LeftShift64(1, 63));
end;

procedure TTsScalarTests.TestAlmostDequalUlps;
begin
  Assert.IsTrue(TTsScalar.AlmostDequalUlps(1, 1));
  Assert.IsTrue(TTsScalar.AlmostDequalUlps(1, 1.0000001));
  Assert.IsFalse(TTsScalar.AlmostDequalUlps(1, 1.001));
  Assert.IsTrue(TTsScalar.AlmostDequalUlps(0, -0.0));
end;

procedure TTsScalarTests.TestNormalizedF32Clamps;
begin
  Assert.AreEqual<Single>(1, TTsNormalizedF32.CreateClamped(1.5).Get);
  Assert.AreEqual<Single>(0, TTsNormalizedF32.CreateClamped(-0.5).Get);
  Assert.AreEqual<Single>(0, TTsNormalizedF32.CreateClamped(Single.NaN).Get);
  Assert.AreEqual<Single>(0.25, TTsNormalizedF32.CreateClamped(0.25).Get);
end;

procedure TTsScalarTests.TestNormalizedF32TryCreateRejectsOutOfRange;
begin
  var Value: TTsNormalizedF32;

  Assert.IsTrue(TTsNormalizedF32.TryCreate(0, Value));
  Assert.IsTrue(TTsNormalizedF32.TryCreate(1, Value));
  Assert.IsFalse(TTsNormalizedF32.TryCreate(1.1, Value));
  Assert.IsFalse(TTsNormalizedF32.TryCreate(-0.1, Value));
  Assert.IsFalse(TTsNormalizedF32.TryCreate(Single.NaN, Value));
end;

procedure TTsScalarTests.TestNormalizedF32ExclusiveBounds;
begin
  var Value: TTsNormalizedF32Exclusive;

  Assert.IsFalse(TTsNormalizedF32Exclusive.TryCreate(0, Value));
  Assert.IsFalse(TTsNormalizedF32Exclusive.TryCreate(1, Value));
  Assert.IsTrue(TTsNormalizedF32Exclusive.TryCreate(0.5, Value));
  Assert.AreEqual<Single>(0.5, Value.Get);
  Assert.AreEqual<Single>(TTsScalar.FloatEpsilon, TTsNormalizedF32Exclusive.CreateBounded(0).Get);
  Assert.AreEqual<Single>(1 - TTsScalar.FloatEpsilon, TTsNormalizedF32Exclusive.CreateBounded(2).Get);
  Assert.AreEqual<Single>(0.5, TTsNormalizedF32Exclusive.Half.ToNormalized.Get);
end;

procedure TTsScalarTests.TestFiniteAndNonZeroPositiveTryCreate;
begin
  var Finite: TTsFiniteF32;
  var Positive: TTsNonZeroPositiveF32;

  Assert.IsTrue(TTsFiniteF32.TryCreate(-3, Finite));
  Assert.AreEqual<Single>(-3, Finite.Get);
  Assert.IsFalse(TTsFiniteF32.TryCreate(Single.PositiveInfinity, Finite));
  Assert.IsFalse(TTsFiniteF32.TryCreate(Single.NaN, Finite));

  Assert.IsTrue(TTsNonZeroPositiveF32.TryCreate(2, Positive));
  Assert.AreEqual<Single>(2, Positive.Get);
  Assert.IsFalse(TTsNonZeroPositiveF32.TryCreate(0, Positive));
  Assert.IsFalse(TTsNonZeroPositiveF32.TryCreate(-1, Positive));
  Assert.IsFalse(TTsNonZeroPositiveF32.TryCreate(Single.PositiveInfinity, Positive));
end;

procedure TTsScalarTests.TestFloatModeMasksAndRestores;
begin
  const PreviousMask = SetExceptionMask([]);
  try
    const MaskBeforeEnter = GetExceptionMask;
    FZero := 0;

    const State = TTsFloatMode.Enter;
    var Quotient: Single;
    try
      Quotient := 1 / FZero;
    finally
      TTsFloatMode.Leave(State);
    end;

    Assert.IsTrue(IsInfinite(Quotient));
    Assert.IsTrue(GetExceptionMask = MaskBeforeEnter, 'Leave restores the exception mask');
  finally
    SetExceptionMask(PreviousMask);
  end;
end;

procedure TTsScalarTests.TestRemainderKeepsTheSignOfTheDividend;
begin
  const NegativeZeroBits: Cardinal = $80000000;
  var NegativeZero: Single;
  Move(NegativeZeroBits, NegativeZero, SizeOf(Single));

  Assert.AreEqual<Single>(1, TTsScalar.RemainderF(7, 3));
  Assert.AreEqual<Single>(-1, TTsScalar.RemainderF(-7, 3));
  Assert.IsTrue(TTsScalar.IsSignNegative(TTsScalar.RemainderF(NegativeZero, 3)), 'Rust: -0 % 3 is -0');
  Assert.IsTrue(TTsScalar.IsSignNegative(TTsScalar.RemainderF(-6, 3)), 'Rust: -6 % 3 is -0');
  Assert.IsFalse(TTsScalar.IsSignNegative(TTsScalar.RemainderF(0, 3)), 'Rust: 0 % 3 is +0');
end;

procedure TTsScalarTests.TestSingleStepsRoundPerOperation;
begin
  FStep := 2.5;
  FBig := 8388608;

  const State = TTsFloatMode.Enter;
  try
    FSum := FStep + FBig;
    FSum := FSum - FBig;
  finally
    TTsFloatMode.Leave(State);
  end;

  Assert.AreEqual<Single>(2, FSum);
end;

end.
