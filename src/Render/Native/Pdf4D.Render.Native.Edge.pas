// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/edge.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Edge;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.FixedPoint;

// Edges of the scan converter: a line, a quadratic and a cubic edge, in fixed point.
//
// Rust adds and multiplies i32 with wrapping (a release build) and panics on a division by zero or an overflowing division. Here every
// operation wraps without raising, and a division that panics in Rust makes the edge creation fail: the edge is not made. A float to
// i32 conversion saturates and turns NaN into 0, as `as i32` does. The shift of the anti-aliasing is limited to 0..MaxShift (Rust
// uses 0 and 2), so that no shift or scale can overflow.
//
// The Rust enum Edge is a record with a Kind and the variants over each other: every variant starts with its LineEdge, so Edge.Line is
// as_line() of every kind. Prev and Next imitate a linked list; NoLink is None.

type
  TTsLineEdge = record
  public const
    NoLink = -1;
    MaxShift = 8;

  public
    // Imitate a linked list.
    Prev: Integer;
    Next: Integer;

    X: Integer;
    Dx: Integer;
    FirstY: Integer;
    LastY: Integer;
    Winding: ShortInt; // 1 or -1

    class function TryCreate(const P0, P1: TTsPoint; const Shift: Integer; out Edge: TTsLineEdge): Boolean; static;

    function IsVertical: Boolean;

  private
    function Update(const X0, Y0, X1, Y1: Integer): Boolean;
  end;

  TTsQuadraticEdge = record
  public
    Line: TTsLineEdge;
    CurveCount: ShortInt;

  private
    FCurveShift: Byte; // applied to all dx/ddx/dddx
    FQx: Integer;
    FQy: Integer;
    FQdx: Integer;
    FQdy: Integer;
    FQddx: Integer;
    FQddy: Integer;
    FQLastX: Integer;
    FQLastY: Integer;

    class function TryCreate2(const Points: array of TTsPoint; const PointsOffset, Shift: Integer; out Edge: TTsQuadraticEdge): Boolean; static;

  public
    // Points[PointsOffset..PointsOffset + 2] are the control points
    class function TryCreate(const Points: array of TTsPoint; const PointsOffset, Shift: Integer; out Edge: TTsQuadraticEdge): Boolean; static;

    function Update: Boolean;
  end;

  TTsCubicEdge = record
  public
    Line: TTsLineEdge;
    CurveCount: ShortInt;

  private
    FCurveShift: Byte; // applied to all dx/ddx/dddx except for dshift exception
    FDshift: Byte; // applied to cdx and cdy
    FCx: Integer;
    FCy: Integer;
    FCdx: Integer;
    FCdy: Integer;
    FCddx: Integer;
    FCddy: Integer;
    FCdddx: Integer;
    FCdddy: Integer;
    FCLastX: Integer;
    FCLastY: Integer;

    class function TryCreate2(const Points: array of TTsPoint; const PointsOffset, Shift: Integer; const SortY: Boolean;
                              out Edge: TTsCubicEdge): Boolean; static;

  public
    // Points[PointsOffset..PointsOffset + 3] are the control points
    class function TryCreate(const Points: array of TTsPoint; const PointsOffset, Shift: Integer; out Edge: TTsCubicEdge): Boolean; static;

    function Update: Boolean;
  end;

  TTsEdgeKind = (
    Line,
    Quadratic,
    Cubic);

  TTsEdge = record
  public
    Kind: TTsEdgeKind;

    case Integer of
      0: (Line: TTsLineEdge);
      1: (Quadratic: TTsQuadraticEdge);
      2: (Cubic: TTsCubicEdge);
  end;

implementation

const
  // We store 1<<shift in a (signed) byte, so its maximum value is 1<<6 == 64.
  //
  // Note that this limits the number of lines we use to approximate a curve.
  // If we need to increase this, we need to store curve_count in something
  // larger than i8.
  MaxCoeffShift = 6;

function WAdd(const A, B: Integer): Integer; inline;
begin
  Result := TTsScalar.WrappingAddI32(A, B);
end;

function WSub(const A, B: Integer): Integer; inline;
begin
  Result := TTsScalar.WrappingSubI32(A, B);
end;

function WMul(const A, B: Integer): Integer; inline;
begin
  const Product = Int64(A) * Int64(B);

  Result := Integer(Product);
end;

// i32::abs of the lowest value stays the lowest value in a release build
function WAbs(const Value: Integer): Integer; inline;
begin
  if Value < 0 then
  begin
    Exit(WSub(0, Value));
  end;

  Result := Value;
end;

function LeadingZeros(const Value: Cardinal): Integer;
begin
  Result := 32;

  var Remaining := Value;
  while Remaining <> 0 do
  begin
    Dec(Result);
    Remaining := Remaining shr 1;
  end;
end;

// fdot6::div, but a division that panics in Rust (by zero, or the lowest value by -1) gives False
function TryFdot6Div(const A, B: Integer; out Quotient: Integer): Boolean;
begin
  Quotient := 0;

  if B = 0 then
  begin
    Exit(False);
  end;

  const FitsInI16 = ((A >= Low(SmallInt)) and (A <= High(SmallInt)));
  if FitsInI16 and (B = -1) and (TTsScalar.LeftShift(A, 16) = Low(Integer)) then
  begin
    Exit(False);
  end;

  Quotient := TTsFdot6.&Div(A, B);
  Result := True;
end;

// This correctly favors the lower-pixel when y0 is on a 1/2 pixel boundary
function ComputeDy(const Top, Y0: Integer): Integer;
begin
  Result := WSub(WAdd(TTsScalar.LeftShift(Top, 6), 32), Y0);
end;

function CheapDistance(const Dx, Dy: Integer): Integer;
begin
  const AbsDx = WAbs(Dx);
  const AbsDy = WAbs(Dy);

  // return max + min/2
  if AbsDx > AbsDy then
  begin
    Result := WAdd(AbsDx, TTsScalar.ShiftRightI32(AbsDy, 1));
  end
  else
  begin
    Result := WAdd(AbsDy, TTsScalar.ShiftRightI32(AbsDx, 1));
  end;
end;

function DiffToShift(const Dx, Dy, ShiftAa: Integer): Integer;
begin
  // cheap calc of distance from center of p0-p2 to the center of the curve
  var Dist := CheapDistance(Dx, Dy);

  // shift down dist (it is currently in dot6)
  // down by 3 should give us 1/8 pixel accuracy (assuming our dist is accurate...)
  // this is chosen by heuristic: make it as big as possible (to minimize segments)
  // ... but small enough so that our curves still look smooth
  // When shift > 0, we're using AA and everything is scaled up so we can
  // lower the accuracy.
  Dist := TTsScalar.ShiftRightI32(WAdd(Dist, 1 shl (2 + ShiftAa)), 3 + ShiftAa);

  // each subdivision (shift value) cuts this dist (error) by 1/4
  Result := TTsScalar.ShiftRightI32(32 - LeadingZeros(Cardinal(Dist)), 1);
end;

// In LineEdge::new, QuadraticEdge::new, CubicEdge::new, the first thing we do is to convert
// the points into FDot6. This is modulated by the shift parameter, which
// will either be 0, or something like 2 for antialiasing.
//
// In the float case, we want to turn the float into .6 by saying pt * 64,
// or pt * 256 for antialiasing. This is implemented as 1 << (shift + 6).
//
// In the fixed case, we want to turn the fixed into .6 by saying pt >> 10,
// or pt >> 8 for antialiasing. This is implemented as pt >> (10 - shift).
function Fdot6ToFixedDiv2(const Value: Integer): Integer;
begin
  // we want to return SkFDot6ToFixed(value >> 1), but we don't want to throw
  // away data in value, so just perform a modify up-shift
  Result := TTsScalar.LeftShift(Value, 16 - 6 - 1);
end;

function Fdot6UpShift(const X, UpShift: Integer): Integer;
begin
  Result := TTsScalar.LeftShift(X, UpShift);
end;

// f(1/3) = (8a + 12b + 6c + d) / 27
// f(2/3) = (a + 6b + 12c + 8d) / 27
//
// f(1/3)-b = (8a - 15b + 6c + d) / 27
// f(2/3)-c = (a + 6b - 15c + 8d) / 27
//
// use 16/512 to approximate 1/27
function CubicDeltaFromLine(const A, B, C, D: Integer): Integer;
begin
  // since our parameters may be negative, we don't use <<
  const OneThird = TTsScalar.ShiftRightI32(WMul(WAdd(WAdd(WSub(WMul(A, 8), WMul(B, 15)), WMul(6, C)), D), 19), 9);
  const TwoThird = TTsScalar.ShiftRightI32(WMul(WAdd(WSub(WAdd(A, WMul(6, B)), WMul(C, 15)), WMul(D, 8)), 19), 9);

  const AbsOneThird = WAbs(OneThird);
  const AbsTwoThird = WAbs(TwoThird);
  if AbsOneThird > AbsTwoThird then
  begin
    Result := AbsOneThird;
  end
  else
  begin
    Result := AbsTwoThird;
  end;
end;

// (p * scale) as i32 with scale = (1 << (shift + 6)) as f32
function ScaleToFdot6(const Value, Scale: Single): Integer;
begin
  const Scaled: Single = Value * Scale;

  Result := TTsScalar.SaturateToInt32(Scaled);
end;

function ShiftScale(const Shift: Integer): Single;
begin
  const Scale: Integer = 1 shl (Shift + 6);

  Result := Scale;
end;

{ TTsLineEdge }

class function TTsLineEdge.TryCreate(const P0, P1: TTsPoint; const Shift: Integer; out Edge: TTsLineEdge): Boolean;
begin
  Edge := Default(TTsLineEdge);

  if (Shift < 0) or (Shift > MaxShift) then
  begin
    Exit(False);
  end;

  const Scale = ShiftScale(Shift);
  var X0 := ScaleToFdot6(P0.X, Scale);
  var Y0 := ScaleToFdot6(P0.Y, Scale);
  var X1 := ScaleToFdot6(P1.X, Scale);
  var Y1 := ScaleToFdot6(P1.Y, Scale);

  var Winding := 1;

  if Y0 > Y1 then
  begin
    var Swapped := X0;
    X0 := X1;
    X1 := Swapped;

    Swapped := Y0;
    Y0 := Y1;
    Y1 := Swapped;

    Winding := -1;
  end;

  const Top = TTsFdot6.Round(Y0);
  const Bottom = TTsFdot6.Round(Y1);

  // are we a zero-height line?
  if Top = Bottom then
  begin
    Exit(False);
  end;

  var Slope: Integer;
  if not TryFdot6Div(WSub(X1, X0), WSub(Y1, Y0), Slope) then
  begin
    Exit(False);
  end;

  const Dy = ComputeDy(Top, Y0);

  Edge.Prev := NoLink;
  Edge.Next := NoLink;
  Edge.X := TTsFdot6.ToFdot16(WAdd(X0, TTsFdot16.Mul(Slope, Dy)));
  Edge.Dx := Slope;
  Edge.FirstY := Top;
  Edge.LastY := WSub(Bottom, 1);
  Edge.Winding := ShortInt(Winding);

  Result := True;
end;

function TTsLineEdge.IsVertical: Boolean;
begin
  Result := (Dx = 0);
end;

function TTsLineEdge.Update(const X0, Y0, X1, Y1: Integer): Boolean;
begin
  const ShiftedY0 = TTsScalar.ShiftRightI32(Y0, 10);
  const ShiftedY1 = TTsScalar.ShiftRightI32(Y1, 10);

  const Top = TTsFdot6.Round(ShiftedY0);
  const Bottom = TTsFdot6.Round(ShiftedY1);

  // are we a zero-height line?
  if Top = Bottom then
  begin
    Exit(False);
  end;

  const ShiftedX0 = TTsScalar.ShiftRightI32(X0, 10);
  const ShiftedX1 = TTsScalar.ShiftRightI32(X1, 10);

  var Slope: Integer;
  if not TryFdot6Div(WSub(ShiftedX1, ShiftedX0), WSub(ShiftedY1, ShiftedY0), Slope) then
  begin
    Exit(False);
  end;

  const Dy = ComputeDy(Top, ShiftedY0);

  Self.X := TTsFdot6.ToFdot16(WAdd(ShiftedX0, TTsFdot16.Mul(Slope, Dy)));
  Self.Dx := Slope;
  Self.FirstY := Top;
  Self.LastY := WSub(Bottom, 1);

  Result := True;
end;

{ TTsQuadraticEdge }

class function TTsQuadraticEdge.TryCreate(const Points: array of TTsPoint; const PointsOffset, Shift: Integer;
                                          out Edge: TTsQuadraticEdge): Boolean;
begin
  Result := TryCreate2(Points, PointsOffset, Shift, Edge) and Edge.Update;
end;

class function TTsQuadraticEdge.TryCreate2(const Points: array of TTsPoint; const PointsOffset, Shift: Integer;
                                           out Edge: TTsQuadraticEdge): Boolean;
begin
  Edge := Default(TTsQuadraticEdge);

  if (Shift < 0) or (Shift > TTsLineEdge.MaxShift) or (PointsOffset < 0) or (PointsOffset + 2 > High(Points)) then
  begin
    Exit(False);
  end;

  const Scale = ShiftScale(Shift);
  var X0 := ScaleToFdot6(Points[PointsOffset].X, Scale);
  var Y0 := ScaleToFdot6(Points[PointsOffset].Y, Scale);
  const X1 = ScaleToFdot6(Points[PointsOffset + 1].X, Scale);
  const Y1 = ScaleToFdot6(Points[PointsOffset + 1].Y, Scale);
  var X2 := ScaleToFdot6(Points[PointsOffset + 2].X, Scale);
  var Y2 := ScaleToFdot6(Points[PointsOffset + 2].Y, Scale);

  var Winding := 1;
  if Y0 > Y2 then
  begin
    var Swapped := X0;
    X0 := X2;
    X2 := Swapped;

    Swapped := Y0;
    Y0 := Y2;
    Y2 := Swapped;

    Winding := -1;
  end;

  const Top = TTsFdot6.Round(Y0);
  const Bottom = TTsFdot6.Round(Y2);

  // are we a zero-height quad (line)?
  if Top = Bottom then
  begin
    Exit(False);
  end;

  // compute number of steps needed (1 << shift)
  var CurveShift: Integer;
  begin
    const Dx = TTsScalar.ShiftRightI32(WSub(WSub(TTsScalar.LeftShift(X1, 1), X0), X2), 2);
    const Dy = TTsScalar.ShiftRightI32(WSub(WSub(TTsScalar.LeftShift(Y1, 1), Y0), Y2), 2);

    // This is a little confusing:
    // before this line, shift is the scale up factor for AA;
    // after this line, shift is the fCurveShift.
    CurveShift := DiffToShift(Dx, Dy, Shift);
  end;

  // need at least 1 subdivision for our bias trick
  if CurveShift = 0 then
  begin
    CurveShift := 1;
  end
  else if CurveShift > MaxCoeffShift then
  begin
    CurveShift := MaxCoeffShift;
  end;

  Edge.CurveCount := ShortInt(1 shl CurveShift);

  // We want to reformulate into polynomial form, to make it clear how we
  // should forward-difference.
  //
  // p0 (1 - t)^2 + p1 t(1 - t) + p2 t^2 ==> At^2 + Bt + C
  //
  // A = p0 - 2p1 + p2
  // B = 2(p1 - p0)
  // C = p0
  //
  // Our caller must have constrained our inputs (p0..p2) to all fit into
  // 16.16. However, as seen above, we sometimes compute values that can be
  // larger (e.g. B = 2*(p1 - p0)). To guard against overflow, we will store
  // A and B at 1/2 of their actual value, and just apply a 2x scale during
  // application in updateQuadratic(). Hence we store (shift - 1) in
  // curve_shift.

  Edge.FCurveShift := Byte(CurveShift - 1);

  var A := Fdot6ToFixedDiv2(WAdd(WSub(WSub(X0, X1), X1), X2)); // 1/2 the real value
  var B := TTsFdot6.ToFdot16(WSub(X1, X0)); // 1/2 the real value

  Edge.FQx := TTsFdot6.ToFdot16(X0);
  Edge.FQdx := WAdd(B, TTsScalar.ShiftRightI32(A, CurveShift)); // biased by shift
  Edge.FQddx := TTsScalar.ShiftRightI32(A, CurveShift - 1); // biased by shift

  A := Fdot6ToFixedDiv2(WAdd(WSub(WSub(Y0, Y1), Y1), Y2)); // 1/2 the real value
  B := TTsFdot6.ToFdot16(WSub(Y1, Y0)); // 1/2 the real value

  Edge.FQy := TTsFdot6.ToFdot16(Y0);
  Edge.FQdy := WAdd(B, TTsScalar.ShiftRightI32(A, CurveShift)); // biased by shift
  Edge.FQddy := TTsScalar.ShiftRightI32(A, CurveShift - 1); // biased by shift

  Edge.FQLastX := TTsFdot6.ToFdot16(X2);
  Edge.FQLastY := TTsFdot6.ToFdot16(Y2);

  Edge.Line.Prev := TTsLineEdge.NoLink;
  Edge.Line.Next := TTsLineEdge.NoLink;
  Edge.Line.Winding := ShortInt(Winding);

  Result := True;
end;

function TTsQuadraticEdge.Update: Boolean;
begin
  // The edge has no segment left; Rust would count below zero
  if CurveCount <= 0 then
  begin
    Exit(False);
  end;

  var Success: Boolean;
  var Count: Integer := CurveCount;
  var OldX := FQx;
  var OldY := FQy;
  var Dx := FQdx;
  var Dy := FQdy;
  var NewX: Integer;
  var NewY: Integer;
  const Shift = FCurveShift;

  repeat
    Dec(Count);
    if Count > 0 then
    begin
      NewX := WAdd(OldX, TTsScalar.ShiftRightI32(Dx, Shift));
      Dx := WAdd(Dx, FQddx);
      NewY := WAdd(OldY, TTsScalar.ShiftRightI32(Dy, Shift));
      Dy := WAdd(Dy, FQddy);
    end
    else
    begin
      // last segment
      NewX := FQLastX;
      NewY := FQLastY;
    end;

    Success := Line.Update(OldX, OldY, NewX, NewY);
    OldX := NewX;
    OldY := NewY;
  until (Count = 0) or Success;

  FQx := NewX;
  FQy := NewY;
  FQdx := Dx;
  FQdy := Dy;
  CurveCount := ShortInt(Count);

  Result := Success;
end;

{ TTsCubicEdge }

class function TTsCubicEdge.TryCreate(const Points: array of TTsPoint; const PointsOffset, Shift: Integer;
                                      out Edge: TTsCubicEdge): Boolean;
begin
  Result := TryCreate2(Points, PointsOffset, Shift, True, Edge) and Edge.Update;
end;

class function TTsCubicEdge.TryCreate2(const Points: array of TTsPoint; const PointsOffset, Shift: Integer; const SortY: Boolean;
                                       out Edge: TTsCubicEdge): Boolean;
begin
  Edge := Default(TTsCubicEdge);

  if (Shift < 0) or (Shift > TTsLineEdge.MaxShift) or (PointsOffset < 0) or (PointsOffset + 3 > High(Points)) then
  begin
    Exit(False);
  end;

  const Scale = ShiftScale(Shift);
  var X0 := ScaleToFdot6(Points[PointsOffset].X, Scale);
  var Y0 := ScaleToFdot6(Points[PointsOffset].Y, Scale);
  var X1 := ScaleToFdot6(Points[PointsOffset + 1].X, Scale);
  var Y1 := ScaleToFdot6(Points[PointsOffset + 1].Y, Scale);
  var X2 := ScaleToFdot6(Points[PointsOffset + 2].X, Scale);
  var Y2 := ScaleToFdot6(Points[PointsOffset + 2].Y, Scale);
  var X3 := ScaleToFdot6(Points[PointsOffset + 3].X, Scale);
  var Y3 := ScaleToFdot6(Points[PointsOffset + 3].Y, Scale);

  var Winding := 1;
  if SortY and (Y0 > Y3) then
  begin
    var Swapped := X0;
    X0 := X3;
    X3 := Swapped;

    Swapped := X1;
    X1 := X2;
    X2 := Swapped;

    Swapped := Y0;
    Y0 := Y3;
    Y3 := Swapped;

    Swapped := Y1;
    Y1 := Y2;
    Y2 := Swapped;

    Winding := -1;
  end;

  const Top = TTsFdot6.Round(Y0);
  const Bot = TTsFdot6.Round(Y3);

  // are we a zero-height cubic (line)?
  if SortY and (Top = Bot) then
  begin
    Exit(False);
  end;

  // compute number of steps needed (1 << shift)
  var CurveShift: Integer;
  begin
    // Can't use (center of curve - center of baseline), since center-of-curve
    // need not be the max delta from the baseline (it could even be coincident)
    // so we try just looking at the two off-curve points
    const Dx = CubicDeltaFromLine(X0, X1, X2, X3);
    const Dy = CubicDeltaFromLine(Y0, Y1, Y2, Y3);

    // add 1 (by observation)
    CurveShift := DiffToShift(Dx, Dy, 2) + 1;
  end;

  // need at least 1 subdivision for our bias trick
  if CurveShift > MaxCoeffShift then
  begin
    CurveShift := MaxCoeffShift;
  end;

  // Since our in coming data is initially shifted down by 10 (or 8 in
  // antialias). That means the most we can shift up is 8. However, we
  // compute coefficients with a 3*, so the safest upshift is really 6
  var UpShift := 6; // largest safe value
  var DownShift := CurveShift + UpShift - 10;
  if DownShift < 0 then
  begin
    DownShift := 0;
    UpShift := 10 - CurveShift;
  end;

  Edge.CurveCount := ShortInt(TTsScalar.LeftShift(-1, CurveShift));
  Edge.FCurveShift := Byte(CurveShift);
  Edge.FDshift := Byte(DownShift);

  var B := Fdot6UpShift(WMul(3, WSub(X1, X0)), UpShift);
  var C := Fdot6UpShift(WMul(3, WAdd(WSub(WSub(X0, X1), X1), X2)), UpShift);
  var D := Fdot6UpShift(WSub(WAdd(X3, WMul(3, WSub(X1, X2))), X0), UpShift);

  Edge.FCx := TTsFdot6.ToFdot16(X0);
  Edge.FCdx := WAdd(WAdd(B, TTsScalar.ShiftRightI32(C, CurveShift)), TTsScalar.ShiftRightI32(D, 2 * CurveShift)); // biased by shift
  Edge.FCddx := WAdd(WMul(2, C), TTsScalar.ShiftRightI32(WMul(3, D), CurveShift - 1)); // biased by 2*shift
  Edge.FCdddx := TTsScalar.ShiftRightI32(WMul(3, D), CurveShift - 1); // biased by 2*shift

  B := Fdot6UpShift(WMul(3, WSub(Y1, Y0)), UpShift);
  C := Fdot6UpShift(WMul(3, WAdd(WSub(WSub(Y0, Y1), Y1), Y2)), UpShift);
  D := Fdot6UpShift(WSub(WAdd(Y3, WMul(3, WSub(Y1, Y2))), Y0), UpShift);

  Edge.FCy := TTsFdot6.ToFdot16(Y0);
  Edge.FCdy := WAdd(WAdd(B, TTsScalar.ShiftRightI32(C, CurveShift)), TTsScalar.ShiftRightI32(D, 2 * CurveShift)); // biased by shift
  Edge.FCddy := WAdd(WMul(2, C), TTsScalar.ShiftRightI32(WMul(3, D), CurveShift - 1)); // biased by 2*shift
  Edge.FCdddy := TTsScalar.ShiftRightI32(WMul(3, D), CurveShift - 1); // biased by 2*shift

  Edge.FCLastX := TTsFdot6.ToFdot16(X3);
  Edge.FCLastY := TTsFdot6.ToFdot16(Y3);

  Edge.Line.Prev := TTsLineEdge.NoLink;
  Edge.Line.Next := TTsLineEdge.NoLink;
  Edge.Line.Winding := ShortInt(Winding);

  Result := True;
end;

function TTsCubicEdge.Update: Boolean;
begin
  // The edge has no segment left; Rust would count past zero
  if CurveCount >= 0 then
  begin
    Exit(False);
  end;

  var Success: Boolean;
  var Count: Integer := CurveCount;
  var OldX := FCx;
  var OldY := FCy;
  var NewX: Integer;
  var NewY: Integer;
  const DdShift = FCurveShift;
  const DShift = FDshift;

  repeat
    Inc(Count);
    if Count < 0 then
    begin
      NewX := WAdd(OldX, TTsScalar.ShiftRightI32(FCdx, DShift));
      FCdx := WAdd(FCdx, TTsScalar.ShiftRightI32(FCddx, DdShift));
      FCddx := WAdd(FCddx, FCdddx);

      NewY := WAdd(OldY, TTsScalar.ShiftRightI32(FCdy, DShift));
      FCdy := WAdd(FCdy, TTsScalar.ShiftRightI32(FCddy, DdShift));
      FCddy := WAdd(FCddy, FCdddy);
    end
    else
    begin
      // last segment
      NewX := FCLastX;
      NewY := FCLastY;
    end;

    // we want to say debug_assert(oldy <= newy), but our finite fixedpoint
    // doesn't always achieve that, so we have to explicitly pin it here.
    if NewY < OldY then
    begin
      NewY := OldY;
    end;

    Success := Line.Update(OldX, OldY, NewX, NewY);
    OldX := NewX;
    OldY := NewY;
  until (Count = 0) or Success;

  FCx := NewX;
  FCy := NewY;
  CurveCount := ShortInt(Count);

  Result := Success;
end;

end.
