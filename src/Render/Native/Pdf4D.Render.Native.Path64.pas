// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/path64/mod.rs
// Port of: tiny-skia v0.12.0 src/path64/point64.rs
// Port of: tiny-skia v0.12.0 src/path64/quad64.rs
// Port of: tiny-skia v0.12.0 src/path64/cubic64.rs
// Port of: tiny-skia v0.12.0 src/path64/line_cubic_intersections.rs
// Copyright (c) 2012 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Path64;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry;

// The f64 code of tiny-skia (from SkPathOpsTypes and friends): finds the t of a cubic at a given x or y. It is plain Double code;
// on Win64 it needs no special precision handling.
//
// The Rust slices of f64 are fixed arrays; where Rust passes a sub-slice (&slice[1..]) the function takes an offset.
//
// Where Rust would index outside an array or loop forever, this port stops instead (every such place says so): the input is a
// cubic of finite points, but hostile values must never raise or hang.

type
  TTsDoubles3 = array[0..2] of Double;
  TTsDoubles6 = array[0..5] of Double;
  TTsDoubles8 = array[0..7] of Double;

  TTsSearchAxis = (
    X,
    Y);

  TTsPoint64 = record
  public
    X: Double;
    Y: Double;

    class function FromXY(const FromX, FromY: Double): TTsPoint64; static;
    class function FromPoint(const Point: TTsPoint): TTsPoint64; static;
    class function Zero: TTsPoint64; static;

    function ToPoint: TTsPoint;
    function AxisCoord(const Axis: TTsSearchAxis): Double;
  end;

  // The Scalar64 trait of path64/mod.rs for f64
  TTsScalar64 = record
  public
    // Works just like SkTPin, returning `max` for NaN/inf
    class function Bound(const Value, Min, Max: Double): Double; static;

    // Returns true if (a <= self <= b) || (a >= self >= b).
    class function Between(const Value, A, B: Double): Boolean; static;
    class function PreciselyZero(const Value: Double): Boolean; static;
    class function ApproximatelyZeroOrMore(const Value: Double): Boolean; static;
    class function ApproximatelyOneOrLess(const Value: Double): Boolean; static;
    class function ApproximatelyZero(const Value: Double): Boolean; static;
    class function ApproximatelyZeroInverse(const Value: Double): Boolean; static;
    class function ApproximatelyZeroCubed(const Value: Double): Boolean; static;
    class function ApproximatelyZeroHalf(const Value: Double): Boolean; static;
    class function ApproximatelyZeroWhenComparedTo(const Value, Other: Double): Boolean; static;

    // Use this for comparing Ts in the range of 0 to 1. For general numbers (larger and smaller) use
    // AlmostDequalUlps instead.
    class function ApproximatelyEqual(const Value, Other: Double): Boolean; static;
    class function ApproximatelyEqualHalf(const Value, Other: Double): Boolean; static;
    class function AlmostDequalUlps(const Value, Other: Double): Boolean; static;
  end;

  // The free functions of path64/mod.rs
  TTsPath64 = record
  public
    class function CubeRoot(const X: Double): Double; static;
    class function Interp(const A, B, T: Double): Double; static;

  private
    // cube root approximation using 3 iterations of Halley's method (double)
    class function HalleyCbrt3d(const D: Double): Double; static;

    // cube root approximation using bit hack for 64-bit float, adapted from Kahan's cbrt
    class function Cbrt5d(const D: Double): Double; static;

    // iterative cube root approximation using Halley's method (double)
    class function CbrtaHalleyd(const A, R: Double): Double; static;
  end;

  // Quadratic equations of path64/quad64.rs
  TTsQuad64 = record
  public
    class function PushValidTs(const S: array of Double; const RealRoots: Integer; var T: array of Double): Integer; static;

    // note: caller expects multiple results to be sorted smaller first
    // note: http://en.wikipedia.org/wiki/Loss_of_significance has an interesting
    //  analysis of the quadratic equation, suggesting why the following looks at
    //  the sign of B -- and further suggesting that the greatest loss of precision
    //  is in b squared less two a c
    class function RootsValidT(const A, B, C: Double; var T: array of Double): Integer; static;

    // Numeric Solutions (5.6) suggests to solve the quadratic by computing
    //     Q = -1/2(B + sgn(B)Sqrt(B^2 - 4 A C))
    // and using the roots
    //     t1 = Q / A
    //     t2 = C / Q
    //
    // this does not discard real roots <= 0 or >= 1
    class function RootsReal(const A, B, C: Double; var S: TTsDoubles3): Integer; static;

  private
    class function HandleZero(const B, C: Double; var S: TTsDoubles3): Integer; static;
  end;

  TTsCubic64Pair = record
    Points: array[0..6] of TTsPoint64;
  end;

  TTsCubic64 = record
  public const
    PointCount = 4;

  public
    Points: array[0..PointCount - 1] of TTsPoint64;

    class function Create(const Points: array of TTsPoint64): TTsCubic64; static;

    function AsF64Slice: TTsDoubles8;
    function PointAtT(const T: Double): TTsPoint64;

    // Returns the number of valid roots in ValidRoots
    function SearchRoots(const Extrema: Integer; const AxisIntercept: Double; const XAxis: TTsSearchAxis; var ExtremeTs: TTsDoubles6;
                         var ValidRoots: TTsDoubles3): Integer;
    function ChopAt(const T: Double): TTsCubic64Pair;

    // Cubic64'(t) = At^2 + Bt + C, where
    // A = 3(-a + 3(b - c) + d)
    // B = 6(a - 2b + c)
    // C = 3(b - a)
    // Solve for t, keeping only those that fit between 0 < t < 1. The coordinates start at Offset in Src (Rust slices Src[1..]).
    class function FindExtrema(const Src: TTsDoubles8; const Offset: Integer; var TValues: array of Double): Integer; static;

    // The coordinates start at Offset in Src (Rust slices Src[1..])
    class procedure Coefficients(const Src: TTsDoubles8; const Offset: Integer; out A, B, C, D: Double); static;

    // from SkGeometry.cpp (and Numeric Solutions, 5.6)
    class function RootsValidT(const A, B, C, D: Double; var T: TTsDoubles3): Integer; static;

  private const
    // Rust loops until the step underflows; with NaN points the loop of the binary search would never end
    MaxBinarySearchSteps = 4096;

  private
    function FindInflections(var TValues: TTsDoubles3): Integer;

    // give up when changing t no longer moves point
    // also, copy point rather than recompute it when it does change
    function BinarySearch(const Min, Max, AxisIntercept: Double; const XAxis: TTsSearchAxis): Double;

    class function RootsReal(const A, B, C, D: Double; var S: TTsDoubles3): Integer; static;

    // Skia doesn't seems to care about NaN/inf during sorting, so we don't too.
    class procedure SortF64(var Values: TTsDoubles6; const Count: Integer); static;
  end;

  // Intersections of a horizontal or vertical line with a cubic (path64/line_cubic_intersections.rs)
  TTsLineCubicIntersections = record
  public
    class function HorizontalIntersect(const Cubic: TTsCubic64; const AxisIntercept: Double; var Roots: TTsDoubles3): Integer; static;
    class function VerticalIntersect(const Cubic: TTsCubic64; const AxisIntercept: Double; var Roots: TTsDoubles3): Integer; static;
  end;

implementation

const
  // f64::EPSILON and f32::EPSILON, both exact powers of two
  DblEpsilon: Double = 2.220446049250313080847263336181640625E-16;
  FltEpsilon: Single = 1.1920928955078125E-7;

  // The constants of SkPathOpsTypes
  DblEpsilonErr: Double = 2.220446049250313080847263336181640625E-16 * 4.0;
  FltEpsilonHalf: Double = 5.9604644775390625E-8;
  FltEpsilonCubed: Double = 1.69406589450860068E-21;
  FltEpsilonInverse: Double = 8388608.0;
  FltEpsilonTimes16: Double = 1.9073486328125E-6;

  Pi64: Double = 3.141592653589793;

type
  // Reads the two halves of a Double
  TDoubleBits = record
    case Boolean of
      False: (AsDouble: Double);
      True: (AsBits: UInt64);
  end;

function MaxIgnoringNan(const A, B: Double): Double;
begin
  // f64::max: a NaN operand gives the other one
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
    Result := A;
  end
  else
  begin
    Result := B;
  end;
end;

{ TTsPoint64 }

class function TTsPoint64.FromXY(const FromX, FromY: Double): TTsPoint64;
begin
  Result.X := FromX;
  Result.Y := FromY;
end;

class function TTsPoint64.FromPoint(const Point: TTsPoint): TTsPoint64;
begin
  Result.X := Point.X;
  Result.Y := Point.Y;
end;

class function TTsPoint64.Zero: TTsPoint64;
begin
  Result.X := 0.0;
  Result.Y := 0.0;
end;

function TTsPoint64.ToPoint: TTsPoint;
begin
  const SingleX: Single = X;
  const SingleY: Single = Y;

  Result := TTsPoint.FromXY(SingleX, SingleY);
end;

function TTsPoint64.AxisCoord(const Axis: TTsSearchAxis): Double;
begin
  if Axis = TTsSearchAxis.X then
  begin
    Result := X;
  end
  else
  begin
    Result := Y;
  end;
end;

{ TTsScalar64 }

class function TTsScalar64.Bound(const Value, Min, Max: Double): Double;
begin
  // max.min(self).max(min)
  var Pinned := Max;
  if Value < Pinned then
  begin
    Pinned := Value;
  end;

  Result := MaxIgnoringNan(Pinned, Min);
end;

class function TTsScalar64.Between(const Value, A, B: Double): Boolean;
begin
  Result := ((A - Value) * (B - Value) <= 0.0);
end;

class function TTsScalar64.PreciselyZero(const Value: Double): Boolean;
begin
  Result := (Abs(Value) < DblEpsilonErr);
end;

class function TTsScalar64.ApproximatelyZeroOrMore(const Value: Double): Boolean;
begin
  Result := (Value > -DblEpsilon);
end;

class function TTsScalar64.ApproximatelyOneOrLess(const Value: Double): Boolean;
begin
  Result := (Value < 1.0 + DblEpsilon);
end;

class function TTsScalar64.ApproximatelyZero(const Value: Double): Boolean;
begin
  Result := (Abs(Value) < DblEpsilon);
end;

class function TTsScalar64.ApproximatelyZeroInverse(const Value: Double): Boolean;
begin
  Result := (Abs(Value) > FltEpsilonInverse);
end;

class function TTsScalar64.ApproximatelyZeroCubed(const Value: Double): Boolean;
begin
  Result := (Abs(Value) < FltEpsilonCubed);
end;

class function TTsScalar64.ApproximatelyZeroHalf(const Value: Double): Boolean;
begin
  Result := (Value < FltEpsilonHalf);
end;

class function TTsScalar64.ApproximatelyZeroWhenComparedTo(const Value, Other: Double): Boolean;
begin
  const Scaled: Double = Other * FltEpsilon;

  Result := ((Value = 0.0) or (Abs(Value) < Abs(Scaled)));
end;

class function TTsScalar64.ApproximatelyEqual(const Value, Other: Double): Boolean;
begin
  Result := ApproximatelyZero(Value - Other);
end;

class function TTsScalar64.ApproximatelyEqualHalf(const Value, Other: Double): Boolean;
begin
  Result := ApproximatelyZeroHalf(Value - Other);
end;

class function TTsScalar64.AlmostDequalUlps(const Value, Other: Double): Boolean;
begin
  if (Abs(Value) < TTsScalar.ScalarMax) and (Abs(Other) < TTsScalar.ScalarMax) then
  begin
    const SingleValue: Single = Value;
    const SingleOther: Single = Other;

    Exit(TTsScalar.AlmostDequalUlps(SingleValue, SingleOther));
  end;

  Result := (Abs(Value - Other) / MaxIgnoringNan(Abs(Value), Abs(Other)) < FltEpsilonTimes16);
end;

{ TTsPath64 }

class function TTsPath64.CubeRoot(const X: Double): Double;
begin
  if TTsScalar64.ApproximatelyZeroCubed(X) then
  begin
    Exit(0.0);
  end;

  const Root = HalleyCbrt3d(Abs(X));
  if X < 0.0 then
  begin
    Result := -Root;
  end
  else
  begin
    Result := Root;
  end;
end;

class function TTsPath64.HalleyCbrt3d(const D: Double): Double;
begin
  var A := Cbrt5d(D);

  A := CbrtaHalleyd(A, D);
  A := CbrtaHalleyd(A, D);

  Result := CbrtaHalleyd(A, D);
end;

class function TTsPath64.Cbrt5d(const D: Double): Double;
const
  B1 = 715094163;
begin
  var Source: TDoubleBits;
  Source.AsDouble := D;

  // The result starts as 0.0; only its high word is set (index 1 of the u32 pair)
  const HighWord: Cardinal = Cardinal(Source.AsBits shr 32);
  const NewHighWord: Cardinal = HighWord div 3 + B1;

  var Target: TDoubleBits;
  Target.AsBits := UInt64(NewHighWord) shl 32;

  Result := Target.AsDouble;
end;

class function TTsPath64.CbrtaHalleyd(const A, R: Double): Double;
begin
  const A3 = A * A * A;

  Result := A * (A3 + R + R) / (A3 + A3 + R);
end;

class function TTsPath64.Interp(const A, B, T: Double): Double;
begin
  Result := A + (B - A) * T;
end;

{ TTsQuad64 }

class function TTsQuad64.PushValidTs(const S: array of Double; const RealRoots: Integer; var T: array of Double): Integer;
begin
  var FoundRoots := 0;

  for var Index := 0 to RealRoots - 1 do
  begin
    var TValue := S[Index];
    if not (TTsScalar64.ApproximatelyZeroOrMore(TValue) and TTsScalar64.ApproximatelyOneOrLess(TValue)) then
    begin
      Continue;
    end;

    TValue := TTsScalar64.Bound(TValue, 0.0, 1.0);

    var IsDuplicate := False;
    for var Other := 0 to FoundRoots - 1 do
    begin
      if TTsScalar64.ApproximatelyEqual(T[Other], TValue) then
      begin
        IsDuplicate := True;
        Break;
      end;
    end;

    if IsDuplicate then
    begin
      Continue;
    end;

    // Rust indexes outside the slice here, which panics
    if FoundRoots > High(T) then
    begin
      Exit(FoundRoots);
    end;

    T[FoundRoots] := TValue;
    Inc(FoundRoots);
  end;

  Result := FoundRoots;
end;

class function TTsQuad64.RootsValidT(const A, B, C: Double; var T: array of Double): Integer;
begin
  var S: TTsDoubles3;
  S[0] := 0.0;
  S[1] := 0.0;
  S[2] := 0.0;

  const RealRoots = RootsReal(A, B, C, S);

  Result := PushValidTs(S, RealRoots, T);
end;

class function TTsQuad64.RootsReal(const A, B, C: Double; var S: TTsDoubles3): Integer;
begin
  if A = 0.0 then
  begin
    Exit(HandleZero(B, C, S));
  end;

  const P: Double = B / (2.0 * A);
  const Q: Double = C / A;
  if TTsScalar64.ApproximatelyZero(A) and (TTsScalar64.ApproximatelyZeroInverse(P) or TTsScalar64.ApproximatelyZeroInverse(Q)) then
  begin
    Exit(HandleZero(B, C, S));
  end;

  // normal form: x^2 + px + q = 0
  const P2: Double = P * P;
  if (not TTsScalar64.AlmostDequalUlps(P2, Q)) and (P2 < Q) then
  begin
    Exit(0);
  end;

  var SqrtD: Double := 0.0;
  if P2 > Q then
  begin
    SqrtD := System.Sqrt(P2 - Q);
  end;

  S[0] := SqrtD - P;
  S[1] := -SqrtD - P;

  if TTsScalar64.AlmostDequalUlps(S[0], S[1]) then
  begin
    Result := 1;
  end
  else
  begin
    Result := 2;
  end;
end;

class function TTsQuad64.HandleZero(const B, C: Double; var S: TTsDoubles3): Integer;
begin
  if TTsScalar64.ApproximatelyZero(B) then
  begin
    S[0] := 0.0;

    if C = 0.0 then
    begin
      Result := 1;
    end
    else
    begin
      Result := 0;
    end;

    Exit;
  end;

  S[0] := -C / B;
  Result := 1;
end;

{ TTsCubic64 }

class function TTsCubic64.Create(const Points: array of TTsPoint64): TTsCubic64;
begin
  for var Index := 0 to PointCount - 1 do
  begin
    Result.Points[Index] := Points[Index];
  end;
end;

function TTsCubic64.AsF64Slice: TTsDoubles8;
begin
  Result[0] := Points[0].X;
  Result[1] := Points[0].Y;
  Result[2] := Points[1].X;
  Result[3] := Points[1].Y;
  Result[4] := Points[2].X;
  Result[5] := Points[2].Y;
  Result[6] := Points[3].X;
  Result[7] := Points[3].Y;
end;

function TTsCubic64.PointAtT(const T: Double): TTsPoint64;
begin
  if T = 0.0 then
  begin
    Exit(Points[0]);
  end;

  if T = 1.0 then
  begin
    Exit(Points[3]);
  end;

  const OneT: Double = 1.0 - T;
  const OneT2: Double = OneT * OneT;
  const A: Double = OneT2 * OneT;
  const B: Double = 3.0 * OneT2 * T;
  const T2: Double = T * T;
  const C: Double = 3.0 * OneT * T2;
  const D: Double = T2 * T;

  Result := TTsPoint64.FromXY(A * Points[0].X + B * Points[1].X + C * Points[2].X + D * Points[3].X,
                              A * Points[0].Y + B * Points[1].Y + C * Points[2].Y + D * Points[3].Y);
end;

function TTsCubic64.SearchRoots(const Extrema: Integer; const AxisIntercept: Double; const XAxis: TTsSearchAxis;
                                var ExtremeTs: TTsDoubles6; var ValidRoots: TTsDoubles3): Integer;
begin
  var ExtremaCount := Extrema;

  // Rust passes the tail of extreme_ts to find_inflections
  var Inflections: TTsDoubles3;
  const InflectionCount = FindInflections(Inflections);
  for var Index := 0 to InflectionCount - 1 do
  begin
    if ExtremaCount + Index <= High(ExtremeTs) then
    begin
      ExtremeTs[ExtremaCount + Index] := Inflections[Index];
    end;
  end;

  Inc(ExtremaCount, InflectionCount);

  // At most 2 extrema and 2 inflections are found, so 4 + 2 values fit
  if ExtremaCount + 1 > High(ExtremeTs) then
  begin
    Exit(0);
  end;

  ExtremeTs[ExtremaCount] := 0.0;
  Inc(ExtremaCount);
  ExtremeTs[ExtremaCount] := 1.0;

  SortF64(ExtremeTs, ExtremaCount);

  var ValidCount := 0;
  var Index := 0;
  while Index < ExtremaCount do
  begin
    const Min = ExtremeTs[Index];
    Inc(Index);
    const Max = ExtremeTs[Index];
    if Min = Max then
    begin
      Continue;
    end;

    const NewT = BinarySearch(Min, Max, AxisIntercept, XAxis);
    if NewT >= 0.0 then
    begin
      if ValidCount >= 3 then
      begin
        Exit(0);
      end;

      ValidRoots[ValidCount] := NewT;
      Inc(ValidCount);
    end;
  end;

  Result := ValidCount;
end;

function TTsCubic64.FindInflections(var TValues: TTsDoubles3): Integer;
begin
  const Ax: Double = Points[1].X - Points[0].X;
  const Ay: Double = Points[1].Y - Points[0].Y;
  const Bx: Double = Points[2].X - 2.0 * Points[1].X + Points[0].X;
  const By: Double = Points[2].Y - 2.0 * Points[1].Y + Points[0].Y;
  const Cx: Double = Points[3].X + 3.0 * (Points[1].X - Points[2].X) - Points[0].X;
  const Cy: Double = Points[3].Y + 3.0 * (Points[1].Y - Points[2].Y) - Points[0].Y;

  Result := TTsQuad64.RootsValidT(Bx * Cy - By * Cx, Ax * Cy - Ay * Cx, Ax * By - Ay * Bx, TValues);
end;

function TTsCubic64.BinarySearch(const Min, Max, AxisIntercept: Double; const XAxis: TTsSearchAxis): Double;
begin
  var T: Double := (Min + Max) / 2.0;
  var Step: Double := (T - Min) / 2.0;
  var CubicAtT := PointAtT(T);
  var CalcPos := CubicAtT.AxisCoord(XAxis);
  var CalcDist: Double := CalcPos - AxisIntercept;

  for var Steps := 1 to MaxBinarySearchSteps do
  begin
    const PriorT = MaxIgnoringNan(Min, T - Step);

    const LessPt = PointAtT(PriorT);
    if TTsScalar64.ApproximatelyEqualHalf(LessPt.X, CubicAtT.X) and TTsScalar64.ApproximatelyEqualHalf(LessPt.Y, CubicAtT.Y) then
    begin
      // binary search found no point at this axis intercept
      Exit(-1.0);
    end;

    const LessDist: Double = LessPt.AxisCoord(XAxis) - AxisIntercept;
    const LastStep = Step;
    Step := Step / 2.0;

    var Ok: Boolean;
    if CalcDist > 0.0 then
    begin
      Ok := (CalcDist > LessDist);
    end
    else
    begin
      Ok := (CalcDist < LessDist);
    end;

    if Ok then
    begin
      T := PriorT;
    end
    else
    begin
      const NextT = T + LastStep;
      if NextT > Max then
      begin
        Exit(-1.0);
      end;

      const MorePt = PointAtT(NextT);
      if TTsScalar64.ApproximatelyEqualHalf(MorePt.X, CubicAtT.X) and TTsScalar64.ApproximatelyEqualHalf(MorePt.Y, CubicAtT.Y) then
      begin
        // binary search found no point at this axis intercept
        Exit(-1.0);
      end;

      const MoreDist: Double = MorePt.AxisCoord(XAxis) - AxisIntercept;
      if CalcDist > 0.0 then
      begin
        Ok := (CalcDist <= MoreDist);
      end
      else
      begin
        Ok := (CalcDist >= MoreDist);
      end;

      if Ok then
      begin
        Continue;
      end;

      T := NextT;
    end;

    CubicAtT := PointAtT(T);
    CalcPos := CubicAtT.AxisCoord(XAxis);
    CalcDist := CalcPos - AxisIntercept;

    if TTsScalar64.ApproximatelyEqual(CalcPos, AxisIntercept) then
    begin
      Exit(T);
    end;
  end;

  // Rust never gets here; NaN points keep the loop going for ever
  Result := -1.0;
end;

function TTsCubic64.ChopAt(const T: Double): TTsCubic64Pair;
begin
  if T = 0.5 then
  begin
    Result.Points[0] := Points[0];
    Result.Points[1].X := (Points[0].X + Points[1].X) / 2.0;
    Result.Points[1].Y := (Points[0].Y + Points[1].Y) / 2.0;
    Result.Points[2].X := (Points[0].X + 2.0 * Points[1].X + Points[2].X) / 4.0;
    Result.Points[2].Y := (Points[0].Y + 2.0 * Points[1].Y + Points[2].Y) / 4.0;
    Result.Points[3].X := (Points[0].X + 3.0 * (Points[1].X + Points[2].X) + Points[3].X) / 8.0;
    Result.Points[3].Y := (Points[0].Y + 3.0 * (Points[1].Y + Points[2].Y) + Points[3].Y) / 8.0;
    Result.Points[4].X := (Points[1].X + 2.0 * Points[2].X + Points[3].X) / 4.0;
    Result.Points[4].Y := (Points[1].Y + 2.0 * Points[2].Y + Points[3].Y) / 4.0;
    Result.Points[5].X := (Points[2].X + Points[3].X) / 2.0;
    Result.Points[5].Y := (Points[2].Y + Points[3].Y) / 2.0;
    Result.Points[6] := Points[3];

    Exit;
  end;

  // classic one t subdivision, per coordinate
  const AbX = TTsPath64.Interp(Points[0].X, Points[1].X, T);
  const BcX = TTsPath64.Interp(Points[1].X, Points[2].X, T);
  const CdX = TTsPath64.Interp(Points[2].X, Points[3].X, T);
  const AbcX = TTsPath64.Interp(AbX, BcX, T);
  const BcdX = TTsPath64.Interp(BcX, CdX, T);
  const AbcdX = TTsPath64.Interp(AbcX, BcdX, T);

  Result.Points[0].X := Points[0].X;
  Result.Points[1].X := AbX;
  Result.Points[2].X := AbcX;
  Result.Points[3].X := AbcdX;
  Result.Points[4].X := BcdX;
  Result.Points[5].X := CdX;
  Result.Points[6].X := Points[3].X;

  const AbY = TTsPath64.Interp(Points[0].Y, Points[1].Y, T);
  const BcY = TTsPath64.Interp(Points[1].Y, Points[2].Y, T);
  const CdY = TTsPath64.Interp(Points[2].Y, Points[3].Y, T);
  const AbcY = TTsPath64.Interp(AbY, BcY, T);
  const BcdY = TTsPath64.Interp(BcY, CdY, T);
  const AbcdY = TTsPath64.Interp(AbcY, BcdY, T);

  Result.Points[0].Y := Points[0].Y;
  Result.Points[1].Y := AbY;
  Result.Points[2].Y := AbcY;
  Result.Points[3].Y := AbcdY;
  Result.Points[4].Y := BcdY;
  Result.Points[5].Y := CdY;
  Result.Points[6].Y := Points[3].Y;
end;

class procedure TTsCubic64.Coefficients(const Src: TTsDoubles8; const Offset: Integer; out A, B, C, D: Double);
begin
  A := Src[Offset + 6]; // d
  B := Src[Offset + 4] * 3.0; // 3*c
  C := Src[Offset + 2] * 3.0; // 3*b
  D := Src[Offset]; // a

  A := A - (D - C + B); // A =   -a + 3*b - 3*c + d
  B := B + (3.0 * D - 2.0 * C); // B =  3*a - 6*b + 3*c
  C := C - 3.0 * D; // C = -3*a + 3*b
end;

class function TTsCubic64.RootsValidT(const A, B, C, D: Double; var T: TTsDoubles3): Integer;
begin
  var S: TTsDoubles3;
  S[0] := 0.0;
  S[1] := 0.0;
  S[2] := 0.0;

  const RealRoots = RootsReal(A, B, C, D, S);
  var FoundRoots := TTsQuad64.PushValidTs(S, RealRoots, T);

  for var Index := 0 to RealRoots - 1 do
  begin
    const TValue = S[Index];

    var Snapped: Double;
    if (not TTsScalar64.ApproximatelyOneOrLess(TValue)) and TTsScalar64.Between(TValue, 1.0, 1.00005) then
    begin
      Snapped := 1.0;
    end
    else if (not TTsScalar64.ApproximatelyZeroOrMore(TValue)) and TTsScalar64.Between(TValue, -0.00005, 0.0) then
    begin
      Snapped := 0.0;
    end
    else
    begin
      Continue;
    end;

    var IsDuplicate := False;
    for var Other := 0 to FoundRoots - 1 do
    begin
      if TTsScalar64.ApproximatelyEqual(T[Other], Snapped) then
      begin
        IsDuplicate := True;
        Break;
      end;
    end;

    // Rust asserts that there is room (and would index outside the array otherwise)
    if (not IsDuplicate) and (FoundRoots <= High(T)) then
    begin
      T[FoundRoots] := Snapped;
      Inc(FoundRoots);
    end;
  end;

  Result := FoundRoots;
end;

class function TTsCubic64.RootsReal(const A, B, C, D: Double; var S: TTsDoubles3): Integer;
begin
  if TTsScalar64.ApproximatelyZero(A) and TTsScalar64.ApproximatelyZeroWhenComparedTo(A, B) and
     TTsScalar64.ApproximatelyZeroWhenComparedTo(A, C) and TTsScalar64.ApproximatelyZeroWhenComparedTo(A, D) then
  begin
    // we're just a quadratic
    Exit(TTsQuad64.RootsReal(B, C, D, S));
  end;

  if TTsScalar64.ApproximatelyZeroWhenComparedTo(D, A) and TTsScalar64.ApproximatelyZeroWhenComparedTo(D, B) and
     TTsScalar64.ApproximatelyZeroWhenComparedTo(D, C) then
  begin
    // 0 is one root
    var Num := TTsQuad64.RootsReal(A, B, C, S);
    for var Index := 0 to Num - 1 do
    begin
      if TTsScalar64.ApproximatelyZero(S[Index]) then
      begin
        Exit(Num);
      end;
    end;

    S[Num] := 0.0;
    Inc(Num);

    Exit(Num);
  end;

  if TTsScalar64.ApproximatelyZero(A + B + C + D) then
  begin
    // 1 is one root
    var Num := TTsQuad64.RootsReal(A, A + B, -D, S);
    for var Index := 0 to Num - 1 do
    begin
      if TTsScalar64.AlmostDequalUlps(S[Index], 1.0) then
      begin
        Exit(Num);
      end;
    end;

    S[Num] := 1.0;
    Inc(Num);

    Exit(Num);
  end;

  const InvA: Double = 1.0 / A;
  const NormA: Double = B * InvA;
  const NormB: Double = C * InvA;
  const NormC: Double = D * InvA;

  const A2: Double = NormA * NormA;
  const Q: Double = (A2 - NormB * 3.0) / 9.0;
  const R: Double = (2.0 * A2 * NormA - 9.0 * NormA * NormB + 27.0 * NormC) / 54.0;
  const R2: Double = R * R;
  const Q3: Double = Q * Q * Q;
  const R2MinusQ3: Double = R2 - Q3;
  const ADiv3: Double = NormA / 3.0;

  var Offset := 0;
  if R2MinusQ3 < 0.0 then
  begin
    // we have 3 real roots

    // the divide/root can, due to finite precisions, be slightly outside of -1...1
    const Theta: Double = ArcCos(TTsScalar64.Bound(R / System.Sqrt(Q3), -1.0, 1.0));
    const Neg2RootQ: Double = -2.0 * System.Sqrt(Q);

    var Root: Double := Neg2RootQ * System.Cos(Theta / 3.0) - ADiv3;
    S[Offset] := Root;
    Inc(Offset);

    Root := Neg2RootQ * System.Cos((Theta + 2.0 * Pi64) / 3.0) - ADiv3;
    if not TTsScalar64.AlmostDequalUlps(S[0], Root) then
    begin
      S[Offset] := Root;
      Inc(Offset);
    end;

    Root := Neg2RootQ * System.Cos((Theta - 2.0 * Pi64) / 3.0) - ADiv3;
    if (not TTsScalar64.AlmostDequalUlps(S[0], Root)) and ((Offset = 1) or (not TTsScalar64.AlmostDequalUlps(S[1], Root))) then
    begin
      S[Offset] := Root;
      Inc(Offset);
    end;
  end
  else
  begin
    // we have 1 real root
    const SqrtR2MinusQ3: Double = System.Sqrt(R2MinusQ3);

    var Root: Double := Abs(R) + SqrtR2MinusQ3;
    Root := TTsPath64.CubeRoot(Root);
    if R > 0.0 then
    begin
      Root := -Root;
    end;

    if Root <> 0.0 then
    begin
      Root := Root + Q / Root;
    end;

    var Second: Double := Root - ADiv3;
    S[Offset] := Second;
    Inc(Offset);

    if TTsScalar64.AlmostDequalUlps(Second, Q3) then
    begin
      Second := -Root / 2.0 - ADiv3;
      if not TTsScalar64.AlmostDequalUlps(S[0], Second) then
      begin
        S[Offset] := Second;
        Inc(Offset);
      end;
    end;
  end;

  Result := Offset;
end;

class function TTsCubic64.FindExtrema(const Src: TTsDoubles8; const Offset: Integer; var TValues: array of Double): Integer;
begin
  // we divide A,B,C by 3 to simplify
  const A = Src[Offset];
  const B = Src[Offset + 2];
  const C = Src[Offset + 4];
  const D = Src[Offset + 6];
  const A2: Double = D - A + 3.0 * (B - C);
  const B2: Double = 2.0 * (A - B - B + C);
  const C2: Double = B - A;

  Result := TTsQuad64.RootsValidT(A2, B2, C2, TValues);
end;

class procedure TTsCubic64.SortF64(var Values: TTsDoubles6; const Count: Integer);
begin
  // A stable insertion sort of the first Count values; the comparison is the one of cmp_f64, where NaN is equal to everything
  for var Index := 1 to Count - 1 do
  begin
    const Current = Values[Index];

    var Position := Index;
    while (Position > 0) and (Values[Position - 1] > Current) do
    begin
      Values[Position] := Values[Position - 1];
      Dec(Position);
    end;

    Values[Position] := Current;
  end;
end;

{ TTsLineCubicIntersections }

class function TTsLineCubicIntersections.HorizontalIntersect(const Cubic: TTsCubic64; const AxisIntercept: Double;
                                                             var Roots: TTsDoubles3): Integer;
begin
  const Slice = Cubic.AsF64Slice;

  var A, B, C, D: Double;
  TTsCubic64.Coefficients(Slice, 1, A, B, C, D);
  D := D - AxisIntercept;

  var Count := TTsCubic64.RootsValidT(A, B, C, D, Roots);
  var Index := 0;
  while Index < Count do
  begin
    const CalcPt = Cubic.PointAtT(Roots[Index]);
    if not TTsScalar64.ApproximatelyEqual(CalcPt.Y, AxisIntercept) then
    begin
      var ExtremeTs: TTsDoubles6;
      FillChar(ExtremeTs, SizeOf(ExtremeTs), 0);

      const Extrema = TTsCubic64.FindExtrema(Slice, 1, ExtremeTs);
      Count := Cubic.SearchRoots(Extrema, AxisIntercept, TTsSearchAxis.Y, ExtremeTs, Roots);

      Break;
    end;

    Inc(Index);
  end;

  Result := Count;
end;

class function TTsLineCubicIntersections.VerticalIntersect(const Cubic: TTsCubic64; const AxisIntercept: Double;
                                                           var Roots: TTsDoubles3): Integer;
begin
  const Slice = Cubic.AsF64Slice;

  var A, B, C, D: Double;
  TTsCubic64.Coefficients(Slice, 0, A, B, C, D);
  D := D - AxisIntercept;

  var Count := TTsCubic64.RootsValidT(A, B, C, D, Roots);
  var Index := 0;
  while Index < Count do
  begin
    const CalcPt = Cubic.PointAtT(Roots[Index]);
    if not TTsScalar64.ApproximatelyEqual(CalcPt.X, AxisIntercept) then
    begin
      var ExtremeTs: TTsDoubles6;
      FillChar(ExtremeTs, SizeOf(ExtremeTs), 0);

      const Extrema = TTsCubic64.FindExtrema(Slice, 0, ExtremeTs);
      Count := Cubic.SearchRoots(Extrema, AxisIntercept, TTsSearchAxis.X, ExtremeTs, Roots);

      Break;
    end;

    Inc(Index);
  end;

  Result := Count;
end;

end.
