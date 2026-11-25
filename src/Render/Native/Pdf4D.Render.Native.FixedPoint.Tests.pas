// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/fixed_point.rs
unit Pdf4D.Render.Native.FixedPoint.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.FixedPoint;

type
  [TestFixture]
  TTsFixedPointTests = class
  public
    [Test]
    procedure TestFdot6ToFdot16;

    [Test]
    procedure TestFdot16FromF32;

    [Test]
    procedure TestFdot16FromF32Saturates;

    [Test]
    procedure TestFdot6Constructors;

    [Test]
    procedure TestFdot6RoundingShiftsKeepTheSign;

    [Test]
    procedure TestFdot6Div;

    [Test]
    procedure TestFdot6DivOfALargeNumeratorGoesThroughFdot16;

    [Test]
    procedure TestFdot6CanConvertToFdot16;

    [Test]
    procedure TestFdot6SmallScale;

    [Test]
    procedure TestFdot8FromFdot16;

    [Test]
    procedure TestFdot16Constants;

    [Test]
    procedure TestFdot16IntegerConversions;

    [Test]
    procedure TestFdot16MulAndDivUseSixtyFourBits;

    [Test]
    procedure TestFdot16DivClampsTo32Bits;

    [Test]
    procedure TestFdot16FastDiv;
  end;

implementation

{ TTsFixedPointTests }

procedure TTsFixedPointTests.TestFdot6ToFdot16;
begin
  Assert.AreEqual(65536, TTsFdot6.ToFdot16(64));
  Assert.AreEqual(-65536, TTsFdot6.ToFdot16(-64));
end;

procedure TTsFixedPointTests.TestFdot16FromF32;
begin
  Assert.AreEqual(98304, TTsFdot16.FromF32(1.5));
  Assert.AreEqual(-98304, TTsFdot16.FromF32(-1.5));
end;

procedure TTsFixedPointTests.TestFdot16FromF32Saturates;
begin
  // The saturating cast of the f32 clamps to the largest f32 that fits an i32, as tiny-skia does, not to i32::MAX
  Assert.AreEqual(2147483520, TTsFdot16.FromF32(1E10));
  Assert.AreEqual(-2147483520, TTsFdot16.FromF32(-1E10));
end;

procedure TTsFixedPointTests.TestFdot6Constructors;
begin
  Assert.AreEqual(64, TTsFdot6.One);
  Assert.AreEqual(640, TTsFdot6.FromI32(10));
  Assert.AreEqual(-64, TTsFdot6.FromI32(-1));
  Assert.AreEqual(96, TTsFdot6.FromF32(1.5));
  Assert.AreEqual(-96, TTsFdot6.FromF32(-1.5));
  Assert.AreEqual(0, TTsFdot6.FromF32(0.015));
end;

procedure TTsFixedPointTests.TestFdot6RoundingShiftsKeepTheSign;
begin
  Assert.AreEqual(1, TTsFdot6.Floor(100));
  Assert.AreEqual(-2, TTsFdot6.Floor(-100));
  Assert.AreEqual(2, TTsFdot6.Ceil(65));
  Assert.AreEqual(1, TTsFdot6.Ceil(64));
  Assert.AreEqual(-1, TTsFdot6.Ceil(-65));
  Assert.AreEqual(2, TTsFdot6.Round(96));
  Assert.AreEqual(1, TTsFdot6.Round(95));
  Assert.AreEqual(0, TTsFdot6.Round(-32));
  Assert.AreEqual(-1, TTsFdot6.Round(-33));
  Assert.AreEqual(-1, TTsFdot6.Round(-96));
  Assert.AreEqual(-2, TTsFdot6.Round(-97));
end;

procedure TTsFixedPointTests.TestFdot6Div;
begin
  Assert.AreEqual(32768, TTsFdot6.Div(32, 64));
  Assert.AreEqual(-32768, TTsFdot6.Div(-32, 64));
  Assert.AreEqual(131072, TTsFdot6.Div(128, 64));
end;

procedure TTsFixedPointTests.TestFdot6DivOfALargeNumeratorGoesThroughFdot16;
begin
  // 40000 does not fit an i16: the quotient is computed in 64 bits and clamped
  Assert.AreEqual(Integer(Int64(40000) * 65536 div 3), TTsFdot6.Div(40000, 3));
  Assert.AreEqual(High(Integer), TTsFdot6.Div(40000, 1));
end;

procedure TTsFixedPointTests.TestFdot6CanConvertToFdot16;
begin
  Assert.IsTrue(TTsFdot6.CanConvertToFdot16(0));
  Assert.IsTrue(TTsFdot6.CanConvertToFdot16(High(Integer) shr 10));
  Assert.IsTrue(TTsFdot6.CanConvertToFdot16(-(High(Integer) shr 10)));
  Assert.IsFalse(TTsFdot6.CanConvertToFdot16((High(Integer) shr 10) + 1));
  Assert.IsFalse(TTsFdot6.CanConvertToFdot16(-(High(Integer) shr 10) - 1));
end;

procedure TTsFixedPointTests.TestFdot6SmallScale;
begin
  Assert.AreEqual(255, Integer(TTsFdot6.SmallScale(255, 64)));
  Assert.AreEqual(127, Integer(TTsFdot6.SmallScale(255, 32)));
  Assert.AreEqual(0, Integer(TTsFdot6.SmallScale(255, 0)));
  Assert.AreEqual(100, Integer(TTsFdot6.SmallScale(200, 32)));
end;

procedure TTsFixedPointTests.TestFdot8FromFdot16;
begin
  Assert.AreEqual(256, TTsFdot8.FromFdot16(65536));
  Assert.AreEqual(1, TTsFdot8.FromFdot16(128));
  Assert.AreEqual(0, TTsFdot8.FromFdot16(127));
  Assert.AreEqual(-256, TTsFdot8.FromFdot16(-65536));
  Assert.AreEqual(0, TTsFdot8.FromFdot16(-128));
end;

procedure TTsFixedPointTests.TestFdot16Constants;
begin
  Assert.AreEqual(32768, TTsFdot16.Half);
  Assert.AreEqual(65536, TTsFdot16.One);
end;

procedure TTsFixedPointTests.TestFdot16IntegerConversions;
begin
  Assert.AreEqual(1, TTsFdot16.FloorToI32(98304));
  Assert.AreEqual(-2, TTsFdot16.FloorToI32(-98304));
  Assert.AreEqual(2, TTsFdot16.CeilToI32(98304));
  Assert.AreEqual(1, TTsFdot16.CeilToI32(65536));
  Assert.AreEqual(2, TTsFdot16.RoundToI32(98304));
  Assert.AreEqual(1, TTsFdot16.RoundToI32(98303));
  Assert.AreEqual(0, TTsFdot16.RoundToI32(-32768));
  Assert.AreEqual(-1, TTsFdot16.RoundToI32(-32769));
end;

procedure TTsFixedPointTests.TestFdot16MulAndDivUseSixtyFourBits;
begin
  Assert.AreEqual(98304, TTsFdot16.Mul(65536 * 3, 32768));
  Assert.AreEqual(-98304, TTsFdot16.Mul(-65536 * 3, 32768));
  Assert.AreEqual(Integer(Int64(1) shl 30), TTsFdot16.Mul(1 shl 30, 65536));
  Assert.AreEqual(131072, TTsFdot16.Div(2, 1));
  Assert.AreEqual(-131072, TTsFdot16.Div(-2, 1));
end;

procedure TTsFixedPointTests.TestFdot16DivClampsTo32Bits;
begin
  Assert.AreEqual(High(Integer), TTsFdot16.Div(High(Integer), 1));
  Assert.AreEqual(Low(Integer), TTsFdot16.Div(Low(Integer), 1));
end;

procedure TTsFixedPointTests.TestFdot16FastDiv;
begin
  Assert.AreEqual(32768, TTsFdot16.FastDiv(1, 2));
  Assert.AreEqual(-32768, TTsFdot16.FastDiv(-1, 2));
  Assert.AreEqual(65536 * 100, TTsFdot16.FastDiv(100, 1));
end;

end.
