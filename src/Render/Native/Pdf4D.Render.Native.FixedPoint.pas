// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/fixed_point.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.FixedPoint;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Native.Scalar;

// Skia uses fixed point values pretty chaotically, so tiny-skia has no strong types for them and neither has this port: FDot6 (26.6),
// FDot8 (24.8) and FDot16 (16.16) are all an Integer. The records hold the functions of the Rust modules fdot6, fdot8 and fdot16.
//
// Rust shifts right with the sign bit copied (TTsScalar.ShiftRightI32 and ShiftRightI64), adds with wrapping in a release build
// (TTsScalar.WrappingAddI32) and panics on a division by zero; the Div functions raise EDivByZero for a zero divisor, and the caller
// (the edge builder) never passes one.

type
  // A 26.6 fixed point
  TTsFdot6 = record
  public const
    One = 64;

  public
    class function FromI32(const N: Integer): Integer; static;
    class function FromF32(const N: Single): Integer; static;
    class function Floor(const N: Integer): Integer; static;
    class function Ceil(const N: Integer): Integer; static;
    class function Round(const N: Integer): Integer; static;
    class function ToFdot16(const N: Integer): Integer; static;
    class function &Div(const A, B: Integer): Integer; static;
    class function CanConvertToFdot16(const N: Integer): Boolean; static;
    class function SmallScale(const Value: Byte; const Dot6: Integer): Byte; static;
  end;

  // A 24.8 fixed point
  TTsFdot8 = record
    class function FromFdot16(const X: Integer): Integer; static;
  end;

  // A 16.16 fixed point
  TTsFdot16 = record
  public const
    Half = (1 shl 16) div 2;
    One = 1 shl 16;

  public
    class function FromF32(const X: Single): Integer; static;
    class function FloorToI32(const X: Integer): Integer; static;
    class function CeilToI32(const X: Integer): Integer; static;
    class function RoundToI32(const X: Integer): Integer; static;

    // The product may exceed 32 bits; it is cut to 32 bits
    class function Mul(const A, B: Integer): Integer; static;

    // The quotient may exceed 32 bits; it is clamped to a signed 32 bit result
    class function &Div(const Numer, Denom: Integer): Integer; static;
    class function FastDiv(const A, B: Integer): Integer; static;
  end;

implementation

const
  MaxDot6ToFdot16 = High(Integer) shr (16 - 6);
  Fdot6Scale: Single = 64.0;
  Fdot16Scale: Single = 65536.0;

{ TTsFdot6 }

class function TTsFdot6.FromI32(const N: Integer): Integer;
begin
  Result := TTsScalar.LeftShift(N, 6);
end;

class function TTsFdot6.FromF32(const N: Single): Integer;
begin
  const Scaled: Single = N * Fdot6Scale;

  Result := TTsScalar.SaturateToInt32(Scaled);
end;

class function TTsFdot6.Floor(const N: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(N, 6);
end;

class function TTsFdot6.Ceil(const N: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(TTsScalar.WrappingAddI32(N, 63), 6);
end;

class function TTsFdot6.Round(const N: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(TTsScalar.WrappingAddI32(N, 32), 6);
end;

class function TTsFdot6.ToFdot16(const N: Integer): Integer;
begin
  Result := TTsScalar.LeftShift(N, 10);
end;

class function TTsFdot6.&Div(const A, B: Integer): Integer;
begin
  const FitsInI16 = ((A >= Low(SmallInt)) and (A <= High(SmallInt)));
  if FitsInI16 then
  begin
    Exit(TTsScalar.LeftShift(A, 16) div B);
  end;

  Result := TTsFdot16.Div(A, B);
end;

class function TTsFdot6.CanConvertToFdot16(const N: Integer): Boolean;
begin
  Result := ((N >= -MaxDot6ToFdot16) and (N <= MaxDot6ToFdot16));
end;

class function TTsFdot6.SmallScale(const Value: Byte; const Dot6: Integer): Byte;
begin
  const Scaled = TTsScalar.ShiftRightI32(Integer(Value) * Dot6, 6);

  Result := Byte(Scaled);
end;

{ TTsFdot8 }

class function TTsFdot8.FromFdot16(const X: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(TTsScalar.WrappingAddI32(X, $80), 8);
end;

{ TTsFdot16 }

// `from_f32` seems to lack a rounding step. For all fixed-point values, this version is as accurate as possible for
// (fixed -> float -> fixed). Rounding reduces accuracy if the intermediate floats are in the range that only holds integers.
class function TTsFdot16.FromF32(const X: Single): Integer;
begin
  const Scaled: Single = X * Fdot16Scale;

  Result := TTsScalar.SaturateFrom(Scaled);
end;

class function TTsFdot16.FloorToI32(const X: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(X, 16);
end;

class function TTsFdot16.CeilToI32(const X: Integer): Integer;
begin
  const Sum = TTsScalar.WrappingSubI32(TTsScalar.WrappingAddI32(X, One), 1);

  Result := TTsScalar.ShiftRightI32(Sum, 16);
end;

class function TTsFdot16.RoundToI32(const X: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(TTsScalar.WrappingAddI32(X, Half), 16);
end;

class function TTsFdot16.Mul(const A, B: Integer): Integer;
begin
  const Product = Int64(A) * Int64(B);

  Result := Integer(TTsScalar.ShiftRightI64(Product, 16));
end;

class function TTsFdot16.&Div(const Numer, Denom: Integer): Integer;
begin
  const Quotient = TTsScalar.LeftShift64(Int64(Numer), 16) div Int64(Denom);

  if Quotient < Low(Integer) then
  begin
    Exit(Low(Integer));
  end;

  if Quotient > High(Integer) then
  begin
    Exit(High(Integer));
  end;

  Result := Integer(Quotient);
end;

class function TTsFdot16.FastDiv(const A, B: Integer): Integer;
begin
  Result := TTsScalar.LeftShift(A, 16) div B;
end;

end.
