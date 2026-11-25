// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/edge_clipper.rs
// Port of: tiny-skia v0.12.0 src/line_clipper.rs
// Port of: tiny-skia v0.12.0 src/edge_builder.rs (PathEdge and PathEdgeIter)
// Copyright (c) 2009 The Android Open Source Project, (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.EdgeClipper;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.PathGeometry,
  Pdf4D.Render.Native.Path;

// is_between_unsorted of line_clipper.rs only serves debug assertions and is not ported.
//
// Clips the segments of a path against a rectangle: lines (line_clipper.rs), and quads and cubics (edge_clipper.rs).
//
// edge_clipper.rs uses PathEdge and PathEdgeIter of edge_builder.rs, and edge_builder.rs uses the clipper. Units cannot use each other,
// so PathEdge and PathEdgeIter are declared here and the edge builder unit uses them from here.
//
// The Rust ClippedEdges is an ArrayVec of 18 edges and panics when it is full. The array here holds 27 = the loose count of 3 pieces in Y
// times 3 in X (9 pieces), with at most 3 edges each (a vertical line, a cubic and another vertical line). The analytic bound is 15
// edges (a cubic has at most 2 extrema in X and 2 in Y, so at most 5 pieces), so the 18 of Rust holds for real input and the larger
// array changes no output.

type
  TTsPoints2 = array[0..1] of TTsPoint;

  TTsPathEdgeKind = (
    LineTo,
    QuadTo,
    CubicTo);

  // The segment of a contour; the points that the kind does not use are zero
  TTsPathEdge = record
  public
    Kind: TTsPathEdgeKind;
    P0: TTsPoint;
    P1: TTsPoint;
    P2: TTsPoint;
    P3: TTsPoint;

    class function MakeLineTo(const Pt0, Pt1: TTsPoint): TTsPathEdge; static;
    class function MakeQuadTo(const Pt0, Pt1, Pt2: TTsPoint): TTsPathEdge; static;
    class function MakeCubicTo(const Pt0, Pt1, Pt2, Pt3: TTsPoint): TTsPathEdge; static;
  end;

  // Lightweight variant of PathIter that only returns segments (e.g. lines/quads).
  //
  // Does not return Move or Close. Always "auto-closes" each contour.
  TTsPathEdgeIter = record
  private
    FVerbs: TArray<TTsPathVerb>;
    FPoints: TArray<TTsPoint>;
    FVerbIndex: Integer;
    FPointsIndex: Integer;
    FMoveTo: TTsPoint;
    FNeedsCloseLine: Boolean;

    function TryPointAt(const Index: Integer; out Pt: TTsPoint): Boolean;
    function TryCloseLine(out Edge: TTsPathEdge): Boolean;
    function Stop: Boolean;

  public
    class function Create(const Path: TTsPath): TTsPathEdgeIter; static;

    function TryNext(out Edge: TTsPathEdge): Boolean;
  end;

  TTsLineClipper = record
  public const
    MaxPoints = 4;

  public
    // Clip the line pts[0]...pts[1] against clip, ignoring segments that
    // lie completely above or below the clip. For portions to the left or
    // right, turn those into vertical line segments that are aligned to the
    // edge of the clip.
    //
    // Return the number of points that result (0 when nothing is left), and store the end-points
    // of those segments sequentially in lines as follows:
    //
    // 1st segment: lines[0]..lines[1]
    // 2nd segment: lines[1]..lines[2]
    // 3rd segment: lines[2]..lines[3]
    class function Clip(const Src: TTsPoints2; const ClipRect: TTsRect; const CanCullToTheRight: Boolean; var Points: TTsPoints4): Integer; static;

    // Intersect the line segment against the rect. If there is a non-empty
    // resulting segment, return true and set dst[] to that segment. If not,
    // return false and ignore dst[].
    //
    // `clip` is specialized for scan-conversion, as it adds vertical
    // segments on the sides to show where the line extended beyond the
    // left or right sides. `intersect` does not.
    class function Intersect(const Src: TTsPoints2; const ClipRect: TTsRect; var Dst: TTsPoints2): Boolean; static;

  private
    // Returns X coordinate of intersection with horizontal line at Y.
    class function SectWithHorizontal(const Src: TTsPoints2; const Y: Single): Single; static;

    class function SectClampWithVertical(const Src: TTsPoints2; const X: Single): Single; static;

    // Returns Y coordinate of intersection with vertical line at X.
    class function SectWithVertical(const Src: TTsPoints2; const X: Single): Single; static;
    class function PinUnsortedF32(const Value, Limit0, Limit1: Single): Single; static;
    class function PinUnsortedF64(const Value, Limit0, Limit1: Double): Double; static;
    class function NestedLt(const A, B, Dim: Single): Boolean; static;

    // returns true if outer contains inner, even if inner is empty.
    class function ContainsNoEmptyCheck(const Outer, Inner: TTsRect): Boolean; static;
  end;

  TTsClippedEdges = record
  public const
    // Rust: Max curvature in X and Y split cubic into 9 pieces, * (line + cubic) = 18; see the unit comment
    MaxEdges = 27;

  public
    Items: array[0..MaxEdges - 1] of TTsPathEdge;
    Count: Integer;

    procedure Push(const Edge: TTsPathEdge);
  end;

  TTsEdgeClipper = record
  private
    FClip: TTsRect;
    FCanCullToTheRight: Boolean;
    FEdges: TTsClippedEdges;

    procedure PushLine(const P0, P1: TTsPoint);
    procedure PushVline(const X: Single; const Y0, Y1: Single; const Reverse: Boolean);
    procedure PushQuad(const Pts: TTsPoints3; const Reverse: Boolean);
    procedure PushCubic(const Pts: TTsPoints4; const Reverse: Boolean);

    // src[] must be monotonic in X and Y
    procedure ClipMonoQuad(const Src: TTsPoints3);

    // src[] must be monotonic in X and Y
    procedure ClipMonoCubic(const Src: TTsPoints4);

    // Modifies pts[] in place so that it is clipped in Y to the clip rect.
    procedure ChopQuadInY(var Pts: TTsPoints3);

    // Modifies pts[] in place so that it is clipped in Y to the clip rect.
    procedure ChopCubicInY(var Pts: TTsPoints4);

  public
    class function Create(const ClipRect: TTsRect; const CanCullToTheRight: Boolean): TTsEdgeClipper; static;

    // The functions return False when no edge is left
    function TryClipLine(const P0, P1: TTsPoint; out Edges: TTsClippedEdges): Boolean;
    function TryClipQuad(const P0, P1, P2: TTsPoint; out Edges: TTsClippedEdges): Boolean;
    function TryClipCubic(const P0, P1, P2, P3: TTsPoint; out Edges: TTsClippedEdges): Boolean;
  end;

  TTsEdgeClipperIter = record
  private
    FEdgeIter: TTsPathEdgeIter;
    FClip: TTsRect;
    FCanCullToTheRight: Boolean;

  public
    class function Create(const Path: TTsPath; const ClipRect: TTsRect; const CanCullToTheRight: Boolean): TTsEdgeClipperIter; static;

    // The edges of the next segment that has some part inside the clip; False at the end of the path
    function TryNext(out Edges: TTsClippedEdges): Boolean;
  end;

implementation

const
  // Delphi evaluates a Single expression with a real literal in Double; the literals of the f32 arithmetic are typed Single constants
  Half: Single = 0.5;
  Quarter: Single = 0.25;
  Two: Single = 2.0;
  Three: Single = 3.0;

type
  TSingles4 = array[0..3] of Single;

{ TTsPathEdge }

class function TTsPathEdge.MakeLineTo(const Pt0, Pt1: TTsPoint): TTsPathEdge;
begin
  Result := Default(TTsPathEdge);
  Result.Kind := TTsPathEdgeKind.LineTo;
  Result.P0 := Pt0;
  Result.P1 := Pt1;
end;

class function TTsPathEdge.MakeQuadTo(const Pt0, Pt1, Pt2: TTsPoint): TTsPathEdge;
begin
  Result := Default(TTsPathEdge);
  Result.Kind := TTsPathEdgeKind.QuadTo;
  Result.P0 := Pt0;
  Result.P1 := Pt1;
  Result.P2 := Pt2;
end;

class function TTsPathEdge.MakeCubicTo(const Pt0, Pt1, Pt2, Pt3: TTsPoint): TTsPathEdge;
begin
  Result := Default(TTsPathEdge);
  Result.Kind := TTsPathEdgeKind.CubicTo;
  Result.P0 := Pt0;
  Result.P1 := Pt1;
  Result.P2 := Pt2;
  Result.P3 := Pt3;
end;

{ TTsPathEdgeIter }

class function TTsPathEdgeIter.Create(const Path: TTsPath): TTsPathEdgeIter;
begin
  Result := Default(TTsPathEdgeIter);
  Result.FVerbs := Path.Verbs;
  Result.FPoints := Path.Points;
  Result.FMoveTo := TTsPoint.Zero;
end;

function TTsPathEdgeIter.TryPointAt(const Index: Integer; out Pt: TTsPoint): Boolean;
begin
  Pt := TTsPoint.Zero;

  // Rust indexes the points of a valid path, which cannot fail
  Result := ((Index >= 0) and (Index < Length(FPoints)));
  if Result then
  begin
    Pt := FPoints[Index];
  end;
end;

function TTsPathEdgeIter.TryCloseLine(out Edge: TTsPathEdge): Boolean;
begin
  Edge := Default(TTsPathEdge);
  FNeedsCloseLine := False;

  var Last: TTsPoint;
  if not TryPointAt(FPointsIndex - 1, Last) then
  begin
    Exit(Stop);
  end;

  Edge := TTsPathEdge.MakeLineTo(Last, FMoveTo);
  Result := True;
end;

function TTsPathEdgeIter.Stop: Boolean;
begin
  FVerbIndex := Length(FVerbs);
  FNeedsCloseLine := False;

  Result := False;
end;

function TTsPathEdgeIter.TryNext(out Edge: TTsPathEdge): Boolean;
begin
  Edge := Default(TTsPathEdge);

  while FVerbIndex < Length(FVerbs) do
  begin
    const Verb = FVerbs[FVerbIndex];
    Inc(FVerbIndex);

    case Verb of
      TTsPathVerb.Move:
      begin
        const HadCloseLine = FNeedsCloseLine;

        var CloseEdge := Default(TTsPathEdge);
        if HadCloseLine and (not TryCloseLine(CloseEdge)) then
        begin
          Exit(False);
        end;

        if not TryPointAt(FPointsIndex, FMoveTo) then
        begin
          Exit(Stop);
        end;

        Inc(FPointsIndex);

        if HadCloseLine then
        begin
          Edge := CloseEdge;
          Exit(True);
        end;
      end;

      TTsPathVerb.Close:
      begin
        if FNeedsCloseLine then
        begin
          Exit(TryCloseLine(Edge));
        end;
      end;
    else
      // Actual edge.
      FNeedsCloseLine := True;

      var P0, P1, P2, P3: TTsPoint;
      case Verb of
        TTsPathVerb.Line:
        begin
          if not (TryPointAt(FPointsIndex - 1, P0) and TryPointAt(FPointsIndex, P1)) then
          begin
            Exit(Stop);
          end;

          Edge := TTsPathEdge.MakeLineTo(P0, P1);
          Inc(FPointsIndex);
        end;

        TTsPathVerb.Quad:
        begin
          if not (TryPointAt(FPointsIndex - 1, P0) and TryPointAt(FPointsIndex, P1) and TryPointAt(FPointsIndex + 1, P2)) then
          begin
            Exit(Stop);
          end;

          Edge := TTsPathEdge.MakeQuadTo(P0, P1, P2);
          Inc(FPointsIndex, 2);
        end;
      else
        if not (TryPointAt(FPointsIndex - 1, P0) and TryPointAt(FPointsIndex, P1) and TryPointAt(FPointsIndex + 1, P2) and
                TryPointAt(FPointsIndex + 2, P3)) then
        begin
          Exit(Stop);
        end;

        Edge := TTsPathEdge.MakeCubicTo(P0, P1, P2, P3);
        Inc(FPointsIndex, 3);
      end;

      Exit(True);
    end;
  end;

  if FNeedsCloseLine then
  begin
    Exit(TryCloseLine(Edge));
  end;

  Result := False;
end;

{ TTsLineClipper }

class function TTsLineClipper.Clip(const Src: TTsPoints2; const ClipRect: TTsRect; const CanCullToTheRight: Boolean;
                                   var Points: TTsPoints4): Integer;
begin
  var Index0: Integer;
  var Index1: Integer;
  if Src[0].Y < Src[1].Y then
  begin
    Index0 := 0;
    Index1 := 1;
  end
  else
  begin
    Index0 := 1;
    Index1 := 0;
  end;

  // Check if we're completely clipped out in Y (above or below)

  if Src[Index1].Y <= ClipRect.Top then
  begin
    // we're above the clip
    Exit(0);
  end;

  if Src[Index0].Y >= ClipRect.Bottom then
  begin
    // we're below the clip
    Exit(0);
  end;

  // Chop in Y to produce a single segment, stored in tmp[0..1]

  var Tmp := Src;

  // now compute intersections
  if Src[Index0].Y < ClipRect.Top then
  begin
    Tmp[Index0] := TTsPoint.FromXY(SectWithHorizontal(Src, ClipRect.Top), ClipRect.Top);
  end;

  if Tmp[Index1].Y > ClipRect.Bottom then
  begin
    Tmp[Index1] := TTsPoint.FromXY(SectWithHorizontal(Src, ClipRect.Bottom), ClipRect.Bottom);
  end;

  // Chop it into 1..3 segments that are wholly within the clip in X.

  // temp storage for up to 3 segments
  var ResultStorage: TTsPoints4;
  for var Index := 0 to High(ResultStorage) do
  begin
    ResultStorage[Index] := TTsPoint.Zero;
  end;

  var LineCount := 1;
  var Reverse: Boolean;

  if Src[0].X < Src[1].X then
  begin
    Index0 := 0;
    Index1 := 1;
    Reverse := False;
  end
  else
  begin
    Index0 := 1;
    Index1 := 0;
    Reverse := True;
  end;

  if Tmp[Index1].X <= ClipRect.Left then
  begin
    // wholly to the left
    Tmp[0].X := ClipRect.Left;
    Tmp[1].X := ClipRect.Left;
    Reverse := False;

    ResultStorage[0] := Tmp[0];
    ResultStorage[1] := Tmp[1];
  end
  else if Tmp[Index0].X >= ClipRect.Right then
  begin
    // wholly to the right
    if CanCullToTheRight then
    begin
      Exit(0);
    end;

    Tmp[0].X := ClipRect.Right;
    Tmp[1].X := ClipRect.Right;
    Reverse := False;

    ResultStorage[0] := Tmp[0];
    ResultStorage[1] := Tmp[1];
  end
  else
  begin
    var Offset := 0;

    if Tmp[Index0].X < ClipRect.Left then
    begin
      ResultStorage[Offset] := TTsPoint.FromXY(ClipRect.Left, Tmp[Index0].Y);
      Inc(Offset);
      ResultStorage[Offset] := TTsPoint.FromXY(ClipRect.Left, SectClampWithVertical(Tmp, ClipRect.Left));
    end
    else
    begin
      ResultStorage[Offset] := Tmp[Index0];
    end;

    Inc(Offset);

    if Tmp[Index1].X > ClipRect.Right then
    begin
      ResultStorage[Offset] := TTsPoint.FromXY(ClipRect.Right, SectClampWithVertical(Tmp, ClipRect.Right));
      Inc(Offset);
      ResultStorage[Offset] := TTsPoint.FromXY(ClipRect.Right, Tmp[Index1].Y);
    end
    else
    begin
      ResultStorage[Offset] := Tmp[Index1];
    end;

    LineCount := Offset;
  end;

  // Now copy the results into the caller's lines[] parameter
  if Reverse then
  begin
    // copy the pts in reverse order to maintain winding order
    for var Index := 0 to LineCount do
    begin
      Points[LineCount - Index] := ResultStorage[Index];
    end;
  end
  else
  begin
    for var Index := 0 to LineCount do
    begin
      Points[Index] := ResultStorage[Index];
    end;
  end;

  Result := LineCount + 1;
end;

class function TTsLineClipper.SectWithHorizontal(const Src: TTsPoints2; const Y: Single): Single;
begin
  const Dy: Single = Src[1].Y - Src[0].Y;
  if TTsScalar.IsNearlyZero(Dy) then
  begin
    Exit(TTsScalar.Ave(Src[0].X, Src[1].X));
  end;

  // need the extra precision so we don't compute a value that exceeds
  // our original limits
  const X0: Double = Src[0].X;
  const Y0: Double = Src[0].Y;
  const X1: Double = Src[1].X;
  const Y1: Double = Src[1].Y;
  const Intersection: Double = X0 + (Double(Y) - Y0) * (X1 - X0) / (Y1 - Y0);

  // The computed X value might still exceed [X0..X1] due to quantum flux
  // when the doubles were added and subtracted, so we have to pin the
  // answer :(
  const Pinned: Double = PinUnsortedF64(Intersection, X0, X1);

  Result := Single(Pinned);
end;

class function TTsLineClipper.SectClampWithVertical(const Src: TTsPoints2; const X: Single): Single;
begin
  const Y: Single = SectWithVertical(Src, X);

  // Our caller expects y to be between src[0].y and src[1].y (unsorted), but due to the
  // numerics of floats/doubles, we might have computed a value slightly outside of that,
  // so we have to manually clamp afterwards.
  // See skbug.com/7491
  Result := PinUnsortedF32(Y, Src[0].Y, Src[1].Y);
end;

class function TTsLineClipper.SectWithVertical(const Src: TTsPoints2; const X: Single): Single;
begin
  const Dx: Single = Src[1].X - Src[0].X;
  if TTsScalar.IsNearlyZero(Dx) then
  begin
    Exit(TTsScalar.Ave(Src[0].Y, Src[1].Y));
  end;

  // need the extra precision so we don't compute a value that exceeds
  // our original limits
  const X0: Double = Src[0].X;
  const Y0: Double = Src[0].Y;
  const X1: Double = Src[1].X;
  const Y1: Double = Src[1].Y;
  const Intersection: Double = Y0 + (Double(X) - X0) * (Y1 - Y0) / (X1 - X0);

  Result := Single(Intersection);
end;

class function TTsLineClipper.PinUnsortedF32(const Value, Limit0, Limit1: Single): Single;
begin
  var Lower := Limit0;
  var Upper := Limit1;
  if Upper < Lower then
  begin
    Lower := Limit1;
    Upper := Limit0;
  end;

  // now the limits are sorted
  if Value < Lower then
  begin
    Exit(Lower);
  end;

  if Value > Upper then
  begin
    Exit(Upper);
  end;

  Result := Value;
end;

class function TTsLineClipper.PinUnsortedF64(const Value, Limit0, Limit1: Double): Double;
begin
  var Lower := Limit0;
  var Upper := Limit1;
  if Upper < Lower then
  begin
    Lower := Limit1;
    Upper := Limit0;
  end;

  // now the limits are sorted
  if Value < Lower then
  begin
    Exit(Lower);
  end;

  if Value > Upper then
  begin
    Exit(Upper);
  end;

  Result := Value;
end;

class function TTsLineClipper.Intersect(const Src: TTsPoints2; const ClipRect: TTsRect; var Dst: TTsPoints2): Boolean;
begin
  var Bounds: TTsRect;
  const HasBounds = TTsRect.TryFromLTRB(TTsScalar.MinF(Src[0].X, Src[1].X), TTsScalar.MinF(Src[0].Y, Src[1].Y),
                                        TTsScalar.MaxF(Src[0].X, Src[1].X), TTsScalar.MaxF(Src[0].Y, Src[1].Y), Bounds);
  if HasBounds then
  begin
    if ContainsNoEmptyCheck(ClipRect, Bounds) then
    begin
      Dst := Src;
      Exit(True);
    end;

    // check for no overlap, and only permit coincident edges if the line
    // and the edge are collinear
    if NestedLt(Bounds.Right, ClipRect.Left, Bounds.Width) or NestedLt(ClipRect.Right, Bounds.Left, Bounds.Width) or
       NestedLt(Bounds.Bottom, ClipRect.Top, Bounds.Height) or NestedLt(ClipRect.Bottom, Bounds.Top, Bounds.Height) then
    begin
      Exit(False);
    end;
  end;

  var Index0: Integer;
  var Index1: Integer;
  if Src[0].Y < Src[1].Y then
  begin
    Index0 := 0;
    Index1 := 1;
  end
  else
  begin
    Index0 := 1;
    Index1 := 0;
  end;

  var Tmp := Src;

  // now compute Y intersections
  if Tmp[Index0].Y < ClipRect.Top then
  begin
    Tmp[Index0] := TTsPoint.FromXY(SectWithHorizontal(Src, ClipRect.Top), ClipRect.Top);
  end;

  if Tmp[Index1].Y > ClipRect.Bottom then
  begin
    Tmp[Index1] := TTsPoint.FromXY(SectWithHorizontal(Src, ClipRect.Bottom), ClipRect.Bottom);
  end;

  if Tmp[0].X < Tmp[1].X then
  begin
    Index0 := 0;
    Index1 := 1;
  end
  else
  begin
    Index0 := 1;
    Index1 := 0;
  end;

  // check for quick-reject in X again, now that we may have been chopped
  if (Tmp[Index1].X <= ClipRect.Left) or (Tmp[Index0].X >= ClipRect.Right) then
  begin
    // usually we will return false, but we don't if the line is vertical and coincident
    // with the clip.
    if (Tmp[0].X <> Tmp[1].X) or (Tmp[0].X < ClipRect.Left) or (Tmp[0].X > ClipRect.Right) then
    begin
      Exit(False);
    end;
  end;

  if Tmp[Index0].X < ClipRect.Left then
  begin
    Tmp[Index0] := TTsPoint.FromXY(ClipRect.Left, SectWithVertical(Src, ClipRect.Left));
  end;

  if Tmp[Index1].X > ClipRect.Right then
  begin
    Tmp[Index1] := TTsPoint.FromXY(ClipRect.Right, SectWithVertical(Src, ClipRect.Right));
  end;

  Dst := Tmp;
  Result := True;
end;

class function TTsLineClipper.NestedLt(const A, B, Dim: Single): Boolean;
begin
  Result := ((A <= B) and ((A < B) or (Dim > 0.0)));
end;

class function TTsLineClipper.ContainsNoEmptyCheck(const Outer, Inner: TTsRect): Boolean;
begin
  Result := ((Outer.Left <= Inner.Left) and (Outer.Top <= Inner.Top) and (Outer.Right >= Inner.Right) and
             (Outer.Bottom >= Inner.Bottom));
end;

{ TTsClippedEdges }

procedure TTsClippedEdges.Push(const Edge: TTsPathEdge);
begin
  // Rust panics when the ArrayVec is full; MaxEdges cannot be reached
  if Count < MaxEdges then
  begin
    Items[Count] := Edge;
    Inc(Count);
  end;
end;

{ Helpers of the edge clipper }

// src[] must be monotonic in Y. This routine copies src into dst, and sorts
// it to be increasing in Y. If it had to reverse the order of the points,
// it returns true, otherwise it returns false
function SortIncreasingY(const Src: array of TTsPoint; var Dst: array of TTsPoint): Boolean;
begin
  // We need the data to be monotonically increasing in Y.
  // Never fails, because src is always non-empty.
  Result := (Src[0].Y > Src[High(Src)].Y);

  for var Index := 0 to High(Src) do
  begin
    if Result then
    begin
      Dst[Index] := Src[High(Src) - Index];
    end
    else
    begin
      Dst[Index] := Src[Index];
    end;
  end;
end;

function QuickReject(const Bounds, ClipRect: TTsRect): Boolean;
begin
  Result := ((Bounds.Top >= ClipRect.Bottom) or (Bounds.Bottom <= ClipRect.Top));
end;

function ChopMonoQuadAt(const C0, C1, C2, Target: Single; var T: TTsNormalizedF32Exclusive): Boolean;
begin
  // Solve F(t) = y where F(t) := [0](1-t)^2 + 2[1]t(1-t) + [2]t^2
  // We solve for t, using quadratic equation, hence we have to rearrange
  // our coefficients to look like At^2 + Bt + C
  const A: Single = C0 - C1 - C1 + C2;
  const B: Single = Two * (C1 - C0);
  const C: Single = C0 - Target;

  var Roots := TTsPathGeometry.NewTValues;
  const Count = TTsPathGeometry.FindUnitQuadRoots(A, B, C, Roots);
  if Count <> 0 then
  begin
    T := Roots[0];
    Exit(True);
  end;

  Result := False;
end;

function ChopMonoQuadAtX(const Pts: TTsPoints3; const X: Single; var T: TTsNormalizedF32Exclusive): Boolean;
begin
  Result := ChopMonoQuadAt(Pts[0].X, Pts[1].X, Pts[2].X, X, T);
end;

function ChopMonoQuadAtY(const Pts: TTsPoints3; const Y: Single; var T: TTsNormalizedF32Exclusive): Boolean;
begin
  Result := ChopMonoQuadAt(Pts[0].Y, Pts[1].Y, Pts[2].Y, Y, T);
end;

function TooBigForReliableFloatMath(const R: TTsRect): Boolean;
begin
  // limit set as the largest float value for which we can still reliably compute things like
  // - chopping at XY extrema
  // - chopping at Y or X values for clipping
  //
  // Current value chosen just by experiment. Larger (and still succeeds) is always better.

  const Limit: Single = 1 shl 22;

  Result := ((R.Left < -Limit) or (R.Top < -Limit) or (R.Right > Limit) or (R.Bottom > Limit));
end;

function MonoCubicClosestT(const Src: TSingles4; const X: Single): TTsNormalizedF32Exclusive;
begin
  var Target: Single := X;
  var T: Single := Half;
  var LastT: Single;
  var BestT: Single := T;
  var Step: Single := Quarter;
  const D: Single = Src[0];
  const A: Single = Src[3] + Three * (Src[1] - Src[2]) - D;
  const B: Single = Three * (Src[2] - Src[1] - Src[1] + D);
  const C: Single = Three * (Src[1] - D);
  Target := Target - D;

  var Closest: Single := TTsScalar.ScalarMax;
  var KeepSearching: Boolean;
  repeat
    const Loc: Single = ((A * T + B) * T + C) * T;
    const Dist: Single = Abs(Loc - Target);
    if Closest > Dist then
    begin
      Closest := Dist;
      BestT := T;
    end;

    LastT := T;
    if Loc < Target then
    begin
      T := T + Step;
    end
    else
    begin
      T := T + (-Step);
    end;

    Step := Step * Half;

    // `while closest > 0.25 && last_t != t` in Rust: the positive comparison is false for NaN, so a NaN ends the search
    KeepSearching := ((Closest > 0.25) and (LastT <> T));
  until not KeepSearching;

  // Rust unwraps new(best_t), which panics when rounding pushed t to 1; new_bounded keeps it inside
  if not TTsNormalizedF32Exclusive.TryCreate(BestT, Result) then
  begin
    Result := TTsNormalizedF32Exclusive.CreateBounded(BestT);
  end;
end;

procedure ChopMonoCubicAtX(const Src: TTsPoints4; const X: Single; var Dst: TTsPoints7);
begin
  if TTsPathGeometry.ChopMonoCubicAtX(Src, X, Dst) then
  begin
    Exit;
  end;

  var SrcValues: TSingles4;
  for var Index := 0 to 3 do
  begin
    SrcValues[Index] := Src[Index].X;
  end;

  TTsPathGeometry.ChopCubicAt2(Src, MonoCubicClosestT(SrcValues, X), Dst);
end;

procedure ChopMonoCubicAtY(const Src: TTsPoints4; const Y: Single; var Dst: TTsPoints7);
begin
  if TTsPathGeometry.ChopMonoCubicAtY(Src, Y, Dst) then
  begin
    Exit;
  end;

  var SrcValues: TSingles4;
  for var Index := 0 to 3 do
  begin
    SrcValues[Index] := Src[Index].Y;
  end;

  TTsPathGeometry.ChopCubicAt2(Src, MonoCubicClosestT(SrcValues, Y), Dst);
end;

function ZeroPoints7: TTsPoints7;
begin
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := TTsPoint.Zero;
  end;
end;

function ZeroPoints5: TTsPoints5;
begin
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := TTsPoint.Zero;
  end;
end;

function ZeroPoints10: TTsPoints10;
begin
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := TTsPoint.Zero;
  end;
end;

{ TTsEdgeClipper }

class function TTsEdgeClipper.Create(const ClipRect: TTsRect; const CanCullToTheRight: Boolean): TTsEdgeClipper;
begin
  Result.FClip := ClipRect;
  Result.FCanCullToTheRight := CanCullToTheRight;
  Result.FEdges.Count := 0;
end;

function TTsEdgeClipper.TryClipLine(const P0, P1: TTsPoint; out Edges: TTsClippedEdges): Boolean;
begin
  Edges.Count := 0;

  var Src: TTsPoints2;
  Src[0] := P0;
  Src[1] := P1;

  var Points: TTsPoints4;
  for var Index := 0 to High(Points) do
  begin
    Points[Index] := TTsPoint.Zero;
  end;

  const PointCount = TTsLineClipper.Clip(Src, FClip, FCanCullToTheRight, Points);
  for var Index := 0 to PointCount - 2 do
  begin
    PushLine(Points[Index], Points[Index + 1]);
  end;

  Edges := FEdges;
  Result := (FEdges.Count > 0);
end;

procedure TTsEdgeClipper.PushLine(const P0, P1: TTsPoint);
begin
  FEdges.Push(TTsPathEdge.MakeLineTo(P0, P1));
end;

procedure TTsEdgeClipper.PushVline(const X: Single; const Y0, Y1: Single; const Reverse: Boolean);
begin
  var From := Y0;
  var Till := Y1;
  if Reverse then
  begin
    From := Y1;
    Till := Y0;
  end;

  FEdges.Push(TTsPathEdge.MakeLineTo(TTsPoint.FromXY(X, From), TTsPoint.FromXY(X, Till)));
end;

function TTsEdgeClipper.TryClipQuad(const P0, P1, P2: TTsPoint; out Edges: TTsClippedEdges): Boolean;
begin
  Edges.Count := 0;

  var Pts: TTsPoints3;
  Pts[0] := P0;
  Pts[1] := P1;
  Pts[2] := P2;

  var Bounds: TTsRect;
  if not TTsRect.TryFromPoints(Pts, Bounds) then
  begin
    Exit(False);
  end;

  if not QuickReject(Bounds, FClip) then
  begin
    var MonoY := ZeroPoints5;
    const CountY = TTsPathGeometry.ChopQuadAtYExtrema(Pts, MonoY);
    for var Y := 0 to CountY do
    begin
      var MonoX := ZeroPoints5;
      var YPoints: TTsPoints3;
      YPoints[0] := MonoY[Y * 2];
      YPoints[1] := MonoY[Y * 2 + 1];
      YPoints[2] := MonoY[Y * 2 + 2];

      const CountX = TTsPathGeometry.ChopQuadAtXExtrema(YPoints, MonoX);
      for var X := 0 to CountX do
      begin
        var XPoints: TTsPoints3;
        XPoints[0] := MonoX[X * 2];
        XPoints[1] := MonoX[X * 2 + 1];
        XPoints[2] := MonoX[X * 2 + 2];

        ClipMonoQuad(XPoints);
      end;
    end;
  end;

  Edges := FEdges;
  Result := (FEdges.Count > 0);
end;

procedure TTsEdgeClipper.ClipMonoQuad(const Src: TTsPoints3);
begin
  var Pts: TTsPoints3;
  var Reverse := SortIncreasingY(Src, Pts);

  // are we completely above or below
  if (Pts[2].Y <= FClip.Top) or (Pts[0].Y >= FClip.Bottom) then
  begin
    Exit;
  end;

  // Now chop so that pts is contained within clip in Y
  ChopQuadInY(Pts);

  if Pts[0].X > Pts[2].X then
  begin
    const Swapped = Pts[0];
    Pts[0] := Pts[2];
    Pts[2] := Swapped;

    Reverse := not Reverse;
  end;

  // Now chop in X has needed, and record the segments

  if Pts[2].X <= FClip.Left then
  begin
    // wholly to the left
    PushVline(FClip.Left, Pts[0].Y, Pts[2].Y, Reverse);
    Exit;
  end;

  if Pts[0].X >= FClip.Right then
  begin
    // wholly to the right
    if not FCanCullToTheRight then
    begin
      PushVline(FClip.Right, Pts[0].Y, Pts[2].Y, Reverse);
    end;

    Exit;
  end;

  var T := TTsNormalizedF32Exclusive.Any;
  var Tmp := ZeroPoints5;

  // are we partially to the left
  if Pts[0].X < FClip.Left then
  begin
    if ChopMonoQuadAtX(Pts, FClip.Left, T) then
    begin
      TTsPathGeometry.ChopQuadAt(Pts, T, Tmp);
      PushVline(FClip.Left, Tmp[0].Y, Tmp[2].Y, Reverse);

      // clamp to clean up imprecise numerics in the chop
      Tmp[2].X := FClip.Left;
      Tmp[3].X := TTsScalar.MaxF(Tmp[3].X, FClip.Left);

      Pts[0] := Tmp[2];
      Pts[1] := Tmp[3];
    end
    else
    begin
      // if chopMonoQuadAtY failed, then we may have hit inexact numerics
      // so we just clamp against the left
      PushVline(FClip.Left, Pts[0].Y, Pts[2].Y, Reverse);
      Exit;
    end;
  end;

  // are we partially to the right
  if Pts[2].X > FClip.Right then
  begin
    if ChopMonoQuadAtX(Pts, FClip.Right, T) then
    begin
      TTsPathGeometry.ChopQuadAt(Pts, T, Tmp);

      // clamp to clean up imprecise numerics in the chop
      Tmp[1].X := TTsScalar.MinF(Tmp[1].X, FClip.Right);
      Tmp[2].X := FClip.Right;

      var First: TTsPoints3;
      First[0] := Tmp[0];
      First[1] := Tmp[1];
      First[2] := Tmp[2];

      PushQuad(First, Reverse);
      PushVline(FClip.Right, Tmp[2].Y, Tmp[4].Y, Reverse);
    end
    else
    begin
      // if chopMonoQuadAtY failed, then we may have hit inexact numerics
      // so we just clamp against the right
      Pts[1].X := TTsScalar.MinF(Pts[1].X, FClip.Right);
      Pts[2].X := TTsScalar.MinF(Pts[2].X, FClip.Right);
      PushQuad(Pts, Reverse);
    end;
  end
  else
  begin
    // wholly inside the clip
    PushQuad(Pts, Reverse);
  end;
end;

procedure TTsEdgeClipper.PushQuad(const Pts: TTsPoints3; const Reverse: Boolean);
begin
  if Reverse then
  begin
    FEdges.Push(TTsPathEdge.MakeQuadTo(Pts[2], Pts[1], Pts[0]));
  end
  else
  begin
    FEdges.Push(TTsPathEdge.MakeQuadTo(Pts[0], Pts[1], Pts[2]));
  end;
end;

procedure TTsEdgeClipper.ChopQuadInY(var Pts: TTsPoints3);
begin
  var T := TTsNormalizedF32Exclusive.Any;
  var Tmp := ZeroPoints5;

  // are we partially above
  if Pts[0].Y < FClip.Top then
  begin
    if ChopMonoQuadAtY(Pts, FClip.Top, T) then
    begin
      // take the 2nd chopped quad
      TTsPathGeometry.ChopQuadAt(Pts, T, Tmp);

      // clamp to clean up imprecise numerics in the chop
      Tmp[2].Y := FClip.Top;
      Tmp[3].Y := TTsScalar.MaxF(Tmp[3].Y, FClip.Top);

      Pts[0] := Tmp[2];
      Pts[1] := Tmp[3];
    end
    else
    begin
      // if chop_mono_quad_at_y failed, then we may have hit inexact numerics
      // so we just clamp against the top
      for var Index := 0 to High(Pts) do
      begin
        if Pts[Index].Y < FClip.Top then
        begin
          Pts[Index].Y := FClip.Top;
        end;
      end;
    end;
  end;

  // are we partially below
  if Pts[2].Y > FClip.Bottom then
  begin
    if ChopMonoQuadAtY(Pts, FClip.Bottom, T) then
    begin
      TTsPathGeometry.ChopQuadAt(Pts, T, Tmp);

      // clamp to clean up imprecise numerics in the chop
      Tmp[1].Y := TTsScalar.MinF(Tmp[1].Y, FClip.Bottom);
      Tmp[2].Y := FClip.Bottom;

      Pts[1] := Tmp[1];
      Pts[2] := Tmp[2];
    end
    else
    begin
      // if chop_mono_quad_at_y failed, then we may have hit inexact numerics
      // so we just clamp against the bottom
      for var Index := 0 to High(Pts) do
      begin
        if Pts[Index].Y > FClip.Bottom then
        begin
          Pts[Index].Y := FClip.Bottom;
        end;
      end;
    end;
  end;
end;

function TTsEdgeClipper.TryClipCubic(const P0, P1, P2, P3: TTsPoint; out Edges: TTsClippedEdges): Boolean;
begin
  Edges.Count := 0;

  var Pts: TTsPoints4;
  Pts[0] := P0;
  Pts[1] := P1;
  Pts[2] := P2;
  Pts[3] := P3;

  var Bounds: TTsRect;
  if not TTsRect.TryFromPoints(Pts, Bounds) then
  begin
    Exit(False);
  end;

  // check if we're clipped out vertically
  if (Bounds.Bottom > FClip.Top) and (Bounds.Top < FClip.Bottom) then
  begin
    if TooBigForReliableFloatMath(Bounds) then
    begin
      // can't safely clip the cubic, so we give up and draw a line (which we can safely clip)
      //
      // If we rewrote chopcubicat*extrema and chopmonocubic using doubles, we could very
      // likely always handle the cubic safely, but (it seems) at a big loss in speed, so
      // we'd only want to take that alternate impl if needed.
      Exit(TryClipLine(P0, P3, Edges));
    end;

    var MonoY := ZeroPoints10;
    const CountY = TTsPathGeometry.ChopCubicAtYExtrema(Pts, MonoY);
    for var Y := 0 to CountY do
    begin
      var MonoX := ZeroPoints10;
      var YPoints: TTsPoints4;
      for var Index := 0 to 3 do
      begin
        YPoints[Index] := MonoY[Y * 3 + Index];
      end;

      const CountX = TTsPathGeometry.ChopCubicAtXExtrema(YPoints, MonoX);
      for var X := 0 to CountX do
      begin
        var XPoints: TTsPoints4;
        for var Index := 0 to 3 do
        begin
          XPoints[Index] := MonoX[X * 3 + Index];
        end;

        ClipMonoCubic(XPoints);
      end;
    end;
  end;

  Edges := FEdges;
  Result := (FEdges.Count > 0);
end;

procedure TTsEdgeClipper.ClipMonoCubic(const Src: TTsPoints4);
begin
  var Pts: TTsPoints4;
  var Reverse := SortIncreasingY(Src, Pts);

  // are we completely above or below
  if (Pts[3].Y <= FClip.Top) or (Pts[0].Y >= FClip.Bottom) then
  begin
    Exit;
  end;

  // Now chop so that pts is contained within clip in Y
  ChopCubicInY(Pts);

  if Pts[0].X > Pts[3].X then
  begin
    var Swapped := Pts[0];
    Pts[0] := Pts[3];
    Pts[3] := Swapped;

    Swapped := Pts[1];
    Pts[1] := Pts[2];
    Pts[2] := Swapped;

    Reverse := not Reverse;
  end;

  // Now chop in X has needed, and record the segments

  if Pts[3].X <= FClip.Left then
  begin
    // wholly to the left
    PushVline(FClip.Left, Pts[0].Y, Pts[3].Y, Reverse);
    Exit;
  end;

  if Pts[0].X >= FClip.Right then
  begin
    // wholly to the right
    if not FCanCullToTheRight then
    begin
      PushVline(FClip.Right, Pts[0].Y, Pts[3].Y, Reverse);
    end;

    Exit;
  end;

  // are we partially to the left
  if Pts[0].X < FClip.Left then
  begin
    var Tmp := ZeroPoints7;
    ChopMonoCubicAtX(Pts, FClip.Left, Tmp);
    PushVline(FClip.Left, Tmp[0].Y, Tmp[3].Y, Reverse);

    // tmp[3, 4].fX should all be to the right of clip.left().
    // Since we can't trust the numerics of
    // the chopper, we force those conditions now
    Tmp[3].X := FClip.Left;
    Tmp[4].X := TTsScalar.MaxF(Tmp[4].X, FClip.Left);

    Pts[0] := Tmp[3];
    Pts[1] := Tmp[4];
    Pts[2] := Tmp[5];
  end;

  // are we partially to the right
  if Pts[3].X > FClip.Right then
  begin
    var Tmp := ZeroPoints7;
    ChopMonoCubicAtX(Pts, FClip.Right, Tmp);
    Tmp[3].X := FClip.Right;
    Tmp[2].X := TTsScalar.MinF(Tmp[2].X, FClip.Right);

    var First: TTsPoints4;
    for var Index := 0 to 3 do
    begin
      First[Index] := Tmp[Index];
    end;

    PushCubic(First, Reverse);
    PushVline(FClip.Right, Tmp[3].Y, Tmp[6].Y, Reverse);
  end
  else
  begin
    // wholly inside the clip
    PushCubic(Pts, Reverse);
  end;
end;

procedure TTsEdgeClipper.PushCubic(const Pts: TTsPoints4; const Reverse: Boolean);
begin
  if Reverse then
  begin
    FEdges.Push(TTsPathEdge.MakeCubicTo(Pts[3], Pts[2], Pts[1], Pts[0]));
  end
  else
  begin
    FEdges.Push(TTsPathEdge.MakeCubicTo(Pts[0], Pts[1], Pts[2], Pts[3]));
  end;
end;

procedure TTsEdgeClipper.ChopCubicInY(var Pts: TTsPoints4);
begin
  // are we partially above
  if Pts[0].Y < FClip.Top then
  begin
    var Tmp := ZeroPoints7;
    ChopMonoCubicAtY(Pts, FClip.Top, Tmp);

    // For a large range in the points, we can do a poor job of chopping, such that the t
    // we computed resulted in the lower cubic still being partly above the clip.
    //
    // If just the first or first 2 Y values are above the fTop, we can just smash them
    // down. If the first 3 Ys are above fTop, we can't smash all 3, as that can really
    // distort the cubic. In this case, we take the first output (tmp[3..6] and treat it as
    // a guess, and re-chop against fTop. Then we fall through to checking if we need to
    // smash the first 1 or 2 Y values.
    if (Tmp[3].Y < FClip.Top) and (Tmp[4].Y < FClip.Top) and (Tmp[5].Y < FClip.Top) then
    begin
      var Tmp2: TTsPoints4;
      for var Index := 0 to 3 do
      begin
        Tmp2[Index] := Tmp[3 + Index];
      end;

      ChopMonoCubicAtY(Tmp2, FClip.Top, Tmp);
    end;

    // tmp[3, 4].y should all be to the below clip.fTop.
    // Since we can't trust the numerics of the chopper, we force those conditions now
    Tmp[3].Y := FClip.Top;
    Tmp[4].Y := TTsScalar.MaxF(Tmp[4].Y, FClip.Top);

    Pts[0] := Tmp[3];
    Pts[1] := Tmp[4];
    Pts[2] := Tmp[5];
  end;

  // are we partially below
  if Pts[3].Y > FClip.Bottom then
  begin
    var Tmp := ZeroPoints7;
    ChopMonoCubicAtY(Pts, FClip.Bottom, Tmp);
    Tmp[3].Y := FClip.Bottom;
    Tmp[2].Y := TTsScalar.MinF(Tmp[2].Y, FClip.Bottom);

    Pts[1] := Tmp[1];
    Pts[2] := Tmp[2];
    Pts[3] := Tmp[3];
  end;
end;

{ TTsEdgeClipperIter }

class function TTsEdgeClipperIter.Create(const Path: TTsPath; const ClipRect: TTsRect; const CanCullToTheRight: Boolean): TTsEdgeClipperIter;
begin
  Result := Default(TTsEdgeClipperIter);
  Result.FEdgeIter := TTsPathEdgeIter.Create(Path);
  Result.FClip := ClipRect;
  Result.FCanCullToTheRight := CanCullToTheRight;
end;

function TTsEdgeClipperIter.TryNext(out Edges: TTsClippedEdges): Boolean;
begin
  Edges.Count := 0;

  var Edge: TTsPathEdge;
  while FEdgeIter.TryNext(Edge) do
  begin
    var Clipper := TTsEdgeClipper.Create(FClip, FCanCullToTheRight);

    var Found: Boolean;
    case Edge.Kind of
      TTsPathEdgeKind.LineTo:
        Found := Clipper.TryClipLine(Edge.P0, Edge.P1, Edges);

      TTsPathEdgeKind.QuadTo:
        Found := Clipper.TryClipQuad(Edge.P0, Edge.P1, Edge.P2, Edges);
    else
      Found := Clipper.TryClipCubic(Edge.P0, Edge.P1, Edge.P2, Edge.P3, Edges);
    end;

    if Found then
    begin
      Exit(True);
    end;
  end;

  Result := False;
end;

end.
