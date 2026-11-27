// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/dash.rs
// Copyright (c) 2014 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Dash;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.PathGeometry,
  Pdf4D.Render.Native.Path;

// This module is a mix of SkDashPath, SkDashPathEffect, SkContourMeasure and SkPathMeasure.
//
// Path.dash is the record helper TTsPathDashHelper (TTsPath is declared in the Path unit). A record type has one active helper in a unit:
// the helper of Pdf4D.Render.Native.Stroker has TryStroke and TryDash, so a unit that needs both uses the Stroker unit after this one.
//
// The Rust ContourMeasureIter is an iterator over the contours of a path; it is the record TTsContourMeasureIter of the implementation with
// TryNext. compute_pos_tan keeps the optional tangent of the Rust code as a nil-able pointer.

type
  // A stroke dashing properties.
  //
  // Contains an array of pairs, where the first number indicates an "on" interval and the second one indicates an "off" interval; a dash
  // offset value and internal properties.
  //
  // Guarantees:
  // - The dash array always have an even number of values.
  // - All dash array values are finite and >= 0.
  // - There is at least two dash array values.
  // - The sum of all dash array values is positive and finite.
  // - Dash offset is finite.
  TTsStrokeDash = record
  private
    FArray: TArray<Single>;
    FOffset: Single;
    FIntervalLen: TTsNonZeroPositiveF32;
    FFirstLen: Single;
    FFirstIndex: Integer;

    class function AdjustDashOffset(const Offset, Len: Single): Single; static;
    class function FindFirstInterval(const DashArray: TArray<Single>; const DashOffset: Single; out FirstLen: Single): Integer; static;

  public
    // Creates a new stroke dashing object. Returns False for an invalid dash array or offset.
    class function TryCreate(const Intervals: TArray<Single>; const Offset: Single; out Dash: TTsStrokeDash): Boolean; static;
  end;

  // The dashed path of Src; the Rust Path.dash. TTsPathDashHelper.TryDash and the helper of the Stroker unit call it.
  //
  // ResScale can be obtained via TTsPathStroker.ComputeResolutionScale.
  //
  // Returns False when more than 1_000_000 dashes had to be produced or when the final path has an invalid bounding box.
function TryDashPath(const Src: TTsPath; const Dash: TTsStrokeDash; const ResScale: Single; out Dashed: TTsPath): Boolean;

type
  TTsPathDashHelper = record helper for TTsPath
    // Converts the current path into a dashed one.
    //
    // ResScale can be obtained via TTsPathStroker.ComputeResolutionScale.
    //
    // Returns False when more than 1_000_000 dashes had to be produced or when the final path has an invalid bounding box.
    function TryDash(const Dash: TTsStrokeDash; const ResScale: Single; out Dashed: TTsPath): Boolean;
  end;

implementation

const
  MaxDashCount = 1000000;
  MaxTValue: Cardinal = $3FFFFFFF;
  // 1.0 / MAX_T_VALUE as f32: MAX_T_VALUE as f32 is 2^30 (the nearest f32 of 0x3FFFFFFF), so this is 2^-30
  MaxTReciprocal: Single = 1 / 1073741824;
  // can't use tangents, since we need [0..1..................2] to be seen as definitely not a line (it is when drawn, but not
  // parametrically) so we compare midpoints
  CheapDistLimit: Single = 0.5; // just made this value up
  OneThird: Single = 1 / 3;
  TwoThirds: Single = 2 / 3;
  One: Single = 1;

type
  TTsSegmentKind = (
    Line,
    Quad,
    Cubic);

  TTsDashSegment = record
    Distance: Single; // total distance up to this point
    PointIndex: Integer; // index into the TTsContourMeasure.Points array
    TValue: Cardinal;
    Kind: TTsSegmentKind;

    function ScalarT: Single;
  end;

  TTsContourMeasure = record
  public
    Segments: TArray<TTsDashSegment>;
    SegmentCount: Integer;
    Points: TArray<TTsPoint>;
    PointCount: Integer;
    TotalLength: Single;
    IsClosed: Boolean;

    procedure AddPoint(const Pt: TTsPoint);
    procedure AddSegment(const Distance: Single; const PointIndex: Integer; const TValue: Cardinal; const Kind: TTsSegmentKind);

    procedure PushSegment(const StartDistance, StopDistance: Single; const StartWithMoveTo: Boolean; var Pb: TTsPathBuilder);
    function TryDistanceToSegment(const Distance: Single; out SegmentIndex: Integer; out T: TTsNormalizedF32): Boolean;
    function ComputeLineSeg(const P0, P1: TTsPoint; const Distance: Single; const PointIndex: Integer): Single;
    function ComputeQuadSegs(const P0, P1, P2: TTsPoint; const Distance: Single; const MinT, MaxT: Cardinal; const PointIndex: Integer;
                             const Tolerance: Single): Single;
    function ComputeCubicSegs(const P0, P1, P2, P3: TTsPoint; const Distance: Single; const MinT, MaxT: Cardinal; const PointIndex: Integer;
                              const Tolerance: Single): Single;
  end;

  TTsContourMeasureIter = record
  private
    FIter: TTsPathSegmentsIter;
    FTolerance: Single;

  public
    class function Create(const Path: TTsPath; const ResScale: Single): TTsContourMeasureIter; static;

    // If it encounters a zero-length contour, it is skipped.
    function TryNext(out Contour: TTsContourMeasure): Boolean;
  end;

  PTsDashPoint = ^TTsPoint;

// Linearly interpolate between A and B, based on t.
//
// If t is 0, return A. If t is 1, return B else interpolate.
function Interp(const A, B: Single; const T: TTsNormalizedF32): Single;
begin
  const Delta: Single = B - A;
  const Scaled: Single = Delta * T.Get;

  Result := A + Scaled;
end;

function InterpSafe(const A, B, T: Single): Single;
begin
  const Delta: Single = B - A;
  const Scaled: Single = Delta * T;

  Result := A + Scaled;
end;

function TTsDashSegment.ScalarT: Single;
begin
  // 1/kMaxTValue can't be represented as a float, but it's close and the limits work fine.
  const Whole: Single = TValue;

  Result := Whole * MaxTReciprocal;
end;

{ TTsStrokeDash }

// Adjust phase to be between 0 and len, "flipping" phase if negative.
// e.g., if len is 100, then phase of -20 (or -120) is equivalent to 80.
class function TTsStrokeDash.AdjustDashOffset(const Offset, Len: Single): Single;
begin
  var Adjusted: Single := Offset;

  if Adjusted < 0 then
  begin
    Adjusted := -Adjusted;
    if Adjusted > Len then
    begin
      Adjusted := TTsScalar.RemainderF(Adjusted, Len);
    end;

    Adjusted := Len - Adjusted;

    // Due to finite precision, it's possible that phase == len, even after the subtract (if len >>> phase), so fix that here.
    if Adjusted = Len then
    begin
      Adjusted := 0;
    end;

    Result := Adjusted;
  end
  else if Adjusted >= Len then
  begin
    Result := TTsScalar.RemainderF(Adjusted, Len);
  end
  else
  begin
    Result := Adjusted;
  end;
end;

class function TTsStrokeDash.FindFirstInterval(const DashArray: TArray<Single>; const DashOffset: Single; out FirstLen: Single): Integer;
begin
  var Remaining: Single := DashOffset;

  for var Index := 0 to High(DashArray) do
  begin
    const Gap: Single = DashArray[Index];
    if (Remaining > Gap) or ((Remaining = Gap) and (Gap <> 0)) then
    begin
      Remaining := Remaining - Gap;
    end
    else
    begin
      FirstLen := Gap - Remaining;
      Exit(Index);
    end;
  end;

  // If we get here, phase "appears" to be larger than our length. This shouldn't happen with perfect precision, but we can accumulate
  // errors during the initial length computation (rounding can make our sum be too big or too small. In that event, we just have to eat
  // the error here.
  FirstLen := DashArray[0];
  Result := 0;
end;

class function TTsStrokeDash.TryCreate(const Intervals: TArray<Single>; const Offset: Single; out Dash: TTsStrokeDash): Boolean;
begin
  Dash := Default(TTsStrokeDash);

  var DashOffset: TTsFiniteF32;
  if not TTsFiniteF32.TryCreate(Offset, DashOffset) then
  begin
    Exit(False);
  end;

  if (Length(Intervals) < 2) or (Length(Intervals) mod 2 <> 0) then
  begin
    Exit(False);
  end;

  var IntervalSum: Single := 0;
  for var Interval in Intervals do
  begin
    if (not IsNan(Interval)) and (Interval < 0) then
    begin
      Exit(False);
    end;

    IntervalSum := IntervalSum + Interval;
  end;

  var IntervalLen: TTsNonZeroPositiveF32;
  if not TTsNonZeroPositiveF32.TryCreate(IntervalSum, IntervalLen) then
  begin
    Exit(False);
  end;

  const AdjustedOffset: Single = AdjustDashOffset(DashOffset.Get, IntervalLen.Get);

  var FirstLen: Single;
  const FirstIndex = FindFirstInterval(Intervals, AdjustedOffset, FirstLen);

  Dash.FArray := Copy(Intervals);
  Dash.FOffset := AdjustedOffset;
  Dash.FIntervalLen := IntervalLen;
  Dash.FFirstLen := FirstLen;
  Dash.FFirstIndex := FirstIndex;
  Result := True;
end;

{ TTsContourMeasure }

procedure TTsContourMeasure.AddPoint(const Pt: TTsPoint);
begin
  if PointCount = Length(Points) then
  begin
    SetLength(Points, PointCount * 2 + 8);
  end;

  Points[PointCount] := Pt;
  Inc(PointCount);
end;

procedure TTsContourMeasure.AddSegment(const Distance: Single; const PointIndex: Integer; const TValue: Cardinal;
                                       const Kind: TTsSegmentKind);
begin
  if SegmentCount = Length(Segments) then
  begin
    SetLength(Segments, SegmentCount * 2 + 8);
  end;

  Segments[SegmentCount].Distance := Distance;
  Segments[SegmentCount].PointIndex := PointIndex;
  Segments[SegmentCount].TValue := TValue;
  Segments[SegmentCount].Kind := Kind;
  Inc(SegmentCount);
end;

function FindSegment(const Base: TArray<TTsDashSegment>; const Count: Integer; const Key: Single): Integer;
begin
  var Lo := 0;
  var Hi := Count - 1;

  while Lo < Hi do
  begin
    const Mid = (Hi + Lo) shr 1;
    if Base[Mid].Distance < Key then
    begin
      Lo := Mid + 1;
    end
    else
    begin
      Hi := Mid;
    end;
  end;

  if Base[Hi].Distance < Key then
  begin
    Inc(Hi);
    Hi := not Hi;
  end
  else if Key < Base[Hi].Distance then
  begin
    Hi := not Hi;
  end;

  Result := Hi;
end;

procedure ComputePosTan(const Points: TArray<TTsPoint>; const Offset: Integer; const SegKind: TTsSegmentKind; const T: TTsNormalizedF32;
                        const Pos: PTsDashPoint; const Tangent: PTsDashPoint);
begin
  case SegKind of
    TTsSegmentKind.Line:
    begin
      if Pos <> nil then
      begin
        Pos^ := TTsPoint.FromXY(Interp(Points[Offset].X, Points[Offset + 1].X, T), Interp(Points[Offset].Y, Points[Offset + 1].Y, T));
      end;

      if Tangent <> nil then
      begin
        Tangent^.SetNormalize(Points[Offset + 1].X - Points[Offset].X, Points[Offset + 1].Y - Points[Offset].Y);
      end;
    end;

    TTsSegmentKind.Quad:
    begin
      var Src: TTsPoints3;
      for var Index := 0 to 2 do
      begin
        Src[Index] := Points[Offset + Index];
      end;

      if Pos <> nil then
      begin
        Pos^ := TTsPathGeometry.EvalQuadAt(Src, T);
      end;

      if Tangent <> nil then
      begin
        Tangent^ := TTsPathGeometry.EvalQuadTangentAt(Src, T);
        Tangent^.Normalize;
      end;
    end;

    TTsSegmentKind.Cubic:
    begin
      var Src: TTsPoints4;
      for var Index := 0 to 3 do
      begin
        Src[Index] := Points[Offset + Index];
      end;

      if Pos <> nil then
      begin
        Pos^ := TTsPathGeometry.EvalCubicPosAt(Src, T);
      end;

      if Tangent <> nil then
      begin
        Tangent^ := TTsPathGeometry.EvalCubicTangentAt(Src, T);
        Tangent^.Normalize;
      end;
    end;
  end;
end;

procedure SegmentTo(const Points: TArray<TTsPoint>; const Offset: Integer; const SegKind: TTsSegmentKind; const StartT, StopT: TTsNormalizedF32;
                    var Pb: TTsPathBuilder);
begin
  if StartT.Get = StopT.Get then
  begin
    var LastPt: TTsPoint;
    if Pb.TryLastPoint(LastPt) then
    begin
      // If the dash as a zero-length on segment, add a corresponding zero-length line. The stroke code will add end caps to zero length
      // lines as appropriate.
      Pb.LineTo(LastPt.X, LastPt.Y);
    end;

    Exit;
  end;

  case SegKind of
    TTsSegmentKind.Line:
    begin
      if StopT.Get = 1 then
      begin
        Pb.LineTo(Points[Offset + 1].X, Points[Offset + 1].Y);
      end
      else
      begin
        Pb.LineTo(Interp(Points[Offset].X, Points[Offset + 1].X, StopT), Interp(Points[Offset].Y, Points[Offset + 1].Y, StopT));
      end;
    end;

    TTsSegmentKind.Quad:
    begin
      var Src: TTsPoints3;
      for var Index := 0 to 2 do
      begin
        Src[Index] := Points[Offset + Index];
      end;

      var Tmp0: TTsPoints5;
      var Tmp1: TTsPoints5;
      if StartT.Get = 0 then
      begin
        if StopT.Get = 1 then
        begin
          Pb.QuadToPt(Src[1], Src[2]);
        end
        else
        begin
          TTsPathGeometry.ChopQuadAt(Src, TTsNormalizedF32Exclusive.CreateBounded(StopT.Get), Tmp0);
          Pb.QuadToPt(Tmp0[1], Tmp0[2]);
        end;
      end
      else
      begin
        TTsPathGeometry.ChopQuadAt(Src, TTsNormalizedF32Exclusive.CreateBounded(StartT.Get), Tmp0);
        if StopT.Get = 1 then
        begin
          Pb.QuadToPt(Tmp0[3], Tmp0[4]);
        end
        else
        begin
          const Numerator: Single = StopT.Get - StartT.Get;
          const Denominator: Single = One - StartT.Get;
          const NewT: Single = Numerator / Denominator;

          var Tail: TTsPoints3;
          for var Index := 0 to 2 do
          begin
            Tail[Index] := Tmp0[2 + Index];
          end;

          TTsPathGeometry.ChopQuadAt(Tail, TTsNormalizedF32Exclusive.CreateBounded(NewT), Tmp1);
          Pb.QuadToPt(Tmp1[1], Tmp1[2]);
        end;
      end;
    end;

    TTsSegmentKind.Cubic:
    begin
      var Src: TTsPoints4;
      for var Index := 0 to 3 do
      begin
        Src[Index] := Points[Offset + Index];
      end;

      var Tmp0: TTsPoints7;
      var Tmp1: TTsPoints7;
      if StartT.Get = 0 then
      begin
        if StopT.Get = 1 then
        begin
          Pb.CubicToPt(Src[1], Src[2], Src[3]);
        end
        else
        begin
          TTsPathGeometry.ChopCubicAt2(Src, TTsNormalizedF32Exclusive.CreateBounded(StopT.Get), Tmp0);
          Pb.CubicToPt(Tmp0[1], Tmp0[2], Tmp0[3]);
        end;
      end
      else
      begin
        TTsPathGeometry.ChopCubicAt2(Src, TTsNormalizedF32Exclusive.CreateBounded(StartT.Get), Tmp0);
        if StopT.Get = 1 then
        begin
          Pb.CubicToPt(Tmp0[4], Tmp0[5], Tmp0[6]);
        end
        else
        begin
          const Numerator: Single = StopT.Get - StartT.Get;
          const Denominator: Single = One - StartT.Get;
          const NewT: Single = Numerator / Denominator;

          var Tail: TTsPoints4;
          for var Index := 0 to 3 do
          begin
            Tail[Index] := Tmp0[3 + Index];
          end;

          TTsPathGeometry.ChopCubicAt2(Tail, TTsNormalizedF32Exclusive.CreateBounded(NewT), Tmp1);
          Pb.CubicToPt(Tmp1[1], Tmp1[2], Tmp1[3]);
        end;
      end;
    end;
  end;
end;

function TTsContourMeasure.TryDistanceToSegment(const Distance: Single; out SegmentIndex: Integer; out T: TTsNormalizedF32): Boolean;
begin
  SegmentIndex := 0;
  T := TTsNormalizedF32.Zero;

  var Index := FindSegment(Segments, SegmentCount, Distance);
  // don't care if we hit an exact match or not, so we xor index if it is negative
  if Index < 0 then
  begin
    Index := not Index;
  end;

  // Rust panics on an index past the segments; the caller clamps the distance to the length, so this does not happen
  if Index >= SegmentCount then
  begin
    Exit(False);
  end;

  const Seg = Segments[Index];

  // now interpolate t-values with the prev segment (if possible)
  var StartT: Single := 0;
  var StartD: Single := 0;
  // check if the prev segment is legal, and references the same set of points
  if Index > 0 then
  begin
    StartD := Segments[Index - 1].Distance;
    if Segments[Index - 1].PointIndex = Seg.PointIndex then
    begin
      StartT := Segments[Index - 1].ScalarT;
    end;
  end;

  const DeltaT: Single = Seg.ScalarT - StartT;
  const DeltaD: Single = Distance - StartD;
  const Scaled: Single = DeltaT * DeltaD;
  const Span: Single = Seg.Distance - StartD;
  const Quotient: Single = Scaled / Span;
  const NewT: Single = StartT + Quotient;

  if IsNan(NewT) then
  begin
    Exit(False);
  end;

  if not TTsNormalizedF32.TryCreate(NewT, T) then
  begin
    Exit(False);
  end;

  SegmentIndex := Index;
  Result := True;
end;

procedure TTsContourMeasure.PushSegment(const StartDistance, StopDistance: Single; const StartWithMoveTo: Boolean; var Pb: TTsPathBuilder);
begin
  var StartD: Single := StartDistance;
  var StopD: Single := StopDistance;

  if StartD < 0 then
  begin
    StartD := 0;
  end;

  if StopD > TotalLength then
  begin
    StopD := TotalLength;
  end;

  // catch NaN values as well
  if IsNan(StartD) or IsNan(StopD) or not (StartD <= StopD) then
  begin
    Exit;
  end;

  if SegmentCount = 0 then
  begin
    Exit;
  end;

  var SegIndex: Integer;
  var StartT: TTsNormalizedF32;
  if not TryDistanceToSegment(StartD, SegIndex, StartT) then
  begin
    Exit;
  end;

  var Seg := Segments[SegIndex];

  var StopSegIndex: Integer;
  var StopT: TTsNormalizedF32;
  if not TryDistanceToSegment(StopD, StopSegIndex, StopT) then
  begin
    Exit;
  end;

  const StopSeg = Segments[StopSegIndex];

  if StartWithMoveTo then
  begin
    var P: TTsPoint;
    ComputePosTan(Points, Seg.PointIndex, Seg.Kind, StartT, @P, nil);
    Pb.MoveTo(P.X, P.Y);
  end;

  if Seg.PointIndex = StopSeg.PointIndex then
  begin
    SegmentTo(Points, Seg.PointIndex, Seg.Kind, StartT, StopT, Pb);
  end
  else
  begin
    var NewSegIndex := SegIndex;
    while True do
    begin
      SegmentTo(Points, Seg.PointIndex, Seg.Kind, StartT, TTsNormalizedF32.One, Pb);

      const OldPointIndex = Seg.PointIndex;
      while True do
      begin
        Inc(NewSegIndex);
        // Rust panics on an index past the segments; the stop segment has a later point index, so this does not happen
        if NewSegIndex >= SegmentCount then
        begin
          Exit;
        end;

        if Segments[NewSegIndex].PointIndex <> OldPointIndex then
        begin
          Break;
        end;
      end;

      Seg := Segments[NewSegIndex];

      StartT := TTsNormalizedF32.Zero;

      if Seg.PointIndex >= StopSeg.PointIndex then
      begin
        Break;
      end;
    end;

    SegmentTo(Points, Seg.PointIndex, Seg.Kind, TTsNormalizedF32.Zero, StopT, Pb);
  end;
end;

function TTsContourMeasure.ComputeLineSeg(const P0, P1: TTsPoint; const Distance: Single; const PointIndex: Integer): Single;
begin
  const D: Single = P0.Distance(P1);
  const PrevD: Single = Distance;

  Result := Distance + D;
  if Result > PrevD then
  begin
    AddSegment(Result, PointIndex, MaxTValue, TTsSegmentKind.Line);
  end;
end;

function TSpanBigEnough(const TSpan: Cardinal): Cardinal;
begin
  Result := TSpan shr 10;
end;

function QuadTooCurvy(const P0, P1, P2: TTsPoint; const Tolerance: Single): Boolean;
begin
  // diff = (a/4 + b/2 + c/4) - (a/2 + c/2)
  // diff = -a/4 + b/2 - c/4
  const SumX: Single = P0.X + P2.X;
  const SumY: Single = P0.Y + P2.Y;
  const Dx: Single = TTsScalar.Half(P1.X) - TTsScalar.Half(TTsScalar.Half(SumX));
  const Dy: Single = TTsScalar.Half(P1.Y) - TTsScalar.Half(TTsScalar.Half(SumY));

  const Dist: Single = TTsScalar.MaxF(Abs(Dx), Abs(Dy));
  Result := (not IsNan(Dist)) and (Dist > Tolerance);
end;

function CheapDistExceedsLimit(const Pt: TTsPoint; const X, Y, Tolerance: Single): Boolean;
begin
  const Dx: Single = X - Pt.X;
  const Dy: Single = Y - Pt.Y;
  const Dist: Single = TTsScalar.MaxF(Abs(Dx), Abs(Dy));

  // just made up the 1/2
  Result := (not IsNan(Dist)) and (Dist > Tolerance);
end;

function CubicTooCurvy(const P0, P1, P2, P3: TTsPoint; const Tolerance: Single): Boolean;
begin
  const N0 = CheapDistExceedsLimit(P1, InterpSafe(P0.X, P3.X, OneThird), InterpSafe(P0.Y, P3.Y, OneThird), Tolerance);
  const N1 = CheapDistExceedsLimit(P2, InterpSafe(P0.X, P3.X, TwoThirds), InterpSafe(P0.Y, P3.Y, TwoThirds), Tolerance);

  Result := N0 or N1;
end;

function TTsContourMeasure.ComputeQuadSegs(const P0, P1, P2: TTsPoint; const Distance: Single; const MinT, MaxT: Cardinal;
                                           const PointIndex: Integer; const Tolerance: Single): Single;
begin
  Result := Distance;

  if (TSpanBigEnough(MaxT - MinT) <> 0) and QuadTooCurvy(P0, P1, P2, Tolerance) then
  begin
    var Src: TTsPoints3;
    Src[0] := P0;
    Src[1] := P1;
    Src[2] := P2;

    var Tmp: TTsPoints5;
    const HalfT = (MinT + MaxT) shr 1;

    TTsPathGeometry.ChopQuadAt(Src, TTsNormalizedF32Exclusive.Half, Tmp);
    Result := ComputeQuadSegs(Tmp[0], Tmp[1], Tmp[2], Result, MinT, HalfT, PointIndex, Tolerance);
    Result := ComputeQuadSegs(Tmp[2], Tmp[3], Tmp[4], Result, HalfT, MaxT, PointIndex, Tolerance);
  end
  else
  begin
    const D: Single = P0.Distance(P2);
    const PrevD: Single = Result;

    Result := Result + D;
    if Result > PrevD then
    begin
      AddSegment(Result, PointIndex, MaxT, TTsSegmentKind.Quad);
    end;
  end;
end;

function TTsContourMeasure.ComputeCubicSegs(const P0, P1, P2, P3: TTsPoint; const Distance: Single; const MinT, MaxT: Cardinal;
                                            const PointIndex: Integer; const Tolerance: Single): Single;
begin
  Result := Distance;

  if (TSpanBigEnough(MaxT - MinT) <> 0) and CubicTooCurvy(P0, P1, P2, P3, Tolerance) then
  begin
    var Src: TTsPoints4;
    Src[0] := P0;
    Src[1] := P1;
    Src[2] := P2;
    Src[3] := P3;

    var Tmp: TTsPoints7;
    const HalfT = (MinT + MaxT) shr 1;

    TTsPathGeometry.ChopCubicAt2(Src, TTsNormalizedF32Exclusive.Half, Tmp);
    Result := ComputeCubicSegs(Tmp[0], Tmp[1], Tmp[2], Tmp[3], Result, MinT, HalfT, PointIndex, Tolerance);
    Result := ComputeCubicSegs(Tmp[3], Tmp[4], Tmp[5], Tmp[6], Result, HalfT, MaxT, PointIndex, Tolerance);
  end
  else
  begin
    const D: Single = P0.Distance(P3);
    const PrevD: Single = Result;

    Result := Result + D;
    if Result > PrevD then
    begin
      AddSegment(Result, PointIndex, MaxT, TTsSegmentKind.Cubic);
    end;
  end;
end;

{ TTsContourMeasureIter }

class function TTsContourMeasureIter.Create(const Path: TTsPath; const ResScale: Single): TTsContourMeasureIter;
begin
  Result.FIter := Path.Segments;
  Result.FTolerance := CheapDistLimit * TTsScalar.Invert(ResScale);
end;

function TTsContourMeasureIter.TryNext(out Contour: TTsContourMeasure): Boolean;
begin
  // Note:
  // as we accumulate distance, we have to check that the result of += actually made it larger, since a very small delta might be > 0, but
  // still have no effect on distance (if distance >>> delta).
  //
  // We do this check below, and in compute_quad_segs and compute_cubic_segs
  Contour := Default(TTsContourMeasure);

  var PointIndex := 0;
  var Distance: Single := 0;
  var HaveSeenClose := False;
  var PrevP := TTsPoint.Zero;

  var Seg: TTsPathSegment;
  while FIter.TryNext(Seg) do
  begin
    case Seg.Verb of
      TTsPathVerb.Move:
      begin
        Contour.AddPoint(Seg.P0);
        PrevP := Seg.P0;
      end;

      TTsPathVerb.Line:
      begin
        const PrevD: Single = Distance;
        Distance := Contour.ComputeLineSeg(PrevP, Seg.P0, Distance, PointIndex);

        if Distance > PrevD then
        begin
          Contour.AddPoint(Seg.P0);
          Inc(PointIndex);
        end;

        PrevP := Seg.P0;
      end;

      TTsPathVerb.Quad:
      begin
        const PrevD: Single = Distance;
        Distance := Contour.ComputeQuadSegs(PrevP, Seg.P0, Seg.P1, Distance, 0, MaxTValue, PointIndex, FTolerance);

        if Distance > PrevD then
        begin
          Contour.AddPoint(Seg.P0);
          Contour.AddPoint(Seg.P1);
          Inc(PointIndex, 2);
        end;

        PrevP := Seg.P1;
      end;

      TTsPathVerb.Cubic:
      begin
        const PrevD: Single = Distance;
        Distance := Contour.ComputeCubicSegs(PrevP, Seg.P0, Seg.P1, Seg.P2, Distance, 0, MaxTValue, PointIndex, FTolerance);

        if Distance > PrevD then
        begin
          Contour.AddPoint(Seg.P0);
          Contour.AddPoint(Seg.P1);
          Contour.AddPoint(Seg.P2);
          Inc(PointIndex, 3);
        end;

        PrevP := Seg.P2;
      end;

      TTsPathVerb.Close:
      begin
        HaveSeenClose := True;
      end;
    end;

    var NextVerb: TTsPathVerb;
    if FIter.TryNextVerb(NextVerb) and (NextVerb = TTsPathVerb.Move) then
    begin
      Break;
    end;
  end;

  if not TTsScalar.IsFinite(Distance) then
  begin
    Exit(False);
  end;

  if HaveSeenClose then
  begin
    const PrevD: Single = Distance;
    const FirstPt = Contour.Points[0];
    Distance := Contour.ComputeLineSeg(Contour.Points[PointIndex], FirstPt, Distance, PointIndex);

    if Distance > PrevD then
    begin
      Contour.AddPoint(FirstPt);
    end;
  end;

  Contour.TotalLength := Distance;
  Contour.IsClosed := HaveSeenClose;

  Result := Contour.PointCount > 0;
end;

function IsEven(const X: Integer): Boolean;
begin
  Result := (X mod 2 = 0);
end;

function TryDashPath(const Src: TTsPath; const Dash: TTsStrokeDash; const ResScale: Single; out Dashed: TTsPath): Boolean;
begin
  // We do not support the `cull_path` branch here.
  // Skia has a lot of code for cases when a path contains only a single zero-length line or when a path is a rect. Not sure why.
  // We simply ignoring it for the sake of simplicity.

  // We also doesn't support the `SpecialLineRec` case.
  // I have no idea what the point in it.
  Dashed := Default(TTsPath);

  var Pb := TTsPathBuilder.New;
  var DashCount: Single := 0;
  var Iter := TTsContourMeasureIter.Create(Src, ResScale);

  var Contour: TTsContourMeasure;
  while Iter.TryNext(Contour) do
  begin
    var SkipFirstSegment := Contour.IsClosed;
    var AddedSegment := False;
    const ContourLength: Single = Contour.TotalLength;
    var Index := Dash.FFirstIndex;

    // Since the path length / dash length ratio may be arbitrarily large, we can exert significant memory pressure while attempting to
    // build the filtered path. To avoid this, we simply give up dashing beyond a certain threshold.
    //
    // The original bug report (http://crbug.com/165432) is based on a path yielding more than 90 million dash segments and crashing the
    // memory allocator. A limit of 1 million segments seems reasonable: at 2 verbs per segment * 9 bytes per verb, this caps the maximum
    // dash memory overhead at roughly 17MB per path.
    const PairCount: Single = Length(Dash.FArray) shr 1;
    const Scaled: Single = ContourLength * PairCount;
    const Added: Single = Scaled / Dash.FIntervalLen.Get;
    DashCount := DashCount + Added;
    if DashCount > MaxDashCount then
    begin
      Exit(False);
    end;

    // Using double precision to avoid looping indefinitely due to single precision rounding (for extreme path_length/dash_length ratios).
    // See test_infinite_dash() unittest.
    var Distance: Single := 0;
    var DLen: Single := Dash.FFirstLen;

    while Distance < ContourLength do
    begin
      AddedSegment := False;
      if IsEven(Index) and not SkipFirstSegment then
      begin
        AddedSegment := True;
        Contour.PushSegment(Distance, Distance + DLen, True, Pb);
      end;

      Distance := Distance + DLen;

      // clear this so we only respect it the first time around
      SkipFirstSegment := False;

      // wrap around our intervals array if necessary
      Inc(Index);
      if Index = Length(Dash.FArray) then
      begin
        Index := 0;
      end;

      // fetch our next d_len
      DLen := Dash.FArray[Index];
    end;

    // extend if we ended on a segment and we need to join up with the (skipped) initial segment
    if Contour.IsClosed and IsEven(Dash.FFirstIndex) and (Dash.FFirstLen >= 0) then
    begin
      Contour.PushSegment(0, Dash.FFirstLen, not AddedSegment, Pb);
    end;
  end;

  Result := Pb.TryFinish(Dashed);
end;

{ TTsPathDashHelper }

function TTsPathDashHelper.TryDash(const Dash: TTsStrokeDash; const ResScale: Single; out Dashed: TTsPath): Boolean;
begin
  Result := TryDashPath(Self, Dash, ResScale, Dashed);
end;

end.
