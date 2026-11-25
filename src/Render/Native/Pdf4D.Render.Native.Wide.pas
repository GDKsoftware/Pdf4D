// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/wide/mod.rs
// Port of: tiny-skia v0.12.0 src/wide/f32x4_t.rs
// Port of: tiny-skia v0.12.0 src/wide/f32x8_t.rs
// Port of: tiny-skia v0.12.0 src/wide/f32x16_t.rs
// Port of: tiny-skia v0.12.0 src/wide/i32x4_t.rs
// Port of: tiny-skia v0.12.0 src/wide/i32x8_t.rs
// Port of: tiny-skia v0.12.0 src/wide/u32x4_t.rs
// Port of: tiny-skia v0.12.0 src/wide/u32x8_t.rs
// Port of: tiny-skia v0.12.0 src/wide/u16x16_t.rs
// Port of: tiny-skia v0.12.0 path/src/f32x2_t.rs
// Port of: tiny-skia v0.12.0 path/src/f32x4_t.rs
// Copyright (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Wide;

// The wrapping arithmetic of the integer lanes is intended
{$OVERFLOWCHECKS OFF}
{$EXCESSPRECISION OFF}

interface

uses
  System.Math,
  Pdf4D.Render.Native.Scalar;

// Only the scalar branch of every cfg_if! is ported: each type is a flat array of lanes and every lane gets the operations of the Rust
// code in the same order. A comparison gives a mask lane with all bits set (the bits of a NaN) or no bits; mask lanes and bitcasts are
// written as bits and never loaded into an FPU register, so that they stay as they are.
//
// Where Rust compares with a NaN the result is false (true for !=). Delphi can evaluate such a comparison as true, so every comparison on a
// lane is guarded with IsNan.
//
// The operations run in the float mode of TTsFloatMode: with unmasked exceptions a division by zero raises where Rust gives infinity.
//
// The Rust f32x4 of tiny-skia-path (only min, max and the arithmetic) is TF32x4Path. Not ported: f32x8::powf (only the gamma stages use
// it) and the AddAssign and MulAssign operators (a Rust a += b is a := a + b). The Rust cross type conversions of the integer types are
// record helpers at the end of the interface, because a record cannot refer to a record declared later.

type
  // The lane operations that the types below share; the Rust code repeats them per type
  TTsLane = record
  public
    class function Bits(const Value: Single): Cardinal; static; inline;
    class procedure SetBits(var Value: Single; const Bits: Cardinal); static; inline;
    class function MaskBits(const Condition: Boolean): Cardinal; static; inline;

    class function IsEq(const A, B: Single): Boolean; static; inline;
    class function IsNe(const A, B: Single): Boolean; static; inline;
    class function IsLt(const A, B: Single): Boolean; static; inline;
    class function IsLe(const A, B: Single): Boolean; static; inline;
    class function IsGt(const A, B: Single): Boolean; static; inline;
    class function IsGe(const A, B: Single): Boolean; static; inline;

    // faster_min and faster_max of wide/mod.rs: NaN does not matter, the comparison is false
    class function FasterMin(const Value, Rhs: Single): Single; static; inline;
    class function FasterMax(const Value, Rhs: Single): Single; static; inline;

    // The round of f32x4: half to even, by adding and subtracting 2^23 with every step stored as a Single
    class function Round(const Value: Single): Single; static;

    // The floor of f32x4 and f32x8: trunc_int, back to f32, minus 1 when that is more than the value
    class function Floor(const Value: Single): Single; static;

    class function Normalize(const Value: Single): Single; static; inline;
  end;

  TU32x4 = record
  public
    Lanes: array[0..3] of Cardinal;

    class function Splat(const Value: Cardinal): TU32x4; static;
    class function FromArray(const Values: array of Cardinal): TU32x4; static;

    function CmpEq(const Rhs: TU32x4): TU32x4;
    function ShiftLeft(const Count: Integer): TU32x4;
    function ShiftRight(const Count: Integer): TU32x4;

    class operator LogicalNot(const A: TU32x4): TU32x4;
    class operator Add(const A, B: TU32x4): TU32x4;
    class operator BitwiseAnd(const A, B: TU32x4): TU32x4;
    class operator BitwiseOr(const A, B: TU32x4): TU32x4;
  end;

  TI32x4 = record
  public
    Lanes: array[0..3] of Integer;

    class function Splat(const Value: Integer): TI32x4; static;
    class function FromArray(const Values: array of Integer): TI32x4; static;

    // Self is the mask: lanes with all bits set take OnTrue
    function Blend(const OnTrue, OnFalse: TI32x4): TI32x4;
    function CmpEq(const Rhs: TI32x4): TI32x4;
    function CmpGt(const Rhs: TI32x4): TI32x4;
    function CmpLt(const Rhs: TI32x4): TI32x4;

    function ToU32x4Bitcast: TU32x4;

    class operator Add(const A, B: TI32x4): TI32x4;
    class operator BitwiseAnd(const A, B: TI32x4): TI32x4;
    class operator Multiply(const A, B: TI32x4): TI32x4;
    class operator BitwiseOr(const A, B: TI32x4): TI32x4;
    class operator BitwiseXor(const A, B: TI32x4): TI32x4;
  end;

  TF32x4 = record
  public
    Lanes: array[0..3] of Single;

    constructor Create(const A, B, C, D: Single);
    class function Splat(const Value: Single): TF32x4; static;
    class function FromArray(const Values: array of Single): TF32x4; static;

    function Floor: TF32x4;
    function Abs: TF32x4;
    function Max(const Rhs: TF32x4): TF32x4;
    function Min(const Rhs: TF32x4): TF32x4;

    function CmpEq(const Rhs: TF32x4): TF32x4;
    function CmpNe(const Rhs: TF32x4): TF32x4;
    function CmpGe(const Rhs: TF32x4): TF32x4;
    function CmpGt(const Rhs: TF32x4): TF32x4;
    function CmpLe(const Rhs: TF32x4): TF32x4;
    function CmpLt(const Rhs: TF32x4): TF32x4;

    // Self is the mask: lanes with all bits set take OnTrue
    function Blend(const OnTrue, OnFalse: TF32x4): TF32x4;

    function Round: TF32x4;
    function RoundInt: TI32x4;
    function TruncInt: TI32x4;
    function RecipFast: TF32x4;
    function RecipSqrt: TF32x4;
    function Sqrt: TF32x4;

    // The Rust cast between the 128 bit types
    function ToI32x4Bitcast: TI32x4;
    function ToU32x4Bitcast: TU32x4;

    class operator Add(const A, B: TF32x4): TF32x4;
    class operator Subtract(const A, B: TF32x4): TF32x4;
    class operator Multiply(const A, B: TF32x4): TF32x4;
    class operator Divide(const A, B: TF32x4): TF32x4;
    class operator BitwiseAnd(const A, B: TF32x4): TF32x4;
    class operator BitwiseOr(const A, B: TF32x4): TF32x4;
    class operator BitwiseXor(const A, B: TF32x4): TF32x4;
    class operator Negative(const A: TF32x4): TF32x4;
    class operator LogicalNot(const A: TF32x4): TF32x4;
    class operator Equal(const A, B: TF32x4): Boolean;
    class operator NotEqual(const A, B: TF32x4): Boolean;
  end;

  TU32x8 = record
  public
    Lanes: array[0..7] of Cardinal;

    class function Splat(const Value: Cardinal): TU32x8; static;
    class function FromArray(const Values: array of Cardinal): TU32x8; static;

    function CmpEq(const Rhs: TU32x8): TU32x8;
    function ShiftLeft(const Count: Integer): TU32x8;
    function ShiftRight(const Count: Integer): TU32x8;

    class operator LogicalNot(const A: TU32x8): TU32x8;
    class operator Add(const A, B: TU32x8): TU32x8;
    class operator BitwiseAnd(const A, B: TU32x8): TU32x8;
    class operator BitwiseOr(const A, B: TU32x8): TU32x8;
  end;

  TI32x8 = record
  public
    Lanes: array[0..7] of Integer;

    class function Splat(const Value: Integer): TI32x8; static;
    class function FromArray(const Values: array of Integer): TI32x8; static;

    // Self is the mask: lanes with all bits set take OnTrue
    function Blend(const OnTrue, OnFalse: TI32x8): TI32x8;
    function CmpEq(const Rhs: TI32x8): TI32x8;
    function CmpGt(const Rhs: TI32x8): TI32x8;
    function CmpLt(const Rhs: TI32x8): TI32x8;

    function ToU32x8Bitcast: TU32x8;

    class operator Add(const A, B: TI32x8): TI32x8;
    class operator BitwiseAnd(const A, B: TI32x8): TI32x8;
    class operator Multiply(const A, B: TI32x8): TI32x8;
    class operator BitwiseOr(const A, B: TI32x8): TI32x8;
    class operator BitwiseXor(const A, B: TI32x8): TI32x8;
  end;

  TF32x8 = record
  public
    Lanes: array[0..7] of Single;

    class function Splat(const Value: Single): TF32x8; static;
    class function FromArray(const Values: array of Single): TF32x8; static;

    function Floor: TF32x8;
    function Fract: TF32x8;
    function Normalize: TF32x8;

    function ToI32x8Bitcast: TI32x8;
    function ToU32x8Bitcast: TU32x8;

    function CmpEq(const Rhs: TF32x8): TF32x8;
    function CmpNe(const Rhs: TF32x8): TF32x8;
    function CmpGe(const Rhs: TF32x8): TF32x8;
    function CmpGt(const Rhs: TF32x8): TF32x8;
    function CmpLe(const Rhs: TF32x8): TF32x8;
    function CmpLt(const Rhs: TF32x8): TF32x8;

    // Self is the mask: lanes with all bits set take OnTrue
    function Blend(const OnTrue, OnFalse: TF32x8): TF32x8;

    function Abs: TF32x8;
    function Max(const Rhs: TF32x8): TF32x8;
    function Min(const Rhs: TF32x8): TF32x8;

    // A mask: all bits set for the lanes that are neither infinite nor NaN
    function IsFinite: TF32x8;

    function Round: TF32x8;
    function RoundInt: TI32x8;
    function TruncInt: TI32x8;
    function RecipFast: TF32x8;
    function RecipSqrt: TF32x8;
    function Sqrt: TF32x8;

    class operator Add(const A, B: TF32x8): TF32x8;
    class operator Subtract(const A, B: TF32x8): TF32x8;
    class operator Multiply(const A, B: TF32x8): TF32x8;
    class operator Divide(const A, B: TF32x8): TF32x8;
    class operator BitwiseAnd(const A, B: TF32x8): TF32x8;
    class operator BitwiseOr(const A, B: TF32x8): TF32x8;
    class operator BitwiseXor(const A, B: TF32x8): TF32x8;
    class operator Negative(const A: TF32x8): TF32x8;
    class operator LogicalNot(const A: TF32x8): TF32x8;
    class operator Equal(const A, B: TF32x8): Boolean;
    class operator NotEqual(const A, B: TF32x8): Boolean;
  end;

  TU16x16 = record
  public
    Lanes: array[0..15] of Word;

    class function Splat(const Value: Word): TU16x16; static;
    class function FromArray(const Values: array of Word): TU16x16; static;

    function Min(const Rhs: TU16x16): TU16x16;
    function Max(const Rhs: TU16x16): TU16x16;
    function CmpLe(const Rhs: TU16x16): TU16x16;

    // Self is the mask: lanes with all bits set take OnTrue
    function Blend(const OnTrue, OnFalse: TU16x16): TU16x16;

    class operator Add(const A, B: TU16x16): TU16x16;
    class operator Subtract(const A, B: TU16x16): TU16x16;
    class operator Multiply(const A, B: TU16x16): TU16x16;
    class operator Divide(const A, B: TU16x16): TU16x16;
    class operator BitwiseAnd(const A, B: TU16x16): TU16x16;
    class operator BitwiseOr(const A, B: TU16x16): TU16x16;
    class operator LogicalNot(const A: TU16x16): TU16x16;
    // The shift count wraps to 0..15 as the release build of Rust does
    class operator RightShift(const A, B: TU16x16): TU16x16;
    class operator Equal(const A, B: TU16x16): Boolean;
    class operator NotEqual(const A, B: TU16x16): Boolean;
  end;

  // f32x16 is two f32x8 in Rust; here it is flat
  TF32x16 = record
  public
    Lanes: array[0..15] of Single;

    constructor Create(const First, Second: TF32x8);
    class function Splat(const Value: Single): TF32x16; static;

    function Abs: TF32x16;
    function CmpGt(const Rhs: TF32x16): TF32x16;
    // Self is the mask: lanes with all bits set take OnTrue
    function Blend(const OnTrue, OnFalse: TF32x16): TF32x16;
    function Normalize: TF32x16;
    function Floor: TF32x16;
    function Sqrt: TF32x16;
    function Round: TF32x16;

    // Casts without rounding, as Skia does: saturating, NaN becomes 0
    procedure SaveToU16x16(var Destination: TU16x16);

    class operator Add(const A, B: TF32x16): TF32x16;
    class operator Subtract(const A, B: TF32x16): TF32x16;
    class operator Multiply(const A, B: TF32x16): TF32x16;
  end;

  // path/src/f32x2_t.rs
  TF32x2 = record
  public
    Lanes: array[0..1] of Single;

    constructor Create(const A, B: Single);
    class function Splat(const Value: Single): TF32x2; static;

    function Abs: TF32x2;
    function Min(const Other: TF32x2): TF32x2;
    function Max(const Other: TF32x2): TF32x2;
    function MaxComponent: Single;
    function X: Single;
    function Y: Single;

    class operator Add(const A, B: TF32x2): TF32x2;
    class operator Subtract(const A, B: TF32x2): TF32x2;
    class operator Multiply(const A, B: TF32x2): TF32x2;
    class operator Divide(const A, B: TF32x2): TF32x2;
    class operator Equal(const A, B: TF32x2): Boolean;
    class operator NotEqual(const A, B: TF32x2): Boolean;
  end;

  // path/src/f32x4_t.rs, the f32x4 of tiny-skia-path: min and max follow f32::min and f32::max
  TF32x4Path = record
  public
    Lanes: array[0..3] of Single;

    constructor Create(const A, B, C, D: Single);

    function Max(const Rhs: TF32x4Path): TF32x4Path;
    function Min(const Rhs: TF32x4Path): TF32x4Path;

    class operator Add(const A, B: TF32x4Path): TF32x4Path;
    class operator Subtract(const A, B: TF32x4Path): TF32x4Path;
    class operator Multiply(const A, B: TF32x4Path): TF32x4Path;
    class operator Equal(const A, B: TF32x4Path): Boolean;
    class operator NotEqual(const A, B: TF32x4Path): Boolean;
  end;

  TU32x4Casts = record helper for TU32x4
    function ToI32x4Bitcast: TI32x4;
    function ToF32x4Bitcast: TF32x4;
  end;

  TI32x4Casts = record helper for TI32x4
    function ToF32x4: TF32x4;
    function ToF32x4Bitcast: TF32x4;
  end;

  TU32x8Casts = record helper for TU32x8
    function ToI32x8Bitcast: TI32x8;
    function ToF32x8Bitcast: TF32x8;
  end;

  TI32x8Casts = record helper for TI32x8
    function ToF32x8: TF32x8;
    function ToF32x8Bitcast: TF32x8;
  end;

implementation

uses
  System.SysUtils;

const
  AllBits: Cardinal = $FFFFFFFF;
  NonSignBits: Cardinal = $7FFFFFFF;
  // 1.0 / f32::EPSILON
  RoundMagic: Single = 8388608.0;

procedure CheckLaneCount(const Expected, Actual: Integer);
begin
  if Expected <> Actual then
  begin
    raise EArgumentException.CreateFmt('A wide type has %d lanes, got %d values', [Expected, Actual]);
  end;
end;

{ TTsLane }

class function TTsLane.Bits(const Value: Single): Cardinal;
begin
  Move(Value, Result, SizeOf(Cardinal));
end;

class procedure TTsLane.SetBits(var Value: Single; const Bits: Cardinal);
begin
  Move(Bits, Value, SizeOf(Single));
end;

class function TTsLane.MaskBits(const Condition: Boolean): Cardinal;
begin
  if Condition then
  begin
    Exit($FFFFFFFF);
  end;

  Result := 0;
end;

class function TTsLane.IsEq(const A, B: Single): Boolean;
begin
  Result := ((not IsNan(A)) and (not IsNan(B)) and (A = B));
end;

class function TTsLane.IsNe(const A, B: Single): Boolean;
begin
  Result := (IsNan(A) or IsNan(B) or (A <> B));
end;

class function TTsLane.IsLt(const A, B: Single): Boolean;
begin
  Result := ((not IsNan(A)) and (not IsNan(B)) and (A < B));
end;

class function TTsLane.IsLe(const A, B: Single): Boolean;
begin
  Result := ((not IsNan(A)) and (not IsNan(B)) and (A <= B));
end;

class function TTsLane.IsGt(const A, B: Single): Boolean;
begin
  Result := ((not IsNan(A)) and (not IsNan(B)) and (A > B));
end;

class function TTsLane.IsGe(const A, B: Single): Boolean;
begin
  Result := ((not IsNan(A)) and (not IsNan(B)) and (A >= B));
end;

class function TTsLane.FasterMin(const Value, Rhs: Single): Single;
begin
  if IsLt(Rhs, Value) then
  begin
    Exit(Rhs);
  end;

  Result := Value;
end;

class function TTsLane.FasterMax(const Value, Rhs: Single): Single;
begin
  if IsLt(Value, Rhs) then
  begin
    Exit(Rhs);
  end;

  Result := Value;
end;

class function TTsLane.Round(const Value: Single): Single;
begin
  const Exponent = Integer((Bits(Value) shr 23) and $FF);

  const IsNoOp = (Exponent >= ($7F + 23));
  if IsNoOp then
  begin
    Exit(Value);
  end;

  const IsZero = (Exponent < ($7F - 1));
  if IsZero then
  begin
    const Zero: Single = 0;

    Exit(Value * Zero);
  end;

  const IsNegative = (Integer(Bits(Value)) < 0);
  var Magnitude := Value;
  if IsNegative then
  begin
    const Origin: Single = 0;

    Magnitude := Origin - Value;
  end;

  // Every step is stored: on x87 a wider intermediate would change the result
  var Rounded: Single := Magnitude + RoundMagic;
  Rounded := Rounded - RoundMagic;
  Rounded := Rounded - Magnitude;

  const Sum: Single = Rounded + Magnitude;
  if IsGt(Rounded, 0.5) then
  begin
    Rounded := Sum - (-1.0);
  end
  else if IsLt(Rounded, -0.5) then
  begin
    Rounded := Sum + 1.0;
  end
  else
  begin
    Rounded := Sum;
  end;

  if IsNegative then
  begin
    const Origin: Single = 0;

    Rounded := Origin - Rounded;
  end;

  Result := Rounded;
end;

class function TTsLane.Floor(const Value: Single): Single;
begin
  const Roundtrip: Single = TTsScalar.SaturateToInt32(Value);

  var Correction: Single := 0;
  if IsGt(Roundtrip, Value) then
  begin
    Correction := 1;
  end;

  Result := Roundtrip - Correction;
end;

class function TTsLane.Normalize(const Value: Single): Single;
begin
  Result := FasterMin(FasterMax(Value, 0), 1);
end;

{ TU32x4 }

class function TU32x4.Splat(const Value: Cardinal): TU32x4;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TU32x4.FromArray(const Values: array of Cardinal): TU32x4;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TU32x4.CmpEq(const Rhs: TU32x4): TU32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.MaskBits(Lanes[I] = Rhs.Lanes[I]);
  end;
end;

function TU32x4.ShiftLeft(const Count: Integer): TU32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Cardinal(Lanes[I] shl Count);
  end;
end;

function TU32x4.ShiftRight(const Count: Integer): TU32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Lanes[I] shr Count;
  end;
end;

class operator TU32x4.LogicalNot(const A: TU32x4): TU32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := not A.Lanes[I];
  end;
end;

class operator TU32x4.Add(const A, B: TU32x4): TU32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.WrappingAddU32(A.Lanes[I], B.Lanes[I]);
  end;
end;

class operator TU32x4.BitwiseAnd(const A, B: TU32x4): TU32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] and B.Lanes[I];
  end;
end;

class operator TU32x4.BitwiseOr(const A, B: TU32x4): TU32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] or B.Lanes[I];
  end;
end;

{ TI32x4 }

class function TI32x4.Splat(const Value: Integer): TI32x4;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TI32x4.FromArray(const Values: array of Integer): TI32x4;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TI32x4.Blend(const OnTrue, OnFalse: TI32x4): TI32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := OnFalse.Lanes[I] xor ((OnFalse.Lanes[I] xor OnTrue.Lanes[I]) and Lanes[I]);
  end;
end;

function TI32x4.CmpEq(const Rhs: TI32x4): TI32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Integer(TTsLane.MaskBits(Lanes[I] = Rhs.Lanes[I]));
  end;
end;

function TI32x4.CmpGt(const Rhs: TI32x4): TI32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Integer(TTsLane.MaskBits(Lanes[I] > Rhs.Lanes[I]));
  end;
end;

function TI32x4.CmpLt(const Rhs: TI32x4): TI32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Integer(TTsLane.MaskBits(Lanes[I] < Rhs.Lanes[I]));
  end;
end;

function TI32x4.ToU32x4Bitcast: TU32x4;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

class operator TI32x4.Add(const A, B: TI32x4): TI32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.WrappingAddI32(A.Lanes[I], B.Lanes[I]);
  end;
end;

class operator TI32x4.BitwiseAnd(const A, B: TI32x4): TI32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] and B.Lanes[I];
  end;
end;

class operator TI32x4.Multiply(const A, B: TI32x4): TI32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    const Product: Int64 = Int64(A.Lanes[I]) * B.Lanes[I];

    Result.Lanes[I] := Integer(Cardinal(Product and $FFFFFFFF));
  end;
end;

class operator TI32x4.BitwiseOr(const A, B: TI32x4): TI32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] or B.Lanes[I];
  end;
end;

class operator TI32x4.BitwiseXor(const A, B: TI32x4): TI32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] xor B.Lanes[I];
  end;
end;

{ TF32x4 }

constructor TF32x4.Create(const A, B, C, D: Single);
begin
  Lanes[0] := A;
  Lanes[1] := B;
  Lanes[2] := C;
  Lanes[3] := D;
end;

class function TF32x4.Splat(const Value: Single): TF32x4;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TF32x4.FromArray(const Values: array of Single): TF32x4;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TF32x4.Floor: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Floor(Lanes[I]);
  end;
end;

function TF32x4.Abs: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(Lanes[I]) and NonSignBits);
  end;
end;

function TF32x4.Max(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.FasterMax(Lanes[I], Rhs.Lanes[I]);
  end;
end;

function TF32x4.Min(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.FasterMin(Lanes[I], Rhs.Lanes[I]);
  end;
end;

function TF32x4.CmpEq(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsEq(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x4.CmpNe(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsNe(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x4.CmpGe(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsGe(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x4.CmpGt(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsGt(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x4.CmpLe(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsLe(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x4.CmpLt(const Rhs: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsLt(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x4.Blend(const OnTrue, OnFalse: TF32x4): TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    const WhenFalse = TTsLane.Bits(OnFalse.Lanes[I]);
    const WhenTrue = TTsLane.Bits(OnTrue.Lanes[I]);

    TTsLane.SetBits(Result.Lanes[I], WhenFalse xor ((WhenFalse xor WhenTrue) and TTsLane.Bits(Lanes[I])));
  end;
end;

function TF32x4.Round: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Round(Lanes[I]);
  end;
end;

function TF32x4.RoundInt: TI32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.SaturateToInt32(TTsLane.Round(Lanes[I]));
  end;
end;

function TF32x4.TruncInt: TI32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.SaturateToInt32(Lanes[I]);
  end;
end;

function TF32x4.RecipFast: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := 1.0 / Lanes[I];
  end;
end;

function TF32x4.RecipSqrt: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    const Root: Single = System.Sqrt(Lanes[I]);

    Result.Lanes[I] := 1.0 / Root;
  end;
end;

function TF32x4.Sqrt: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := System.Sqrt(Lanes[I]);
  end;
end;

function TF32x4.ToI32x4Bitcast: TI32x4;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

function TF32x4.ToU32x4Bitcast: TU32x4;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

class operator TF32x4.Add(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] + B.Lanes[I];
  end;
end;

class operator TF32x4.Subtract(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] - B.Lanes[I];
  end;
end;

class operator TF32x4.Multiply(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] * B.Lanes[I];
  end;
end;

class operator TF32x4.Divide(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] / B.Lanes[I];
  end;
end;

class operator TF32x4.BitwiseAnd(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) and TTsLane.Bits(B.Lanes[I]));
  end;
end;

class operator TF32x4.BitwiseOr(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) or TTsLane.Bits(B.Lanes[I]));
  end;
end;

class operator TF32x4.BitwiseXor(const A, B: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) xor TTsLane.Bits(B.Lanes[I]));
  end;
end;

class operator TF32x4.Negative(const A: TF32x4): TF32x4;
begin
  const Origin: Single = 0;

  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Origin - A.Lanes[I];
  end;
end;

class operator TF32x4.LogicalNot(const A: TF32x4): TF32x4;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) xor AllBits);
  end;
end;

class operator TF32x4.Equal(const A, B: TF32x4): Boolean;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    if not TTsLane.IsEq(A.Lanes[I], B.Lanes[I]) then
    begin
      Exit(False);
    end;
  end;

  Result := True;
end;

class operator TF32x4.NotEqual(const A, B: TF32x4): Boolean;
begin
  Result := not (A = B);
end;

{ TU32x8 }

class function TU32x8.Splat(const Value: Cardinal): TU32x8;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TU32x8.FromArray(const Values: array of Cardinal): TU32x8;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TU32x8.CmpEq(const Rhs: TU32x8): TU32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.MaskBits(Lanes[I] = Rhs.Lanes[I]);
  end;
end;

function TU32x8.ShiftLeft(const Count: Integer): TU32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Cardinal(Lanes[I] shl Count);
  end;
end;

function TU32x8.ShiftRight(const Count: Integer): TU32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Lanes[I] shr Count;
  end;
end;

class operator TU32x8.LogicalNot(const A: TU32x8): TU32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := not A.Lanes[I];
  end;
end;

class operator TU32x8.Add(const A, B: TU32x8): TU32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.WrappingAddU32(A.Lanes[I], B.Lanes[I]);
  end;
end;

class operator TU32x8.BitwiseAnd(const A, B: TU32x8): TU32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] and B.Lanes[I];
  end;
end;

class operator TU32x8.BitwiseOr(const A, B: TU32x8): TU32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] or B.Lanes[I];
  end;
end;

{ TI32x8 }

class function TI32x8.Splat(const Value: Integer): TI32x8;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TI32x8.FromArray(const Values: array of Integer): TI32x8;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TI32x8.Blend(const OnTrue, OnFalse: TI32x8): TI32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := OnFalse.Lanes[I] xor ((OnFalse.Lanes[I] xor OnTrue.Lanes[I]) and Lanes[I]);
  end;
end;

function TI32x8.CmpEq(const Rhs: TI32x8): TI32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Integer(TTsLane.MaskBits(Lanes[I] = Rhs.Lanes[I]));
  end;
end;

function TI32x8.CmpGt(const Rhs: TI32x8): TI32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Integer(TTsLane.MaskBits(Lanes[I] > Rhs.Lanes[I]));
  end;
end;

function TI32x8.CmpLt(const Rhs: TI32x8): TI32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Integer(TTsLane.MaskBits(Lanes[I] < Rhs.Lanes[I]));
  end;
end;

function TI32x8.ToU32x8Bitcast: TU32x8;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

class operator TI32x8.Add(const A, B: TI32x8): TI32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.WrappingAddI32(A.Lanes[I], B.Lanes[I]);
  end;
end;

class operator TI32x8.BitwiseAnd(const A, B: TI32x8): TI32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] and B.Lanes[I];
  end;
end;

class operator TI32x8.Multiply(const A, B: TI32x8): TI32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    const Product: Int64 = Int64(A.Lanes[I]) * B.Lanes[I];

    Result.Lanes[I] := Integer(Cardinal(Product and $FFFFFFFF));
  end;
end;

class operator TI32x8.BitwiseOr(const A, B: TI32x8): TI32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] or B.Lanes[I];
  end;
end;

class operator TI32x8.BitwiseXor(const A, B: TI32x8): TI32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] xor B.Lanes[I];
  end;
end;

{ TF32x8 }

class function TF32x8.Splat(const Value: Single): TF32x8;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TF32x8.FromArray(const Values: array of Single): TF32x8;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TF32x8.Floor: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Floor(Lanes[I]);
  end;
end;

function TF32x8.Fract: TF32x8;
begin
  Result := Self - Floor;
end;

function TF32x8.Normalize: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Normalize(Lanes[I]);
  end;
end;

function TF32x8.ToI32x8Bitcast: TI32x8;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

function TF32x8.ToU32x8Bitcast: TU32x8;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

function TF32x8.CmpEq(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsEq(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x8.CmpNe(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsNe(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x8.CmpGe(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsGe(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x8.CmpGt(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsGt(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x8.CmpLe(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsLe(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x8.CmpLt(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsLt(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x8.Blend(const OnTrue, OnFalse: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    const WhenFalse = TTsLane.Bits(OnFalse.Lanes[I]);
    const WhenTrue = TTsLane.Bits(OnTrue.Lanes[I]);

    TTsLane.SetBits(Result.Lanes[I], WhenFalse xor ((WhenFalse xor WhenTrue) and TTsLane.Bits(Lanes[I])));
  end;
end;

function TF32x8.Abs: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(Lanes[I]) and NonSignBits);
  end;
end;

function TF32x8.Max(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.FasterMax(Lanes[I], Rhs.Lanes[I]);
  end;
end;

function TF32x8.Min(const Rhs: TF32x8): TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.FasterMin(Lanes[I], Rhs.Lanes[I]);
  end;
end;

function TF32x8.IsFinite: TF32x8;
begin
  const ShiftedExponentMask: Cardinal = $FF000000;

  for var I := 0 to High(Lanes) do
  begin
    const Shifted = Cardinal(TTsLane.Bits(Lanes[I]) shl 1);
    const IsInfiniteOrNaN = ((Shifted and ShiftedExponentMask) = ShiftedExponentMask);

    TTsLane.SetBits(Result.Lanes[I], not TTsLane.MaskBits(IsInfiniteOrNaN));
  end;
end;

function TF32x8.Round: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Round(Lanes[I]);
  end;
end;

function TF32x8.RoundInt: TI32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.SaturateToInt32(TTsLane.Round(Lanes[I]));
  end;
end;

function TF32x8.TruncInt: TI32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.SaturateToInt32(Lanes[I]);
  end;
end;

function TF32x8.RecipFast: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := 1.0 / Lanes[I];
  end;
end;

function TF32x8.RecipSqrt: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    const Root: Single = System.Sqrt(Lanes[I]);

    Result.Lanes[I] := 1.0 / Root;
  end;
end;

function TF32x8.Sqrt: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := System.Sqrt(Lanes[I]);
  end;
end;

class operator TF32x8.Add(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] + B.Lanes[I];
  end;
end;

class operator TF32x8.Subtract(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] - B.Lanes[I];
  end;
end;

class operator TF32x8.Multiply(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] * B.Lanes[I];
  end;
end;

class operator TF32x8.Divide(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] / B.Lanes[I];
  end;
end;

class operator TF32x8.BitwiseAnd(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) and TTsLane.Bits(B.Lanes[I]));
  end;
end;

class operator TF32x8.BitwiseOr(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) or TTsLane.Bits(B.Lanes[I]));
  end;
end;

class operator TF32x8.BitwiseXor(const A, B: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) xor TTsLane.Bits(B.Lanes[I]));
  end;
end;

class operator TF32x8.Negative(const A: TF32x8): TF32x8;
begin
  const Origin: Single = 0;

  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Origin - A.Lanes[I];
  end;
end;

class operator TF32x8.LogicalNot(const A: TF32x8): TF32x8;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(A.Lanes[I]) xor AllBits);
  end;
end;

class operator TF32x8.Equal(const A, B: TF32x8): Boolean;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    if not TTsLane.IsEq(A.Lanes[I], B.Lanes[I]) then
    begin
      Exit(False);
    end;
  end;

  Result := True;
end;

class operator TF32x8.NotEqual(const A, B: TF32x8): Boolean;
begin
  Result := not (A = B);
end;

{ TU16x16 }

class function TU16x16.Splat(const Value: Word): TU16x16;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

class function TU16x16.FromArray(const Values: array of Word): TU16x16;
begin
  CheckLaneCount(Length(Result.Lanes), Length(Values));

  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Values[I];
  end;
end;

function TU16x16.Min(const Rhs: TU16x16): TU16x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Word(System.Math.Min(Lanes[I], Rhs.Lanes[I]));
  end;
end;

function TU16x16.Max(const Rhs: TU16x16): TU16x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Word(System.Math.Max(Lanes[I], Rhs.Lanes[I]));
  end;
end;

function TU16x16.CmpLe(const Rhs: TU16x16): TU16x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Word(TTsLane.MaskBits(Lanes[I] <= Rhs.Lanes[I]) and $FFFF);
  end;
end;

function TU16x16.Blend(const OnTrue, OnFalse: TU16x16): TU16x16;
begin
  Result := (OnTrue and Self) or (OnFalse and (not Self));
end;

class operator TU16x16.Add(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word((Cardinal(A.Lanes[I]) + B.Lanes[I]) and $FFFF);
  end;
end;

class operator TU16x16.Subtract(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word((Cardinal(A.Lanes[I]) - B.Lanes[I]) and $FFFF);
  end;
end;

class operator TU16x16.Multiply(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word((Cardinal(A.Lanes[I]) * B.Lanes[I]) and $FFFF);
  end;
end;

class operator TU16x16.Divide(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word(A.Lanes[I] div B.Lanes[I]);
  end;
end;

class operator TU16x16.BitwiseAnd(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word(A.Lanes[I] and B.Lanes[I]);
  end;
end;

class operator TU16x16.BitwiseOr(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word(A.Lanes[I] or B.Lanes[I]);
  end;
end;

class operator TU16x16.LogicalNot(const A: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word((not Cardinal(A.Lanes[I])) and $FFFF);
  end;
end;

class operator TU16x16.RightShift(const A, B: TU16x16): TU16x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := Word(A.Lanes[I] shr (B.Lanes[I] and 15));
  end;
end;

class operator TU16x16.Equal(const A, B: TU16x16): Boolean;
begin
  Result := CompareMem(@A.Lanes, @B.Lanes, SizeOf(A.Lanes));
end;

class operator TU16x16.NotEqual(const A, B: TU16x16): Boolean;
begin
  Result := not CompareMem(@A.Lanes, @B.Lanes, SizeOf(A.Lanes));
end;

{ TF32x16 }

constructor TF32x16.Create(const First, Second: TF32x8);
begin
  Move(First.Lanes, Lanes[0], SizeOf(First.Lanes));
  Move(Second.Lanes, Lanes[8], SizeOf(Second.Lanes));
end;

class function TF32x16.Splat(const Value: Single): TF32x16;
begin
  for var I := 0 to High(Result.Lanes) do
  begin
    Result.Lanes[I] := Value;
  end;
end;

function TF32x16.Abs: TF32x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(Lanes[I]) and NonSignBits);
  end;
end;

function TF32x16.CmpGt(const Rhs: TF32x16): TF32x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.MaskBits(TTsLane.IsGt(Lanes[I], Rhs.Lanes[I])));
  end;
end;

function TF32x16.Blend(const OnTrue, OnFalse: TF32x16): TF32x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    const WhenFalse = TTsLane.Bits(OnFalse.Lanes[I]);
    const WhenTrue = TTsLane.Bits(OnTrue.Lanes[I]);

    TTsLane.SetBits(Result.Lanes[I], WhenFalse xor ((WhenFalse xor WhenTrue) and TTsLane.Bits(Lanes[I])));
  end;
end;

function TF32x16.Normalize: TF32x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Normalize(Lanes[I]);
  end;
end;

function TF32x16.Floor: TF32x16;
begin
  // Yes, Skia does it in the same way: round, then subtract 1 where that is more than the value
  for var I := 0 to High(Lanes) do
  begin
    const Roundtrip = TTsLane.Round(Lanes[I]);

    var Correction: Single := 0;
    if TTsLane.IsGt(Roundtrip, Lanes[I]) then
    begin
      Correction := 1;
    end;

    Result.Lanes[I] := Roundtrip - Correction;
  end;
end;

function TF32x16.Sqrt: TF32x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := System.Sqrt(Lanes[I]);
  end;
end;

function TF32x16.Round: TF32x16;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.Round(Lanes[I]);
  end;
end;

procedure TF32x16.SaveToU16x16(var Destination: TU16x16);
begin
  for var I := 0 to High(Lanes) do
  begin
    const Value = Lanes[I];

    // Rust `as u16`: NaN becomes 0, the rest saturates
    if IsNan(Value) or (Value <= 0) then
    begin
      Destination.Lanes[I] := 0;
    end
    else if Value >= 65535 then
    begin
      Destination.Lanes[I] := 65535;
    end
    else
    begin
      Destination.Lanes[I] := Word(Trunc(Value));
    end;
  end;
end;

class operator TF32x16.Add(const A, B: TF32x16): TF32x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] + B.Lanes[I];
  end;
end;

class operator TF32x16.Subtract(const A, B: TF32x16): TF32x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] - B.Lanes[I];
  end;
end;

class operator TF32x16.Multiply(const A, B: TF32x16): TF32x16;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] * B.Lanes[I];
  end;
end;

{ TF32x2 }

constructor TF32x2.Create(const A, B: Single);
begin
  Lanes[0] := A;
  Lanes[1] := B;
end;

class function TF32x2.Splat(const Value: Single): TF32x2;
begin
  Result.Lanes[0] := Value;
  Result.Lanes[1] := Value;
end;

function TF32x2.Abs: TF32x2;
begin
  for var I := 0 to High(Lanes) do
  begin
    TTsLane.SetBits(Result.Lanes[I], TTsLane.Bits(Lanes[I]) and NonSignBits);
  end;
end;

// pmin and pmax of f32x2_t.rs are the faster_min and faster_max of the wide types with the operands swapped
function TF32x2.Min(const Other: TF32x2): TF32x2;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.FasterMin(Lanes[I], Other.Lanes[I]);
  end;
end;

function TF32x2.Max(const Other: TF32x2): TF32x2;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsLane.FasterMax(Lanes[I], Other.Lanes[I]);
  end;
end;

function TF32x2.MaxComponent: Single;
begin
  Result := TTsLane.FasterMax(Lanes[0], Lanes[1]);
end;

function TF32x2.X: Single;
begin
  Result := Lanes[0];
end;

function TF32x2.Y: Single;
begin
  Result := Lanes[1];
end;

class operator TF32x2.Add(const A, B: TF32x2): TF32x2;
begin
  Result.Lanes[0] := A.Lanes[0] + B.Lanes[0];
  Result.Lanes[1] := A.Lanes[1] + B.Lanes[1];
end;

class operator TF32x2.Subtract(const A, B: TF32x2): TF32x2;
begin
  Result.Lanes[0] := A.Lanes[0] - B.Lanes[0];
  Result.Lanes[1] := A.Lanes[1] - B.Lanes[1];
end;

class operator TF32x2.Multiply(const A, B: TF32x2): TF32x2;
begin
  Result.Lanes[0] := A.Lanes[0] * B.Lanes[0];
  Result.Lanes[1] := A.Lanes[1] * B.Lanes[1];
end;

class operator TF32x2.Divide(const A, B: TF32x2): TF32x2;
begin
  Result.Lanes[0] := A.Lanes[0] / B.Lanes[0];
  Result.Lanes[1] := A.Lanes[1] / B.Lanes[1];
end;

class operator TF32x2.Equal(const A, B: TF32x2): Boolean;
begin
  Result := (TTsLane.IsEq(A.Lanes[0], B.Lanes[0]) and TTsLane.IsEq(A.Lanes[1], B.Lanes[1]));
end;

class operator TF32x2.NotEqual(const A, B: TF32x2): Boolean;
begin
  Result := not (A = B);
end;

{ TF32x4Path }

constructor TF32x4Path.Create(const A, B, C, D: Single);
begin
  Lanes[0] := A;
  Lanes[1] := B;
  Lanes[2] := C;
  Lanes[3] := D;
end;

function TF32x4Path.Max(const Rhs: TF32x4Path): TF32x4Path;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.MaxF(Lanes[I], Rhs.Lanes[I]);
  end;
end;

function TF32x4Path.Min(const Rhs: TF32x4Path): TF32x4Path;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := TTsScalar.MinF(Lanes[I], Rhs.Lanes[I]);
  end;
end;

class operator TF32x4Path.Add(const A, B: TF32x4Path): TF32x4Path;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] + B.Lanes[I];
  end;
end;

class operator TF32x4Path.Subtract(const A, B: TF32x4Path): TF32x4Path;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] - B.Lanes[I];
  end;
end;

class operator TF32x4Path.Multiply(const A, B: TF32x4Path): TF32x4Path;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    Result.Lanes[I] := A.Lanes[I] * B.Lanes[I];
  end;
end;

class operator TF32x4Path.Equal(const A, B: TF32x4Path): Boolean;
begin
  for var I := 0 to High(A.Lanes) do
  begin
    if not TTsLane.IsEq(A.Lanes[I], B.Lanes[I]) then
    begin
      Exit(False);
    end;
  end;

  Result := True;
end;

class operator TF32x4Path.NotEqual(const A, B: TF32x4Path): Boolean;
begin
  Result := not (A = B);
end;

{ TU32x4Casts }

function TU32x4Casts.ToI32x4Bitcast: TI32x4;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

function TU32x4Casts.ToF32x4Bitcast: TF32x4;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

{ TI32x4Casts }

function TI32x4Casts.ToF32x4: TF32x4;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Lanes[I];
  end;
end;

function TI32x4Casts.ToF32x4Bitcast: TF32x4;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

{ TU32x8Casts }

function TU32x8Casts.ToI32x8Bitcast: TI32x8;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

function TU32x8Casts.ToF32x8Bitcast: TF32x8;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

{ TI32x8Casts }

function TI32x8Casts.ToF32x8: TF32x8;
begin
  for var I := 0 to High(Lanes) do
  begin
    Result.Lanes[I] := Lanes[I];
  end;
end;

function TI32x8Casts.ToF32x8Bitcast: TF32x8;
begin
  Move(Lanes, Result.Lanes, SizeOf(Lanes));
end;

end.
