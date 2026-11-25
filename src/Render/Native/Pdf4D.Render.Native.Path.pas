// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/path.rs
// Port of: tiny-skia v0.12.0 path/src/path_builder.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Path;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.PathGeometry;

// The Rust Option<T> results are TryX functions with an out parameter. The Rust std::fmt::Debug text of a path is not ported.
//
// A path holds its verbs and points in dynamic arrays; a copy of a TTsPath shares them and nothing changes them after the builder made
// the path, so the sharing is safe. TryTransform makes a new points array.
//
// Path.clear (reuse of the allocation of a path in a new builder) is not ported.

type
  TTsPathVerb = (
    Move,
    Line,
    Quad,
    Cubic,
    Close);

  // A path segment. MoveTo and LineTo use P0, QuadTo uses P0 (control) and P1, CubicTo uses P0, P1 and P2 (the last point is the end).
  TTsPathSegment = record
  public
    Verb: TTsPathVerb;
    P0: TTsPoint;
    P1: TTsPoint;
    P2: TTsPoint;

    class function MoveTo(const Pt: TTsPoint): TTsPathSegment; static;
    class function LineTo(const Pt: TTsPoint): TTsPathSegment; static;
    class function QuadTo(const Pt0, Pt1: TTsPoint): TTsPathSegment; static;
    class function CubicTo(const Pt0, Pt1, Pt2: TTsPoint): TTsPathSegment; static;
    class function CloseSegment: TTsPathSegment; static;

    class operator Equal(const A, B: TTsPathSegment): Boolean;
    class operator NotEqual(const A, B: TTsPathSegment): Boolean;
  end;

  // A path segments iterator
  TTsPathSegmentsIter = record
  private
    FVerbs: TArray<TTsPathVerb>;
    FPoints: TArray<TTsPoint>;
    FVerbIndex: Integer;
    FPointsIndex: Integer;
    FIsAutoClose: Boolean;
    FLastMoveTo: TTsPoint;
    FLastPoint: TTsPoint;

  public
    class function Create(const Verbs: TArray<TTsPathVerb>; const Points: TArray<TTsPoint>): TTsPathSegmentsIter; static;

    // Sets the auto closing mode. Off by default.
    //
    // When enabled, emits an additional LineTo from the current position to the previous MoveTo. And only then emits Close.
    procedure SetAutoClose(const Flag: Boolean);
    function AutoClose: TTsPathSegment;
    function HasValidTangent: Boolean;

    // The current verb
    function CurrVerb: TTsPathVerb;

    // The next verb, or False at the end of the path
    function TryNextVerb(out Verb: TTsPathVerb): Boolean;

    // The next segment, or False at the end of the path
    function TryNext(out Segment: TTsPathSegment): Boolean;

    // The last point of the segment that was returned last
    function LastPoint: TTsPoint;
    function LastMoveTo: TTsPoint;
  end;

  // A Bezier path. Can be created via TTsPathBuilder.
  //
  // Guarantees:
  // - Has a valid, precomputed bounds.
  // - All points are finite.
  // - Has at least two segments.
  // - Each contour starts with a MoveTo.
  // - No duplicated Move.
  // - No duplicated Close.
  // - Zero-length contours are allowed.
  TTsPath = record
  private
    FVerbs: TArray<TTsPathVerb>;
    FPoints: TArray<TTsPoint>;
    FBounds: TTsRect;

    class function ComputeQuadExtremas(const P0, P1, P2: TTsPoint; var Extremas: TTsPoints5): Integer; static;
    class function ComputeCubicExtremas(const P0, P1, P2, P3: TTsPoint; var Extremas: TTsPoints5): Integer; static;

  public
    // The path of the parts the builder made; they must follow the guarantees above
    class function FromParts(const Verbs: TArray<TTsPathVerb>; const Points: TArray<TTsPoint>; const Bounds: TTsRect): TTsPath; static;

    // The number of segments in the path
    function Len: Integer;
    function IsEmpty: Boolean;

    // The bounds of the path's points. The value is already calculated.
    function Bounds: TTsRect;

    // The tight bounds of the path. This operation can be expensive.
    function TryComputeTightBounds(out Tight: TTsRect): Boolean;

    // The internal arrays of verbs and points; the caller must not change them
    function Verbs: TArray<TTsPathVerb>;
    function Points: TArray<TTsPoint>;

    // The transformed path. Some points may become NaN/inf therefore this method can fail.
    function TryTransform(const Ts: TTsTransform; out Transformed: TTsPath): Boolean;

    function Segments: TTsPathSegmentsIter;
  end;

  // A path builder. A zero-filled builder is a new builder, TTsPathBuilder.New is the same.
  TTsPathBuilder = record
  private
    FVerbs: TArray<TTsPathVerb>;
    FVerbCount: Integer;
    FPoints: TArray<TTsPoint>;
    FPointCount: Integer;
    FLastMoveToIndex: Integer;
    // The inverse of move_to_required of the Rust code, so that a zero-filled record has the Rust initial value (a move is required)
    FMoveToNotRequired: Boolean;

    procedure AddVerb(const Verb: TTsPathVerb);
    procedure AddPoint(const Pt: TTsPoint);
    procedure InjectMoveToIfNeeded;
    function LastVerbIs(const Verb: TTsPathVerb): Boolean;

  public
    class function New: TTsPathBuilder; static;

    // The number of points depends on a verb type: Move 1, Line 1, Quad 2, Cubic 3, Close 0
    class function WithCapacity(const VerbsCapacity, PointsCapacity: Integer): TTsPathBuilder; static;

    // The path of a rectangle. Segments are created clockwise: TopLeft, TopRight, BottomRight, BottomLeft. The contour is closed.
    class function FromRect(const Rect: TTsRect): TTsPath; static;
    class function TryFromCircle(const Cx, Cy, Radius: Single; out Path: TTsPath): Boolean; static;
    class function TryFromOval(const Oval: TTsRect; out Path: TTsPath): Boolean; static;

    procedure Reserve(const AdditionalVerbs, AdditionalPoints: Integer);

    // The current number of segments in the builder
    function Len: Integer;
    function IsEmpty: Boolean;

    // Adds the beginning of a contour. Multiple continuous MoveTo segments are not allowed. If the previous segment was also MoveTo, it
    // will be overwritten with the current one.
    procedure MoveTo(const X, Y: Single);

    // Adds a line from the last point.
    // - If the path is empty - adds Move(0, 0) first.
    // - If the path ends with Close - adds Move(last_x, last_y) first.
    procedure LineTo(const X, Y: Single);

    // Adds a quad curve from the last point to X, Y. The same Move rules as LineTo.
    procedure QuadTo(const X1, Y1, X, Y: Single);
    procedure QuadToPt(const P1, P: TTsPoint);

    // We do not support conic segments, but Skia still relies on them from time to time. This method will simply convert the input data
    // into quad segments.
    procedure ConicTo(const X1, Y1, X, Y, Weight: Single);
    procedure ConicPointsTo(const Pt1, Pt2: TTsPoint; const Weight: Single);

    // Adds a cubic curve from the last point to X, Y. The same Move rules as LineTo.
    procedure CubicTo(const X1, Y1, X2, Y2, X, Y: Single);
    procedure CubicToPt(const P1, P2, P: TTsPoint);

    // Closes the current contour. A closed contour connects the first and the last point with a line, forming a continuous loop.
    //
    // Does nothing when the path is empty or already closed.
    //
    // Open and closed contour will be filled the same way. Stroking an open contour will add LineCap at contour's start and end. Stroking
    // an closed contour will add LineJoin at contour's start and end.
    procedure Close;

    function TryLastPoint(out Pt: TTsPoint): Boolean;
    procedure SetLastPoint(const Pt: TTsPoint);
    function IsZeroLengthSincePoint(const StartPtIndex: Integer): Boolean;

    // Adds a rectangle contour. The contour is closed and has a clock-wise direction.
    procedure PushRect(const Rect: TTsRect);

    // Adds an oval contour bounded by the provided rectangle. The contour is closed and has a clock-wise direction.
    procedure PushOval(const Oval: TTsRect);

    // Adds a circle contour. The contour is closed and has a clock-wise direction.
    //
    // Does nothing when the radius is <= 0 or any value is not finite or really large.
    procedure PushCircle(const X, Y, R: Single);

    procedure PushPath(const Other: TTsPath);
    procedure PushPathBuilder(const Other: TTsPathBuilder);

    // Appends, in a reverse order, the first contour of the other builder ignoring its last point
    procedure ReversePathTo(const Other: TTsPathBuilder);

    // Reset the builder
    procedure Clear;

    // Finishes the builder and returns the path; the builder is empty afterwards. Returns False when the path is empty, is only a Move or
    // has invalid bounds (a non-finite point).
    function TryFinish(out Path: TTsPath): Boolean;
  end;

implementation

{ TTsPathSegment }

class function TTsPathSegment.MoveTo(const Pt: TTsPoint): TTsPathSegment;
begin
  Result := Default(TTsPathSegment);
  Result.Verb := TTsPathVerb.Move;
  Result.P0 := Pt;
end;

class function TTsPathSegment.LineTo(const Pt: TTsPoint): TTsPathSegment;
begin
  Result := Default(TTsPathSegment);
  Result.Verb := TTsPathVerb.Line;
  Result.P0 := Pt;
end;

class function TTsPathSegment.QuadTo(const Pt0, Pt1: TTsPoint): TTsPathSegment;
begin
  Result := Default(TTsPathSegment);
  Result.Verb := TTsPathVerb.Quad;
  Result.P0 := Pt0;
  Result.P1 := Pt1;
end;

class function TTsPathSegment.CubicTo(const Pt0, Pt1, Pt2: TTsPoint): TTsPathSegment;
begin
  Result.Verb := TTsPathVerb.Cubic;
  Result.P0 := Pt0;
  Result.P1 := Pt1;
  Result.P2 := Pt2;
end;

class function TTsPathSegment.CloseSegment: TTsPathSegment;
begin
  Result := Default(TTsPathSegment);
  Result.Verb := TTsPathVerb.Close;
end;

class operator TTsPathSegment.Equal(const A, B: TTsPathSegment): Boolean;
begin
  if A.Verb <> B.Verb then
  begin
    Exit(False);
  end;

  case A.Verb of
    TTsPathVerb.Move, TTsPathVerb.Line:
      Result := (A.P0 = B.P0);

    TTsPathVerb.Quad:
      Result := (A.P0 = B.P0) and (A.P1 = B.P1);

    TTsPathVerb.Cubic:
      Result := (A.P0 = B.P0) and (A.P1 = B.P1) and (A.P2 = B.P2);

    TTsPathVerb.Close:
      Result := True;
  else
    raise EInvalidOpException.Create('Unknown path verb');
  end;
end;

class operator TTsPathSegment.NotEqual(const A, B: TTsPathSegment): Boolean;
begin
  Result := not (A = B);
end;

{ TTsPathSegmentsIter }

class function TTsPathSegmentsIter.Create(const Verbs: TArray<TTsPathVerb>; const Points: TArray<TTsPoint>): TTsPathSegmentsIter;
begin
  Result := Default(TTsPathSegmentsIter);
  Result.FVerbs := Verbs;
  Result.FPoints := Points;
end;

procedure TTsPathSegmentsIter.SetAutoClose(const Flag: Boolean);
begin
  FIsAutoClose := Flag;
end;

function TTsPathSegmentsIter.AutoClose: TTsPathSegment;
begin
  if FIsAutoClose and (FLastPoint <> FLastMoveTo) then
  begin
    Dec(FVerbIndex);
    Result := TTsPathSegment.LineTo(FLastMoveTo);
  end
  else
  begin
    Result := TTsPathSegment.CloseSegment;
  end;
end;

function TTsPathSegmentsIter.HasValidTangent: Boolean;
begin
  var Iter := Self;
  var Segment: TTsPathSegment;
  while Iter.TryNext(Segment) do
  begin
    case Segment.Verb of
      TTsPathVerb.Move:
        Exit(False);

      TTsPathVerb.Line:
      begin
        if Iter.FLastPoint = Segment.P0 then
        begin
          Continue;
        end;

        Exit(True);
      end;

      TTsPathVerb.Quad:
      begin
        if (Iter.FLastPoint = Segment.P0) and (Iter.FLastPoint = Segment.P1) then
        begin
          Continue;
        end;

        Exit(True);
      end;

      TTsPathVerb.Cubic:
      begin
        if (Iter.FLastPoint = Segment.P0) and (Iter.FLastPoint = Segment.P1) and (Iter.FLastPoint = Segment.P2) then
        begin
          Continue;
        end;

        Exit(True);
      end;

      TTsPathVerb.Close:
        Exit(False);
    else
      raise EInvalidOpException.Create('Unknown path verb');
    end;
  end;

  Result := False;
end;

function TTsPathSegmentsIter.CurrVerb: TTsPathVerb;
begin
  Result := FVerbs[FVerbIndex - 1];
end;

function TTsPathSegmentsIter.TryNextVerb(out Verb: TTsPathVerb): Boolean;
begin
  Verb := TTsPathVerb.Move;

  Result := (FVerbIndex < Length(FVerbs));
  if Result then
  begin
    Verb := FVerbs[FVerbIndex];
  end;
end;

function TTsPathSegmentsIter.TryNext(out Segment: TTsPathSegment): Boolean;
begin
  Segment := Default(TTsPathSegment);

  if FVerbIndex >= Length(FVerbs) then
  begin
    Exit(False);
  end;

  const Verb = FVerbs[FVerbIndex];
  Inc(FVerbIndex);

  case Verb of
    TTsPathVerb.Move:
    begin
      Inc(FPointsIndex);
      FLastMoveTo := FPoints[FPointsIndex - 1];
      FLastPoint := FLastMoveTo;
      Segment := TTsPathSegment.MoveTo(FLastMoveTo);
    end;

    TTsPathVerb.Line:
    begin
      Inc(FPointsIndex);
      FLastPoint := FPoints[FPointsIndex - 1];
      Segment := TTsPathSegment.LineTo(FLastPoint);
    end;

    TTsPathVerb.Quad:
    begin
      Inc(FPointsIndex, 2);
      FLastPoint := FPoints[FPointsIndex - 1];
      Segment := TTsPathSegment.QuadTo(FPoints[FPointsIndex - 2], FLastPoint);
    end;

    TTsPathVerb.Cubic:
    begin
      Inc(FPointsIndex, 3);
      FLastPoint := FPoints[FPointsIndex - 1];
      Segment := TTsPathSegment.CubicTo(FPoints[FPointsIndex - 3], FPoints[FPointsIndex - 2], FLastPoint);
    end;

    TTsPathVerb.Close:
    begin
      Segment := AutoClose;
      FLastPoint := FLastMoveTo;
    end;
  else
    raise EInvalidOpException.Create('Unknown path verb');
  end;

  Result := True;
end;

function TTsPathSegmentsIter.LastPoint: TTsPoint;
begin
  Result := FLastPoint;
end;

function TTsPathSegmentsIter.LastMoveTo: TTsPoint;
begin
  Result := FLastMoveTo;
end;

{ TTsPath }

class function TTsPath.FromParts(const Verbs: TArray<TTsPathVerb>; const Points: TArray<TTsPoint>; const Bounds: TTsRect): TTsPath;
begin
  Result.FVerbs := Verbs;
  Result.FPoints := Points;
  Result.FBounds := Bounds;
end;

function TTsPath.Len: Integer;
begin
  Result := Length(FVerbs);
end;

function TTsPath.IsEmpty: Boolean;
begin
  Result := (Length(FVerbs) = 0);
end;

function TTsPath.Bounds: TTsRect;
begin
  Result := FBounds;
end;

function TTsPath.TryComputeTightBounds(out Tight: TTsRect): Boolean;
begin
  // big enough to hold worst-case curve type (cubic) extremas + 1
  var Extremas: TTsPoints5;
  for var Index := 0 to High(Extremas) do
  begin
    Extremas[Index] := TTsPoint.Zero;
  end;

  var Min := FPoints[0];
  var Max := FPoints[0];
  var Iter := Segments;
  var LastPoint := TTsPoint.Zero;
  var Segment: TTsPathSegment;
  while Iter.TryNext(Segment) do
  begin
    var Count := 0;
    case Segment.Verb of
      TTsPathVerb.Move:
      begin
        Extremas[0] := Segment.P0;
        Count := 1;
      end;

      TTsPathVerb.Line:
      begin
        Extremas[0] := Segment.P0;
        Count := 1;
      end;

      TTsPathVerb.Quad:
        Count := ComputeQuadExtremas(LastPoint, Segment.P0, Segment.P1, Extremas);

      TTsPathVerb.Cubic:
        Count := ComputeCubicExtremas(LastPoint, Segment.P0, Segment.P1, Segment.P2, Extremas);

      TTsPathVerb.Close:
        ;
    else
      raise EInvalidOpException.Create('Unknown path verb');
    end;

    LastPoint := Iter.LastPoint;
    for var Index := 0 to Count - 1 do
    begin
      Min.X := TTsScalar.MinF(Min.X, Extremas[Index].X);
      Min.Y := TTsScalar.MinF(Min.Y, Extremas[Index].Y);
      Max.X := TTsScalar.MaxF(Max.X, Extremas[Index].X);
      Max.Y := TTsScalar.MaxF(Max.Y, Extremas[Index].Y);
    end;
  end;

  Result := TTsRect.TryFromLTRB(Min.X, Min.Y, Max.X, Max.Y, Tight);
end;

class function TTsPath.ComputeQuadExtremas(const P0, P1, P2: TTsPoint; var Extremas: TTsPoints5): Integer;
begin
  var Src: TTsPoints3;
  Src[0] := P0;
  Src[1] := P1;
  Src[2] := P2;

  var T: TTsNormalizedF32Exclusive;
  var ExtremaIndex := 0;

  if TTsPathGeometry.TryFindQuadExtrema(P0.X, P1.X, P2.X, T) then
  begin
    Extremas[ExtremaIndex] := TTsPathGeometry.EvalQuadAt(Src, T.ToNormalized);
    Inc(ExtremaIndex);
  end;

  if TTsPathGeometry.TryFindQuadExtrema(P0.Y, P1.Y, P2.Y, T) then
  begin
    Extremas[ExtremaIndex] := TTsPathGeometry.EvalQuadAt(Src, T.ToNormalized);
    Inc(ExtremaIndex);
  end;

  Extremas[ExtremaIndex] := P2;
  Result := ExtremaIndex + 1;
end;

class function TTsPath.ComputeCubicExtremas(const P0, P1, P2, P3: TTsPoint; var Extremas: TTsPoints5): Integer;
begin
  var Ts0 := TTsPathGeometry.NewTValues;
  var Ts1 := TTsPathGeometry.NewTValues;
  const N0 = TTsPathGeometry.FindCubicExtrema(P0.X, P1.X, P2.X, P3.X, Ts0);
  const N1 = TTsPathGeometry.FindCubicExtrema(P0.Y, P1.Y, P2.Y, P3.Y, Ts1);
  const TotalLen = N0 + N1;

  var Src: TTsPoints4;
  Src[0] := P0;
  Src[1] := P1;
  Src[2] := P2;
  Src[3] := P3;

  var ExtremaIndex := 0;
  for var Index := 0 to N0 - 1 do
  begin
    Extremas[ExtremaIndex] := TTsPathGeometry.EvalCubicPosAt(Src, Ts0[Index].ToNormalized);
    Inc(ExtremaIndex);
  end;

  for var Index := 0 to N1 - 1 do
  begin
    Extremas[ExtremaIndex] := TTsPathGeometry.EvalCubicPosAt(Src, Ts1[Index].ToNormalized);
    Inc(ExtremaIndex);
  end;

  Extremas[TotalLen] := P3;
  Result := TotalLen + 1;
end;

function TTsPath.Verbs: TArray<TTsPathVerb>;
begin
  Result := FVerbs;
end;

function TTsPath.Points: TArray<TTsPoint>;
begin
  Result := FPoints;
end;

function TTsPath.TryTransform(const Ts: TTsTransform; out Transformed: TTsPath): Boolean;
begin
  Transformed := Self;

  if Ts.IsIdentity then
  begin
    Exit(True);
  end;

  Transformed.FPoints := Copy(FPoints);
  Ts.MapPoints(Transformed.FPoints);

  // Update bounds.
  Result := TTsRect.TryFromPoints(Transformed.FPoints, Transformed.FBounds);
end;

function TTsPath.Segments: TTsPathSegmentsIter;
begin
  Result := TTsPathSegmentsIter.Create(FVerbs, FPoints);
end;

{ TTsPathBuilder }

class function TTsPathBuilder.New: TTsPathBuilder;
begin
  Result := Default(TTsPathBuilder);
end;

class function TTsPathBuilder.WithCapacity(const VerbsCapacity, PointsCapacity: Integer): TTsPathBuilder;
begin
  Result := Default(TTsPathBuilder);
  SetLength(Result.FVerbs, VerbsCapacity);
  SetLength(Result.FPoints, PointsCapacity);
end;

class function TTsPathBuilder.FromRect(const Rect: TTsRect): TTsPath;
begin
  const Verbs: TArray<TTsPathVerb> = [TTsPathVerb.Move, TTsPathVerb.Line, TTsPathVerb.Line, TTsPathVerb.Line, TTsPathVerb.Close];

  const Points: TArray<TTsPoint> = [
    TTsPoint.FromXY(Rect.Left, Rect.Top),
    TTsPoint.FromXY(Rect.Right, Rect.Top),
    TTsPoint.FromXY(Rect.Right, Rect.Bottom),
    TTsPoint.FromXY(Rect.Left, Rect.Bottom)];

  Result := TTsPath.FromParts(Verbs, Points, Rect);
end;

class function TTsPathBuilder.TryFromCircle(const Cx, Cy, Radius: Single; out Path: TTsPath): Boolean;
begin
  var Builder := New;
  Builder.PushCircle(Cx, Cy, Radius);
  Result := Builder.TryFinish(Path);
end;

class function TTsPathBuilder.TryFromOval(const Oval: TTsRect; out Path: TTsPath): Boolean;
begin
  var Builder := New;
  Builder.PushOval(Oval);
  Result := Builder.TryFinish(Path);
end;

procedure TTsPathBuilder.Reserve(const AdditionalVerbs, AdditionalPoints: Integer);
begin
  if FVerbCount + AdditionalVerbs > Length(FVerbs) then
  begin
    SetLength(FVerbs, FVerbCount + AdditionalVerbs);
  end;

  if FPointCount + AdditionalPoints > Length(FPoints) then
  begin
    SetLength(FPoints, FPointCount + AdditionalPoints);
  end;
end;

procedure TTsPathBuilder.AddVerb(const Verb: TTsPathVerb);
begin
  if FVerbCount = Length(FVerbs) then
  begin
    SetLength(FVerbs, FVerbCount * 2 + 8);
  end;

  FVerbs[FVerbCount] := Verb;
  Inc(FVerbCount);
end;

procedure TTsPathBuilder.AddPoint(const Pt: TTsPoint);
begin
  if FPointCount = Length(FPoints) then
  begin
    SetLength(FPoints, FPointCount * 2 + 8);
  end;

  FPoints[FPointCount] := Pt;
  Inc(FPointCount);
end;

function TTsPathBuilder.LastVerbIs(const Verb: TTsPathVerb): Boolean;
begin
  Result := (FVerbCount > 0) and (FVerbs[FVerbCount - 1] = Verb);
end;

function TTsPathBuilder.Len: Integer;
begin
  Result := FVerbCount;
end;

function TTsPathBuilder.IsEmpty: Boolean;
begin
  Result := (FVerbCount = 0);
end;

procedure TTsPathBuilder.MoveTo(const X, Y: Single);
begin
  if LastVerbIs(TTsPathVerb.Move) then
  begin
    FPoints[FPointCount - 1] := TTsPoint.FromXY(X, Y);
  end
  else
  begin
    FLastMoveToIndex := FPointCount;
    FMoveToNotRequired := True;

    AddVerb(TTsPathVerb.Move);
    AddPoint(TTsPoint.FromXY(X, Y));
  end;
end;

procedure TTsPathBuilder.InjectMoveToIfNeeded;
begin
  if FMoveToNotRequired then
  begin
    Exit;
  end;

  if FLastMoveToIndex < FPointCount then
  begin
    const Pt = FPoints[FLastMoveToIndex];
    MoveTo(Pt.X, Pt.Y);
  end
  else
  begin
    MoveTo(0.0, 0.0);
  end;
end;

procedure TTsPathBuilder.LineTo(const X, Y: Single);
begin
  InjectMoveToIfNeeded;

  AddVerb(TTsPathVerb.Line);
  AddPoint(TTsPoint.FromXY(X, Y));
end;

procedure TTsPathBuilder.QuadTo(const X1, Y1, X, Y: Single);
begin
  InjectMoveToIfNeeded;

  AddVerb(TTsPathVerb.Quad);
  AddPoint(TTsPoint.FromXY(X1, Y1));
  AddPoint(TTsPoint.FromXY(X, Y));
end;

procedure TTsPathBuilder.QuadToPt(const P1, P: TTsPoint);
begin
  QuadTo(P1.X, P1.Y, P.X, P.Y);
end;

procedure TTsPathBuilder.ConicTo(const X1, Y1, X, Y, Weight: Single);
begin
  // check for <= 0 or NaN with this test
  if IsNan(Weight) or not (Weight > 0.0) then
  begin
    LineTo(X, Y);
  end
  else if not TTsScalar.IsFinite(Weight) then
  begin
    LineTo(X1, Y1);
    LineTo(X, Y);
  end
  else if Weight = 1.0 then
  begin
    QuadTo(X1, Y1, X, Y);
  end
  else
  begin
    InjectMoveToIfNeeded;

    var Last: TTsPoint;
    TryLastPoint(Last);

    var Quadder: TTsAutoConicToQuads;
    if TTsAutoConicToQuads.TryCompute(Last, TTsPoint.FromXY(X1, Y1), TTsPoint.FromXY(X, Y), Weight, Quadder) then
    begin
      // Points are ordered as: 0 - 1 2 - 3 4 - 5 6 - ..
      // `count` is a number of pairs +1
      var Offset := 1;
      for var Index := 0 to Quadder.Len - 1 do
      begin
        const Pt1 = Quadder.Points[Offset];
        const Pt2 = Quadder.Points[Offset + 1];
        QuadTo(Pt1.X, Pt1.Y, Pt2.X, Pt2.Y);
        Inc(Offset, 2);
      end;
    end;
  end;
end;

procedure TTsPathBuilder.ConicPointsTo(const Pt1, Pt2: TTsPoint; const Weight: Single);
begin
  ConicTo(Pt1.X, Pt1.Y, Pt2.X, Pt2.Y, Weight);
end;

procedure TTsPathBuilder.CubicTo(const X1, Y1, X2, Y2, X, Y: Single);
begin
  InjectMoveToIfNeeded;

  AddVerb(TTsPathVerb.Cubic);
  AddPoint(TTsPoint.FromXY(X1, Y1));
  AddPoint(TTsPoint.FromXY(X2, Y2));
  AddPoint(TTsPoint.FromXY(X, Y));
end;

procedure TTsPathBuilder.CubicToPt(const P1, P2, P: TTsPoint);
begin
  CubicTo(P1.X, P1.Y, P2.X, P2.Y, P.X, P.Y);
end;

procedure TTsPathBuilder.Close;
begin
  // don't add a close if it's the first verb or a repeat
  if (FVerbCount > 0) and not LastVerbIs(TTsPathVerb.Close) then
  begin
    AddVerb(TTsPathVerb.Close);
  end;

  FMoveToNotRequired := False;
end;

function TTsPathBuilder.TryLastPoint(out Pt: TTsPoint): Boolean;
begin
  Pt := TTsPoint.Zero;

  Result := (FPointCount > 0);
  if Result then
  begin
    Pt := FPoints[FPointCount - 1];
  end;
end;

procedure TTsPathBuilder.SetLastPoint(const Pt: TTsPoint);
begin
  if FPointCount > 0 then
  begin
    FPoints[FPointCount - 1] := Pt;
  end
  else
  begin
    MoveTo(Pt.X, Pt.Y);
  end;
end;

function TTsPathBuilder.IsZeroLengthSincePoint(const StartPtIndex: Integer): Boolean;
begin
  const Count = FPointCount - StartPtIndex;
  if Count < 2 then
  begin
    Exit(True);
  end;

  const First = FPoints[StartPtIndex];
  for var Index := 1 to Count - 1 do
  begin
    if First <> FPoints[StartPtIndex + Index] then
    begin
      Exit(False);
    end;
  end;

  Result := True;
end;

procedure TTsPathBuilder.PushRect(const Rect: TTsRect);
begin
  MoveTo(Rect.Left, Rect.Top);
  LineTo(Rect.Right, Rect.Top);
  LineTo(Rect.Right, Rect.Bottom);
  LineTo(Rect.Left, Rect.Bottom);
  Close;
end;

procedure TTsPathBuilder.PushOval(const Oval: TTsRect);
begin
  const Cx: Single = TTsScalar.Half(Oval.Left) + TTsScalar.Half(Oval.Right);
  const Cy: Single = TTsScalar.Half(Oval.Top) + TTsScalar.Half(Oval.Bottom);

  var Ovals, Rects: array[0..3] of TTsPoint;
  Ovals[0] := TTsPoint.FromXY(Cx, Oval.Bottom);
  Ovals[1] := TTsPoint.FromXY(Oval.Left, Cy);
  Ovals[2] := TTsPoint.FromXY(Cx, Oval.Top);
  Ovals[3] := TTsPoint.FromXY(Oval.Right, Cy);

  Rects[0] := TTsPoint.FromXY(Oval.Right, Oval.Bottom);
  Rects[1] := TTsPoint.FromXY(Oval.Left, Oval.Bottom);
  Rects[2] := TTsPoint.FromXY(Oval.Left, Oval.Top);
  Rects[3] := TTsPoint.FromXY(Oval.Right, Oval.Top);

  MoveTo(Ovals[3].X, Ovals[3].Y);
  for var Index := 0 to 3 do
  begin
    ConicPointsTo(Rects[Index], Ovals[Index], TTsScalar.ScalarRoot2Over2);
  end;

  Close;
end;

procedure TTsPathBuilder.PushCircle(const X, Y, R: Single);
begin
  var Oval: TTsRect;
  if TTsRect.TryFromXYWH(X - R, Y - R, R + R, R + R, Oval) then
  begin
    PushOval(Oval);
  end;
end;

procedure TTsPathBuilder.PushPath(const Other: TTsPath);
begin
  FLastMoveToIndex := FPointCount;

  Reserve(Length(Other.FVerbs), Length(Other.FPoints));
  for var Verb in Other.FVerbs do
  begin
    AddVerb(Verb);
  end;

  for var Pt in Other.FPoints do
  begin
    AddPoint(Pt);
  end;
end;

procedure TTsPathBuilder.PushPathBuilder(const Other: TTsPathBuilder);
begin
  if Other.IsEmpty then
  begin
    Exit;
  end;

  if FLastMoveToIndex <> 0 then
  begin
    FLastMoveToIndex := FPointCount + Other.FLastMoveToIndex;
  end;

  Reserve(Other.FVerbCount, Other.FPointCount);
  for var Index := 0 to Other.FVerbCount - 1 do
  begin
    AddVerb(Other.FVerbs[Index]);
  end;

  for var Index := 0 to Other.FPointCount - 1 do
  begin
    AddPoint(Other.FPoints[Index]);
  end;
end;

procedure TTsPathBuilder.ReversePathTo(const Other: TTsPathBuilder);
begin
  if Other.IsEmpty then
  begin
    Exit;
  end;

  var PointsOffset := Other.FPointCount - 1;
  for var VerbIndex := Other.FVerbCount - 1 downto 0 do
  begin
    case Other.FVerbs[VerbIndex] of
      TTsPathVerb.Move:
        // if the path has multiple contours, stop after reversing the last
        Exit;

      TTsPathVerb.Line:
      begin
        // We're moving one point back manually, to prevent points_offset overflow.
        const Pt = Other.FPoints[PointsOffset - 1];
        Dec(PointsOffset);
        LineTo(Pt.X, Pt.Y);
      end;

      TTsPathVerb.Quad:
      begin
        const Pt1 = Other.FPoints[PointsOffset - 1];
        const Pt2 = Other.FPoints[PointsOffset - 2];
        Dec(PointsOffset, 2);
        QuadTo(Pt1.X, Pt1.Y, Pt2.X, Pt2.Y);
      end;

      TTsPathVerb.Cubic:
      begin
        const Pt1 = Other.FPoints[PointsOffset - 1];
        const Pt2 = Other.FPoints[PointsOffset - 2];
        const Pt3 = Other.FPoints[PointsOffset - 3];
        Dec(PointsOffset, 3);
        CubicTo(Pt1.X, Pt1.Y, Pt2.X, Pt2.Y, Pt3.X, Pt3.Y);
      end;

      TTsPathVerb.Close:
        ;
    else
      raise EInvalidOpException.Create('Unknown path verb');
    end;
  end;
end;

procedure TTsPathBuilder.Clear;
begin
  FVerbCount := 0;
  FPointCount := 0;
  FLastMoveToIndex := 0;
  FMoveToNotRequired := False;
end;

function TTsPathBuilder.TryFinish(out Path: TTsPath): Boolean;
begin
  Path := Default(TTsPath);

  // Just a move to? Bail.
  if FVerbCount <= 1 then
  begin
    Clear;
    Exit(False);
  end;

  SetLength(FVerbs, FVerbCount);
  SetLength(FPoints, FPointCount);

  var Bounds: TTsRect;
  Result := TTsRect.TryFromPoints(FPoints, Bounds);
  if Result then
  begin
    Path := TTsPath.FromParts(FVerbs, FPoints, Bounds);
  end;

  // The path owns the arrays now
  FVerbs := nil;
  FPoints := nil;
  Clear;
end;

end.
