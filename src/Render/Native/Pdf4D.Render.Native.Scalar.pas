// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/scalar.rs
// Port of: tiny-skia v0.12.0 path/src/floating_point.rs
// Port of: tiny-skia v0.12.0 src/math.rs
// Copyright (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Scalar;

{$EXCESSPRECISION OFF}

interface

uses
  System.Math;

type
  // The helpers give the Rust semantics of f32 and integer operations that the RTL does differently
  // (saturating casts, NaN handling of min and max, rounding, floor and ceil that stay Single, wrapping arithmetic).
  TTsScalar = record
  public const
    ScalarMax: Single = 3.402823466E+38;
    ScalarNearlyZero: Single = 1 / 4096;
    ScalarRoot2Over2: Single = 0.707106781;
    FloatPi: Single = 3.14159265;
    FloatEpsilon: Single = 1.1920929E-7;
    MaxI32FitsInF32: Single = 2147483520.0;
    MinI32FitsInF32: Single = -2147483520.0;

  private
    class function FloatBits(const Value: Single): Integer; static;
    class function NegativeZero: Single; static;
    class function WithSignOf(const Value, Source: Single): Single; static;
    class function SignBitToTwosComplement(const Bits: Integer): Integer; static;

  public
    // `x as i32`: saturating, NaN becomes 0
    class function SaturateToInt32(const Value: Single): Integer; static;

    // SaturateCast<f32> for i32: clamps to the range of Single that fits an i32, NaN becomes MaxI32FitsInF32
    class function SaturateFrom(const Value: Single): Integer; overload; static;
    class function SaturateFromF64(const Value: Double): Integer; static;
    class function SaturateFloor(const Value: Single): Integer; static;
    class function SaturateCeil(const Value: Single): Integer; static;
    class function SaturateRound(const Value: Single): Integer; static;

    class function RoundHalfAwayFromZero(const Value: Single): Single; static;
    class function FloorF(const Value: Single): Single; static;
    class function CeilF(const Value: Single): Single; static;
    class function TruncF(const Value: Single): Single; static;
    class function MinF(const A, B: Single): Single; static;
    class function MaxF(const A, B: Single): Single; static;

    // The f32 % operator of Rust (fmod): the exact remainder with the sign of the dividend; NaN for an infinite dividend or a zero divisor
    class function RemainderF(const Value, Divisor: Single): Single; static;

    class function IsFinite(const Value: Single): Boolean; static;
    class function IsSignNegative(const Value: Single): Boolean; static;

    // trait Scalar for f32
    class function Half(const Value: Single): Single; static;
    class function Ave(const Value, Other: Single): Single; static;
    class function Sqr(const Value: Single): Single; static;
    class function Invert(const Value: Single): Single; static;
    class function Bound(const Value, Min, Max: Single): Single; static;
    class function IsNearlyEqual(const Value, Other: Single): Boolean; static;
    class function IsNearlyEqualWithinTolerance(const Value, Other, Tolerance: Single): Boolean; static;
    class function IsNearlyZero(const Value: Single): Boolean; static;
    class function IsNearlyZeroWithinTolerance(const Value, Tolerance: Single): Boolean; static;
    class function AlmostDequalUlps(const Value, Other: Single): Boolean; static;

    class function F32As2sCompliment(const Value: Single): Integer; static;

    // math.rs
    class function LeftShift(const Value, Shift: Integer): Integer; static;
    class function LeftShift64(const Value: Int64; const Shift: Integer): Int64; static;

    // Rust `>>` on a signed integer copies the sign bit; the Delphi shr fills with zeros
    class function ShiftRightI32(const Value, Shift: Integer): Integer; static;
    class function ShiftRightI64(const Value: Int64; const Shift: Integer): Int64; static;
    class function BoundInt(const Min, Value, Max: Integer): Integer; static;

    // wrapping_* and saturating_* of the integer types
    class function WrappingAddU32(const A, B: Cardinal): Cardinal; static;
    class function WrappingSubU32(const A, B: Cardinal): Cardinal; static;
    class function WrappingAddI32(const A, B: Integer): Integer; static;
    class function WrappingSubI32(const A, B: Integer): Integer; static;
    class function SaturatingSubU32(const A, B: Cardinal): Cardinal; static;
  end;

  TTsFiniteF32 = record
  private
    FValue: Single;

  public
    class function TryCreate(const Value: Single; out Finite: TTsFiniteF32): Boolean; static;
    class function CreateUnchecked(const Value: Single): TTsFiniteF32; static;

    function Get: Single;
  end;

  TTsNonZeroPositiveF32 = record
  private
    FValue: Single;

  public
    class function TryCreate(const Value: Single; out Positive: TTsNonZeroPositiveF32): Boolean; static;
    class function CreateUnchecked(const Value: Single): TTsNonZeroPositiveF32; static;

    function Get: Single;
  end;

  // A Single in [0, 1]
  TTsNormalizedF32 = record
  private
    FValue: Single;

  public
    class function Zero: TTsNormalizedF32; static;
    class function One: TTsNormalizedF32; static;
    class function TryCreate(const Value: Single; out Normalized: TTsNormalizedF32): Boolean; static;
    class function CreateUnchecked(const Value: Single): TTsNormalizedF32; static;

    // Clamps to [0, 1]; NaN and infinity give 0
    class function CreateClamped(const Value: Single): TTsNormalizedF32; static;
    class function CreateU8(const Value: Byte): TTsNormalizedF32; static;

    function Get: Single;
  end;

  // A Single in (0, 1)
  TTsNormalizedF32Exclusive = record
  private
    FValue: Single;

  public
    class function Half: TTsNormalizedF32Exclusive; static;
    class function Any: TTsNormalizedF32Exclusive; static;
    class function TryCreate(const Value: Single; out Exclusive: TTsNormalizedF32Exclusive): Boolean; static;
    class function CreateBounded(const Value: Single): TTsNormalizedF32Exclusive; static;

    function Get: Single;
    function ToNormalized: TTsNormalizedF32;
  end;

  TTsFloatState = record
    ExceptionMask: TArithmeticExceptionMask;
    RoundMode: TRoundingMode;
    {$IFDEF CPUX86}
    {$WARN SYMBOL_PLATFORM OFF}
    PrecisionMode: TFPUPrecisionMode;
    {$WARN SYMBOL_PLATFORM ON}
    {$ENDIF}
  end;

  // Every public entry of the device runs between Enter and Leave: all exceptions masked, round to nearest and, on Win32,
  // double precision for the x87 unit so that the f64 code behaves as on SSE
  TTsFloatMode = record
    class function Enter: TTsFloatState; static;
    class procedure Leave(const State: TTsFloatState); static;
  end;

implementation

const
  TwoPower23: Single = 8388608.0;
  AllExceptions: TArithmeticExceptionMask = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision];

{ TTsScalar }

class function TTsScalar.FloatBits(const Value: Single): Integer;
begin
  Move(Value, Result, SizeOf(Integer));
end;

class function TTsScalar.NegativeZero: Single;
begin
  const Bits: Integer = Low(Integer);

  Move(Bits, Result, SizeOf(Single));
end;

class function TTsScalar.WithSignOf(const Value, Source: Single): Single;
begin
  const IsNegativeZero = ((Value = 0) and IsSignNegative(Source));
  if IsNegativeZero then
  begin
    Exit(NegativeZero);
  end;

  Result := Value;
end;

class function TTsScalar.SignBitToTwosComplement(const Bits: Integer): Integer;
begin
  if Bits < 0 then
  begin
    Exit(-(Bits and $7FFFFFFF));
  end;

  Result := Bits;
end;

class function TTsScalar.SaturateToInt32(const Value: Single): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;

  if Value >= 2147483648.0 then
  begin
    Exit(High(Integer));
  end;

  if Value <= -2147483648.0 then
  begin
    Exit(Low(Integer));
  end;

  Result := Trunc(Value);
end;

class function TTsScalar.SaturateFrom(const Value: Single): Integer;
begin
  var Clamped: Single := Value;

  if not (Clamped < MaxI32FitsInF32) then
  begin
    Clamped := MaxI32FitsInF32;
  end;

  if not (Clamped > MinI32FitsInF32) then
  begin
    Clamped := MinI32FitsInF32;
  end;

  Result := SaturateToInt32(Clamped);
end;

class function TTsScalar.SaturateFromF64(const Value: Double): Integer;
begin
  var Clamped := Value;

  if not (Clamped < High(Integer)) then
  begin
    Clamped := High(Integer);
  end;

  if not (Clamped > Low(Integer)) then
  begin
    Clamped := Low(Integer);
  end;

  Result := Trunc(Clamped);
end;

class function TTsScalar.SaturateFloor(const Value: Single): Integer;
begin
  Result := SaturateFrom(FloorF(Value));
end;

class function TTsScalar.SaturateCeil(const Value: Single): Integer;
begin
  Result := SaturateFrom(CeilF(Value));
end;

class function TTsScalar.SaturateRound(const Value: Single): Integer;
begin
  const Floored: Single = FloorF(Value);
  const Shifted: Single = Floored + 0.5;

  Result := SaturateFrom(Shifted);
end;

class function TTsScalar.RoundHalfAwayFromZero(const Value: Single): Single;
begin
  const IsIntegral = (IsNan(Value) or (Abs(Value) >= TwoPower23));
  if IsIntegral then
  begin
    Exit(Value);
  end;

  const Truncated: Single = TruncF(Value);
  const Fraction: Single = Value - Truncated;
  const IsHalfOrMore = (Abs(Fraction) >= 0.5);
  if not IsHalfOrMore then
  begin
    Exit(Truncated);
  end;

  if Value < 0 then
  begin
    Exit(Truncated - 1);
  end;

  Result := Truncated + 1;
end;

class function TTsScalar.FloorF(const Value: Single): Single;
begin
  const Truncated: Single = TruncF(Value);
  const IsBelowValue = (Truncated > Value);
  if IsBelowValue then
  begin
    Exit(Truncated - 1);
  end;

  Result := Truncated;
end;

class function TTsScalar.CeilF(const Value: Single): Single;
begin
  const Truncated: Single = TruncF(Value);
  const IsAboveValue = (Truncated < Value);
  if IsAboveValue then
  begin
    Exit(Truncated + 1);
  end;

  Result := Truncated;
end;

class function TTsScalar.TruncF(const Value: Single): Single;
begin
  const IsIntegral = (IsNan(Value) or (Abs(Value) >= TwoPower23));
  if IsIntegral then
  begin
    Exit(Value);
  end;

  const IntegerPart: Integer = Trunc(Value);
  const Truncated: Single = IntegerPart;

  Result := WithSignOf(Truncated, Value);
end;

class function TTsScalar.MinF(const A, B: Single): Single;
begin
  if IsNan(A) then
  begin
    Exit(B);
  end;

  if IsNan(B) then
  begin
    Exit(A);
  end;

  if A < B then
  begin
    Exit(A);
  end;

  Result := B;
end;

class function TTsScalar.RemainderF(const Value, Divisor: Single): Single;
begin
  if IsNan(Value) or IsNan(Divisor) or IsInfinite(Value) or (Divisor = 0) then
  begin
    Exit(NaN);
  end;

  if IsInfinite(Divisor) then
  begin
    Exit(Value);
  end;

  // Singles are exact in a Double, and subtracting T from A with T <= A < 2 * T is exact, so the loop gives the exact remainder
  var Remaining: Double := Abs(Value);
  const Step: Double = Abs(Divisor);
  while Remaining >= Step do
  begin
    var Multiple: Double := Step;
    while (Multiple * 2) <= Remaining do
    begin
      Multiple := Multiple * 2;
    end;

    Remaining := Remaining - Multiple;
  end;

  // Rust % keeps the sign of the dividend, also for -0
  Result := Remaining;
  if IsSignNegative(Value) then
  begin
    Result := -Result;
  end;
end;

class function TTsScalar.MaxF(const A, B: Single): Single;
begin
  if IsNan(A) then
  begin
    Exit(B);
  end;

  if IsNan(B) then
  begin
    Exit(A);
  end;

  if A > B then
  begin
    Exit(A);
  end;

  Result := B;
end;

class function TTsScalar.IsFinite(const Value: Single): Boolean;
begin
  const Bits = Cardinal(FloatBits(Value));

  Result := ((Bits and $7F800000) <> $7F800000);
end;

class function TTsScalar.IsSignNegative(const Value: Single): Boolean;
begin

  Result := (FloatBits(Value) < 0);
end;

class function TTsScalar.Half(const Value: Single): Single;
begin
  Result := Value * 0.5;
end;

class function TTsScalar.Ave(const Value, Other: Single): Single;
begin
  const Sum: Single = Value + Other;

  Result := Sum * 0.5;
end;

class function TTsScalar.Sqr(const Value: Single): Single;
begin
  Result := Value * Value;
end;

class function TTsScalar.Invert(const Value: Single): Single;
begin
  Result := 1 / Value;
end;

// Works like SkTPin: returns Max for NaN and infinity
class function TTsScalar.Bound(const Value, Min, Max: Single): Single;
begin
  Result := MaxF(MinF(Max, Value), Min);
end;

class function TTsScalar.IsNearlyEqual(const Value, Other: Single): Boolean;
begin
  Result := IsNearlyEqualWithinTolerance(Value, Other, ScalarNearlyZero);
end;

class function TTsScalar.IsNearlyEqualWithinTolerance(const Value, Other, Tolerance: Single): Boolean;
begin
  const Difference: Single = Value - Other;

  Result := (Abs(Difference) <= Tolerance);
end;

class function TTsScalar.IsNearlyZero(const Value: Single): Boolean;
begin
  Result := IsNearlyZeroWithinTolerance(Value, ScalarNearlyZero);
end;

class function TTsScalar.IsNearlyZeroWithinTolerance(const Value, Tolerance: Single): Boolean;
begin
  Result := (Abs(Value) <= Tolerance);
end;

// From SkPathOpsTypes
class function TTsScalar.AlmostDequalUlps(const Value, Other: Single): Boolean;
const
  UlpsEpsilon = 16;
begin
  const ValueBits = F32As2sCompliment(Value);
  const OtherBits = F32As2sCompliment(Other);

  Result := ((ValueBits < OtherBits + UlpsEpsilon) and (OtherBits < ValueBits + UlpsEpsilon));
end;

// Only for comparing floats with each other or with positive float bit constants
class function TTsScalar.F32As2sCompliment(const Value: Single): Integer;
begin

  Result := SignBitToTwosComplement(FloatBits(Value));
end;

class function TTsScalar.LeftShift(const Value, Shift: Integer): Integer;
begin
  const Shifted = Int64(Cardinal(Value)) shl Shift;

  Result := Integer(Shifted);
end;

class function TTsScalar.LeftShift64(const Value: Int64; const Shift: Integer): Int64;
begin
  const Shifted = UInt64(Value) shl Shift;

  Result := Int64(Shifted);
end;

class function TTsScalar.ShiftRightI32(const Value, Shift: Integer): Integer;
begin
  if Value >= 0 then
  begin
    Exit(Value shr Shift);
  end;

  Result := not ((not Value) shr Shift);
end;

class function TTsScalar.ShiftRightI64(const Value: Int64; const Shift: Integer): Int64;
begin
  if Value >= 0 then
  begin
    Exit(Value shr Shift);
  end;

  Result := not ((not Value) shr Shift);
end;

class function TTsScalar.BoundInt(const Min, Value, Max: Integer): Integer;
begin
  Result := System.Math.Max(System.Math.Min(Max, Value), Min);
end;

class function TTsScalar.WrappingAddU32(const A, B: Cardinal): Cardinal;
begin
  const Sum = Int64(A) + Int64(B);

  Result := Cardinal(Sum);
end;

class function TTsScalar.WrappingSubU32(const A, B: Cardinal): Cardinal;
begin
  const Difference = Int64(A) - Int64(B);

  Result := Cardinal(Difference);
end;

class function TTsScalar.WrappingAddI32(const A, B: Integer): Integer;
begin
  const Sum = Int64(A) + Int64(B);

  Result := Integer(Sum);
end;

class function TTsScalar.WrappingSubI32(const A, B: Integer): Integer;
begin
  const Difference = Int64(A) - Int64(B);

  Result := Integer(Difference);
end;

class function TTsScalar.SaturatingSubU32(const A, B: Cardinal): Cardinal;
begin
  if A <= B then
  begin
    Exit(0);
  end;

  Result := A - B;
end;

{ TTsFiniteF32 }

class function TTsFiniteF32.TryCreate(const Value: Single; out Finite: TTsFiniteF32): Boolean;
begin
  Finite := Default(TTsFiniteF32);

  Result := TTsScalar.IsFinite(Value);
  if Result then
  begin
    Finite.FValue := Value;
  end;
end;

class function TTsFiniteF32.CreateUnchecked(const Value: Single): TTsFiniteF32;
begin
  Result.FValue := Value;
end;

function TTsFiniteF32.Get: Single;
begin
  Result := FValue;
end;

{ TTsNonZeroPositiveF32 }

class function TTsNonZeroPositiveF32.TryCreate(const Value: Single; out Positive: TTsNonZeroPositiveF32): Boolean;
begin
  Positive := Default(TTsNonZeroPositiveF32);

  Result := (TTsScalar.IsFinite(Value) and (Value > 0));
  if Result then
  begin
    Positive.FValue := Value;
  end;
end;

class function TTsNonZeroPositiveF32.CreateUnchecked(const Value: Single): TTsNonZeroPositiveF32;
begin
  Result.FValue := Value;
end;

function TTsNonZeroPositiveF32.Get: Single;
begin
  Result := FValue;
end;

{ TTsNormalizedF32 }

class function TTsNormalizedF32.Zero: TTsNormalizedF32;
begin
  Result.FValue := 0;
end;

class function TTsNormalizedF32.One: TTsNormalizedF32;
begin
  Result.FValue := 1;
end;

class function TTsNormalizedF32.TryCreate(const Value: Single; out Normalized: TTsNormalizedF32): Boolean;
begin
  Normalized := Default(TTsNormalizedF32);

  Result := ((Value >= 0) and (Value <= 1));
  if Result then
  begin
    Normalized.FValue := Value;
  end;
end;

class function TTsNormalizedF32.CreateUnchecked(const Value: Single): TTsNormalizedF32;
begin
  Result.FValue := Value;
end;

class function TTsNormalizedF32.CreateClamped(const Value: Single): TTsNormalizedF32;
begin
  if not TTsScalar.IsFinite(Value) then
  begin
    Exit(Zero);
  end;

  Result.FValue := TTsScalar.Bound(Value, 0, 1);
end;

class function TTsNormalizedF32.CreateU8(const Value: Byte): TTsNormalizedF32;
begin
  const Whole: Single = Value;

  Result.FValue := Whole / 255;
end;

function TTsNormalizedF32.Get: Single;
begin
  Result := FValue;
end;

{ TTsNormalizedF32Exclusive }

class function TTsNormalizedF32Exclusive.Half: TTsNormalizedF32Exclusive;
begin
  Result.FValue := 0.5;
end;

class function TTsNormalizedF32Exclusive.Any: TTsNormalizedF32Exclusive;
begin
  Result := Half;
end;

class function TTsNormalizedF32Exclusive.TryCreate(const Value: Single; out Exclusive: TTsNormalizedF32Exclusive): Boolean;
begin
  Exclusive := Default(TTsNormalizedF32Exclusive);

  Result := ((Value > 0) and (Value < 1));
  if Result then
  begin
    Exclusive.FValue := Value;
  end;
end;

// Returns 1 - epsilon for NaN and infinity, because Bound returns the maximum for them
class function TTsNormalizedF32Exclusive.CreateBounded(const Value: Single): TTsNormalizedF32Exclusive;
begin
  const UpperBound: Single = 1 - TTsScalar.FloatEpsilon;

  Result.FValue := TTsScalar.Bound(Value, TTsScalar.FloatEpsilon, UpperBound);
end;

function TTsNormalizedF32Exclusive.Get: Single;
begin
  Result := FValue;
end;

function TTsNormalizedF32Exclusive.ToNormalized: TTsNormalizedF32;
begin
  Result := TTsNormalizedF32.CreateUnchecked(FValue);
end;

{ TTsFloatMode }

class function TTsFloatMode.Enter: TTsFloatState;
begin
  Result.ExceptionMask := SetExceptionMask(AllExceptions);
  Result.RoundMode := SetRoundMode(TRoundingMode.rmNearest);
  {$IFDEF CPUX86}
  {$WARN SYMBOL_PLATFORM OFF}
  Result.PrecisionMode := SetPrecisionMode(TFPUPrecisionMode.pmDouble);
  {$WARN SYMBOL_PLATFORM ON}
  {$ENDIF}
end;

class procedure TTsFloatMode.Leave(const State: TTsFloatState);
begin
  {$IFDEF CPUX86}
  {$WARN SYMBOL_PLATFORM OFF}
  SetPrecisionMode(State.PrecisionMode);
  {$WARN SYMBOL_PLATFORM ON}
  {$ENDIF}
  SetRoundMode(State.RoundMode);
  SetExceptionMask(State.ExceptionMask);
end;

end.
