// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Wide.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Wide;

type
  [TestFixture]
  TTsWideTests = class
  private
    FNaN: Single;

    procedure AssertLanes(const Expected: array of Single; const Actual: TF32x4); overload;
    procedure AssertLanes(const Expected: array of Single; const Actual: TF32x8); overload;
    procedure AssertLanes(const Expected: array of Integer; const Actual: TI32x4); overload;
    procedure AssertMask(const Expected: array of Boolean; const Actual: TF32x4); overload;
    procedure AssertMask(const Expected: array of Boolean; const Actual: TF32x8); overload;

  public
    [Setup]
    procedure Setup;

    [Test]
    procedure TestF32x4RoundIsHalfToEven;

    [Test]
    procedure TestF32x4RoundKeepsSpecialValues;

    [Test]
    procedure TestF32x4FloorOfNegatives;

    [Test]
    procedure TestTruncIntSaturates;

    [Test]
    procedure TestRoundIntUsesHalfToEven;

    [Test]
    procedure TestRecipSqrtIsOneOverSqrt;

    [Test]
    procedure TestBlendSelectsByMask;

    [Test]
    procedure TestU16x16WrapsOnOverflow;

    [Test]
    procedure TestF32x8LanesAreIndependent;

    [Test]
    procedure TestCmpMasksFollowRustForNaN;

    [Test]
    procedure TestBitOperationsWorkOnTheBits;

    [Test]
    procedure TestAbsAndNegAndNormalize;

    [Test]
    procedure TestMinMaxAreFasterVariants;

    [Test]
    procedure TestF32x8FractAndFloorRoundtrip;

    [Test]
    procedure TestIsFiniteMask;

    [Test]
    procedure TestIntegerTypesWrap;

    [Test]
    procedure TestIntegerComparesAndBlend;

    [Test]
    procedure TestU32ShiftsAndBitcasts;

    [Test]
    procedure TestU16x16Operations;

    [Test]
    procedure TestF32x16FloorAndSave;

    [Test]
    procedure TestF32x2AndPathF32x4;

    [Test]
    procedure TestEqualityIsFalseForNaN;
  end;

implementation

{ TTsWideTests }

procedure TTsWideTests.Setup;
begin
  FNaN := Single.NaN;
end;

procedure TTsWideTests.AssertLanes(const Expected: array of Single; const Actual: TF32x4);
begin
  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual<Single>(Expected[I], Actual.Lanes[I], Format('lane %d', [I]));
  end;
end;

procedure TTsWideTests.AssertLanes(const Expected: array of Single; const Actual: TF32x8);
begin
  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual<Single>(Expected[I], Actual.Lanes[I], Format('lane %d', [I]));
  end;
end;

procedure TTsWideTests.AssertLanes(const Expected: array of Integer; const Actual: TI32x4);
begin
  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual(Expected[I], Actual.Lanes[I], Format('lane %d', [I]));
  end;
end;

procedure TTsWideTests.AssertMask(const Expected: array of Boolean; const Actual: TF32x4);
begin
  const Bits = Actual.ToU32x4Bitcast;

  for var I := 0 to High(Expected) do
  begin
    const ExpectedBits: Cardinal = IfThen(Expected[I], $FFFFFFFF, 0);

    Assert.AreEqual<Cardinal>(ExpectedBits, Bits.Lanes[I], Format('mask lane %d', [I]));
  end;
end;

procedure TTsWideTests.AssertMask(const Expected: array of Boolean; const Actual: TF32x8);
begin
  const Bits = Actual.ToU32x8Bitcast;

  for var I := 0 to High(Expected) do
  begin
    const ExpectedBits: Cardinal = IfThen(Expected[I], $FFFFFFFF, 0);

    Assert.AreEqual<Cardinal>(ExpectedBits, Bits.Lanes[I], Format('mask lane %d', [I]));
  end;
end;

procedure TTsWideTests.TestF32x4RoundIsHalfToEven;
begin
  const Rounded = TF32x4.FromArray([0.5, 1.5, 2.5, -1.5]).Round;

  AssertLanes([0, 2, 2, -2], Rounded);
end;

procedure TTsWideTests.TestF32x4RoundKeepsSpecialValues;
begin
  const Rounded = TF32x4.FromArray([FNaN, 8388609.0, -0.25, 3.4]).Round;

  Assert.IsTrue(IsNan(Rounded.Lanes[0]), 'NaN stays NaN');
  Assert.AreEqual<Single>(8388609.0, Rounded.Lanes[1]);
  Assert.AreEqual<Single>(0, Rounded.Lanes[2]);
  Assert.AreEqual<Single>(3, Rounded.Lanes[3]);
end;

procedure TTsWideTests.TestF32x4FloorOfNegatives;
begin
  const Floored = TF32x4.FromArray([-1.5, 2.7, -3, 0.25]).Floor;

  AssertLanes([-2, 2, -3, 0], Floored);
end;

procedure TTsWideTests.TestTruncIntSaturates;
begin
  const Truncated = TF32x4.FromArray([FNaN, 3E9, -3E9, 1.9]).TruncInt;

  AssertLanes([0, 2147483647, -2147483648, 1], Truncated);
end;

procedure TTsWideTests.TestRoundIntUsesHalfToEven;
begin
  const Rounded = TF32x4.FromArray([2.5, 3.5, -2.5, 0.49]).RoundInt;

  AssertLanes([2, 4, -2, 0], Rounded);
end;

procedure TTsWideTests.TestRecipSqrtIsOneOverSqrt;
begin
  const Four = TF32x4.Splat(4);

  AssertLanes([0.5, 0.5, 0.5, 0.5], Four.RecipSqrt);
  AssertLanes([0.25, 0.25, 0.25, 0.25], Four.RecipFast);
  AssertLanes([2, 2, 2, 2], Four.Sqrt);
end;

procedure TTsWideTests.TestBlendSelectsByMask;
begin
  const Mask = TF32x4.FromArray([1, 5, 1, 5]).CmpGt(TF32x4.Splat(2));

  const Blended = Mask.Blend(TF32x4.Splat(9), TF32x4.Splat(0));

  AssertLanes([0, 9, 0, 9], Blended);
end;

procedure TTsWideTests.TestU16x16WrapsOnOverflow;
begin
  const Sum = TU16x16.Splat(65535) + TU16x16.Splat(1);
  const Difference = TU16x16.Splat(0) - TU16x16.Splat(1);
  const Product = TU16x16.Splat(256) * TU16x16.Splat(256);

  Assert.AreEqual<Word>(0, Sum.Lanes[0]);
  Assert.AreEqual<Word>(0, Sum.Lanes[15]);
  Assert.AreEqual<Word>(65535, Difference.Lanes[0]);
  Assert.AreEqual<Word>(65535, Difference.Lanes[15]);
  Assert.AreEqual<Word>(0, Product.Lanes[7]);
end;

procedure TTsWideTests.TestF32x8LanesAreIndependent;
begin
  const Values = TF32x8.FromArray([0.5, 1.5, 2.5, FNaN, 4.5, 5.5, 6.5, 7.5]);

  const Floored = Values.Floor;
  const Rounded = Values.Round;
  const Minimum = Values.Min(TF32x8.Splat(3));

  Assert.AreEqual<Single>(2, Floored.Lanes[2]);
  Assert.AreEqual<Single>(0, Floored.Lanes[3], 'floor(NaN) is 0 through trunc_int');
  Assert.AreEqual<Single>(4, Floored.Lanes[4]);
  Assert.AreEqual<Single>(2, Rounded.Lanes[2]);
  Assert.IsTrue(IsNan(Rounded.Lanes[3]));
  Assert.AreEqual<Single>(4, Rounded.Lanes[4]);
  Assert.AreEqual<Single>(2.5, Minimum.Lanes[2]);
  Assert.IsTrue(IsNan(Minimum.Lanes[3]), 'faster_min(NaN, 3): 3 < NaN is false, so self stays NaN');
  Assert.AreEqual<Single>(3, Minimum.Lanes[4]);
end;

procedure TTsWideTests.TestCmpMasksFollowRustForNaN;
begin
  const A = TF32x4.FromArray([FNaN, 1, 2, FNaN]);
  const B = TF32x4.FromArray([1, 1, 3, FNaN]);

  AssertMask([False, True, False, False], A.CmpEq(B));
  AssertMask([True, False, True, True], A.CmpNe(B));
  AssertMask([False, False, True, False], A.CmpLt(B));
  AssertMask([False, True, True, False], A.CmpLe(B));
  AssertMask([False, False, False, False], A.CmpGt(B));
  AssertMask([False, True, False, False], A.CmpGe(B));

  const A8 = TF32x8.FromArray([FNaN, 1, 2, FNaN, 5, 5, 5, 5]);
  const B8 = TF32x8.FromArray([1, 1, 3, FNaN, 4, 5, 6, FNaN]);

  AssertMask([False, False, True, False, False, False, True, False], A8.CmpLt(B8));
  AssertMask([False, False, False, False, True, False, False, False], A8.CmpGt(B8));
  AssertMask([True, False, True, True, True, False, True, True], A8.CmpNe(B8));
end;

procedure TTsWideTests.TestBitOperationsWorkOnTheBits;
begin
  const Mask = TF32x4.FromArray([1, 5, 1, 5]).CmpGt(TF32x4.Splat(2));
  const Inverted = not Mask;
  const Both = Mask and Inverted;
  const Either = Mask or Inverted;
  const Exclusive = Mask xor Inverted;

  AssertMask([False, True, False, True], Mask);
  AssertMask([True, False, True, False], Inverted);
  AssertMask([False, False, False, False], Both);
  AssertMask([True, True, True, True], Either);
  AssertMask([True, True, True, True], Exclusive);
end;

procedure TTsWideTests.TestAbsAndNegAndNormalize;
begin
  AssertLanes([1, 2, 0, 3], TF32x4.FromArray([-1, 2, -0.0, -3]).Abs);
  AssertLanes([-1, 2, 0, -3], -TF32x4.FromArray([1, -2, 0, 3]));
  const Normalized = TF32x8.FromArray([-1, 0.5, 1, 7, FNaN, 0, 1, 0.25]).Normalize;

  AssertLanes([0, 0.5, 1, 1], Normalized);
  Assert.IsTrue(IsNan(Normalized.Lanes[4]), 'NaN passes through max and min');
  AssertLanes([0, 0, 0, 0, 0, 0, 1, 0.25], TF32x8.FromArray([0, 0, 0, 0, 0, 0, 1, 0.25]).Normalize);
end;

procedure TTsWideTests.TestMinMaxAreFasterVariants;
begin
  const A = TF32x4.FromArray([1, 5, FNaN, 2]);
  const B = TF32x4.FromArray([3, 4, 7, FNaN]);

  const Minimum = A.Min(B);
  const Maximum = A.Max(B);

  Assert.AreEqual<Single>(1, Minimum.Lanes[0]);
  Assert.AreEqual<Single>(4, Minimum.Lanes[1]);
  Assert.IsTrue(IsNan(Minimum.Lanes[2]), 'faster_min(NaN, 7): 7 < NaN is false, so self');
  Assert.AreEqual<Single>(2, Minimum.Lanes[3], 'faster_min(2, NaN): NaN < 2 is false, so self');
  Assert.AreEqual<Single>(3, Maximum.Lanes[0]);
  Assert.AreEqual<Single>(5, Maximum.Lanes[1]);
  Assert.IsTrue(IsNan(Maximum.Lanes[2]), 'faster_max(NaN, 7): NaN < 7 is false, so self');
  Assert.AreEqual<Single>(2, Maximum.Lanes[3], 'faster_max(2, NaN): 2 < NaN is false, so self');
end;

procedure TTsWideTests.TestF32x8FractAndFloorRoundtrip;
begin
  const Values = TF32x8.FromArray([1.25, -1.25, 0, 3, 2.75, -0.5, 100.125, -100.125]);

  const Fraction = Values.Fract;

  AssertLanes([0.25, 0.75, 0, 0, 0.75, 0.5, 0.125, 0.875], Fraction);
end;

procedure TTsWideTests.TestIsFiniteMask;
begin
  const Values = TF32x8.FromArray([1, FNaN, Single.PositiveInfinity, Single.NegativeInfinity, 0, -3, 1E38, -0.0]);

  AssertMask([True, False, False, False, True, True, True, True], Values.IsFinite);
end;

procedure TTsWideTests.TestIntegerTypesWrap;
begin
  const Big = TI32x4.Splat(High(Integer));
  const Sum = Big + TI32x4.Splat(1);
  const Product = Big * TI32x4.Splat(2);
  const UnsignedSum = TU32x4.Splat($FFFFFFFF) + TU32x4.Splat(2);
  const UnsignedSum8 = TU32x8.Splat($FFFFFFFF) + TU32x8.Splat(2);
  const SignedSum8 = TI32x8.Splat(High(Integer)) + TI32x8.Splat(1);

  AssertLanes([Low(Integer), Low(Integer), Low(Integer), Low(Integer)], Sum);
  AssertLanes([-2, -2, -2, -2], Product);
  Assert.AreEqual<Cardinal>(1, UnsignedSum.Lanes[3]);
  Assert.AreEqual<Cardinal>(1, UnsignedSum8.Lanes[7]);
  Assert.AreEqual(Low(Integer), SignedSum8.Lanes[7]);
end;

procedure TTsWideTests.TestIntegerComparesAndBlend;
begin
  const A = TI32x4.FromArray([1, 5, -1, 5]);
  const B = TI32x4.Splat(2);
  const Greater = A.CmpGt(B);
  const Less = A.CmpLt(B);
  const Equal = A.CmpEq(TI32x4.FromArray([1, 0, -1, 0]));

  AssertLanes([0, -1, 0, -1], Greater);
  AssertLanes([-1, 0, -1, 0], Less);
  AssertLanes([-1, 0, -1, 0], Equal);
  AssertLanes([7, 9, 7, 9], Greater.Blend(TI32x4.Splat(9), TI32x4.Splat(7)));
  AssertLanes([0, 1, 0, 1], (Greater and TI32x4.Splat(1)));
  AssertLanes([-1, 5, -1, 5], (Less or A) );
  AssertLanes([0, 0, 0, 0], Greater xor Greater);
end;

procedure TTsWideTests.TestU32ShiftsAndBitcasts;
begin
  const Shifted = TU32x4.Splat($80000001).ShiftRight(23);
  const Left = TU32x8.Splat(1).ShiftLeft(31);
  const Bits = TF32x8.Splat(1).ToU32x8Bitcast;
  const Back = Bits.ToF32x8Bitcast;
  const Signed = Bits.ToI32x8Bitcast;

  Assert.AreEqual<Cardinal>($100, Shifted.Lanes[0]);
  Assert.AreEqual<Cardinal>($80000000, Left.Lanes[5]);
  Assert.AreEqual<Cardinal>($3F800000, Bits.Lanes[3]);
  Assert.AreEqual<Single>(1, Back.Lanes[3]);
  Assert.AreEqual($3F800000, Signed.Lanes[3]);
  Assert.AreEqual<Single>(-3, TI32x4.FromArray([-3, 0, 0, 0]).ToF32x4.Lanes[0]);
end;

procedure TTsWideTests.TestU16x16Operations;
begin
  const A = TU16x16.Splat(10);
  const B = TU16x16.Splat(3);

  Assert.AreEqual<Word>(3, (A / B).Lanes[0]);
  Assert.AreEqual<Word>(3, A.Min(B).Lanes[4]);
  Assert.AreEqual<Word>(10, A.Max(B).Lanes[4]);
  Assert.AreEqual<Word>($FFFF, B.CmpLe(A).Lanes[9]);
  Assert.AreEqual<Word>(0, A.CmpLe(B).Lanes[9]);
  Assert.AreEqual<Word>(7, B.CmpLe(A).Blend(TU16x16.Splat(7), TU16x16.Splat(1)).Lanes[0]);
  Assert.AreEqual<Word>(1, A.CmpLe(B).Blend(TU16x16.Splat(7), TU16x16.Splat(1)).Lanes[0]);
  Assert.AreEqual<Word>(2, (A shr TU16x16.Splat(2)).Lanes[2]);
  Assert.AreEqual<Word>($FFF5, (not A).Lanes[1]);
  Assert.AreEqual<Word>(2, (A and B).Lanes[1]);
  Assert.AreEqual<Word>(11, (A or B).Lanes[1]);
  Assert.AreEqual<Word>(30, (A * B).Lanes[15]);
  Assert.IsTrue(A = TU16x16.Splat(10));
end;

procedure TTsWideTests.TestF32x16FloorAndSave;
begin
  const FirstHalf = TF32x8.FromArray([-1.5, 2.7, -3, 0.25, 1.5, 2.5, 3.5, 4.5]);
  const SecondHalf = TF32x8.FromArray([65535.9, 70000, -5, FNaN, 0.5, 1, 2, 3]);
  const Wide = TF32x16.Create(FirstHalf, SecondHalf);

  const Floored = Wide.Floor;
  var Saved: TU16x16;
  Wide.SaveToU16x16(Saved);

  Assert.AreEqual<Single>(-2, Floored.Lanes[0]);
  Assert.AreEqual<Single>(2, Floored.Lanes[5]);
  Assert.AreEqual<Single>(65535, Floored.Lanes[8]);
  Assert.AreEqual<Word>(0, Saved.Lanes[0], 'negative saturates to 0');
  Assert.AreEqual<Word>(2, Saved.Lanes[1]);
  Assert.AreEqual<Word>(65535, Saved.Lanes[8]);
  Assert.AreEqual<Word>(65535, Saved.Lanes[9], 'above 65535 saturates');
  Assert.AreEqual<Word>(0, Saved.Lanes[11], 'NaN becomes 0');
  Assert.AreEqual<Single>(70000, Floored.Lanes[9]);
  Assert.AreEqual<Single>(4.5, (Wide + Wide - Wide).Lanes[7]);
  Assert.AreEqual<Single>(20.25, (Wide * Wide).Lanes[7]);
end;

procedure TTsWideTests.TestF32x2AndPathF32x4;
begin
  const Pair = TF32x2.Create(-1, 4);
  const Other = TF32x2.Create(FNaN, 2);

  Assert.AreEqual<Single>(1, Pair.Abs.X);
  Assert.AreEqual<Single>(-1, Pair.Min(Other).X, 'pmin(-1, NaN): NaN < -1 is false');
  Assert.AreEqual<Single>(2, Pair.Min(Other).Y);
  Assert.AreEqual<Single>(-1, Pair.Max(Other).X, 'pmax(-1, NaN): -1 < NaN is false');
  Assert.AreEqual<Single>(4, Pair.Max(Other).Y);
  Assert.AreEqual<Single>(4, Pair.MaxComponent);
  Assert.AreEqual<Single>(6, (Pair + TF32x2.Splat(2)).Y);
  Assert.AreEqual<Single>(8, (Pair * TF32x2.Splat(2)).Y);
  Assert.AreEqual<Single>(2, (Pair / TF32x2.Splat(2)).Y);
  Assert.AreEqual<Single>(2, (Pair - TF32x2.Splat(2)).Y);

  const First = TF32x4Path.Create(1, FNaN, 3, 4);
  const Second = TF32x4Path.Create(FNaN, 2, 1, 9);

  Assert.AreEqual<Single>(1, First.Max(Second).Lanes[0], 'f32::max ignores NaN');
  Assert.AreEqual<Single>(2, First.Max(Second).Lanes[1]);
  Assert.AreEqual<Single>(3, First.Max(Second).Lanes[2]);
  Assert.AreEqual<Single>(1, First.Min(Second).Lanes[2]);
  Assert.AreEqual<Single>(13, (First + Second).Lanes[3]);
  Assert.AreEqual<Single>(-5, (First - Second).Lanes[3]);
  Assert.AreEqual<Single>(36, (First * Second).Lanes[3]);
  Assert.IsFalse(First * TF32x4Path.Create(0, 0, 0, 0) = TF32x4Path.Create(0, 0, 0, 0), 'NaN * 0 is not equal to 0');
end;

procedure TTsWideTests.TestEqualityIsFalseForNaN;
begin
  Assert.IsTrue(TF32x4.Splat(1) = TF32x4.Splat(1));
  Assert.IsFalse(TF32x4.Splat(FNaN) = TF32x4.Splat(FNaN));
  Assert.IsTrue(TF32x8.Splat(1) = TF32x8.Splat(1));
  Assert.IsFalse(TF32x8.Splat(1) = TF32x8.Splat(2));
  Assert.IsFalse(TF32x8.Splat(FNaN) = TF32x8.Splat(FNaN));
end;

end.
