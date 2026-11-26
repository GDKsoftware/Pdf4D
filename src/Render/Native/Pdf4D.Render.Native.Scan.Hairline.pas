// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/scan/hairline.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Scan.Hairline;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.FixedPoint,
  Pdf4D.Render.Native.PathGeometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.EdgeClipper,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Blitter;

// The hairline stroker (a stroke of one pixel wide): the segments of a path become short lines, which a line procedure draws. The non-anti-
// aliased procedure is here, the anti-aliased one is in Pdf4D.Render.Native.Scan.HairlineAntiAlias; both go through StrokePathImpl.
//
// The Rust Option<&ScreenIntRect> of the line procedure is a HasClip flag and a Clip; the slices of points are open arrays.
//
// Where a vertical line starts at an X that lies on the right edge of the clip, Rust blits a pixel outside of the clip as well (it checks
// only the left side and the rows); the blitter must ignore what lies outside of its pixmap.
//
// Must run inside TTsFloatMode: a path with huge coordinates gives infinities and NaN in the arithmetic of the curves.

type
  TTsLineProc = procedure(const Points: array of TTsPoint; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                          const Blitter: TTsBlitter);

  TTsScanHairline = record
  private const
    MaxCubicSubdivideLevel = 9;
    MaxQuadSubdivideLevel = 5;

  private
    class procedure ExtendPts(const LineCap: TTsLineCap; const PrevVerb: TTsPathVerb; const HasNextVerb: Boolean;
                              const NextVerb: TTsPathVerb; var Points: array of TTsPoint); static;
    class procedure HairQuad(const Points: TTsPoints3; const HasClip: Boolean; const Clip: TTsScreenIntRect; const HasInsetClip: Boolean;
                             const InsetClip, OutsetClip: TTsIntRect; const Level: Integer; const LineProc: TTsLineProc;
                             const Blitter: TTsBlitter); static;
    class function TryComputeNocheckQuadBounds(const Points: TTsPoints3; out Bounds: TTsRect): Boolean; static;
    class function GeometricOverlap(const A, B: TTsRect): Boolean; static;
    class function GeometricContains(const Outer, Inner: TTsRect): Boolean; static;
    class procedure HairQuad2(const Points: TTsPoints3; const HasClip: Boolean; const Clip: TTsScreenIntRect; const Level: Integer;
                              const LineProc: TTsLineProc; const Blitter: TTsBlitter); static;
    class function ComputeQuadLevel(const Points: TTsPoints3): Integer; static;
    class function ComputeIntQuadDist(const Points: TTsPoints3): Cardinal; static;
    class procedure HairCubic(const Points: TTsPoints4; const HasClip: Boolean; const Clip: TTsScreenIntRect; const HasInsetClip: Boolean;
                              const InsetClip, OutsetClip: TTsIntRect; const LineProc: TTsLineProc; const Blitter: TTsBlitter); static;
    class function TryComputeNocheckCubicBounds(const Points: TTsPoints4; out Bounds: TTsRect): Boolean; static;
    class function QuickCubicNicenessCheck(const Points: TTsPoints4): Boolean; static;
    class function Lt90(const P0, Pivot, P2: TTsPoint): Boolean; static;
    class procedure HairCubic2(const Points: TTsPoints4; const HasClip: Boolean; const Clip: TTsScreenIntRect; const LineProc: TTsLineProc;
                               const Blitter: TTsBlitter); static;
    class function ComputeCubicSegments(const Points: TTsPoints4): Integer; static;

  public
    class procedure StrokePath(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect;
                               const Blitter: TTsBlitter); static;

    // The line procedure of the non-anti-aliased hairline
    class procedure HairLineRgn(const Points: array of TTsPoint; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                                const Blitter: TTsBlitter); static;

    class procedure StrokePathImpl(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect;
                                   const LineProc: TTsLineProc; const Blitter: TTsBlitter); static;
  end;

implementation

const
  FixedBoundsMax: Single = 32767.0;
  QuadPointCount = (1 shl 5) + 1;
  CubicPointCount = (1 shl 9) + 1;

{ TTsScanHairline }

class procedure TTsScanHairline.StrokePath(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect;
                                           const Blitter: TTsBlitter);
begin
  StrokePathImpl(Path, LineCap, Clip, HairLineRgn, Blitter);
end;

class procedure TTsScanHairline.HairLineRgn(const Points: array of TTsPoint; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                                            const Blitter: TTsBlitter);
begin
  var FixedBounds: TTsRect;
  if not TTsRect.TryFromLTRB(-FixedBoundsMax, -FixedBoundsMax, FixedBoundsMax, FixedBoundsMax, FixedBounds) then
  begin
    Exit;
  end;

  var ClipBounds := Default(TTsRect);
  if HasClip then
  begin
    ClipBounds := Clip.ToRect;
  end;

  for var Index := 0 to High(Points) - 1 do
  begin
    var Pts: TTsPoints2;
    var Segment: TTsPoints2;
    Segment[0] := Points[Index];
    Segment[1] := Points[Index + 1];

    // We have to pre-clip the line to fit in a Fixed, so we just chop the line.
    if not TTsLineClipper.Intersect(Segment, FixedBounds, Pts) then
    begin
      Continue;
    end;

    if HasClip then
    begin
      const Tmp = Pts;

      // Perform a clip in scalar space, so we catch huge values which might be missed after we convert to FDot6 (overflow).
      if not TTsLineClipper.Intersect(Tmp, ClipBounds, Pts) then
      begin
        Continue;
      end;
    end;

    var X0 := TTsFdot6.FromF32(Pts[0].X);
    var Y0 := TTsFdot6.FromF32(Pts[0].Y);
    var X1 := TTsFdot6.FromF32(Pts[1].X);
    var Y1 := TTsFdot6.FromF32(Pts[1].Y);

    const Dx = X1 - X0;
    const Dy = Y1 - Y0;

    if Abs(Dx) > Abs(Dy) then
    begin
      // mostly horizontal

      if X0 > X1 then
      begin
        // we want to go left-to-right
        const SwapX = X0;
        X0 := X1;
        X1 := SwapX;
        // the other end point is not used after the swap: only the Y of the left one is
        Y0 := Y1;
      end;

      var Ix0 := TTsFdot6.Round(X0);
      const Ix1 = TTsFdot6.Round(X1);
      if Ix0 = Ix1 then
      begin
        // too short to draw
        Continue;
      end;

      const Slope = TTsFdot16.&Div(Dy, Dx);
      var StartY := TTsFdot6.ToFdot16(Y0) + TTsScalar.ShiftRightI32(Slope * ((32 - X0) and 63), 6);

      // In some cases, probably due to precision/rounding issues, `start_y` can become equal to the image height, which will lead to
      // panic, because we would be accessing pixels outside the current memory buffer.
      // This is tiny-skia specific issue. Skia handles this part differently.
      var MaxY := High(Integer);
      if HasClip then
      begin
        MaxY := TTsFdot16.FromF32(ClipBounds.Bottom);
      end;

      repeat
        if (Ix0 >= 0) and (StartY >= 0) and (StartY < MaxY) then
        begin
          Blitter.BlitH(Cardinal(Ix0), Cardinal(TTsScalar.ShiftRightI32(StartY, 16)), 1);
        end;

        StartY := StartY + Slope;
        Inc(Ix0);
      until Ix0 >= Ix1;
    end
    else
    begin
      // mostly vertical

      if Y0 > Y1 then
      begin
        // we want to go top-to-bottom
        const SwapY = Y0;
        Y0 := Y1;
        Y1 := SwapY;
        // the other end point is not used after the swap: only the X of the top one is
        X0 := X1;
      end;

      var Iy0 := TTsFdot6.Round(Y0);
      const Iy1 = TTsFdot6.Round(Y1);
      if Iy0 = Iy1 then
      begin
        // too short to draw
        Continue;
      end;

      const Slope = TTsFdot16.&Div(Dx, Dy);
      var StartX := TTsFdot6.ToFdot16(X0) + TTsScalar.ShiftRightI32(Slope * ((32 - Y0) and 63), 6);

      repeat
        if (StartX >= 0) and (Iy0 >= 0) then
        begin
          Blitter.BlitH(Cardinal(TTsScalar.ShiftRightI32(StartX, 16)), Cardinal(Iy0), 1);
        end;

        StartX := StartX + Slope;
        Inc(Iy0);
      until Iy0 >= Iy1;
    end;
  end;
end;

class procedure TTsScanHairline.StrokePathImpl(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect;
                                               const LineProc: TTsLineProc; const Blitter: TTsBlitter);
begin
  var HasInsetClip := False;
  var InsetClip := Default(TTsIntRect);
  var OutsetClip := Default(TTsIntRect);

  begin
    var CapOut: Single := 1.0;
    if LineCap <> TTsLineCap.Butt then
    begin
      CapOut := 2.0;
    end;

    var Outset: TTsRect;
    if not Path.Bounds.TryOutset(CapOut, CapOut, Outset) then
    begin
      Exit;
    end;

    var IBounds: TTsIntRect;
    if not Outset.TryRoundOut(IBounds) then
    begin
      Exit;
    end;

    const ClipInt = Clip.ToIntRect;
    var Intersection: TTsIntRect;
    if not ClipInt.TryIntersect(IBounds, Intersection) then
    begin
      Exit;
    end;

    if not ClipInt.Contains(IBounds) then
    begin
      // We now cache two scalar rects, to use for culling per-segment (e.g. cubic). Since we're hairlining, the "bounds" of the control
      // points isn't necessarily the limit of where a segment can draw (it might draw up to 1 pixel beyond in aa-hairs).
      //
      // Compute the pt-bounds per segment is easy, so we do that, and then inversely adjust the culling bounds so we can just do a
      // straight compare per segment.
      //
      // insetClip is use for quick-accept (i.e. the segment is not clipped), so we inset it from the clip-bounds (since segment bounds
      // can be off by 1).
      //
      // outsetClip is used for quick-reject (i.e. the segment is entirely outside), so we outset it from the clip-bounds.
      if not ClipInt.TryMakeOutset(1, 1, OutsetClip) then
      begin
        Exit;
      end;

      // Pdf4D deviation from tiny-skia: a clip that is under 3 px in one direction has no inset rect, and tiny-skia then returns without
      // drawing. A thin device, group layer or tile slice would lose every hairline that way, so here the segments simply take the
      // clipped path (without the quick-accept and quick-reject that the inset rect allows).
      HasInsetClip := ClipInt.TryInset(1, 1, InsetClip);
    end;
  end;

  var PrevVerb := TTsPathVerb.Move;
  var FirstPt := TTsPoint.Zero;
  var LastPt := TTsPoint.Zero;

  var Iter := Path.Segments;
  var Segment: TTsPathSegment;
  while Iter.TryNext(Segment) do
  begin
    const Verb = Iter.CurrVerb;
    var NextVerb: TTsPathVerb;
    const HasNextVerb = Iter.TryNextVerb(NextVerb);
    var LastPt2: TTsPoint;

    case Segment.Verb of
      TTsPathVerb.Move:
        begin
          FirstPt := Segment.P0;
          LastPt := Segment.P0;
          LastPt2 := Segment.P0;
        end;

      TTsPathVerb.Line:
        begin
          var Points: array[0..1] of TTsPoint;
          Points[0] := LastPt;
          Points[1] := Segment.P0;
          if LineCap <> TTsLineCap.Butt then
          begin
            ExtendPts(LineCap, PrevVerb, HasNextVerb, NextVerb, Points);
          end;

          LineProc(Points, True, Clip, Blitter);
          LastPt := Segment.P0;
          LastPt2 := Points[0];
        end;

      TTsPathVerb.Quad:
        begin
          var Points: TTsPoints3;
          Points[0] := LastPt;
          Points[1] := Segment.P0;
          Points[2] := Segment.P1;
          if LineCap <> TTsLineCap.Butt then
          begin
            ExtendPts(LineCap, PrevVerb, HasNextVerb, NextVerb, Points);
          end;

          HairQuad(Points, True, Clip, HasInsetClip, InsetClip, OutsetClip, ComputeQuadLevel(Points), LineProc, Blitter);

          LastPt := Segment.P1;
          LastPt2 := Points[0];
        end;

      TTsPathVerb.Cubic:
        begin
          var Points: TTsPoints4;
          Points[0] := LastPt;
          Points[1] := Segment.P0;
          Points[2] := Segment.P1;
          Points[3] := Segment.P2;
          if LineCap <> TTsLineCap.Butt then
          begin
            ExtendPts(LineCap, PrevVerb, HasNextVerb, NextVerb, Points);
          end;

          HairCubic(Points, True, Clip, HasInsetClip, InsetClip, OutsetClip, LineProc, Blitter);

          LastPt := Segment.P2;
          LastPt2 := Points[0];
        end;
    else
      begin
        // Close
        var Points: array[0..1] of TTsPoint;
        Points[0] := LastPt;
        Points[1] := FirstPt;
        if (LineCap <> TTsLineCap.Butt) and (PrevVerb = TTsPathVerb.Move) then
        begin
          // cap moveTo/close to match svg expectations for degenerate segments
          ExtendPts(LineCap, PrevVerb, HasNextVerb, NextVerb, Points);
        end;

        LineProc(Points, True, Clip, Blitter);
        LastPt2 := Points[0];
      end;
    end;

    if LineCap <> TTsLineCap.Butt then
    begin
      if (PrevVerb = TTsPathVerb.Move) and (Verb in [TTsPathVerb.Line, TTsPathVerb.Quad, TTsPathVerb.Cubic]) then
      begin
        // the curve moved the initial point, so close to it instead
        FirstPt := LastPt2;
      end;

      PrevVerb := Verb;
    end;
  end;
end;

// Extend the points in the direction of the starting or ending tangent by 1/2 unit to account for a round or square cap.
//
// If there's no distance between the end point and the control point, use the next control point to create a tangent. If the curve is
// degenerate, move the cap out 1/2 unit horizontally.
class procedure TTsScanHairline.ExtendPts(const LineCap: TTsLineCap; const PrevVerb: TTsPathVerb; const HasNextVerb: Boolean;
                                          const NextVerb: TTsPathVerb; var Points: array of TTsPoint);
begin
  // The area of a circle is PI*R*R. For a unit circle, R=1/2, and the cap covers half of that.
  var CapOutset: Single := 0.5;
  if LineCap <> TTsLineCap.Square then
  begin
    CapOutset := TTsScalar.FloatPi / 8.0;
  end;

  const Count = Length(Points);

  if PrevVerb = TTsPathVerb.Move then
  begin
    const First = Points[0];
    var Offset := 0;
    var Controls := Count - 1;
    var Tangent := TTsPoint.Zero;
    while True do
    begin
      Inc(Offset);
      Tangent := First - Points[Offset];

      if not Tangent.IsZero then
      begin
        Break;
      end;

      Dec(Controls);
      if Controls = 0 then
      begin
        Break;
      end;
    end;

    if Tangent.IsZero then
    begin
      Tangent := TTsPoint.FromXY(1.0, 0.0);
      // If all points are equal, move all but one.
      Controls := Count - 1;
    end
    else
    begin
      Tangent.Normalize;
    end;

    Offset := 0;
    while True do
    begin
      // If the end point and control points are equal, loop to move them in tandem.
      Points[Offset].X := Points[Offset].X + Tangent.X * CapOutset;
      Points[Offset].Y := Points[Offset].Y + Tangent.Y * CapOutset;

      Inc(Offset);
      Inc(Controls);
      if Controls >= Count then
      begin
        Break;
      end;
    end;
  end;

  const IsAtTheEnd = ((not HasNextVerb) or (NextVerb in [TTsPathVerb.Move, TTsPathVerb.Close]));
  if IsAtTheEnd then
  begin
    const Last = Points[Count - 1];
    var Offset := Count - 1;
    var Controls := Count - 1;
    var Tangent := TTsPoint.Zero;
    while True do
    begin
      Dec(Offset);
      Tangent := Last - Points[Offset];

      if not Tangent.IsZero then
      begin
        Break;
      end;

      Dec(Controls);
      if Controls = 0 then
      begin
        Break;
      end;
    end;

    if Tangent.IsZero then
    begin
      Tangent := TTsPoint.FromXY(-1.0, 0.0);
      Controls := Count - 1;
    end
    else
    begin
      Tangent.Normalize;
    end;

    Offset := Count - 1;
    while True do
    begin
      Points[Offset].X := Points[Offset].X + Tangent.X * CapOutset;
      Points[Offset].Y := Points[Offset].Y + Tangent.Y * CapOutset;

      Dec(Offset);
      Inc(Controls);
      if Controls >= Count then
      begin
        Break;
      end;
    end;
  end;
end;

class procedure TTsScanHairline.HairQuad(const Points: TTsPoints3; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                                         const HasInsetClip: Boolean; const InsetClip, OutsetClip: TTsIntRect; const Level: Integer;
                                         const LineProc: TTsLineProc; const Blitter: TTsBlitter);
begin
  var UseClip := HasClip;

  if HasInsetClip then
  begin
    var Bounds: TTsRect;
    if not TryComputeNocheckQuadBounds(Points, Bounds) then
    begin
      Exit;
    end;

    if not GeometricOverlap(OutsetClip.ToRect, Bounds) then
    begin
      // nothing to do
      Exit;
    end
    else if GeometricContains(InsetClip.ToRect, Bounds) then
    begin
      UseClip := False;
    end;
  end;

  HairQuad2(Points, UseClip, Clip, Level, LineProc, Blitter);
end;

class function TTsScanHairline.TryComputeNocheckQuadBounds(const Points: TTsPoints3; out Bounds: TTsRect): Boolean;
begin
  var MinPoint := Points[0].ToF32x2;
  var MaxPoint := MinPoint;
  for var Index := 1 to 2 do
  begin
    const Pair = Points[Index].ToF32x2;
    MinPoint := MinPoint.Min(Pair);
    MaxPoint := MaxPoint.Max(Pair);
  end;

  Result := TTsRect.TryFromLTRB(MinPoint.X, MinPoint.Y, MaxPoint.X, MaxPoint.Y, Bounds);
end;

class function TTsScanHairline.GeometricOverlap(const A, B: TTsRect): Boolean;
begin
  Result := ((A.Left < B.Right) and (B.Left < A.Right) and (A.Top < B.Bottom) and (B.Top < A.Bottom));
end;

class function TTsScanHairline.GeometricContains(const Outer, Inner: TTsRect): Boolean;
begin
  Result := ((Inner.Right <= Outer.Right) and (Inner.Left >= Outer.Left) and (Inner.Bottom <= Outer.Bottom) and (Inner.Top >= Outer.Top));
end;

class procedure TTsScanHairline.HairQuad2(const Points: TTsPoints3; const HasClip: Boolean; const Clip: TTsScreenIntRect; const Level: Integer;
                                          const LineProc: TTsLineProc; const Blitter: TTsBlitter);
begin
  const Coeff = TTsQuadCoeff.FromPoints(Points);

  const MaxPoints = QuadPointCount;
  const Lines = 1 shl Level;

  var Tmp: array[0..QuadPointCount - 1] of TTsPoint;
  for var Index := 0 to MaxPoints - 1 do
  begin
    Tmp[Index] := TTsPoint.Zero;
  end;

  Tmp[0] := Points[0];

  var T := Default(TF32x2);
  const OneOverLines: Single = 1.0 / Lines;
  const Dt = TF32x2.Splat(OneOverLines);
  for var Index := 1 to Lines - 1 do
  begin
    T := T + Dt;
    const V = Coeff.Eval(T);
    Tmp[Index] := TTsPoint.FromXY(V.X, V.Y);
  end;

  Tmp[Lines] := Points[2];
  LineProc(Slice(Tmp, Lines + 1), HasClip, Clip, Blitter);
end;

class function TTsScanHairline.ComputeQuadLevel(const Points: TTsPoints3): Integer;
begin
  const D = ComputeIntQuadDist(Points);

  // Quadratics approach the line connecting their start and end points 4x closer with each subdivision, so we compute the number of
  // subdivisions to be the minimum need to get that distance to be less than a pixel.
  var LeadingZeros := 0;
  var Probe := D;
  while (LeadingZeros < 32) and ((Probe and $80000000) = 0) do
  begin
    Probe := Probe shl 1;
    Inc(LeadingZeros);
  end;

  Result := (33 - LeadingZeros) shr 1;

  // sanity check on level (from the previous version)
  if Result > MaxQuadSubdivideLevel then
  begin
    Result := MaxQuadSubdivideLevel;
  end;
end;

class function TTsScanHairline.ComputeIntQuadDist(const Points: TTsPoints3): Cardinal;
begin
  // compute the vector between the control point ([1]) and the middle of the line connecting the start and end ([0] and [2])
  const SumX: Single = Points[0].X + Points[2].X;
  const SumY: Single = Points[0].Y + Points[2].Y;
  const DiffX: Single = TTsScalar.Half(SumX) - Points[1].X;
  const DiffY: Single = TTsScalar.Half(SumY) - Points[1].Y;
  const Dx: Single = Abs(DiffX);
  const Dy: Single = Abs(DiffY);

  // convert to whole pixel values (use ceiling to be conservative). assign to unsigned so we can safely add 1/2 of the smaller and still fit
  // in u32, since T::saturate_from() returns 31 bits at most.
  const Idx = Cardinal(TTsScalar.SaturateCeil(Dx));
  const Idy = Cardinal(TTsScalar.SaturateCeil(Dy));

  // use the cheap approx for distance
  if Idx > Idy then
  begin
    Result := Idx + (Idy shr 1);
  end
  else
  begin
    Result := Idy + (Idx shr 1);
  end;
end;

class procedure TTsScanHairline.HairCubic(const Points: TTsPoints4; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                                          const HasInsetClip: Boolean; const InsetClip, OutsetClip: TTsIntRect;
                                          const LineProc: TTsLineProc; const Blitter: TTsBlitter);
begin
  var UseClip := HasClip;

  if HasInsetClip then
  begin
    var Bounds: TTsRect;
    if not TryComputeNocheckCubicBounds(Points, Bounds) then
    begin
      Exit;
    end;

    if not GeometricOverlap(OutsetClip.ToRect, Bounds) then
    begin
      // noting to do
      Exit;
    end
    else if GeometricContains(InsetClip.ToRect, Bounds) then
    begin
      UseClip := False;
    end;
  end;

  if QuickCubicNicenessCheck(Points) then
  begin
    HairCubic2(Points, UseClip, Clip, LineProc, Blitter);
  end
  else
  begin
    var Tmp: array[0..12] of TTsPoint;
    for var Index := 0 to High(Tmp) do
    begin
      Tmp[Index] := TTsPoint.Zero;
    end;

    var TValues := TTsPathGeometry.NewTValues;

    const Count = TTsPathGeometry.ChopCubicAtMaxCurvature(Points, TValues, Tmp);
    for var Index := 0 to Count - 1 do
    begin
      const Offset = Index * 3;
      var NewPoints: TTsPoints4;
      for var PointIndex := 0 to 3 do
      begin
        NewPoints[PointIndex] := Tmp[Offset + PointIndex];
      end;

      HairCubic2(NewPoints, UseClip, Clip, LineProc, Blitter);
    end;
  end;
end;

class function TTsScanHairline.TryComputeNocheckCubicBounds(const Points: TTsPoints4; out Bounds: TTsRect): Boolean;
begin
  var MinPoint := Points[0].ToF32x2;
  var MaxPoint := MinPoint;
  for var Index := 1 to 3 do
  begin
    const Pair = Points[Index].ToF32x2;
    MinPoint := MinPoint.Min(Pair);
    MaxPoint := MaxPoint.Max(Pair);
  end;

  Result := TTsRect.TryFromLTRB(MinPoint.X, MinPoint.Y, MaxPoint.X, MaxPoint.Y, Bounds);
end;

// The off-curve points are "inside" the limits of the on-curve points.
class function TTsScanHairline.QuickCubicNicenessCheck(const Points: TTsPoints4): Boolean;
begin
  Result := (Lt90(Points[1], Points[0], Points[3]) and Lt90(Points[2], Points[0], Points[3]) and
             Lt90(Points[1], Points[3], Points[0]) and Lt90(Points[2], Points[3], Points[0]));
end;

class function TTsScanHairline.Lt90(const P0, Pivot, P2: TTsPoint): Boolean;
begin
  const Dot: Single = (P0 - Pivot).Dot(P2 - Pivot);

  Result := TTsLane.IsGe(Dot, 0.0);
end;

class procedure TTsScanHairline.HairCubic2(const Points: TTsPoints4; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                                           const LineProc: TTsLineProc; const Blitter: TTsBlitter);
begin
  const Lines = ComputeCubicSegments(Points);
  if Lines = 1 then
  begin
    var Line: array[0..1] of TTsPoint;
    Line[0] := Points[0];
    Line[1] := Points[3];
    LineProc(Line, HasClip, Clip, Blitter);
    Exit;
  end;

  const Coeff = TTsCubicCoeff.FromPoints(Points);

  const MaxPoints = CubicPointCount;
  var Tmp: array[0..CubicPointCount - 1] of TTsPoint;
  for var Index := 0 to MaxPoints - 1 do
  begin
    Tmp[Index] := TTsPoint.Zero;
  end;

  const OneOverLines: Single = 1.0 / Lines;
  const Dt = TF32x2.Splat(OneOverLines);
  var T := Default(TF32x2);

  Tmp[0] := Points[0];
  var AllFinite := True;
  for var Index := 1 to Lines - 1 do
  begin
    T := T + Dt;
    Tmp[Index] := TTsPoint.FromF32x2(Coeff.Eval(T));
    if not Tmp[Index].IsFinite then
    begin
      AllFinite := False;
    end;
  end;

  // else some point(s) are non-finite, so don't draw
  if AllFinite then
  begin
    Tmp[Lines] := Points[3];
    LineProc(Slice(Tmp, Lines + 1), HasClip, Clip, Blitter);
  end;
end;

class function TTsScanHairline.ComputeCubicSegments(const Points: TTsPoints4): Integer;
begin
  const P0 = Points[0].ToF32x2;
  const P1 = Points[1].ToF32x2;
  const P2 = Points[2].ToF32x2;
  const P3 = Points[3].ToF32x2;

  const OneThirdValue: Single = 1 / 3;
  const TwoThirdValue: Single = 2 / 3;
  const OneThird = TF32x2.Splat(OneThirdValue);
  const TwoThird = TF32x2.Splat(TwoThirdValue);

  const P13 = OneThird * P3 + TwoThird * P0;
  const P23 = OneThird * P0 + TwoThird * P3;

  const Diff: Single = (P1 - P13).Abs.Max((P2 - P23).Abs).MaxComponent;
  var Tol: Single := 1.0 / 8.0;

  for var Index := 0 to MaxCubicSubdivideLevel - 1 do
  begin
    if Diff < Tol then
    begin
      Exit(1 shl Index);
    end;

    Tol := Tol * 4.0;
  end;

  Result := 1 shl MaxCubicSubdivideLevel;
end;

end.
