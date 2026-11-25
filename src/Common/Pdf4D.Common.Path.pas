// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.Path;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Common.Matrix;

type
  {$SCOPEDENUMS ON}
  TPdfPathVerb = (MoveTo, LineTo, QuadTo, CubicTo, Close);
  {$SCOPEDENUMS OFF}

  // A path of lines and Bezier curves, like java.awt.geom.GeneralPath, with Single coordinates. The space of the points is
  // chosen by the producer; a consumer always gets the transform to device pixels separately. Not thread safe.
  TPdfPath = class
  private
    FVerbs: TArray<TPdfPathVerb>;
    FPoints: TArray<TPointF>;
    FVerbCount: Integer;
    FPointCount: Integer;
    // The index in FPoints of the MoveTo that started the current subpath; the current point after a Close
    FSubpathStart: Integer;

    procedure AddVerb(const Verb: TPdfPathVerb);
    procedure AddPoint(const X, Y: Single);
    procedure StartSubpathWhenNoCurrentPoint(const X, Y: Single);
    procedure CheckIndex(const Index, Count: Integer);
    // Exactly PointCount points
    function TransformedPoints(const Matrix: TPdfMatrix): TArray<TPointF>;

  public
    constructor Create;

    procedure MoveTo(const X, Y: Single);
    // LineTo, QuadTo and CubicTo without a current point start with an implicit MoveTo to their first point
    procedure LineTo(const X, Y: Single);
    procedure QuadTo(const X1, Y1, X, Y: Single);
    procedure CubicTo(const X1, Y1, X2, Y2, X, Y: Single);
    // No-op without a current point
    procedure ClosePath;
    procedure Clear;

    procedure Append(const Other: TPdfPath); overload;
    procedure Append(const Other: TPdfPath; const Transform: TPdfMatrix); overload;
    procedure Transform(const Matrix: TPdfMatrix);
    function Clone: TPdfPath;

    function IsEmpty: Boolean;
    function HasCurrentPoint: Boolean;
    // Raises EInvalidOpException without a current point
    function CurrentPoint: TPointF;
    // The bounds of all points, control points included; an empty path gives TRectF.Empty
    function Bounds: TRectF;
    function VerbCount: Integer;
    function PointCount: Integer;
    function Verb(const Index: Integer): TPdfPathVerb;
    // MoveTo and LineTo have 1 point, QuadTo 2, CubicTo 3, Close none
    function Point(const Index: Integer): TPointF;
  end;

implementation

uses
  System.Math;

const
  InitialCapacity = 16;

{ TPdfPath }

constructor TPdfPath.Create;
begin
  inherited Create;
end;

procedure TPdfPath.MoveTo(const X, Y: Single);
begin
  AddVerb(TPdfPathVerb.MoveTo);
  FSubpathStart := FPointCount;
  AddPoint(X, Y);
end;

procedure TPdfPath.LineTo(const X, Y: Single);
begin
  if not HasCurrentPoint then
  begin
    MoveTo(X, Y);
    Exit;
  end;

  AddVerb(TPdfPathVerb.LineTo);
  AddPoint(X, Y);
end;

procedure TPdfPath.QuadTo(const X1, Y1, X, Y: Single);
begin
  StartSubpathWhenNoCurrentPoint(X1, Y1);

  AddVerb(TPdfPathVerb.QuadTo);
  AddPoint(X1, Y1);
  AddPoint(X, Y);
end;

procedure TPdfPath.CubicTo(const X1, Y1, X2, Y2, X, Y: Single);
begin
  StartSubpathWhenNoCurrentPoint(X1, Y1);

  AddVerb(TPdfPathVerb.CubicTo);
  AddPoint(X1, Y1);
  AddPoint(X2, Y2);
  AddPoint(X, Y);
end;

procedure TPdfPath.ClosePath;
begin
  if not HasCurrentPoint then
  begin
    Exit;
  end;

  AddVerb(TPdfPathVerb.Close);
end;

procedure TPdfPath.Clear;
begin
  FVerbCount := 0;
  FPointCount := 0;
  FSubpathStart := 0;
end;

procedure TPdfPath.Append(const Other: TPdfPath);
begin
  Append(Other, TPdfMatrix.Identity);
end;

procedure TPdfPath.Append(const Other: TPdfPath; const Transform: TPdfMatrix);
begin
  // The points are transformed first, so that a failing transform leaves Self unchanged
  const OtherVerbCount = Other.FVerbCount;
  const MovedPoints = Other.TransformedPoints(Transform);
  const SubpathStartOffset = FPointCount;

  for var Index := 0 to OtherVerbCount - 1 do
  begin
    AddVerb(Other.FVerbs[Index]);
  end;
  for var Moved in MovedPoints do
  begin
    AddPoint(Moved.X, Moved.Y);
  end;

  if OtherVerbCount > 0 then
  begin
    FSubpathStart := SubpathStartOffset + Other.FSubpathStart;
  end;
end;

procedure TPdfPath.Transform(const Matrix: TPdfMatrix);
begin
  // Assigned only when every point could be transformed
  FPoints := TransformedPoints(Matrix);
end;

function TPdfPath.TransformedPoints(const Matrix: TPdfMatrix): TArray<TPointF>;
begin
  SetLength(Result, FPointCount);
  for var Index := 0 to FPointCount - 1 do
  begin
    const Source = FPoints[Index];
    Result[Index] := Matrix.TransformPoint(Source.X, Source.Y);
  end;
end;

function TPdfPath.Clone: TPdfPath;
begin
  Result := TPdfPath.Create;
  try
    Result.Append(Self);
  except
    Result.Free;
    raise;
  end;
end;

function TPdfPath.IsEmpty: Boolean;
begin
  Result := (FVerbCount = 0);
end;

function TPdfPath.HasCurrentPoint: Boolean;
begin
  Result := (FVerbCount > 0);
end;

function TPdfPath.CurrentPoint: TPointF;
begin
  if not HasCurrentPoint then
  begin
    raise EInvalidOpException.Create('The path has no current point');
  end;

  const IsClosed = (FVerbs[FVerbCount - 1] = TPdfPathVerb.Close);
  if IsClosed then
  begin
    Result := FPoints[FSubpathStart];
  end
  else
  begin
    Result := FPoints[FPointCount - 1];
  end;
end;

function TPdfPath.Bounds: TRectF;
begin
  if FPointCount = 0 then
  begin
    Exit(TRectF.Empty);
  end;

  var Left := FPoints[0].X;
  var Right := Left;
  var Top := FPoints[0].Y;
  var Bottom := Top;
  for var Index := 1 to FPointCount - 1 do
  begin
    Left := Min(Left, FPoints[Index].X);
    Right := Max(Right, FPoints[Index].X);
    Top := Min(Top, FPoints[Index].Y);
    Bottom := Max(Bottom, FPoints[Index].Y);
  end;

  Result := TRectF.Create(Left, Top, Right, Bottom);
end;

function TPdfPath.VerbCount: Integer;
begin
  Result := FVerbCount;
end;

function TPdfPath.PointCount: Integer;
begin
  Result := FPointCount;
end;

function TPdfPath.Verb(const Index: Integer): TPdfPathVerb;
begin
  CheckIndex(Index, FVerbCount);

  Result := FVerbs[Index];
end;

function TPdfPath.Point(const Index: Integer): TPointF;
begin
  CheckIndex(Index, FPointCount);

  Result := FPoints[Index];
end;

procedure TPdfPath.AddVerb(const Verb: TPdfPathVerb);
begin
  if FVerbCount = Length(FVerbs) then
  begin
    SetLength(FVerbs, Max(InitialCapacity, FVerbCount * 2));
  end;

  FVerbs[FVerbCount] := Verb;
  Inc(FVerbCount);
end;

procedure TPdfPath.AddPoint(const X, Y: Single);
begin
  if FPointCount = Length(FPoints) then
  begin
    SetLength(FPoints, Max(InitialCapacity, FPointCount * 2));
  end;

  FPoints[FPointCount] := PointF(X, Y);
  Inc(FPointCount);
end;

procedure TPdfPath.StartSubpathWhenNoCurrentPoint(const X, Y: Single);
begin
  if not HasCurrentPoint then
  begin
    MoveTo(X, Y);
  end;
end;

procedure TPdfPath.CheckIndex(const Index, Count: Integer);
begin
  const IsInRange = ((Index >= 0) and (Index < Count));
  if not IsInRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Index %d is outside the range 0..%d', [Index, Count - 1]);
  end;
end;

end.
