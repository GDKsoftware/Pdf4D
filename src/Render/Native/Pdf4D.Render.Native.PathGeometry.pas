// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/path_geometry.rs
// Port of: tiny-skia v0.12.0 src/path_geometry.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.PathGeometry;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path64;

// A collection of functions to work with Bezier paths: the path_geometry module of tiny-skia-path and the one of tiny-skia.
//
// The Rust slices of fixed size are fixed arrays (TTsPoints3 and so on). Where Rust returns a slice of a t-value array, the function
// returns the count and the caller reads the first Count values. Where Rust passes a sub-slice of a destination (&mut dst[offset..]) the
// function takes an offset. The destinations are var parameters because they are updated in place.
//
// chop_mono_cubic_at_x and chop_mono_cubic_at_y use the f64 code of path64 and return False where Rust returns false.
//
// The Rust PathDirection lives in path_builder.rs; it is declared here because the builder uses this unit and not the other way round.
//
// The cube root, the cosine and the arc cosine are computed in Double and rounded to Single; Rust calls powf, cosf and acosf of libm. The
// results can differ from them in the last bit.

type
  TTsPoints3 = array[0..2] of TTsPoint;
  TTsPoints4 = array[0..3] of TTsPoint;
  TTsPoints5 = array[0..4] of TTsPoint;
  TTsPoints7 = array[0..6] of TTsPoint;
  TTsPoints10 = array[0..9] of TTsPoint;
  TTsPoints64 = array[0..63] of TTsPoint;

  TTsTValues = array[0..2] of TTsNormalizedF32Exclusive;
  TTsNormalizedValues = array[0..2] of TTsNormalizedF32;

  TTsPathDirection = (
    // Clockwise direction for adding closed contours
    CW,
    // Counter-clockwise direction for adding closed contours
    CCW);

  // use for : eval(t) == A * t^2 + B * t + C
  TTsQuadCoeff = record
  public
    A: TF32x2;
    B: TF32x2;
    C: TF32x2;

    class function FromPoints(const Points: TTsPoints3): TTsQuadCoeff; static;

    function Eval(const T: TF32x2): TF32x2;
  end;

  TTsCubicCoeff = record
  public
    A: TF32x2;
    B: TF32x2;
    C: TF32x2;
    D: TF32x2;

    class function FromPoints(const Points: TTsPoints4): TTsCubicCoeff; static;

    function Eval(const T: TF32x2): TF32x2;
  end;

  TTsConic = record
  private
    class function Between(const A, B, C: Single): Boolean; static;
    class function SubdivideWeightValue(const W: Single): Single; static;
    class function Subdivide(const Src: TTsConic; var Points: TTsPoints64; const PointsOffset, Level: Integer): Integer; static;

    function TryComputeQuadPow2(const Tolerance: Single; out Pow2: Byte): Boolean;

    procedure Chop(out First, Second: TTsConic);

  public
    Points: TTsPoints3;
    Weight: Single;

    class function Create(const Pt0, Pt1, Pt2: TTsPoint; const Weight: Single): TTsConic; static;
    class function FromPoints(const Points: array of TTsPoint; const Weight: Single): TTsConic; static;

    // The unit arc of at most four conics; the count is zero when there is no arc
    class function TryBuildUnitArc(const UStart, UStop: TTsPoint; const Dir: TTsPathDirection; const UserTransform: TTsTransform;
                                   var Dst: array of TTsConic; out ConicCount: Integer): Boolean; static;

    // Chop this conic into N quads, stored continuously in Points, where N = 1 << Pow2. The amount of storage needed is (1 + 2 * N).
    function ChopIntoQuadsPow2(const Pow2: Byte; var QuadPoints: TTsPoints64): Byte;
  end;

  TTsAutoConicToQuads = record
  public
    Points: TTsPoints64;
    // The number of quads
    Len: Byte;

    class function TryCompute(const Pt0, Pt1, Pt2: TTsPoint; const Weight: Single; out Quads: TTsAutoConicToQuads): Boolean; static;
  end;

  TTsPathGeometry = record
  private
    class function Interp(const V0, V1, T: TF32x2): TF32x2; static;
    class function Times2(const Value: TF32x2): TF32x2; static;
    class function FormulateF1DotF2(const Src: array of Single): TArray<Single>; static;
    class function SolveCubicPoly(const Coeff: array of Single; var TValues: TTsNormalizedValues): Integer; static;
    class procedure SortArray3(var Values: TTsNormalizedValues); static;
    class function CollapseDuplicates3(const Values: TTsNormalizedValues): Integer; static;
    class function ScalarCubeRoot(const X: Single): Single; static;
    class function EvalCubicDerivative(const Src: TTsPoints4; const T: TTsNormalizedF32): TTsPoint; static;
    class function OnSameSide(const Src: TTsPoints4; const TestIndex, LineIndex: Integer): Boolean; static;
    class function CalcCubicPrecision(const Src: TTsPoints4): Single; static;
    class function IsNotMonotonic(const A, B, C: Single): Boolean; static;

  public
    class function NewTValues: TTsTValues; static;
    class procedure ChopQuadAt(const Src: TTsPoints3; const T: TTsNormalizedF32Exclusive; var Dst: TTsPoints5); static;

    // From Numerical Recipes in C.
    //
    // Q = -1/2 (B + sign(B) sqrt[B*B - 4*A*C])
    // x1 = Q / A
    // x2 = C / Q
    class function FindUnitQuadRoots(const A, B, C: Single; var Roots: TTsTValues): Integer; static;

    // Dst gets 7 points, starting at DstOffset
    class procedure ChopCubicAt2(const Src: TTsPoints4; const T: TTsNormalizedF32Exclusive; var Dst: array of TTsPoint;
                                 const DstOffset: Integer = 0); static;

    // Quad'(t) = At + B, where
    // A = 2(a - 2b + c)
    // B = 2(b - a)
    // Solve for t, only if it fits between 0 < t < 1
    class function TryFindQuadExtrema(const A, B, C: Single; out T: TTsNormalizedF32Exclusive): Boolean; static;
    class function TryValidUnitDivide(const Numer, Denom: Single; out Quotient: TTsNormalizedF32Exclusive): Boolean; static;

    // F(t)    = a (1 - t) ^ 2 + 2 b t (1 - t) + c t ^ 2
    // F'(t)   = 2 (b - a) + 2 (a - 2b + c) t
    // F''(t)  = 2 (a - 2b + c)
    //
    // A = 2 (b - a)
    // B = 2 (a - 2b + c)
    //
    // Maximum curvature for a quadratic means solving
    // Fx' Fx'' + Fy' Fy'' = 0
    //
    // t = - (Ax Bx + Ay By) / (Bx ^ 2 + By ^ 2)
    // False where the Rust code panics: control points so large that the quotient is NaN
    class function TryFindQuadMaxCurvature(const Src: TTsPoints3; out T: TTsNormalizedF32): Boolean; static;
    class function EvalQuadAt(const Src: TTsPoints3; const T: TTsNormalizedF32): TTsPoint; static;
    class function EvalQuadTangentAt(const Src: TTsPoints3; const Tol: TTsNormalizedF32): TTsPoint; static;

    // Looking for F' dot F'' == 0. The roots are the first Count values of TValues.
    //
    // A = b - a
    // B = c - 2b + a
    // C = d - 3c + 3b - a
    //
    // F' = 3Ct^2 + 6Bt + 3A
    // F'' = 6Ct + 6B
    //
    // F' dot F'' -> CCt^3 + 3BCt^2 + (2BB + CA)t + AB
    class function FindCubicMaxCurvature(const Src: TTsPoints4; var TValues: TTsNormalizedValues): Integer; static;

    // This is SkEvalCubicAt split into three functions.
    class function EvalCubicPosAt(const Src: TTsPoints4; const T: TTsNormalizedF32): TTsPoint; static;
    class function EvalCubicTangentAt(const Src: TTsPoints4; const T: TTsNormalizedF32): TTsPoint; static;

    // Cubic'(t) = At^2 + Bt + C, where
    // A = 3(-a + 3(b - c) + d)
    // B = 6(a - 2b + c)
    // C = 3(b - a)
    // Solve for t, keeping only those that fit between 0 < t < 1. The roots are the first Count values of TValues.
    class function FindCubicExtrema(const A, B, C, D: Single; var TValues: TTsTValues): Integer; static;

    // http://www.faculty.idc.ac.il/arik/quality/appendixA.html
    //
    // Inflection means that curvature is zero.
    // Curvature is [F' x F''] / [F'^3]
    // So we solve F'x X F''y - F'y X F''y == 0
    // After some canceling of the cubic term, we get
    // A = b - a
    // B = c - 2b + a
    // C = d - 3c + 3b - a
    // (BxCy - ByCx)t^2 + (AxCy - AyCx)t + AxBy - AyBx == 0
    class function FindCubicInflections(const Src: TTsPoints4; var TValues: TTsTValues): Integer; static;

    // Return location (in t) of cubic cusp, if there is one.
    // Note that classify cubic code does not reliably return all cusp'd cubics, so it is not called here.
    class function TryFindCubicCusp(const Src: TTsPoints4; out T: TTsNormalizedF32Exclusive): Boolean; static;

    // Returns 0 for 1 quad, and 1 for two quads, either way the answer is stored in Dst. Guarantees that the 1/2 quads will be monotonic.
    class function ChopQuadAtXExtrema(const Src: TTsPoints3; var Dst: TTsPoints5): Integer; static;
    class function ChopQuadAtYExtrema(const Src: TTsPoints3; var Dst: TTsPoints5): Integer; static;
    class function ChopCubicAtXExtrema(const Src: TTsPoints4; var Dst: TTsPoints10): Integer; static;

    // Given 4 points on a cubic bezier, chop it into 1, 2, 3 beziers such that the resulting beziers are monotonic in Y. This is called
    // by the scan converter.
    //
    // Depending on what is returned, Dst is treated as follows:
    //
    // - 0: Dst[0..3] is the original cubic
    // - 1: Dst[0..3] and Dst[3..6] are the two new cubics
    // - 2: Dst[0..3], Dst[3..6], Dst[6..9] are the three new cubics
    class function ChopCubicAtYExtrema(const Src: TTsPoints4; var Dst: TTsPoints10): Integer; static;

    // http://code.google.com/p/skia/issues/detail?id=32
    //
    // This test code would fail when we didn't check the return result of valid_unit_divide in SkChopCubicAt(... NormalizedF32Exclusives[],
    // int roots). The reason is that after the first chop, the parameters to valid_unit_divide are equal (thanks to finite float precision
    // and rounding in the subtracts). Thus even though the 2nd NormalizedF32Exclusive looks < 1.0, after we renormalize it, we end up with
    // 1.0, hence the need to check and just return the last cubic as a degenerate clump of 4 points in the same place.
    class procedure ChopCubicAt(const Src: TTsPoints4; const TValues: array of TTsNormalizedF32Exclusive; var Dst: array of TTsPoint); static;
    class function ChopCubicAtMaxCurvature(const Src: TTsPoints4; var TValues: TTsTValues; var Dst: array of TTsPoint): Integer; static;

    // Chops a cubic that is monotonic in X (or Y) at the X (or Y) where it crosses the line. Returns False when the f64 search finds no
    // crossing; Dst gets 7 points otherwise.
    class function ChopMonoCubicAtX(const Src: TTsPoints4; const X: Single; var Dst: TTsPoints7): Boolean; static;
    class function ChopMonoCubicAtY(const Src: TTsPoints4; const Y: Single; var Dst: TTsPoints7): Boolean; static;

  private
    class function CubicDchopAtIntercept(const Src: TTsPoints4; const Intercept: Single; const IsVertical: Boolean;
                                         var Dst: TTsPoints7): Boolean; static;
  end;

implementation

const
  // Delphi evaluates a Single expression with a real literal in Double, without rounding the intermediate results to Single as Rust does
  // for f32. The literals of the f32 arithmetic below are therefore typed Single constants, which keep every step a Single operation.
  NegOne: Single = -1.0;
  One: Single = 1.0;
  Two: Single = 2.0;
  NegTwo: Single = -2.0;
  Three: Single = 3.0;
  Four: Single = 4.0;
  Nine: Single = 9.0;
  TwentySeven: Single = 27.0;
  FiftyFour: Single = 54.0;
  OneHalf: Single = 0.5;
  // The 1e-8 of calc_cubic_precision, as an f32
  PrecisionFactor: Single = 1e-8;
  // The 0.3333333 of the cube root, as an f32
  OneThird: Single = 0.3333333;
  MaxConicToQuadPow2 = 4;

{ TTsQuadCoeff }

class function TTsQuadCoeff.FromPoints(const Points: TTsPoints3): TTsQuadCoeff;
begin
  const C = Points[0].ToF32x2;
  const P1 = Points[1].ToF32x2;
  const P2 = Points[2].ToF32x2;
  const Delta = P1 - C;

  Result.C := C;
  Result.B := Delta + Delta;
  Result.A := P2 - (P1 + P1) + C;
end;

function TTsQuadCoeff.Eval(const T: TF32x2): TF32x2;
begin
  Result := (A * T + B) * T + C;
end;

{ TTsCubicCoeff }

class function TTsCubicCoeff.FromPoints(const Points: TTsPoints4): TTsCubicCoeff;
begin
  const P0 = Points[0].ToF32x2;
  const P1 = Points[1].ToF32x2;
  const P2 = Points[2].ToF32x2;
  const P3 = Points[3].ToF32x2;
  const Three = TF32x2.Splat(3.0);

  Result.A := P3 + Three * (P1 - P2) - P0;
  Result.B := Three * (P2 - (P1 + P1) + P0);
  Result.C := Three * (P1 - P0);
  Result.D := P0;
end;

function TTsCubicCoeff.Eval(const T: TF32x2): TF32x2;
begin
  Result := ((A * T + B) * T + C) * T + D;
end;

{ TTsConic }

class function TTsConic.Create(const Pt0, Pt1, Pt2: TTsPoint; const Weight: Single): TTsConic;
begin
  Result.Points[0] := Pt0;
  Result.Points[1] := Pt1;
  Result.Points[2] := Pt2;
  Result.Weight := Weight;
end;

class function TTsConic.FromPoints(const Points: array of TTsPoint; const Weight: Single): TTsConic;
begin
  Result := Create(Points[0], Points[1], Points[2], Weight);
end;

function TTsConic.TryComputeQuadPow2(const Tolerance: Single; out Pow2: Byte): Boolean;
begin
  Pow2 := 0;

  if IsNan(Tolerance) or (Tolerance < 0) or not TTsScalar.IsFinite(Tolerance) then
  begin
    Exit(False);
  end;

  if not Points[0].IsFinite or not Points[1].IsFinite or not Points[2].IsFinite then
  begin
    Exit(False);
  end;

  // "High order approximation of conic sections by quadratic splines" by Michael Floater, 1993
  const WeightMinusOne: Single = Weight - One;
  const K: Single = WeightMinusOne / (Four * (Two + WeightMinusOne));
  const X: Single = K * (Points[0].X - Two * Points[1].X + Points[2].X);
  const Y: Single = K * (Points[0].Y - Two * Points[1].Y + Points[2].Y);

  var Error: Single := Single(System.Sqrt(Double(X * X + Y * Y)));
  var Count := 0;
  for var Step := 1 to MaxConicToQuadPow2 do
  begin
    if TTsLane.IsLe(Error, Tolerance) then
    begin
      Break;
    end;

    Error := Error * 0.25;
    Inc(Count);
  end;

  // Unlike Skia, we always expect `pow2` to be at least 1. Otherwise it produces ugly results.
  Pow2 := Byte(System.Math.Max(Count, 1));
  Result := True;
end;

function TTsConic.ChopIntoQuadsPow2(const Pow2: Byte; var QuadPoints: TTsPoints64): Byte;
begin
  QuadPoints[0] := Points[0];
  Subdivide(Self, QuadPoints, 1, Pow2);

  const QuadCount = 1 shl Pow2;
  const PointCount = 2 * QuadCount + 1;

  var AllFinite := True;
  for var Index := 0 to PointCount - 1 do
  begin
    if not QuadPoints[Index].IsFinite then
    begin
      AllFinite := False;
      Break;
    end;
  end;

  if not AllFinite then
  begin
    // if we generated a non-finite, pin ourselves to the middle of the hull, as our first and last are already on the first/last pts of
    // the hull.
    for var Index := 1 to PointCount - 2 do
    begin
      QuadPoints[Index] := Points[1];
    end;
  end;

  Result := Byte(QuadCount);
end;

procedure TTsConic.Chop(out First, Second: TTsConic);
begin
  const Scale = TF32x2.Splat(TTsScalar.Invert(1.0 + Weight));
  const NewWeight: Single = SubdivideWeightValue(Weight);

  const P0 = Points[0].ToF32x2;
  const P1 = Points[1].ToF32x2;
  const P2 = Points[2].ToF32x2;
  const WW = TF32x2.Splat(Weight);

  const WP1 = WW * P1;
  const M = (P0 + (WP1 + WP1) + P2) * Scale * TF32x2.Splat(0.5);
  var MPt := TTsPoint.FromF32x2(M);
  if not MPt.IsFinite then
  begin
    const WD: Double = Weight;
    const W2: Double = WD * 2.0;
    const ScaleHalf: Double = 1.0 / (1.0 + WD) * 0.5;
    MPt.X := Single((Double(Points[0].X) + W2 * Double(Points[1].X) + Double(Points[2].X)) * ScaleHalf);
    MPt.Y := Single((Double(Points[0].Y) + W2 * Double(Points[1].Y) + Double(Points[2].Y)) * ScaleHalf);
  end;

  First.Points[0] := Points[0];
  First.Points[1] := TTsPoint.FromF32x2((P0 + WP1) * Scale);
  First.Points[2] := MPt;
  First.Weight := NewWeight;

  Second.Points[0] := MPt;
  Second.Points[1] := TTsPoint.FromF32x2((WP1 + P2) * Scale);
  Second.Points[2] := Points[2];
  Second.Weight := NewWeight;
end;

class function TTsConic.TryBuildUnitArc(const UStart, UStop: TTsPoint; const Dir: TTsPathDirection; const UserTransform: TTsTransform;
                                        var Dst: array of TTsConic; out ConicCount: Integer): Boolean;
begin
  ConicCount := 0;

  // rotate by x,y so that u_start is (1.0)
  const X: Single = UStart.Dot(UStop);
  var Y: Single := UStart.Cross(UStop);

  const AbsY: Single = Abs(Y);

  // check for (effectively) coincident vectors this can happen if our angle is nearly 0 or nearly 180 (y == 0)
  // ... we use the dot-prod to distinguish between 0 and 180 (x > 0)
  if (AbsY <= TTsScalar.ScalarNearlyZero) and (X > 0) and (((Y >= 0) and (Dir = TTsPathDirection.CW)) or ((Y <= 0) and (Dir = TTsPathDirection.CCW))) then
  begin
    Exit(False);
  end;

  if Dir = TTsPathDirection.CCW then
  begin
    Y := -Y;
  end;

  // We decide to use 1-conic per quadrant of a circle. What quadrant does [xy] lie in?
  //      0 == [0  .. 90)
  //      1 == [90 ..180)
  //      2 == [180..270)
  //      3 == [270..360)
  var Quadrant := 0;
  if Y = 0 then
  begin
    Quadrant := 2; // 180
  end
  else if X = 0 then
  begin
    if Y > 0 then
    begin
      Quadrant := 1; // 90
    end
    else
    begin
      Quadrant := 3; // 270
    end;
  end
  else
  begin
    if Y < 0 then
    begin
      Inc(Quadrant, 2);
    end;

    if (X < 0) <> (Y < 0) then
    begin
      Inc(Quadrant);
    end;
  end;

  const QuadrantWeight: Single = TTsScalar.ScalarRoot2Over2;
  const QuadrantPoints: TArray<TTsPoint> = [
    TTsPoint.FromXY(1.0, 0.0),
    TTsPoint.FromXY(1.0, 1.0),
    TTsPoint.FromXY(0.0, 1.0),
    TTsPoint.FromXY(-1.0, 1.0),
    TTsPoint.FromXY(-1.0, 0.0),
    TTsPoint.FromXY(-1.0, -1.0),
    TTsPoint.FromXY(0.0, -1.0),
    TTsPoint.FromXY(1.0, -1.0)];

  var Count := Quadrant;
  for var Index := 0 to Count - 1 do
  begin
    Dst[Index] := FromPoints([QuadrantPoints[Index * 2], QuadrantPoints[Index * 2 + 1], QuadrantPoints[Index * 2 + 2]], QuadrantWeight);
  end;

  // Now compute any remaining (sub-90-degree) arc for the last conic
  const FinalPt = TTsPoint.FromXY(X, Y);
  const LastQ = QuadrantPoints[Quadrant * 2];  // will already be a unit-vector
  const Dot: Single = LastQ.Dot(FinalPt);

  if Dot < 1.0 then
  begin
    var OffCurve := TTsPoint.FromXY(LastQ.X + X, LastQ.Y + Y);

    // compute the bisector vector, and then rescale to be the off-curve point. we compute its length from cos(theta/2) = length / 1, using
    // half-angle identity we get length = sqrt(2 / (1 + cos(theta)). We already have cos() when to computed the dot. This is nice, since our
    // computed weight is cos(theta/2) as well!
    const CosThetaOver2: Single = Single(System.Sqrt(Double((One + Dot) / Two)));
    OffCurve.SetLength(TTsScalar.Invert(CosThetaOver2));
    if not LastQ.AlmostEqual(OffCurve) then
    begin
      Dst[Count] := Create(LastQ, OffCurve, FinalPt, CosThetaOver2);
      Inc(Count);
    end;
  end;

  // now handle counter-clockwise and the initial unitStart rotation
  var Ts := TTsTransform.FromSinCos(UStart.Y, UStart.X);
  if Dir = TTsPathDirection.CCW then
  begin
    Ts := Ts.PreScale(1.0, -1.0);
  end;

  Ts := Ts.PostConcat(UserTransform);

  for var Index := 0 to Count - 1 do
  begin
    Ts.MapPoints(Dst[Index].Points);
  end;

  ConicCount := Count;
  Result := (Count <> 0);
end;

class function TTsConic.SubdivideWeightValue(const W: Single): Single;
begin
  Result := Single(System.Sqrt(Double(OneHalf + W * OneHalf)));
end;

class function TTsConic.Subdivide(const Src: TTsConic; var Points: TTsPoints64; const PointsOffset, Level: Integer): Integer;
begin
  if Level = 0 then
  begin
    Points[PointsOffset] := Src.Points[1];
    Points[PointsOffset + 1] := Src.Points[2];
    Exit(PointsOffset + 2);
  end;

  var First, Second: TTsConic;
  Src.Chop(First, Second);

  const StartY: Single = Src.Points[0].Y;
  const EndY: Single = Src.Points[2].Y;
  if Between(StartY, Src.Points[1].Y, EndY) then
  begin
    // If the input is monotonic and the output is not, the scan converter hangs. Ensure that the chopped conics maintain their y-order.
    const MidY: Single = First.Points[2].Y;
    if not Between(StartY, MidY, EndY) then
    begin
      // If the computed midpoint is outside the ends, move it to the closer one.
      var CloserY: Single := EndY;
      if Abs(MidY - StartY) < Abs(MidY - EndY) then
      begin
        CloserY := StartY;
      end;

      First.Points[2].Y := CloserY;
      Second.Points[0].Y := CloserY;
    end;

    if not Between(StartY, First.Points[1].Y, First.Points[2].Y) then
    begin
      // If the 1st control is not between the start and end, put it at the start. This also reduces the quad to a line.
      First.Points[1].Y := StartY;
    end;

    if not Between(Second.Points[0].Y, Second.Points[1].Y, EndY) then
    begin
      // If the 2nd control is not between the start and end, put it at the end. This also reduces the quad to a line.
      Second.Points[1].Y := EndY;
    end;
  end;

  const NextLevel = Level - 1;
  const NextOffset = Subdivide(First, Points, PointsOffset, NextLevel);
  Result := Subdivide(Second, Points, NextOffset, NextLevel);
end;

// This was originally developed and tested for pathops: see SkOpTypes.h
// returns true if (a <= b <= c) || (a >= b >= c)
class function TTsConic.Between(const A, B, C: Single): Boolean;
begin
  Result := TTsLane.IsLe((A - B) * (C - B), 0.0);
end;

{ TTsAutoConicToQuads }

class function TTsAutoConicToQuads.TryCompute(const Pt0, Pt1, Pt2: TTsPoint; const Weight: Single; out Quads: TTsAutoConicToQuads): Boolean;
begin
  Quads := Default(TTsAutoConicToQuads);

  var Conic := TTsConic.Create(Pt0, Pt1, Pt2, Weight);
  var Pow2: Byte;
  if not Conic.TryComputeQuadPow2(0.25, Pow2) then
  begin
    Exit(False);
  end;

  Quads.Len := Conic.ChopIntoQuadsPow2(Pow2, Quads.Points);
  Result := True;
end;

{ TTsPathGeometry }

class function TTsPathGeometry.NewTValues: TTsTValues;
begin
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := TTsNormalizedF32Exclusive.Any;
  end;
end;

class procedure TTsPathGeometry.ChopQuadAt(const Src: TTsPoints3; const T: TTsNormalizedF32Exclusive; var Dst: TTsPoints5);
begin
  const P0 = Src[0].ToF32x2;
  const P1 = Src[1].ToF32x2;
  const P2 = Src[2].ToF32x2;
  const TT = TF32x2.Splat(T.Get);

  const P01 = Interp(P0, P1, TT);
  const P12 = Interp(P1, P2, TT);

  Dst[0] := TTsPoint.FromF32x2(P0);
  Dst[1] := TTsPoint.FromF32x2(P01);
  Dst[2] := TTsPoint.FromF32x2(Interp(P01, P12, TT));
  Dst[3] := TTsPoint.FromF32x2(P12);
  Dst[4] := TTsPoint.FromF32x2(P2);
end;

class function TTsPathGeometry.FindUnitQuadRoots(const A, B, C: Single; var Roots: TTsTValues): Integer;
begin
  if A = 0 then
  begin
    if TryValidUnitDivide(-C, B, Roots[0]) then
    begin
      Exit(1);
    end;

    Exit(0);
  end;

  // use doubles so we don't overflow temporarily trying to compute R
  var Dr: Double := Double(B) * Double(B) - 4.0 * Double(A) * Double(C);
  if Dr < 0.0 then
  begin
    Exit(0);
  end;

  Dr := System.Sqrt(Dr);
  const R: Single = Single(Dr);
  if not TTsScalar.IsFinite(R) then
  begin
    Exit(0);
  end;

  var Q: Single;
  if B < 0 then
  begin
    Q := -(B - R) / Two;
  end
  else
  begin
    Q := -(B + R) / Two;
  end;

  var RootsOffset := 0;
  if TryValidUnitDivide(Q, A, Roots[RootsOffset]) then
  begin
    Inc(RootsOffset);
  end;

  if TryValidUnitDivide(C, Q, Roots[RootsOffset]) then
  begin
    Inc(RootsOffset);
  end;

  if RootsOffset = 2 then
  begin
    if Roots[0].Get > Roots[1].Get then
    begin
      const Swapped = Roots[0];
      Roots[0] := Roots[1];
      Roots[1] := Swapped;
    end
    else if Roots[0].Get = Roots[1].Get then
    begin
      // nearly-equal?
      Dec(RootsOffset); // skip the double root
    end;
  end;

  Result := RootsOffset;
end;

class procedure TTsPathGeometry.ChopCubicAt2(const Src: TTsPoints4; const T: TTsNormalizedF32Exclusive; var Dst: array of TTsPoint;
                                             const DstOffset: Integer);
begin
  const P0 = Src[0].ToF32x2;
  const P1 = Src[1].ToF32x2;
  const P2 = Src[2].ToF32x2;
  const P3 = Src[3].ToF32x2;
  const TT = TF32x2.Splat(T.Get);

  const AB = Interp(P0, P1, TT);
  const BC = Interp(P1, P2, TT);
  const CD = Interp(P2, P3, TT);
  const ABC = Interp(AB, BC, TT);
  const BCD = Interp(BC, CD, TT);
  const ABCD = Interp(ABC, BCD, TT);

  Dst[DstOffset] := TTsPoint.FromF32x2(P0);
  Dst[DstOffset + 1] := TTsPoint.FromF32x2(AB);
  Dst[DstOffset + 2] := TTsPoint.FromF32x2(ABC);
  Dst[DstOffset + 3] := TTsPoint.FromF32x2(ABCD);
  Dst[DstOffset + 4] := TTsPoint.FromF32x2(BCD);
  Dst[DstOffset + 5] := TTsPoint.FromF32x2(CD);
  Dst[DstOffset + 6] := TTsPoint.FromF32x2(P3);
end;

class function TTsPathGeometry.TryFindQuadExtrema(const A, B, C: Single; out T: TTsNormalizedF32Exclusive): Boolean;
begin
  // At + B == 0
  // t = -B / A
  Result := TryValidUnitDivide(A - B, A - B - B + C, T);
end;

class function TTsPathGeometry.TryValidUnitDivide(const Numer, Denom: Single; out Quotient: TTsNormalizedF32Exclusive): Boolean;
begin
  var NumerValue: Single := Numer;
  var DenomValue: Single := Denom;
  if TTsLane.IsLt(NumerValue, 0.0) then
  begin
    NumerValue := -NumerValue;
    DenomValue := -DenomValue;
  end;

  if TTsLane.IsEq(DenomValue, 0.0) or TTsLane.IsEq(NumerValue, 0.0) or TTsLane.IsGe(NumerValue, DenomValue) then
  begin
    Exit(False);
  end;

  const R: Single = NumerValue / DenomValue;
  if IsNan(R) then
  begin
    Exit(False);
  end;

  // Rust leaves the slot as it was on failure: the result is copied only on success
  var Checked: TTsNormalizedF32Exclusive;
  Result := TTsNormalizedF32Exclusive.TryCreate(R, Checked);
  if Result then
  begin
    Quotient := Checked;
  end;
end;

class function TTsPathGeometry.Interp(const V0, V1, T: TF32x2): TF32x2;
begin
  Result := V0 + (V1 - V0) * T;
end;

class function TTsPathGeometry.Times2(const Value: TF32x2): TF32x2;
begin
  Result := Value + Value;
end;

class function TTsPathGeometry.TryFindQuadMaxCurvature(const Src: TTsPoints3; out T: TTsNormalizedF32): Boolean;
begin
  T := TTsNormalizedF32.Zero;

  const Ax: Single = Src[1].X - Src[0].X;
  const Ay: Single = Src[1].Y - Src[0].Y;
  const Bx: Single = Src[0].X - Src[1].X - Src[1].X + Src[2].X;
  const By: Single = Src[0].Y - Src[1].Y - Src[1].Y + Src[2].Y;

  var Numer: Single := -(Ax * Bx + Ay * By);
  var Denom: Single := Bx * Bx + By * By;
  if TTsLane.IsLt(Denom, 0.0) then
  begin
    Numer := -Numer;
    Denom := -Denom;
  end;

  if TTsLane.IsLe(Numer, 0.0) then
  begin
    Exit(True);
  end;

  if TTsLane.IsGe(Numer, Denom) then
  begin
    // Also catches denom=0
    T := TTsNormalizedF32.One;
    Exit(True);
  end;

  // Rust unwraps NormalizedF32::new(numer / denom), which panics for the NaN of huge control points (inf - inf in numer or denom)
  const Quotient: Single = Numer / Denom;
  Result := TTsNormalizedF32.TryCreate(Quotient, T);
end;

class function TTsPathGeometry.EvalQuadAt(const Src: TTsPoints3; const T: TTsNormalizedF32): TTsPoint;
begin
  Result := TTsPoint.FromF32x2(TTsQuadCoeff.FromPoints(Src).Eval(TF32x2.Splat(T.Get)));
end;

class function TTsPathGeometry.EvalQuadTangentAt(const Src: TTsPoints3; const Tol: TTsNormalizedF32): TTsPoint;
begin
  // The derivative equation is 2(b - a +(a - 2b +c)t). This returns a zero tangent vector when t is 0 or 1, and the control point is equal
  // to the end point. In this case, use the quad end points to compute the tangent.
  if ((Tol.Get = 0) and (Src[0] = Src[1])) or ((Tol.Get = 1) and (Src[1] = Src[2])) then
  begin
    Exit(Src[2] - Src[0]);
  end;

  const P0 = Src[0].ToF32x2;
  const P1 = Src[1].ToF32x2;
  const P2 = Src[2].ToF32x2;

  const B = P1 - P0;
  const A = P2 - P1 - B;
  const T = A * TF32x2.Splat(Tol.Get) + B;

  Result := TTsPoint.FromF32x2(T + T);
end;

class function TTsPathGeometry.FindCubicMaxCurvature(const Src: TTsPoints4; var TValues: TTsNormalizedValues): Integer;
begin
  var CoeffX := FormulateF1DotF2([Src[0].X, Src[1].X, Src[2].X, Src[3].X]);
  const CoeffY = FormulateF1DotF2([Src[0].Y, Src[1].Y, Src[2].Y, Src[3].Y]);

  for var Index := 0 to 3 do
  begin
    CoeffX[Index] := CoeffX[Index] + CoeffY[Index];
  end;

  Result := SolveCubicPoly(CoeffX, TValues);
end;

class function TTsPathGeometry.FormulateF1DotF2(const Src: array of Single): TArray<Single>;
begin
  const A: Single = Src[1] - Src[0];
  const B: Single = Src[2] - Two * Src[1] + Src[0];
  const C: Single = Src[3] + Three * (Src[1] - Src[2]) - Src[0];

  Result := [C * C, Three * B * C, Two * B * B + C * A, A * B];
end;

// Solve coeff(t) == 0, returning the number of roots that lie within 0 < t < 1.
// coeff[0]t^3 + coeff[1]t^2 + coeff[2]t + coeff[3]
//
// Eliminates repeated roots (so that all t_values are distinct, and are always in increasing order.
class function TTsPathGeometry.SolveCubicPoly(const Coeff: array of Single; var TValues: TTsNormalizedValues): Integer;
begin
  if TTsScalar.IsNearlyZero(Coeff[0]) then
  begin
    // we're just a quadratic
    var TmpT := NewTValues;
    const Count = FindUnitQuadRoots(Coeff[1], Coeff[2], Coeff[3], TmpT);
    for var Index := 0 to Count - 1 do
    begin
      TValues[Index] := TmpT[Index].ToNormalized;
    end;

    Exit(Count);
  end;

  const InvA: Single = TTsScalar.Invert(Coeff[0]);
  const A: Single = Coeff[1] * InvA;
  const B: Single = Coeff[2] * InvA;
  const C: Single = Coeff[3] * InvA;

  const Q: Single = (A * A - B * Three) / Nine;
  const R: Single = (Two * A * A * A - Nine * A * B + TwentySeven * C) / FiftyFour;

  const Q3: Single = Q * Q * Q;
  const R2MinusQ3: Single = R * R - Q3;
  const ADiv3: Single = A / Three;

  if TTsLane.IsLt(R2MinusQ3, 0.0) then
  begin
    // we have 3 real roots the divide/root can, due to finite precisions, be slightly outside of -1...1
    const Theta: Single = Single(System.Math.ArcCos(Double(TTsScalar.Bound(R / Single(System.Sqrt(Double(Q3))), NegOne, One))));
    const Neg2RootQ: Single = NegTwo * Single(System.Sqrt(Double(Q)));

    TValues[0] := TTsNormalizedF32.CreateClamped(Neg2RootQ * Single(System.Cos(Double(Theta / Three))) - ADiv3);
    TValues[1] := TTsNormalizedF32.CreateClamped(Neg2RootQ * Single(System.Cos(Double((Theta + Two * TTsScalar.FloatPi) / Three))) - ADiv3);
    TValues[2] := TTsNormalizedF32.CreateClamped(Neg2RootQ * Single(System.Cos(Double((Theta - Two * TTsScalar.FloatPi) / Three))) - ADiv3);

    // now sort the roots
    SortArray3(TValues);
    Result := CollapseDuplicates3(TValues);
  end
  else
  begin
    // we have 1 real root
    var Root: Single := Abs(R) + Single(System.Sqrt(Double(R2MinusQ3)));
    Root := ScalarCubeRoot(Root);
    if R > 0 then
    begin
      Root := -Root;
    end;

    if Root <> 0 then
    begin
      Root := Root + Q / Root;
    end;

    TValues[0] := TTsNormalizedF32.CreateClamped(Root - ADiv3);
    Result := 1;
  end;
end;

class procedure TTsPathGeometry.SortArray3(var Values: TTsNormalizedValues);
begin
  if Values[0].Get > Values[1].Get then
  begin
    const Swapped = Values[0];
    Values[0] := Values[1];
    Values[1] := Swapped;
  end;

  if Values[1].Get > Values[2].Get then
  begin
    const Swapped = Values[1];
    Values[1] := Values[2];
    Values[2] := Swapped;
  end;

  if Values[0].Get > Values[1].Get then
  begin
    const Swapped = Values[0];
    Values[0] := Values[1];
    Values[1] := Swapped;
  end;
end;

class function TTsPathGeometry.CollapseDuplicates3(const Values: TTsNormalizedValues): Integer;
begin
  Result := 3;

  if Values[1].Get = Values[2].Get then
  begin
    Result := 2;
  end;

  if Values[0].Get = Values[1].Get then
  begin
    Result := 1;
  end;
end;

class function TTsPathGeometry.ScalarCubeRoot(const X: Single): Single;
begin
  Result := Single(System.Math.Power(Double(X), Double(OneThird)));
end;

class function TTsPathGeometry.EvalCubicPosAt(const Src: TTsPoints4; const T: TTsNormalizedF32): TTsPoint;
begin
  Result := TTsPoint.FromF32x2(TTsCubicCoeff.FromPoints(Src).Eval(TF32x2.Splat(T.Get)));
end;

class function TTsPathGeometry.EvalCubicTangentAt(const Src: TTsPoints4; const T: TTsNormalizedF32): TTsPoint;
begin
  // The derivative equation returns a zero tangent vector when t is 0 or 1, and the adjacent control point is equal to the end point. In
  // this case, use the next control point or the end points to compute the tangent.
  if ((T.Get = 0) and (Src[0] = Src[1])) or ((T.Get = 1) and (Src[2] = Src[3])) then
  begin
    var Tangent: TTsPoint;
    if T.Get = 0 then
    begin
      Tangent := Src[2] - Src[0];
    end
    else
    begin
      Tangent := Src[3] - Src[1];
    end;

    if (Tangent.X = 0) and (Tangent.Y = 0) then
    begin
      Tangent := Src[3] - Src[0];
    end;

    Result := Tangent;
  end
  else
  begin
    Result := EvalCubicDerivative(Src, T);
  end;
end;

class function TTsPathGeometry.EvalCubicDerivative(const Src: TTsPoints4; const T: TTsNormalizedF32): TTsPoint;
begin
  const P0 = Src[0].ToF32x2;
  const P1 = Src[1].ToF32x2;
  const P2 = Src[2].ToF32x2;
  const P3 = Src[3].ToF32x2;

  // The quadratic of the derivative: the coefficient D of TTsCubicCoeff is not used
  var Coeff: TTsQuadCoeff;
  Coeff.A := P3 + TF32x2.Splat(3.0) * (P1 - P2) - P0;
  Coeff.B := Times2(P2 - Times2(P1) + P0);
  Coeff.C := P1 - P0;

  Result := TTsPoint.FromF32x2(Coeff.Eval(TF32x2.Splat(T.Get)));
end;

class function TTsPathGeometry.FindCubicExtrema(const A, B, C, D: Single; var TValues: TTsTValues): Integer;
begin
  // we divide A,B,C by 3 to simplify
  const AA: Single = D - A + Three * (B - C);
  const BB: Single = Two * (A - B - B + C);
  const CC: Single = B - A;

  Result := FindUnitQuadRoots(AA, BB, CC, TValues);
end;

class function TTsPathGeometry.FindCubicInflections(const Src: TTsPoints4; var TValues: TTsTValues): Integer;
begin
  const Ax: Single = Src[1].X - Src[0].X;
  const Ay: Single = Src[1].Y - Src[0].Y;
  const Bx: Single = Src[2].X - Two * Src[1].X + Src[0].X;
  const By: Single = Src[2].Y - Two * Src[1].Y + Src[0].Y;
  const Cx: Single = Src[3].X + Three * (Src[1].X - Src[2].X) - Src[0].X;
  const Cy: Single = Src[3].Y + Three * (Src[1].Y - Src[2].Y) - Src[0].Y;

  Result := FindUnitQuadRoots(Bx * Cy - By * Cx, Ax * Cy - Ay * Cx, Ax * By - Ay * Bx, TValues);
end;

class function TTsPathGeometry.TryFindCubicCusp(const Src: TTsPoints4; out T: TTsNormalizedF32Exclusive): Boolean;
begin
  T := Default(TTsNormalizedF32Exclusive);

  // When the adjacent control point matches the end point, it behaves as if the cubic has a cusp: there's a point of max curvature where
  // the derivative goes to zero. Ideally, this would be where t is zero or one, but math error makes not so. It is not uncommon to create
  // cubics this way; skip them.
  if Src[0] = Src[1] then
  begin
    Exit(False);
  end;

  if Src[2] = Src[3] then
  begin
    Exit(False);
  end;

  // Cubics only have a cusp if the line segments formed by the control and end points cross. Detect crossing if line ends are on opposite
  // sides of plane formed by the other line.
  if OnSameSide(Src, 0, 2) or OnSameSide(Src, 2, 0) then
  begin
    Exit(False);
  end;

  // Cubics may have multiple points of maximum curvature, although at most only one is a cusp.
  var TValues: TTsNormalizedValues;
  const Count = FindCubicMaxCurvature(Src, TValues);
  for var Index := 0 to Count - 1 do
  begin
    const TestT = TValues[Index];
    if TTsLane.IsGe(0.0, TestT.Get) or TTsLane.IsGe(TestT.Get, 1.0) then
    begin
      // no need to consider max curvature on the end
      Continue;
    end;

    // A cusp is at the max curvature, and also has a derivative close to zero. Choose the 'close to zero' meaning by comparing the
    // derivative length with the overall cubic size.
    const DPt = EvalCubicDerivative(Src, TestT);
    const DPtMagnitude: Single = DPt.LengthSqd;
    const Precision: Single = CalcCubicPrecision(Src);
    if TTsLane.IsLt(DPtMagnitude, Precision) then
    begin
      // All three max curvature t values may be close to the cusp; return the first one.
      T := TTsNormalizedF32Exclusive.CreateBounded(TestT.Get);
      Exit(True);
    end;
  end;

  Result := False;
end;

// Returns true if both points src[testIndex], src[testIndex+1] are in the same half plane defined by the line segment
// src[lineIndex], src[lineIndex+1].
class function TTsPathGeometry.OnSameSide(const Src: TTsPoints4; const TestIndex, LineIndex: Integer): Boolean;
begin
  const Origin = Src[LineIndex];
  const Line = Src[LineIndex + 1] - Origin;
  var Crosses: array[0..1] of Single;
  for var Index := 0 to 1 do
  begin
    const TestLine = Src[TestIndex + Index] - Origin;
    Crosses[Index] := Line.Cross(TestLine);
  end;

  Result := TTsLane.IsGe(Crosses[0] * Crosses[1], 0.0);
end;

// Returns a constant proportional to the dimensions of the cubic. Constant found through experimentation -- maybe there's a better way....
class function TTsPathGeometry.CalcCubicPrecision(const Src: TTsPoints4): Single;
begin
  Result := (Src[1].DistanceToSqd(Src[0]) + Src[2].DistanceToSqd(Src[1]) + Src[3].DistanceToSqd(Src[2])) * PrecisionFactor;
end;

class function TTsPathGeometry.ChopQuadAtXExtrema(const Src: TTsPoints3; var Dst: TTsPoints5): Integer;
begin
  const A: Single = Src[0].X;
  var B: Single := Src[1].X;
  const C: Single = Src[2].X;

  if IsNotMonotonic(A, B, C) then
  begin
    var TValue: TTsNormalizedF32Exclusive;
    if TryValidUnitDivide(A - B, A - B - B + C, TValue) then
    begin
      ChopQuadAt(Src, TValue, Dst);

      // flatten double quad extrema
      Dst[1].X := Dst[2].X;
      Dst[3].X := Dst[2].X;

      Exit(1);
    end;

    // if we get here, we need to force dst to be monotonic, even though we couldn't compute a unit_divide value (probably underflow).
    if Abs(A - B) < Abs(B - C) then
    begin
      B := A;
    end
    else
    begin
      B := C;
    end;
  end;

  Dst[0] := TTsPoint.FromXY(A, Src[0].Y);
  Dst[1] := TTsPoint.FromXY(B, Src[1].Y);
  Dst[2] := TTsPoint.FromXY(C, Src[2].Y);
  Result := 0;
end;

class function TTsPathGeometry.ChopQuadAtYExtrema(const Src: TTsPoints3; var Dst: TTsPoints5): Integer;
begin
  const A: Single = Src[0].Y;
  var B: Single := Src[1].Y;
  const C: Single = Src[2].Y;

  if IsNotMonotonic(A, B, C) then
  begin
    var TValue: TTsNormalizedF32Exclusive;
    if TryValidUnitDivide(A - B, A - B - B + C, TValue) then
    begin
      ChopQuadAt(Src, TValue, Dst);

      // flatten double quad extrema
      Dst[1].Y := Dst[2].Y;
      Dst[3].Y := Dst[2].Y;

      Exit(1);
    end;

    // if we get here, we need to force dst to be monotonic, even though we couldn't compute a unit_divide value (probably underflow).
    if Abs(A - B) < Abs(B - C) then
    begin
      B := A;
    end
    else
    begin
      B := C;
    end;
  end;

  Dst[0] := TTsPoint.FromXY(Src[0].X, A);
  Dst[1] := TTsPoint.FromXY(Src[1].X, B);
  Dst[2] := TTsPoint.FromXY(Src[2].X, C);
  Result := 0;
end;

class function TTsPathGeometry.IsNotMonotonic(const A, B, C: Single): Boolean;
begin
  const AB: Single = A - B;
  var BC: Single := B - C;
  if TTsLane.IsLt(AB, 0.0) then
  begin
    BC := -BC;
  end;

  Result := TTsLane.IsEq(AB, 0.0) or TTsLane.IsLt(BC, 0.0);
end;

class function TTsPathGeometry.ChopCubicAtXExtrema(const Src: TTsPoints4; var Dst: TTsPoints10): Integer;
begin
  var TValues := NewTValues;
  const Count = FindCubicExtrema(Src[0].X, Src[1].X, Src[2].X, Src[3].X, TValues);

  ChopCubicAt(Src, Slice(TValues, Count), Dst);
  if Count <> 0 then
  begin
    // we do some cleanup to ensure our X extrema are flat
    Dst[2].X := Dst[3].X;
    Dst[4].X := Dst[3].X;
    if Count = 2 then
    begin
      Dst[5].X := Dst[6].X;
      Dst[7].X := Dst[6].X;
    end;
  end;

  Result := Count;
end;

class function TTsPathGeometry.ChopCubicAtYExtrema(const Src: TTsPoints4; var Dst: TTsPoints10): Integer;
begin
  var TValues := NewTValues;
  const Count = FindCubicExtrema(Src[0].Y, Src[1].Y, Src[2].Y, Src[3].Y, TValues);

  ChopCubicAt(Src, Slice(TValues, Count), Dst);
  if Count <> 0 then
  begin
    // we do some cleanup to ensure our Y extrema are flat
    Dst[2].Y := Dst[3].Y;
    Dst[4].Y := Dst[3].Y;
    if Count = 2 then
    begin
      Dst[5].Y := Dst[6].Y;
      Dst[7].Y := Dst[6].Y;
    end;
  end;

  Result := Count;
end;

class procedure TTsPathGeometry.ChopCubicAt(const Src: TTsPoints4; const TValues: array of TTsNormalizedF32Exclusive; var Dst: array of TTsPoint);
begin
  if Length(TValues) = 0 then
  begin
    // nothing to chop
    Dst[0] := Src[0];
    Dst[1] := Src[1];
    Dst[2] := Src[2];
    Dst[3] := Src[3];
    Exit;
  end;

  var T := TValues[0];
  var Tmp: TTsPoints4;

  // Rust points src at tmp after the first chop; Current is that pointer
  var Current := Src;

  var DstOffset := 0;
  for var Index := 0 to High(TValues) do
  begin
    ChopCubicAt2(Current, T, Dst, DstOffset);
    if Index = High(TValues) then
    begin
      Break;
    end;

    Inc(DstOffset, 3);

    // have src point to the remaining cubic (after the chop)
    Tmp[0] := Dst[DstOffset];
    Tmp[1] := Dst[DstOffset + 1];
    Tmp[2] := Dst[DstOffset + 2];
    Tmp[3] := Dst[DstOffset + 3];
    Current := Tmp;

    // watch out in case the renormalized t isn't in range
    var Renormalized: TTsNormalizedF32Exclusive;
    if TryValidUnitDivide(TValues[Index + 1].Get - TValues[Index].Get, 1.0 - TValues[Index].Get, Renormalized) then
    begin
      T := Renormalized;
    end
    else
    begin
      // if we can't, just create a degenerate cubic
      Dst[DstOffset + 4] := Current[3];
      Dst[DstOffset + 5] := Current[3];
      Dst[DstOffset + 6] := Current[3];
      Break;
    end;
  end;
end;

class function TTsPathGeometry.ChopCubicAtMaxCurvature(const Src: TTsPoints4; var TValues: TTsTValues; var Dst: array of TTsPoint): Integer;
begin
  var Roots: TTsNormalizedValues;
  const RootCount = FindCubicMaxCurvature(Src, Roots);

  // Throw out values not inside 0..1.
  var Count := 0;
  for var Index := 0 to RootCount - 1 do
  begin
    if TTsLane.IsLt(0.0, Roots[Index].Get) and TTsLane.IsLt(Roots[Index].Get, 1.0) then
    begin
      TValues[Count] := TTsNormalizedF32Exclusive.CreateBounded(Roots[Index].Get);
      Inc(Count);
    end;
  end;

  if Count = 0 then
  begin
    Dst[0] := Src[0];
    Dst[1] := Src[1];
    Dst[2] := Src[2];
    Dst[3] := Src[3];
  end
  else
  begin
    ChopCubicAt(Src, Slice(TValues, Count), Dst);
  end;

  Result := Count + 1;
end;

class function TTsPathGeometry.ChopMonoCubicAtX(const Src: TTsPoints4; const X: Single; var Dst: TTsPoints7): Boolean;
begin
  Result := CubicDchopAtIntercept(Src, X, True, Dst);
end;

class function TTsPathGeometry.ChopMonoCubicAtY(const Src: TTsPoints4; const Y: Single; var Dst: TTsPoints7): Boolean;
begin
  Result := CubicDchopAtIntercept(Src, Y, False, Dst);
end;

class function TTsPathGeometry.CubicDchopAtIntercept(const Src: TTsPoints4; const Intercept: Single; const IsVertical: Boolean;
                                                     var Dst: TTsPoints7): Boolean;
begin
  var Points64: array[0..3] of TTsPoint64;
  for var Index := 0 to 3 do
  begin
    Points64[Index] := TTsPoint64.FromPoint(Src[Index]);
  end;

  const Cubic = TTsCubic64.Create(Points64);

  var Roots: TTsDoubles3;
  Roots[0] := 0.0;
  Roots[1] := 0.0;
  Roots[2] := 0.0;

  var Count: Integer;
  if IsVertical then
  begin
    Count := TTsLineCubicIntersections.VerticalIntersect(Cubic, Intercept, Roots);
  end
  else
  begin
    Count := TTsLineCubicIntersections.HorizontalIntersect(Cubic, Intercept, Roots);
  end;

  if Count <= 0 then
  begin
    Exit(False);
  end;

  const Pair = Cubic.ChopAt(Roots[0]);
  for var Index := 0 to 6 do
  begin
    Dst[Index] := Pair.Points[Index].ToPoint;
  end;

  Result := True;
end;

end.
