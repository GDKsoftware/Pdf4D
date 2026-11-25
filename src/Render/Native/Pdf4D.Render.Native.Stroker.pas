// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/stroker.rs
// Copyright (c) 2008 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Stroker;

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
  Pdf4D.Render.Native.PathGeometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Dash;

// Based on SkStroke.cpp
//
// Path.stroke is the record helper TTsPathStrokeHelper (TTsPath is declared in the Path unit). It has TryStroke and TryDash; a record type
// has one active helper in a unit, so a unit that uses TryStroke and TryDash uses this unit after the Dash unit.
//
// The Rust SwappableBuilders (two references that the joiners swap, not the builders) is TTsSwappableBuilders with two pointers. The cap
// and join functions of Rust are procedural types; the Rust test of the capper function pointer is a test of the line cap. The Rust
// Option<&PathBuilder> and Option<&PathSegmentsIter> arguments are pointers, nil for None.
//
// The Rust comparisons rely on NaN comparing false; the comparisons that can see a NaN use TTsLane.IsLt and its relatives.
//
// All arithmetic that can produce a NaN or an infinity (a huge width, a degenerate curve) needs the masked exceptions of TTsFloatMode.

type
  // Draws at the beginning and end of an open path contour.
  TTsLineCap = (
    // No stroke extension.
    Butt,
    // Adds circle.
    Round,
    // Adds square.
    Square);

  // Specifies how corners are drawn when a shape is stroked.
  //
  // Join affects the four corners of a stroked rectangle, and the connected segments in a stroked path.
  //
  // Choose miter join to draw sharp corners. Choose round join to draw a circle with a radius equal to the stroke width on top of the
  // corner. Choose bevel join to minimally connect the thick strokes.
  //
  // The fill path constructed to describe the stroked path respects the join setting but may not contain the actual join. For instance, a
  // fill path constructed with round joins does not necessarily include circles at each connected segment.
  TTsLineJoin = (
    // Extends to miter limit, then switches to bevel.
    Miter,
    // Extends to miter limit, then clips the corner.
    MiterClip,
    // Adds circle.
    Round,
    // Connects outside edges.
    Bevel);

  // Stroke properties. TTsStroke.New gives the defaults of the Rust Default implementation; a zero-filled record has a width of 0.
  TTsStroke = record
  public
    // A stroke thickness. Must be >= 0. When set to 0, a hairline stroking will be used. Default: 1.0
    Width: Single;

    // The limit at which a sharp corner is drawn beveled. Default: 4.0
    MiterLimit: Single;

    // A stroke line cap. Default: Butt
    LineCap: TTsLineCap;

    // A stroke line join. Default: Miter
    LineJoin: TTsLineJoin;

    // A stroke dashing properties; only used when HasDash is True. Default: none
    Dash: TTsStrokeDash;
    HasDash: Boolean;

    class function New: TTsStroke; static;
  end;

  PTsPathBuilder = ^TTsPathBuilder;
  PTsPathSegmentsIter = ^TTsPathSegmentsIter;
  PTsStrokerPoint = ^TTsPoint;

  // Skia swaps pointers to inner and outer builders during joining, but not builders itself.
  TTsSwappableBuilders = record
  public
    Inner: PTsPathBuilder;
    Outer: PTsPathBuilder;

    procedure Swap;
  end;

  TTsCapProc = procedure(const Pivot, Normal, Stop: TTsPoint; const OtherPath: PTsPathBuilder; var Path: TTsPathBuilder);

  TTsJoinProc = procedure(const BeforeUnitNormal, Pivot, AfterUnitNormal: TTsPoint; const Radius, InvMiterLimit: Single;
                          const PrevIsLine, CurrIsLine: Boolean; Builders: TTsSwappableBuilders);

  TTsReductionType = (
    Point, // all curve points are practically identical
    Line, // the control point is on the line between the ends
    Quad, // the control point is outside the line between the ends
    Degenerate, // the control point is on the line but outside the ends
    Degenerate2, // two control points are on the line but outside ends (cubic)
    Degenerate3, // three areas of max curvature found (for cubic)
    Invalid); // the curve cannot be stroked (no Rust counterpart: Rust panics on an unwrap here)

  TTsStrokeType = (
    Outer, // use sign-opposite values later to flip perpendicular axis
    Inner);

  TTsResultType = (
    Split, // the caller should split the quad stroke in two
    Degenerate, // the caller should add a line
    Quad); // the caller should (continue to try to) add a quad stroke

  TTsIntersectRayType = (
    CtrlPt,
    ResultType);

  // The state of the quad stroke under construction.
  TTsQuadConstruct = record
  public
    Quad: TTsPoints3; // the stroked quad parallel to the original curve
    TangentStart: TTsPoint; // a point tangent to quad[0]
    TangentEnd: TTsPoint; // a point tangent to quad[2]
    StartT: TTsNormalizedF32; // a segment of the original curve
    MidT: TTsNormalizedF32;
    EndT: TTsNormalizedF32;
    StartSet: Boolean; // state to share common points across structs
    EndSet: Boolean;
    OppositeTangents: Boolean; // set if coincident tangents have opposite directions

    // return false if start and end are too close to have a unique middle
    function Init(const Start, Stop: TTsNormalizedF32): Boolean;
    function InitWithStart(const Parent: TTsQuadConstruct): Boolean;
    function InitWithEnd(const Parent: TTsQuadConstruct): Boolean;
  end;

  // A path stroker. It can be used for several paths; the allocations of the builders are reused.
  TTsPathStroker = class
  private
    FRadius: Single;
    FInvMiterLimit: Single;
    FResScale: Single;
    FInvResScale: Single;
    FInvResScaleSquared: Single;

    FFirstNormal: TTsPoint;
    FPrevNormal: TTsPoint;
    FFirstUnitNormal: TTsPoint;
    FPrevUnitNormal: TTsPoint;

    // on original path
    FFirstPt: TTsPoint;
    FPrevPt: TTsPoint;

    FFirstOuterPt: TTsPoint;
    FFirstOuterPtIndexInContour: Integer;
    FSegmentCount: Integer;
    FPrevIsLine: Boolean;

    FLineCap: TTsLineCap;
    FCapper: TTsCapProc;
    FJoiner: TTsJoinProc;

    // outer is our working answer, inner is temp
    FInner: TTsPathBuilder;
    FOuter: TTsPathBuilder;
    FCusper: TTsPathBuilder;

    FStrokeType: TTsStrokeType;

    FRecursionDepth: Integer; // track stack depth to abort if numerics run amok
    FFoundTangents: Boolean; // do less work until tangents meet (cubic)
    FJoinCompleted: Boolean; // previous join was not degenerate
    FAborted: Boolean; // a curve could not be stroked (Rust panics there): the stroke fails

    function StrokeInner(const Path: TTsPath; const Width: TTsNonZeroPositiveF32; const MiterLimit: Single; const LineCap: TTsLineCap;
                         const LineJoin: TTsLineJoin; const ResScale: Single; out Stroked: TTsPath): Boolean;

    function Builders: TTsSwappableBuilders;
    function MoveToPt: TTsPoint;
    procedure MoveTo(const P: TTsPoint);
    procedure LineTo(const P: TTsPoint; const Iter: PTsPathSegmentsIter);
    procedure QuadTo(const P1, P2: TTsPoint);
    procedure CubicTo(const Pt1, Pt2, Pt3: TTsPoint);
    function CubicStroke(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): Boolean;
    function CubicMidOnLine(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): Boolean;
    procedure CubicQuadMid(const Cubic: TTsPoints4; const QuadPoints: TTsQuadConstruct; out Mid: TTsPoint);

    // Given a cubic and t, return the point on curve, its perpendicular, and the perpendicular tangent.
    procedure CubicPerpRay(const Cubic: TTsPoints4; const T: TTsNormalizedF32; out TPt, OnPt: TTsPoint; const Tangent: PTsStrokerPoint);
    procedure SetCubicEndNormal(const Cubic: TTsPoints4; const NormalAb, UnitNormalAb: TTsPoint; out NormalCd, UnitNormalCd: TTsPoint);
    function CompareQuadCubic(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): TTsResultType;

    // Given a cubic and a t range, find the start and end if they haven't been found already.
    procedure CubicQuadEnds(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct);
    procedure Close(const IsLine: Boolean);
    procedure FinishContour(const Close, CurrIsLine: Boolean);
    function PreJoinTo(const P: TTsPoint; const CurrIsLine: Boolean; var Normal, UnitNormal: TTsPoint): Boolean;
    procedure PostJoinTo(const P, Normal, UnitNormal: TTsPoint);
    procedure InitQuad(const StrokeType: TTsStrokeType; const Start, Stop: TTsNormalizedF32; var QuadPoints: TTsQuadConstruct);
    function QuadStroke(const Quad: TTsPoints3; var QuadPoints: TTsQuadConstruct): Boolean;
    function CompareQuadQuad(const Quad: TTsPoints3; var QuadPoints: TTsQuadConstruct): TTsResultType;

    // Given a point on the curve and its derivative, scale the derivative by the radius, and compute the perpendicular point and its
    // tangent.
    procedure SetRayPoints(const Tp: TTsPoint; var Dxy: TTsPoint; out OnP: TTsPoint; const Tangent: PTsStrokerPoint);

    // Given a quad and t, return the point on curve, its perpendicular, and the perpendicular tangent.
    procedure QuadPerpRay(const Quad: TTsPoints3; const T: TTsNormalizedF32; out Tp, OnP: TTsPoint; const Tangent: PTsStrokerPoint);
    procedure AddDegenerateLine(const QuadPoints: TTsQuadConstruct);
    function StrokeCloseEnough(const Stroke: TTsPoints3; const Ray0, Ray1: TTsPoint; const QuadPoints: TTsQuadConstruct): TTsResultType;

    // Find the intersection of the stroke tangents to construct a stroke quad. Return whether the stroke is a degenerate (a line), a quad,
    // or must be split. Optionally compute the quad's control point.
    function IntersectRay(const IntersectRayType: TTsIntersectRayType; var QuadPoints: TTsQuadConstruct): TTsResultType;

    // Given a cubic and a t-range, determine if the stroke can be described by a quadratic.
    function TangentsMeet(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): TTsResultType;
    function Finish(const IsLine: Boolean; out Stroked: TTsPath): Boolean;
    function HasOnlyMoveTo: Boolean;
    function IsCurrentContourEmpty: Boolean;

  public
    constructor Create;

    // Computes a resolution scale.
    //
    // Resolution scale is the "intended" resolution for the output. Default is 1.0.
    //
    // Larger values (res > 1) indicate that the result should be more precise, since it will be zoomed up, and small errors will be
    // magnified.
    //
    // Smaller values (0 < res < 1) indicate that the result can be less precise, since it will be zoomed down, and small errors may be
    // invisible.
    class function ComputeResolutionScale(const Ts: TTsTransform): Single; static;

    // Strokes the path. Can be called multiple times to reuse allocated buffers. Returns False when the path cannot be stroked: a width
    // that is not positive and finite, or a result without a valid path.
    //
    // ResolutionScale can be obtained via ComputeResolutionScale.
    function TryStroke(const Path: TTsPath; const Stroke: TTsStroke; const ResolutionScale: Single; out Stroked: TTsPath): Boolean;
  end;

  TTsPathStrokeHelper = record helper for TTsPath
    // Returns a stroked path; the Rust Path.stroke. ResolutionScale can be obtained via TTsPathStroker.ComputeResolutionScale.
    //
    // If you plan stroking multiple paths, you can try using TTsPathStroker which will preserve temporary allocations required during
    // stroking. This might improve performance a bit.
    function TryStroke(const Stroke: TTsStroke; const ResolutionScale: Single; out Stroked: TTsPath): Boolean;

    // The dashed path; the same as the helper of the Dash unit
    function TryDash(const Dash: TTsStrokeDash; const ResScale: Single; out Dashed: TTsPath): Boolean;
  end;

implementation

const
  QuadRecursiveLimit = 3;

  // quads with extreme widths (e.g. (0,1) (1,6) (0,3) width=5e7) recurse to point of failure
  // largest seen for normal cubics: 5, 26
  // largest seen for normal quads: 11
  RecursiveLimits: array[0..3] of Integer = (5 * 3, 26 * 3, 11 * 3, 11 * 3); // 3x limits seen in practice

  One: Single = 1;
  Two: Single = 2;
  Four: Single = 4;
  HalfValue: Single = 0.5;
  CurvatureSlop: Single = 0.000005; // this multiplier is pulled out of the air
  CubicLineSlopMultiplier: Single = 0.00001; // this multiplier is pulled out of the air

type
  TTsAngleType = (
    Nearly180,
    Sharp,
    Shallow,
    NearlyLine);

{ TTsStroke }

class function TTsStroke.New: TTsStroke;
begin
  Result := Default(TTsStroke);
  Result.Width := 1;
  Result.MiterLimit := 4;
  Result.LineCap := TTsLineCap.Butt;
  Result.LineJoin := TTsLineJoin.Miter;
end;

{ TTsSwappableBuilders }

procedure TTsSwappableBuilders.Swap;
begin
  // Skia swaps pointers to inner and outer builders during joining, but not builders itself. So a swap of the builders would produce
  // invalid results.
  const Other = Inner;
  Inner := Outer;
  Outer := Other;
end;

{ TTsQuadConstruct }

function TTsQuadConstruct.Init(const Start, Stop: TTsNormalizedF32): Boolean;
begin
  StartT := Start;
  MidT := TTsNormalizedF32.CreateClamped(TTsScalar.Half(Start.Get + Stop.Get));
  EndT := Stop;
  StartSet := False;
  EndSet := False;

  Result := (StartT.Get < MidT.Get) and (MidT.Get < EndT.Get);
end;

function TTsQuadConstruct.InitWithStart(const Parent: TTsQuadConstruct): Boolean;
begin
  if not Init(Parent.StartT, Parent.MidT) then
  begin
    Exit(False);
  end;

  Quad[0] := Parent.Quad[0];
  TangentStart := Parent.TangentStart;
  StartSet := True;
  Result := True;
end;

function TTsQuadConstruct.InitWithEnd(const Parent: TTsQuadConstruct): Boolean;
begin
  if not Init(Parent.MidT, Parent.EndT) then
  begin
    Exit(False);
  end;

  Quad[2] := Parent.Quad[2];
  TangentEnd := Parent.TangentEnd;
  EndSet := True;
  Result := True;
end;

// Functions of stroker.rs that the stroker uses.

function DegenerateVector(const V: TTsPoint): Boolean;
begin
  Result := not V.CanNormalize;
end;

// returns the distance squared from the point to the line
function PtToLine(const Pt, LineStart, LineEnd: TTsPoint): Single;
begin
  const Dxy = LineEnd - LineStart;
  const Ab0 = Pt - LineStart;
  const Numer: Single = Dxy.Dot(Ab0);
  const Denom: Single = Dxy.Dot(Dxy);
  const T: Single = Numer / Denom;

  if TTsLane.IsGe(T, 0) and TTsLane.IsLe(T, 1) then
  begin
    const OneMinusT: Single = One - T;
    const StartX: Single = LineStart.X * OneMinusT;
    const EndX: Single = LineEnd.X * T;
    const StartY: Single = LineStart.Y * OneMinusT;
    const EndY: Single = LineEnd.Y * T;
    const Hit = TTsPoint.FromXY(StartX + EndX, StartY + EndY);

    Result := Hit.DistanceToSqd(Pt);
  end
  else
  begin
    Result := Pt.DistanceToSqd(LineStart);
  end;
end;

// Given quad, see if all there points are in a line. Return true if the inside point is close to a line connecting the outermost points.
//
// Find the outermost point by looking for the largest difference in X or Y. Since the XOR of the indices is 3  (0 ^ 1 ^ 2) the missing
// index equals: outer_1 ^ outer_2 ^ 3.
function QuadInLine(const Quad: TTsPoints3): Boolean;
begin
  var PtMax: Single := -1;
  var Outer1 := 0;
  var Outer2 := 0;

  for var Index := 0 to 1 do
  begin
    for var Inner := Index + 1 to 2 do
    begin
      const TestDiff = Quad[Inner] - Quad[Index];
      const TestMax: Single = TTsScalar.MaxF(Abs(TestDiff.X), Abs(TestDiff.Y));
      if TTsLane.IsLt(PtMax, TestMax) then
      begin
        Outer1 := Index;
        Outer2 := Inner;
        PtMax := TestMax;
      end;
    end;
  end;

  const Mid = Outer1 xor Outer2 xor 3;
  const SquaredMax: Single = PtMax * PtMax;
  const LineSlop: Single = SquaredMax * CurvatureSlop;

  Result := TTsLane.IsLe(PtToLine(Quad[Mid], Quad[Outer1], Quad[Outer2]), LineSlop);
end;

function CheckQuadLinear(const Quad: TTsPoints3; out Reduction: TTsPoint): TTsReductionType;
begin
  Reduction := TTsPoint.Zero;

  const DegenerateAb = DegenerateVector(Quad[1] - Quad[0]);
  const DegenerateBc = DegenerateVector(Quad[2] - Quad[1]);
  if DegenerateAb and DegenerateBc then
  begin
    Exit(TTsReductionType.Point);
  end;

  if DegenerateAb or DegenerateBc then
  begin
    Exit(TTsReductionType.Line);
  end;

  if not QuadInLine(Quad) then
  begin
    Exit(TTsReductionType.Quad);
  end;

  var T: TTsNormalizedF32;
  if not TTsPathGeometry.TryFindQuadMaxCurvature(Quad, T) then
  begin
    Exit(TTsReductionType.Invalid);
  end;

  if (T.Get = 0) or (T.Get = 1) then
  begin
    Exit(TTsReductionType.Line);
  end;

  Reduction := TTsPathGeometry.EvalQuadAt(Quad, T);
  Result := TTsReductionType.Degenerate;
end;

// Given a cubic, determine if all four points are in a line.
//
// Return true if the inner points is close to a line connecting the outermost points.
//
// Find the outermost point by looking for the largest difference in X or Y. Given the indices of the outermost points, and that outer_1
// is greater than outer_2, this table shows the index of the smaller of the remaining points:
//
//                   outer_2
//               0    1    2    3
//   outer_1     ----------------
//      0     |  -    2    1    1
//      1     |  -    -    0    0
//      2     |  -    -    -    0
//      3     |  -    -    -    -
//
// If outer_1 == 0 and outer_2 == 1, the smaller of the remaining indices (2 and 3) is 2.
//
// This table can be collapsed to: (1 + (2 >> outer_2)) >> outer_1
//
// Given three indices (outer_1 outer_2 mid_1) from 0..3, the remaining index is:
//
// mid_2 == (outer_1 ^ outer_2 ^ mid_1)
function CubicInLine(const Cubic: TTsPoints4): Boolean;
begin
  var PtMax: Single := -1;
  var Outer1 := 0;
  var Outer2 := 0;

  for var Index := 0 to 2 do
  begin
    for var Inner := Index + 1 to 3 do
    begin
      const TestDiff = Cubic[Inner] - Cubic[Index];
      const TestMax: Single = TTsScalar.MaxF(Abs(TestDiff.X), Abs(TestDiff.Y));
      if TTsLane.IsLt(PtMax, TestMax) then
      begin
        Outer1 := Index;
        Outer2 := Inner;
        PtMax := TestMax;
      end;
    end;
  end;

  const Mid1 = (1 + (2 shr Outer2)) shr Outer1;
  const Mid2 = Outer1 xor Outer2 xor Mid1;
  const SquaredMax: Single = PtMax * PtMax;
  const LineSlop: Single = SquaredMax * CubicLineSlopMultiplier;

  Result := TTsLane.IsLe(PtToLine(Cubic[Mid1], Cubic[Outer1], Cubic[Outer2]), LineSlop) and
            TTsLane.IsLe(PtToLine(Cubic[Mid2], Cubic[Outer1], Cubic[Outer2]), LineSlop);
end;

function CheckCubicLinear(const Cubic: TTsPoints4; var Reduction: TTsPoints3; out TangentPt: TTsPoint): TTsReductionType;
begin
  TangentPt := TTsPoint.Zero;

  const DegenerateAb = DegenerateVector(Cubic[1] - Cubic[0]);
  const DegenerateBc = DegenerateVector(Cubic[2] - Cubic[1]);
  const DegenerateCd = DegenerateVector(Cubic[3] - Cubic[2]);
  if DegenerateAb and DegenerateBc and DegenerateCd then
  begin
    Exit(TTsReductionType.Point);
  end;

  if Ord(DegenerateAb) + Ord(DegenerateBc) + Ord(DegenerateCd) = 2 then
  begin
    Exit(TTsReductionType.Line);
  end;

  if not CubicInLine(Cubic) then
  begin
    if DegenerateAb then
    begin
      TangentPt := Cubic[2];
    end
    else
    begin
      TangentPt := Cubic[1];
    end;

    Exit(TTsReductionType.Quad);
  end;

  var TValues: TTsNormalizedValues;
  const TCount = TTsPathGeometry.FindCubicMaxCurvature(Cubic, TValues);
  var RCount := 0;
  // Now loop over the t-values, and reject any that evaluate to either end-point
  for var Index := 0 to TCount - 1 do
  begin
    const T = TValues[Index];
    if TTsLane.IsGe(0, T.Get) or TTsLane.IsGe(T.Get, 1) then
    begin
      Continue;
    end;

    Reduction[RCount] := TTsPathGeometry.EvalCubicPosAt(Cubic, T);
    if (Reduction[RCount] <> Cubic[0]) and (Reduction[RCount] <> Cubic[3]) then
    begin
      Inc(RCount);
    end;
  end;

  case RCount of
    0: Result := TTsReductionType.Line;
    1: Result := TTsReductionType.Degenerate;
    2: Result := TTsReductionType.Degenerate2;
    3: Result := TTsReductionType.Degenerate3;
  else
    raise EInvalidOpException.Create('A cubic has at most three points of maximum curvature');
  end;
end;

// Intersect the line with the quad and return the t values on the quad where the line crosses.
function IntersectQuadRay(const Ray0, Ray1: TTsPoint; const Quad: TTsPoints3; var Roots: TTsTValues): Integer;
begin
  const Vec = Ray1 - Ray0;
  var R: array[0..2] of Single;
  for var N := 0 to 2 do
  begin
    const DiffY: Single = Quad[N].Y - Ray0.Y;
    const DiffX: Single = Quad[N].X - Ray0.X;
    const ProductY: Single = DiffY * Vec.X;
    const ProductX: Single = DiffX * Vec.Y;
    R[N] := ProductY - ProductX;
  end;

  var A: Single := R[2];
  var B: Single := R[1];
  const C: Single = R[0];
  const TwoB: Single = Two * B;
  const Rest: Single = C - TwoB;
  A := A + Rest; // A = a - 2*b + c
  B := B - C; // B = -(b - c)

  const DoubleB: Single = Two * B;
  Result := TTsPathGeometry.FindUnitQuadRoots(A, DoubleB, C, Roots);
end;

function PointsWithinDist(const NearPt, FarPt: TTsPoint; const Limit: Single): Boolean;
begin
  const LimitSquared: Single = Limit * Limit;

  Result := TTsLane.IsLe(NearPt.DistanceToSqd(FarPt), LimitSquared);
end;

function SharpAngle(const Quad: TTsPoints3): Boolean;
begin
  var Smaller := Quad[1] - Quad[0];
  var Larger := Quad[1] - Quad[2];
  const SmallerLen: Single = Smaller.LengthSqd;
  var LargerLen: Single := Larger.LengthSqd;
  if TTsLane.IsGt(SmallerLen, LargerLen) then
  begin
    const Swapped = Smaller;
    Smaller := Larger;
    Larger := Swapped;
    LargerLen := SmallerLen;
  end;

  if not Smaller.SetLength(LargerLen) then
  begin
    Exit(False);
  end;

  const Dot: Single = Smaller.Dot(Larger);
  Result := TTsLane.IsGt(Dot, 0);
end;

// Return true if the point is close to the bounds of the quad. This is used as a quick reject.
function PtInQuadBounds(const Quad: TTsPoints3; const Pt: TTsPoint; const InvResScale: Single): Boolean;
begin
  const XMin: Single = TTsScalar.MinF(TTsScalar.MinF(Quad[0].X, Quad[1].X), Quad[2].X);
  if TTsLane.IsLt(Pt.X + InvResScale, XMin) then
  begin
    Exit(False);
  end;

  const XMax: Single = TTsScalar.MaxF(TTsScalar.MaxF(Quad[0].X, Quad[1].X), Quad[2].X);
  if TTsLane.IsGt(Pt.X - InvResScale, XMax) then
  begin
    Exit(False);
  end;

  const YMin: Single = TTsScalar.MinF(TTsScalar.MinF(Quad[0].Y, Quad[1].Y), Quad[2].Y);
  if TTsLane.IsLt(Pt.Y + InvResScale, YMin) then
  begin
    Exit(False);
  end;

  const YMax: Single = TTsScalar.MaxF(TTsScalar.MaxF(Quad[0].Y, Quad[1].Y), Quad[2].Y);
  if TTsLane.IsGt(Pt.Y - InvResScale, YMax) then
  begin
    Exit(False);
  end;

  Result := True;
end;

function SetNormalUnitNormal(const Before, After: TTsPoint; const Scale, Radius: Single; var Normal, UnitNormal: TTsPoint): Boolean;
begin
  const DiffX: Single = After.X - Before.X;
  const DiffY: Single = After.Y - Before.Y;
  if not UnitNormal.SetNormalize(DiffX * Scale, DiffY * Scale) then
  begin
    Exit(False);
  end;

  UnitNormal.RotateCcw;
  Normal := UnitNormal.Scaled(Radius);
  Result := True;
end;

function SetNormalUnitNormal2(const Vec: TTsPoint; const Radius: Single; var Normal, UnitNormal: TTsPoint): Boolean;
begin
  if not UnitNormal.SetNormalize(Vec.X, Vec.Y) then
  begin
    Exit(False);
  end;

  UnitNormal.RotateCcw;
  Normal := UnitNormal.Scaled(Radius);
  Result := True;
end;

// Cappers

procedure ButtCapper(const Pivot, Normal, Stop: TTsPoint; const OtherPath: PTsPathBuilder; var Path: TTsPathBuilder);
begin
  Path.LineTo(Stop.X, Stop.Y);
end;

procedure RoundCapper(const Pivot, Normal, Stop: TTsPoint; const OtherPath: PTsPathBuilder; var Path: TTsPathBuilder);
begin
  var Parallel := Normal;
  Parallel.RotateCw;

  const ProjectedCenter = Pivot + Parallel;

  Path.ConicPointsTo(ProjectedCenter + Normal, ProjectedCenter, TTsScalar.ScalarRoot2Over2);
  Path.ConicPointsTo(ProjectedCenter - Normal, Stop, TTsScalar.ScalarRoot2Over2);
end;

procedure SquareCapper(const Pivot, Normal, Stop: TTsPoint; const OtherPath: PTsPathBuilder; var Path: TTsPathBuilder);
begin
  var Parallel := Normal;
  Parallel.RotateCw;

  if OtherPath <> nil then
  begin
    Path.SetLastPoint(TTsPoint.FromXY(Pivot.X + Normal.X + Parallel.X, Pivot.Y + Normal.Y + Parallel.Y));
    Path.LineTo(Pivot.X - Normal.X + Parallel.X, Pivot.Y - Normal.Y + Parallel.Y);
  end
  else
  begin
    Path.LineTo(Pivot.X + Normal.X + Parallel.X, Pivot.Y + Normal.Y + Parallel.Y);
    Path.LineTo(Pivot.X - Normal.X + Parallel.X, Pivot.Y - Normal.Y + Parallel.Y);
    Path.LineTo(Stop.X, Stop.Y);
  end;
end;

function CapFactory(const Cap: TTsLineCap): TTsCapProc;
begin
  case Cap of
    TTsLineCap.Butt: Result := ButtCapper;
    TTsLineCap.Round: Result := RoundCapper;
  else
    Result := SquareCapper;
  end;
end;

// Joiners

function IsClockwise(const Before, After: TTsPoint): Boolean;
begin
  const Left: Single = Before.X * After.Y;
  const Right: Single = Before.Y * After.X;

  Result := TTsLane.IsGt(Left, Right);
end;

function DotToAngleType(const Dot: Single): TTsAngleType;
begin
  if TTsLane.IsGe(Dot, 0) then
  begin
    // shallow or line
    if TTsScalar.IsNearlyZero(One - Dot) then
    begin
      Result := TTsAngleType.NearlyLine;
    end
    else
    begin
      Result := TTsAngleType.Shallow;
    end;
  end
  else
  begin
    // sharp or 180
    if TTsScalar.IsNearlyZero(One + Dot) then
    begin
      Result := TTsAngleType.Nearly180;
    end
    else
    begin
      Result := TTsAngleType.Sharp;
    end;
  end;
end;

procedure HandleInnerJoin(const Pivot, After: TTsPoint; var Inner: TTsPathBuilder);
begin
  // In the degenerate case that the stroke radius is larger than our segments just connecting the two inner segments may "show through"
  // as a funny diagonal. To pseudo-fix this, we go through the pivot point. This adds an extra point/edge, but I can't see a cheap way to
  // know when this is not needed :(
  Inner.LineTo(Pivot.X, Pivot.Y);

  Inner.LineTo(Pivot.X - After.X, Pivot.Y - After.Y);
end;

procedure BevelJoiner(const BeforeUnitNormal, Pivot, AfterUnitNormal: TTsPoint; const Radius, InvMiterLimit: Single;
                      const PrevIsLine, CurrIsLine: Boolean; Builders: TTsSwappableBuilders);
begin
  var After := AfterUnitNormal.Scaled(Radius);

  if not IsClockwise(BeforeUnitNormal, AfterUnitNormal) then
  begin
    Builders.Swap;
    After := -After;
  end;

  Builders.Outer^.LineTo(Pivot.X + After.X, Pivot.Y + After.Y);
  HandleInnerJoin(Pivot, After, Builders.Inner^);
end;

procedure RoundJoiner(const BeforeUnitNormal, Pivot, AfterUnitNormal: TTsPoint; const Radius, InvMiterLimit: Single;
                      const PrevIsLine, CurrIsLine: Boolean; Builders: TTsSwappableBuilders);
begin
  const DotProd: Single = BeforeUnitNormal.Dot(AfterUnitNormal);
  const AngleType = DotToAngleType(DotProd);

  if AngleType = TTsAngleType.NearlyLine then
  begin
    Exit;
  end;

  var Before := BeforeUnitNormal;
  var After := AfterUnitNormal;
  var Dir := TTsPathDirection.CW;

  if not IsClockwise(Before, After) then
  begin
    Builders.Swap;
    Before := -Before;
    After := -After;
    Dir := TTsPathDirection.CCW;
  end;

  const Ts = TTsTransform.FromRow(Radius, 0, 0, Radius, Pivot.X, Pivot.Y);

  var Conics: array[0..4] of TTsConic;
  var ConicCount: Integer;
  if TTsConic.TryBuildUnitArc(Before, After, Dir, Ts, Conics, ConicCount) then
  begin
    for var Index := 0 to ConicCount - 1 do
    begin
      Builders.Outer^.ConicPointsTo(Conics[Index].Points[1], Conics[Index].Points[2], Conics[Index].Weight);
    end;

    After.Scale(Radius);
    HandleInnerJoin(Pivot, After, Builders.Inner^);
  end;
end;

procedure DoBluntOrClipped(const Builders: TTsSwappableBuilders; const Pivot: TTsPoint; const Radius: Single; const PrevIsLine, CurrIsLine: Boolean;
                           const BeforeNormal, MidNormal, AfterNormal: TTsPoint; const InvMiterLimit: Single; const MiterClip: Boolean);
begin
  var Before := BeforeNormal;
  var Mid := MidNormal;
  var After := AfterNormal;

  After.Scale(Radius);

  if MiterClip then
  begin
    Mid.Normalize;

    const CosBeta: Single = Before.Dot(Mid);
    const SinBeta: Single = Before.Cross(Mid);

    var X: Single;
    if TTsLane.IsLe(Abs(SinBeta), TTsScalar.ScalarNearlyZero) then
    begin
      X := One / InvMiterLimit;
    end
    else
    begin
      const MiterLimit: Single = One / InvMiterLimit;
      const Numerator: Single = MiterLimit - CosBeta;
      X := Numerator / SinBeta;
    end;

    Before.Scale(Radius);

    var BeforeTangent := Before;
    BeforeTangent.RotateCw;

    var AfterTangent := After;
    AfterTangent.RotateCcw;

    const C1 = Pivot + Before + BeforeTangent.Scaled(X);
    const C2 = Pivot + After + AfterTangent.Scaled(X);

    if PrevIsLine then
    begin
      Builders.Outer^.SetLastPoint(C1);
    end
    else
    begin
      Builders.Outer^.LineTo(C1.X, C1.Y);
    end;

    Builders.Outer^.LineTo(C2.X, C2.Y);
  end;

  if not CurrIsLine then
  begin
    Builders.Outer^.LineTo(Pivot.X + After.X, Pivot.Y + After.Y);
  end;

  HandleInnerJoin(Pivot, After, Builders.Inner^);
end;

procedure DoMiter(const Builders: TTsSwappableBuilders; const Pivot: TTsPoint; const Radius: Single; const PrevIsLine, CurrIsLine: Boolean;
                  const Mid, AfterNormal: TTsPoint);
begin
  var After := AfterNormal;
  After.Scale(Radius);

  if PrevIsLine then
  begin
    Builders.Outer^.SetLastPoint(TTsPoint.FromXY(Pivot.X + Mid.X, Pivot.Y + Mid.Y));
  end
  else
  begin
    Builders.Outer^.LineTo(Pivot.X + Mid.X, Pivot.Y + Mid.Y);
  end;

  if not CurrIsLine then
  begin
    Builders.Outer^.LineTo(Pivot.X + After.X, Pivot.Y + After.Y);
  end;

  HandleInnerJoin(Pivot, After, Builders.Inner^);
end;

procedure MiterJoinerInner(const BeforeUnitNormal, Pivot, AfterUnitNormal: TTsPoint; const Radius, InvMiterLimit: Single;
                           const MiterClip, PrevIsLine, IsCurrLine: Boolean; Builders: TTsSwappableBuilders);
begin
  var CurrIsLine := IsCurrLine;

  // negate the dot since we're using normals instead of tangents
  const DotProd: Single = BeforeUnitNormal.Dot(AfterUnitNormal);
  const AngleType = DotToAngleType(DotProd);
  var Before := BeforeUnitNormal;
  var After := AfterUnitNormal;
  var Mid := TTsPoint.Zero;

  if AngleType = TTsAngleType.NearlyLine then
  begin
    Exit;
  end;

  if AngleType = TTsAngleType.Nearly180 then
  begin
    CurrIsLine := False;
    Mid := (After - Before).Scaled(Radius / Two);
    DoBluntOrClipped(Builders, Pivot, Radius, PrevIsLine, CurrIsLine, Before, Mid, After, InvMiterLimit, MiterClip);
    Exit;
  end;

  const Ccw = not IsClockwise(Before, After);
  if Ccw then
  begin
    Builders.Swap;
    Before := -Before;
    After := -After;
  end;

  // Before we enter the world of square-roots and divides, check if we're trying to join an upright right angle (common case for
  // stroking rectangles). If so, special case that (for speed an accuracy).
  // Note: we only need to check one normal if dot==0
  if TTsLane.IsEq(DotProd, 0) and TTsLane.IsLe(InvMiterLimit, TTsScalar.ScalarRoot2Over2) then
  begin
    Mid := (Before + After).Scaled(Radius);
    DoMiter(Builders, Pivot, Radius, PrevIsLine, CurrIsLine, Mid, After);
    Exit;
  end;

  // choose the most accurate way to form the initial mid-vector
  if AngleType = TTsAngleType.Sharp then
  begin
    Mid := TTsPoint.FromXY(After.Y - Before.Y, Before.X - After.X);
    if Ccw then
    begin
      Mid := -Mid;
    end;
  end
  else
  begin
    Mid := TTsPoint.FromXY(Before.X + After.X, Before.Y + After.Y);
  end;

  // midLength = radius / sinHalfAngle
  // if (midLength > miterLimit * radius) abort
  // if (radius / sinHalf > miterLimit * radius) abort
  // if (1 / sinHalf > miterLimit) abort
  // if (1 / miterLimit > sinHalf) abort
  // My dotProd is opposite sign, since it is built from normals and not tangents
  // hence 1 + dot instead of 1 - dot in the formula
  const HalfSum: Single = TTsScalar.Half(One + DotProd);
  const SinHalfAngle: Single = System.Sqrt(HalfSum);
  if TTsLane.IsLt(SinHalfAngle, InvMiterLimit) then
  begin
    CurrIsLine := False;
    DoBluntOrClipped(Builders, Pivot, Radius, PrevIsLine, CurrIsLine, Before, Mid, After, InvMiterLimit, MiterClip);
    Exit;
  end;

  const MidLength: Single = Radius / SinHalfAngle;
  Mid.SetLength(MidLength);
  DoMiter(Builders, Pivot, Radius, PrevIsLine, CurrIsLine, Mid, After);
end;

procedure MiterJoiner(const BeforeUnitNormal, Pivot, AfterUnitNormal: TTsPoint; const Radius, InvMiterLimit: Single;
                      const PrevIsLine, CurrIsLine: Boolean; Builders: TTsSwappableBuilders);
begin
  MiterJoinerInner(BeforeUnitNormal, Pivot, AfterUnitNormal, Radius, InvMiterLimit, False, PrevIsLine, CurrIsLine, Builders);
end;

procedure MiterClipJoiner(const BeforeUnitNormal, Pivot, AfterUnitNormal: TTsPoint; const Radius, InvMiterLimit: Single;
                          const PrevIsLine, CurrIsLine: Boolean; Builders: TTsSwappableBuilders);
begin
  MiterJoinerInner(BeforeUnitNormal, Pivot, AfterUnitNormal, Radius, InvMiterLimit, True, PrevIsLine, CurrIsLine, Builders);
end;

function JoinFactory(const Join: TTsLineJoin): TTsJoinProc;
begin
  case Join of
    TTsLineJoin.Miter: Result := MiterJoiner;
    TTsLineJoin.MiterClip: Result := MiterClipJoiner;
    TTsLineJoin.Round: Result := RoundJoiner;
  else
    Result := BevelJoiner;
  end;
end;

{ TTsPathStroker }

constructor TTsPathStroker.Create;
begin
  inherited Create;

  FRadius := 0;
  FInvMiterLimit := 0;
  FResScale := 1;
  FInvResScale := 1;
  FInvResScaleSquared := 1;

  FFirstNormal := TTsPoint.Zero;
  FPrevNormal := TTsPoint.Zero;
  FFirstUnitNormal := TTsPoint.Zero;
  FPrevUnitNormal := TTsPoint.Zero;

  FFirstPt := TTsPoint.Zero;
  FPrevPt := TTsPoint.Zero;

  FFirstOuterPt := TTsPoint.Zero;
  FFirstOuterPtIndexInContour := 0;
  FSegmentCount := -1;
  FPrevIsLine := False;

  FLineCap := TTsLineCap.Butt;
  FCapper := ButtCapper;
  FJoiner := MiterJoiner;

  FInner := TTsPathBuilder.New;
  FOuter := TTsPathBuilder.New;
  FCusper := TTsPathBuilder.New;

  FStrokeType := TTsStrokeType.Outer;

  FRecursionDepth := 0;
  FFoundTangents := False;
  FJoinCompleted := False;
end;

class function TTsPathStroker.ComputeResolutionScale(const Ts: TTsTransform): Single;
begin
  const Sx: Single = TTsPoint.FromXY(Ts.SX, Ts.KX).Length;
  const Sy: Single = TTsPoint.FromXY(Ts.KY, Ts.SY).Length;
  if TTsScalar.IsFinite(Sx) and TTsScalar.IsFinite(Sy) then
  begin
    const Scale: Single = TTsScalar.MaxF(Sx, Sy);
    if TTsLane.IsGt(Scale, 0) then
    begin
      Exit(Scale);
    end;
  end;

  Result := 1;
end;

function TTsPathStroker.TryStroke(const Path: TTsPath; const Stroke: TTsStroke; const ResolutionScale: Single; out Stroked: TTsPath): Boolean;
begin
  Stroked := Default(TTsPath);

  var Width: TTsNonZeroPositiveF32;
  if not TTsNonZeroPositiveF32.TryCreate(Stroke.Width, Width) then
  begin
    Exit(False);
  end;

  Result := StrokeInner(Path, Width, Stroke.MiterLimit, Stroke.LineCap, Stroke.LineJoin, ResolutionScale, Stroked);
end;

function TTsPathStroker.StrokeInner(const Path: TTsPath; const Width: TTsNonZeroPositiveF32; const MiterLimit: Single;
                                    const LineCap: TTsLineCap; const LineJoin: TTsLineJoin; const ResScale: Single; out Stroked: TTsPath): Boolean;
begin
  Stroked := Default(TTsPath);

  // TODO: stroke_rect optimization
  var InvMiterLimit: Single := 0;
  var Join := LineJoin;

  if Join = TTsLineJoin.Miter then
  begin
    if TTsLane.IsLe(MiterLimit, 1) then
    begin
      Join := TTsLineJoin.Bevel;
    end
    else
    begin
      InvMiterLimit := TTsScalar.Invert(MiterLimit);
    end;
  end;

  if Join = TTsLineJoin.MiterClip then
  begin
    InvMiterLimit := TTsScalar.Invert(MiterLimit);
  end;

  FResScale := ResScale;
  // The '4' below matches the fill scan converter's error term.
  const ScaledRes: Single = ResScale * Four;
  FInvResScale := TTsScalar.Invert(ScaledRes);
  FInvResScaleSquared := TTsScalar.Sqr(FInvResScale);

  FRadius := TTsScalar.Half(Width.Get);
  FInvMiterLimit := InvMiterLimit;

  FFirstNormal := TTsPoint.Zero;
  FPrevNormal := TTsPoint.Zero;
  FFirstUnitNormal := TTsPoint.Zero;
  FPrevUnitNormal := TTsPoint.Zero;

  FFirstPt := TTsPoint.Zero;
  FPrevPt := TTsPoint.Zero;

  FFirstOuterPt := TTsPoint.Zero;
  FFirstOuterPtIndexInContour := 0;
  FSegmentCount := -1;
  FPrevIsLine := False;

  FLineCap := LineCap;
  FCapper := CapFactory(LineCap);
  FJoiner := JoinFactory(Join);

  // Need some estimate of how large our final result (fOuter) and our per-contour temp (fInner) will be, so we don't spend extra time
  // repeatedly growing these arrays.
  //
  // 1x for inner == 'wag' (worst contour length would be better guess)
  FInner.Clear;
  FInner.Reserve(Length(Path.Verbs), Length(Path.Points));

  // 3x for result == inner + outer + join (swag)
  FOuter.Clear;
  FOuter.Reserve(Length(Path.Verbs) * 3, Length(Path.Points) * 3);

  FCusper.Clear;

  FStrokeType := TTsStrokeType.Outer;

  FRecursionDepth := 0;
  FFoundTangents := False;
  FJoinCompleted := False;
  FAborted := False;

  var LastSegmentIsLine := False;
  var Iter := Path.Segments;
  Iter.SetAutoClose(True);

  var Segment: TTsPathSegment;
  while Iter.TryNext(Segment) and not FAborted do
  begin
    case Segment.Verb of
      TTsPathVerb.Move:
      begin
        MoveTo(Segment.P0);
      end;

      TTsPathVerb.Line:
      begin
        LineTo(Segment.P0, @Iter);
        LastSegmentIsLine := True;
      end;

      TTsPathVerb.Quad:
      begin
        QuadTo(Segment.P0, Segment.P1);
        LastSegmentIsLine := False;
      end;

      TTsPathVerb.Cubic:
      begin
        CubicTo(Segment.P0, Segment.P1, Segment.P2);
        LastSegmentIsLine := False;
      end;

      TTsPathVerb.Close:
      begin
        if LineCap <> TTsLineCap.Butt then
        begin
          // If the stroke consists of a moveTo followed by a close, treat it as if it were followed by a zero-length line. Lines
          // without length can have square and round end caps.
          if HasOnlyMoveTo then
          begin
            LineTo(MoveToPt, nil);
            LastSegmentIsLine := True;
            Continue;
          end;

          // If the stroke consists of a moveTo followed by one or more zero-length verbs, then followed by a close, treat is as if it
          // were followed by a zero-length line. Lines without length can have square & round end caps.
          if IsCurrentContourEmpty then
          begin
            LastSegmentIsLine := True;
            Continue;
          end;
        end;

        Close(LastSegmentIsLine);
      end;
    end;
  end;

  if FAborted then
  begin
    Exit(False);
  end;

  Result := Finish(LastSegmentIsLine, Stroked);
end;

function TTsPathStroker.Builders: TTsSwappableBuilders;
begin
  Result.Inner := @FInner;
  Result.Outer := @FOuter;
end;

function TTsPathStroker.MoveToPt: TTsPoint;
begin
  Result := FFirstPt;
end;

procedure TTsPathStroker.MoveTo(const P: TTsPoint);
begin
  if FSegmentCount > 0 then
  begin
    FinishContour(False, False);
  end;

  FSegmentCount := 0;
  FFirstPt := P;
  FPrevPt := P;
  FJoinCompleted := False;
end;

procedure TTsPathStroker.LineTo(const P: TTsPoint; const Iter: PTsPathSegmentsIter);
begin
  const Tolerance: Single = TTsScalar.ScalarNearlyZero * FInvResScale;
  const TeenyLine = FPrevPt.EqualsWithinTolerance(P, Tolerance);
  if (FLineCap = TTsLineCap.Butt) and TeenyLine then
  begin
    Exit;
  end;

  if TeenyLine and (FJoinCompleted or ((Iter <> nil) and Iter^.HasValidTangent)) then
  begin
    Exit;
  end;

  var Normal := TTsPoint.Zero;
  var UnitNormal := TTsPoint.Zero;
  if not PreJoinTo(P, True, Normal, UnitNormal) then
  begin
    Exit;
  end;

  FOuter.LineTo(P.X + Normal.X, P.Y + Normal.Y);
  FInner.LineTo(P.X - Normal.X, P.Y - Normal.Y);

  PostJoinTo(P, Normal, UnitNormal);
end;

procedure TTsPathStroker.QuadTo(const P1, P2: TTsPoint);
begin
  var Quad: TTsPoints3;
  Quad[0] := FPrevPt;
  Quad[1] := P1;
  Quad[2] := P2;

  var Reduction: TTsPoint;
  const ReductionType = CheckQuadLinear(Quad, Reduction);
  if ReductionType = TTsReductionType.Invalid then
  begin
    FAborted := True;
    Exit;
  end;

  if ReductionType = TTsReductionType.Point then
  begin
    // If the stroke consists of a moveTo followed by a degenerate curve, treat it as if it were followed by a zero-length line. Lines
    // without length can have square and round end caps.
    LineTo(P2, nil);
    Exit;
  end;

  if ReductionType = TTsReductionType.Line then
  begin
    LineTo(P2, nil);
    Exit;
  end;

  if ReductionType = TTsReductionType.Degenerate then
  begin
    LineTo(Reduction, nil);
    const SaveJoiner = FJoiner;
    FJoiner := RoundJoiner;
    LineTo(P2, nil);
    FJoiner := SaveJoiner;
    Exit;
  end;

  var NormalAb := TTsPoint.Zero;
  var UnitAb := TTsPoint.Zero;
  var NormalBc := TTsPoint.Zero;
  var UnitBc := TTsPoint.Zero;
  if not PreJoinTo(P1, False, NormalAb, UnitAb) then
  begin
    LineTo(P2, nil);
    Exit;
  end;

  var QuadPoints := Default(TTsQuadConstruct);
  InitQuad(TTsStrokeType.Outer, TTsNormalizedF32.Zero, TTsNormalizedF32.One, QuadPoints);
  QuadStroke(Quad, QuadPoints);
  InitQuad(TTsStrokeType.Inner, TTsNormalizedF32.Zero, TTsNormalizedF32.One, QuadPoints);
  QuadStroke(Quad, QuadPoints);

  const Ok = SetNormalUnitNormal(Quad[1], Quad[2], FResScale, FRadius, NormalBc, UnitBc);
  if not Ok then
  begin
    NormalBc := NormalAb;
    UnitBc := UnitAb;
  end;

  PostJoinTo(P2, NormalBc, UnitBc);
end;

procedure TTsPathStroker.CubicTo(const Pt1, Pt2, Pt3: TTsPoint);
begin
  var Cubic: TTsPoints4;
  Cubic[0] := FPrevPt;
  Cubic[1] := Pt1;
  Cubic[2] := Pt2;
  Cubic[3] := Pt3;

  var Reduction: TTsPoints3;
  Reduction[0] := TTsPoint.Zero;
  Reduction[1] := TTsPoint.Zero;
  Reduction[2] := TTsPoint.Zero;
  var TangentPt: TTsPoint;
  const ReductionType = CheckCubicLinear(Cubic, Reduction, TangentPt);
  if ReductionType = TTsReductionType.Point then
  begin
    // If the stroke consists of a moveTo followed by a degenerate curve, treat it as if it were followed by a zero-length line. Lines
    // without length can have square and round end caps.
    LineTo(Pt3, nil);
    Exit;
  end;

  if ReductionType = TTsReductionType.Line then
  begin
    LineTo(Pt3, nil);
    Exit;
  end;

  if (TTsReductionType.Degenerate <= ReductionType) and (TTsReductionType.Degenerate3 >= ReductionType) then
  begin
    LineTo(Reduction[0], nil);
    const SaveJoiner = FJoiner;
    FJoiner := RoundJoiner;
    if TTsReductionType.Degenerate2 <= ReductionType then
    begin
      LineTo(Reduction[1], nil);
    end;

    if TTsReductionType.Degenerate3 = ReductionType then
    begin
      LineTo(Reduction[2], nil);
    end;

    LineTo(Pt3, nil);
    FJoiner := SaveJoiner;
    Exit;
  end;

  var NormalAb := TTsPoint.Zero;
  var UnitAb := TTsPoint.Zero;
  var NormalCd := TTsPoint.Zero;
  var UnitCd := TTsPoint.Zero;
  if not PreJoinTo(TangentPt, False, NormalAb, UnitAb) then
  begin
    LineTo(Pt3, nil);
    Exit;
  end;

  var TValues := TTsPathGeometry.NewTValues;
  const TCount = TTsPathGeometry.FindCubicInflections(Cubic, TValues);
  var LastT := TTsNormalizedF32.Zero;
  for var Index := 0 to TCount do
  begin
    var NextT := TTsNormalizedF32.One;
    if Index < TCount then
    begin
      NextT := TValues[Index].ToNormalized;
    end;

    var QuadPoints := Default(TTsQuadConstruct);
    InitQuad(TTsStrokeType.Outer, LastT, NextT, QuadPoints);
    CubicStroke(Cubic, QuadPoints);
    InitQuad(TTsStrokeType.Inner, LastT, NextT, QuadPoints);
    CubicStroke(Cubic, QuadPoints);
    LastT := NextT;
  end;

  var Cusp: TTsNormalizedF32Exclusive;
  if TTsPathGeometry.TryFindCubicCusp(Cubic, Cusp) then
  begin
    const CuspLoc = TTsPathGeometry.EvalCubicPosAt(Cubic, Cusp.ToNormalized);
    FCusper.PushCircle(CuspLoc.X, CuspLoc.Y, FRadius);
  end;

  // emit the join even if one stroke succeeded but the last one failed
  // this avoids reversing an inner stroke with a partial path followed by another moveto
  SetCubicEndNormal(Cubic, NormalAb, UnitAb, NormalCd, UnitCd);

  PostJoinTo(Pt3, NormalCd, UnitCd);
end;

function TTsPathStroker.CubicStroke(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): Boolean;
begin
  if not FFoundTangents then
  begin
    const ResultType = TangentsMeet(Cubic, QuadPoints);
    if ResultType <> TTsResultType.Quad then
    begin
      const Ok = PointsWithinDist(QuadPoints.Quad[0], QuadPoints.Quad[2], FInvResScale);
      if ((ResultType = TTsResultType.Degenerate) or Ok) and CubicMidOnLine(Cubic, QuadPoints) then
      begin
        AddDegenerateLine(QuadPoints);
        Exit(True);
      end;
    end
    else
    begin
      FFoundTangents := True;
    end;
  end;

  if FFoundTangents then
  begin
    const ResultType = CompareQuadCubic(Cubic, QuadPoints);
    if ResultType = TTsResultType.Quad then
    begin
      if FStrokeType = TTsStrokeType.Outer then
      begin
        FOuter.QuadTo(QuadPoints.Quad[1].X, QuadPoints.Quad[1].Y, QuadPoints.Quad[2].X, QuadPoints.Quad[2].Y);
      end
      else
      begin
        FInner.QuadTo(QuadPoints.Quad[1].X, QuadPoints.Quad[1].Y, QuadPoints.Quad[2].X, QuadPoints.Quad[2].Y);
      end;

      Exit(True);
    end;

    if ResultType = TTsResultType.Degenerate then
    begin
      if not QuadPoints.OppositeTangents then
      begin
        AddDegenerateLine(QuadPoints);
        Exit(True);
      end;
    end;
  end;

  // The Rust code tests the x of quad[2] twice
  if (not TTsScalar.IsFinite(QuadPoints.Quad[2].X)) or (not TTsScalar.IsFinite(QuadPoints.Quad[2].X)) then
  begin
    Exit(False); // just abort if projected quad isn't representable
  end;

  Inc(FRecursionDepth);
  if FRecursionDepth > RecursiveLimits[Ord(FFoundTangents)] then
  begin
    Exit(False); // just abort if projected quad isn't representable
  end;

  var Half := Default(TTsQuadConstruct);
  if not Half.InitWithStart(QuadPoints) then
  begin
    AddDegenerateLine(QuadPoints);
    Dec(FRecursionDepth);
    Exit(True);
  end;

  if not CubicStroke(Cubic, Half) then
  begin
    Exit(False);
  end;

  if not Half.InitWithEnd(QuadPoints) then
  begin
    AddDegenerateLine(QuadPoints);
    Dec(FRecursionDepth);
    Exit(True);
  end;

  if not CubicStroke(Cubic, Half) then
  begin
    Exit(False);
  end;

  Dec(FRecursionDepth);
  Result := True;
end;

function TTsPathStroker.CubicMidOnLine(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): Boolean;
begin
  var StrokeMid: TTsPoint;
  CubicQuadMid(Cubic, QuadPoints, StrokeMid);
  const Dist: Single = PtToLine(StrokeMid, QuadPoints.Quad[0], QuadPoints.Quad[2]);

  Result := TTsLane.IsLt(Dist, FInvResScaleSquared);
end;

procedure TTsPathStroker.CubicQuadMid(const Cubic: TTsPoints4; const QuadPoints: TTsQuadConstruct; out Mid: TTsPoint);
begin
  var CubicMidPt: TTsPoint;
  CubicPerpRay(Cubic, QuadPoints.MidT, CubicMidPt, Mid, nil);
end;

procedure TTsPathStroker.CubicPerpRay(const Cubic: TTsPoints4; const T: TTsNormalizedF32; out TPt, OnPt: TTsPoint;
                                      const Tangent: PTsStrokerPoint);
begin
  TPt := TTsPathGeometry.EvalCubicPosAt(Cubic, T);
  var Dxy := TTsPathGeometry.EvalCubicTangentAt(Cubic, T);

  var Chopped: TTsPoints7;
  var UseChopped := False;
  if TTsLane.IsEq(Dxy.X, 0) and TTsLane.IsEq(Dxy.Y, 0) then
  begin
    if TTsScalar.IsNearlyZero(T.Get) then
    begin
      Dxy := Cubic[2] - Cubic[0];
    end
    else if TTsScalar.IsNearlyZero(One - T.Get) then
    begin
      Dxy := Cubic[3] - Cubic[1];
    end
    else
    begin
      // If the cubic inflection falls on the cusp, subdivide the cubic to find the tangent at that point.
      //
      // The value is never 0 or 1, because we already checked that `t` is not nearly 0 or 1.
      var Exclusive: TTsNormalizedF32Exclusive;
      if not TTsNormalizedF32Exclusive.TryCreate(T.Get, Exclusive) then
      begin
        Exclusive := TTsNormalizedF32Exclusive.CreateBounded(T.Get);
      end;

      TTsPathGeometry.ChopCubicAt2(Cubic, Exclusive, Chopped);
      Dxy := Chopped[3] - Chopped[2];
      if TTsLane.IsEq(Dxy.X, 0) and TTsLane.IsEq(Dxy.Y, 0) then
      begin
        Dxy := Chopped[3] - Chopped[1];
        UseChopped := True;
      end;
    end;

    if TTsLane.IsEq(Dxy.X, 0) and TTsLane.IsEq(Dxy.Y, 0) then
    begin
      // c_points[3] - c_points[0] where c_points is the cubic, or the chopped cubic
      if UseChopped then
      begin
        Dxy := Chopped[3] - Chopped[0];
      end
      else
      begin
        Dxy := Cubic[3] - Cubic[0];
      end;
    end;
  end;

  SetRayPoints(TPt, Dxy, OnPt, Tangent);
end;

procedure TTsPathStroker.SetCubicEndNormal(const Cubic: TTsPoints4; const NormalAb, UnitNormalAb: TTsPoint; out NormalCd, UnitNormalCd: TTsPoint);
begin
  NormalCd := TTsPoint.Zero;
  UnitNormalCd := TTsPoint.Zero;

  var Ab := Cubic[1] - Cubic[0];
  var Cd := Cubic[3] - Cubic[2];

  var DegenerateAb := DegenerateVector(Ab);
  var DegenerateCb := DegenerateVector(Cd);

  if DegenerateAb and DegenerateCb then
  begin
    NormalCd := NormalAb;
    UnitNormalCd := UnitNormalAb;
    Exit;
  end;

  if DegenerateAb then
  begin
    Ab := Cubic[2] - Cubic[0];
    DegenerateAb := DegenerateVector(Ab);
  end;

  if DegenerateCb then
  begin
    Cd := Cubic[3] - Cubic[1];
    DegenerateCb := DegenerateVector(Cd);
  end;

  if DegenerateAb or DegenerateCb then
  begin
    NormalCd := NormalAb;
    UnitNormalCd := UnitNormalAb;
    Exit;
  end;

  SetNormalUnitNormal2(Cd, FRadius, NormalCd, UnitNormalCd);
end;

function TTsPathStroker.CompareQuadCubic(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): TTsResultType;
begin
  // get the quadratic approximation of the stroke
  CubicQuadEnds(Cubic, QuadPoints);
  Result := IntersectRay(TTsIntersectRayType.CtrlPt, QuadPoints);
  if Result <> TTsResultType.Quad then
  begin
    Exit;
  end;

  // project a ray from the curve to the stroke
  // points near midpoint on quad, midpoint on cubic
  var Ray0: TTsPoint;
  var Ray1: TTsPoint;
  CubicPerpRay(Cubic, QuadPoints.MidT, Ray1, Ray0, nil);
  Result := StrokeCloseEnough(QuadPoints.Quad, Ray0, Ray1, QuadPoints);
end;

procedure TTsPathStroker.CubicQuadEnds(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct);
begin
  if not QuadPoints.StartSet then
  begin
    var CubicStartPt: TTsPoint;
    CubicPerpRay(Cubic, QuadPoints.StartT, CubicStartPt, QuadPoints.Quad[0], @QuadPoints.TangentStart);
    QuadPoints.StartSet := True;
  end;

  if not QuadPoints.EndSet then
  begin
    var CubicEndPt: TTsPoint;
    CubicPerpRay(Cubic, QuadPoints.EndT, CubicEndPt, QuadPoints.Quad[2], @QuadPoints.TangentEnd);
    QuadPoints.EndSet := True;
  end;
end;

procedure TTsPathStroker.Close(const IsLine: Boolean);
begin
  FinishContour(True, IsLine);
end;

procedure TTsPathStroker.FinishContour(const Close, CurrIsLine: Boolean);
begin
  if FSegmentCount > 0 then
  begin
    if Close then
    begin
      FJoiner(FPrevUnitNormal, FPrevPt, FFirstUnitNormal, FRadius, FInvMiterLimit, FPrevIsLine, CurrIsLine, Builders);
      FOuter.Close;

      // now add inner as its own contour
      var Pt: TTsPoint;
      if not FInner.TryLastPoint(Pt) then
      begin
        Pt := TTsPoint.Zero;
      end;

      FOuter.MoveTo(Pt.X, Pt.Y);
      FOuter.ReversePathTo(FInner);
      FOuter.Close;
    end
    else
    begin
      // add caps to start and end

      // cap the end
      var Pt: TTsPoint;
      if not FInner.TryLastPoint(Pt) then
      begin
        Pt := TTsPoint.Zero;
      end;

      var OtherPath: PTsPathBuilder := nil;
      if CurrIsLine then
      begin
        OtherPath := @FInner;
      end;

      FCapper(FPrevPt, FPrevNormal, Pt, OtherPath, FOuter);
      FOuter.ReversePathTo(FInner);

      // cap the start
      OtherPath := nil;
      if FPrevIsLine then
      begin
        OtherPath := @FInner;
      end;

      FCapper(FFirstPt, -FFirstNormal, FFirstOuterPt, OtherPath, FOuter);
      FOuter.Close;
    end;

    if not FCusper.IsEmpty then
    begin
      FOuter.PushPathBuilder(FCusper);
      FCusper.Clear;
    end;
  end;

  // since we may re-use `inner`, we rewind instead of reset, to save on reallocating its internal storage.
  FInner.Clear;
  FSegmentCount := -1;
  FFirstOuterPtIndexInContour := FOuter.PointCount;
end;

function TTsPathStroker.PreJoinTo(const P: TTsPoint; const CurrIsLine: Boolean; var Normal, UnitNormal: TTsPoint): Boolean;
begin
  const PrevX: Single = FPrevPt.X;
  const PrevY: Single = FPrevPt.Y;

  const NormalSet = SetNormalUnitNormal(FPrevPt, P, FResScale, FRadius, Normal, UnitNormal);
  if not NormalSet then
  begin
    if FLineCap = TTsLineCap.Butt then
    begin
      Exit(False);
    end;

    // Square caps and round caps draw even if the segment length is zero. Since the zero length segment has no direction, set the
    // orientation to upright as the default orientation.
    Normal := TTsPoint.FromXY(FRadius, 0);
    UnitNormal := TTsPoint.FromXY(1, 0);
  end;

  if FSegmentCount = 0 then
  begin
    FFirstNormal := Normal;
    FFirstUnitNormal := UnitNormal;
    FFirstOuterPt := TTsPoint.FromXY(PrevX + Normal.X, PrevY + Normal.Y);

    FOuter.MoveTo(FFirstOuterPt.X, FFirstOuterPt.Y);
    FInner.MoveTo(PrevX - Normal.X, PrevY - Normal.Y);
  end
  else
  begin
    // we have a previous segment
    FJoiner(FPrevUnitNormal, FPrevPt, UnitNormal, FRadius, FInvMiterLimit, FPrevIsLine, CurrIsLine, Builders);
  end;

  FPrevIsLine := CurrIsLine;
  Result := True;
end;

procedure TTsPathStroker.PostJoinTo(const P, Normal, UnitNormal: TTsPoint);
begin
  FJoinCompleted := True;
  FPrevPt := P;
  FPrevUnitNormal := UnitNormal;
  FPrevNormal := Normal;
  Inc(FSegmentCount);
end;

procedure TTsPathStroker.InitQuad(const StrokeType: TTsStrokeType; const Start, Stop: TTsNormalizedF32; var QuadPoints: TTsQuadConstruct);
begin
  FStrokeType := StrokeType;
  FFoundTangents := False;
  QuadPoints.Init(Start, Stop);
end;

function TTsPathStroker.QuadStroke(const Quad: TTsPoints3; var QuadPoints: TTsQuadConstruct): Boolean;
begin
  const ResultType = CompareQuadQuad(Quad, QuadPoints);
  if ResultType = TTsResultType.Quad then
  begin
    if FStrokeType = TTsStrokeType.Outer then
    begin
      FOuter.QuadTo(QuadPoints.Quad[1].X, QuadPoints.Quad[1].Y, QuadPoints.Quad[2].X, QuadPoints.Quad[2].Y);
    end
    else
    begin
      FInner.QuadTo(QuadPoints.Quad[1].X, QuadPoints.Quad[1].Y, QuadPoints.Quad[2].X, QuadPoints.Quad[2].Y);
    end;

    Exit(True);
  end;

  if ResultType = TTsResultType.Degenerate then
  begin
    AddDegenerateLine(QuadPoints);
    Exit(True);
  end;

  Inc(FRecursionDepth);
  if FRecursionDepth > RecursiveLimits[QuadRecursiveLimit] then
  begin
    Exit(False); // just abort if projected quad isn't representable
  end;

  var Half := Default(TTsQuadConstruct);
  Half.InitWithStart(QuadPoints);
  if not QuadStroke(Quad, Half) then
  begin
    Exit(False);
  end;

  Half.InitWithEnd(QuadPoints);
  if not QuadStroke(Quad, Half) then
  begin
    Exit(False);
  end;

  Dec(FRecursionDepth);
  Result := True;
end;

function TTsPathStroker.CompareQuadQuad(const Quad: TTsPoints3; var QuadPoints: TTsQuadConstruct): TTsResultType;
begin
  // get the quadratic approximation of the stroke
  if not QuadPoints.StartSet then
  begin
    var QuadStartPt: TTsPoint;
    QuadPerpRay(Quad, QuadPoints.StartT, QuadStartPt, QuadPoints.Quad[0], @QuadPoints.TangentStart);
    QuadPoints.StartSet := True;
  end;

  if not QuadPoints.EndSet then
  begin
    var QuadEndPt: TTsPoint;
    QuadPerpRay(Quad, QuadPoints.EndT, QuadEndPt, QuadPoints.Quad[2], @QuadPoints.TangentEnd);
    QuadPoints.EndSet := True;
  end;

  Result := IntersectRay(TTsIntersectRayType.CtrlPt, QuadPoints);
  if Result <> TTsResultType.Quad then
  begin
    Exit;
  end;

  // project a ray from the curve to the stroke
  var Ray0: TTsPoint;
  var Ray1: TTsPoint;
  QuadPerpRay(Quad, QuadPoints.MidT, Ray1, Ray0, nil);
  Result := StrokeCloseEnough(QuadPoints.Quad, Ray0, Ray1, QuadPoints);
end;

procedure TTsPathStroker.SetRayPoints(const Tp: TTsPoint; var Dxy: TTsPoint; out OnP: TTsPoint; const Tangent: PTsStrokerPoint);
begin
  if not Dxy.SetLength(FRadius) then
  begin
    Dxy := TTsPoint.FromXY(FRadius, 0);
  end;

  // go opposite ways for outer, inner
  var AxisFlip: Single := 1;
  if FStrokeType = TTsStrokeType.Inner then
  begin
    AxisFlip := -1;
  end;

  const FlipY: Single = AxisFlip * Dxy.Y;
  const FlipX: Single = AxisFlip * Dxy.X;
  OnP.X := Tp.X + FlipY;
  OnP.Y := Tp.Y - FlipX;

  if Tangent <> nil then
  begin
    Tangent^.X := OnP.X + Dxy.X;
    Tangent^.Y := OnP.Y + Dxy.Y;
  end;
end;

procedure TTsPathStroker.QuadPerpRay(const Quad: TTsPoints3; const T: TTsNormalizedF32; out Tp, OnP: TTsPoint; const Tangent: PTsStrokerPoint);
begin
  Tp := TTsPathGeometry.EvalQuadAt(Quad, T);
  var Dxy := TTsPathGeometry.EvalQuadTangentAt(Quad, T);

  if Dxy.IsZero then
  begin
    Dxy := Quad[2] - Quad[0];
  end;

  SetRayPoints(Tp, Dxy, OnP, Tangent);
end;

procedure TTsPathStroker.AddDegenerateLine(const QuadPoints: TTsQuadConstruct);
begin
  if FStrokeType = TTsStrokeType.Outer then
  begin
    FOuter.LineTo(QuadPoints.Quad[2].X, QuadPoints.Quad[2].Y);
  end
  else
  begin
    FInner.LineTo(QuadPoints.Quad[2].X, QuadPoints.Quad[2].Y);
  end;
end;

function TTsPathStroker.StrokeCloseEnough(const Stroke: TTsPoints3; const Ray0, Ray1: TTsPoint; const QuadPoints: TTsQuadConstruct): TTsResultType;
begin
  const Half = TTsNormalizedF32.CreateClamped(HalfValue);
  const StrokeMid = TTsPathGeometry.EvalQuadAt(Stroke, Half);
  // measure the distance from the curve to the quad-stroke midpoint, compare to radius
  if PointsWithinDist(Ray0, StrokeMid, FInvResScale) then
  begin
    // if the difference is small
    if SharpAngle(QuadPoints.Quad) then
    begin
      Exit(TTsResultType.Split);
    end;

    Exit(TTsResultType.Quad);
  end;

  // measure the distance to quad's bounds (quick reject)
  // an alternative : look for point in triangle
  if not PtInQuadBounds(Stroke, Ray0, FInvResScale) then
  begin
    // if far, subdivide
    Exit(TTsResultType.Split);
  end;

  // measure the curve ray distance to the quad-stroke
  var Roots := TTsPathGeometry.NewTValues;
  const RootCount = IntersectQuadRay(Ray0, Ray1, Stroke, Roots);
  if RootCount <> 1 then
  begin
    Exit(TTsResultType.Split);
  end;

  const QuadPt = TTsPathGeometry.EvalQuadAt(Stroke, Roots[0].ToNormalized);
  const FromMid: Single = Roots[0].Get - HalfValue;
  const Scaled: Single = Abs(FromMid) * Two;
  const Remaining: Single = One - Scaled;
  const Error: Single = FInvResScale * Remaining;
  if PointsWithinDist(Ray0, QuadPt, Error) then
  begin
    // if the difference is small, we're done
    if SharpAngle(QuadPoints.Quad) then
    begin
      Exit(TTsResultType.Split);
    end;

    Exit(TTsResultType.Quad);
  end;

  // otherwise, subdivide
  Result := TTsResultType.Split;
end;

function TTsPathStroker.IntersectRay(const IntersectRayType: TTsIntersectRayType; var QuadPoints: TTsQuadConstruct): TTsResultType;
begin
  const Start = QuadPoints.Quad[0];
  const Stop = QuadPoints.Quad[2];
  const ALen = QuadPoints.TangentStart - Start;
  const BLen = QuadPoints.TangentEnd - Stop;

  // Slopes match when denom goes to zero:
  //                   axLen / ayLen ==                   bxLen / byLen
  // (ayLen * byLen) * axLen / ayLen == (ayLen * byLen) * bxLen / byLen
  //          byLen  * axLen         ==  ayLen          * bxLen
  //          byLen  * axLen         -   ayLen          * bxLen         ( == denom )
  const Denom: Single = ALen.Cross(BLen);
  if TTsLane.IsEq(Denom, 0) or (not TTsScalar.IsFinite(Denom)) then
  begin
    QuadPoints.OppositeTangents := TTsLane.IsLt(ALen.Dot(BLen), 0);
    Exit(TTsResultType.Degenerate);
  end;

  QuadPoints.OppositeTangents := False;
  const Ab0 = Start - Stop;
  var NumerA: Single := BLen.Cross(Ab0);
  const NumerB: Single = ALen.Cross(Ab0);
  if TTsLane.IsGe(NumerA, 0) = TTsLane.IsGe(NumerB, 0) then
  begin
    // if the control point is outside the quad ends

    // if the perpendicular distances from the quad points to the opposite tangent line are small, a straight line is good enough
    const Dist1: Single = PtToLine(Start, Stop, QuadPoints.TangentEnd);
    const Dist2: Single = PtToLine(Stop, Start, QuadPoints.TangentStart);
    if TTsLane.IsLe(TTsScalar.MaxF(Dist1, Dist2), FInvResScaleSquared) then
    begin
      Exit(TTsResultType.Degenerate);
    end;

    Exit(TTsResultType.Split);
  end;

  // check to see if the denominator is teeny relative to the numerator
  // if the offset by one will be lost, the ratio is too large
  NumerA := NumerA / Denom;
  const Shifted: Single = NumerA - One;
  const ValidDivide = TTsLane.IsGt(NumerA, Shifted);
  if ValidDivide then
  begin
    if IntersectRayType = TTsIntersectRayType.CtrlPt then
    begin
      // the intersection of the tangents need not be on the tangent segment so 0 <= numer_a <= 1 is not necessarily true
      const OneMinusA: Single = One - NumerA;
      const StartX: Single = Start.X * OneMinusA;
      const TangentX: Single = QuadPoints.TangentStart.X * NumerA;
      const StartY: Single = Start.Y * OneMinusA;
      const TangentY: Single = QuadPoints.TangentStart.Y * NumerA;
      QuadPoints.Quad[1].X := StartX + TangentX;
      QuadPoints.Quad[1].Y := StartY + TangentY;
    end;

    Exit(TTsResultType.Quad);
  end;

  QuadPoints.OppositeTangents := TTsLane.IsLt(ALen.Dot(BLen), 0);

  // if the lines are parallel, straight line is good enough
  Result := TTsResultType.Degenerate;
end;

function TTsPathStroker.TangentsMeet(const Cubic: TTsPoints4; var QuadPoints: TTsQuadConstruct): TTsResultType;
begin
  CubicQuadEnds(Cubic, QuadPoints);
  Result := IntersectRay(TTsIntersectRayType.ResultType, QuadPoints);
end;

function TTsPathStroker.Finish(const IsLine: Boolean; out Stroked: TTsPath): Boolean;
begin
  FinishContour(False, IsLine);

  // Swap out the outer builder.
  var Buf := FOuter;
  FOuter := TTsPathBuilder.New;

  Result := Buf.TryFinish(Stroked);
end;

function TTsPathStroker.HasOnlyMoveTo: Boolean;
begin
  Result := (FSegmentCount = 0);
end;

function TTsPathStroker.IsCurrentContourEmpty: Boolean;
begin
  Result := FInner.IsZeroLengthSincePoint(0) and FOuter.IsZeroLengthSincePoint(FFirstOuterPtIndexInContour);
end;

{ TTsPathStrokeHelper }

function TTsPathStrokeHelper.TryStroke(const Stroke: TTsStroke; const ResolutionScale: Single; out Stroked: TTsPath): Boolean;
begin
  const Stroker = TTsPathStroker.Create;
  try
    Result := Stroker.TryStroke(Self, Stroke, ResolutionScale, Stroked);
  finally
    Stroker.Free;
  end;
end;

function TTsPathStrokeHelper.TryDash(const Dash: TTsStrokeDash; const ResScale: Single; out Dashed: TTsPath): Boolean;
begin
  Result := TryDashPath(Self, Dash, ResScale, Dashed);
end;

end.
