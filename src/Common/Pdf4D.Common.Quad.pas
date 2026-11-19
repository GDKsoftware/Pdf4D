// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.Quad;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types;

type
  // Four corners in PDF user space, counterclockwise from the start of the baseline. Unlike a rectangle it follows rotated
  // and mirrored text.
  TPdfQuad = record
  private
    class function IsFinitePoint(const Point: TPointF): Boolean; static;
    function GetUp: TPointF;
    // The distance of Point from the baseline of Self along Up, a unit vector
    function HeightOver(const Point, Up: TPointF): Single;
    // The unit vector of the baseline (P1 to P2); False when the quad has no usable baseline
    function TryGetAlong(out Along: TPointF): Boolean;
    // The distance of Point from P1 along Along, a unit vector
    function DistanceAlong(const Point, Along: TPointF): Single;
    function Join(const Other: TPdfQuad): TPdfQuad;
    class function Enclose(const Start, Finish, First, Second: TPdfQuad): TPdfQuad; static;

  public
    // Start-bottom, end-bottom, end-top, start-top
    P1, P2, P3, P4: TPointF;

    class function Create(const P1, P2, P3, P4: TPointF): TPdfQuad; static;

    // Axis aligned: Left <= Right and Top <= Bottom, where Top holds the smallest y
    function Bounds: TRectF;
    function IsFinite: Boolean;
    // The length of the baseline
    function BaselineLength: Single;
    // How far Other lies before Self along the baseline of Self: the distance from the end of Other to the start of Self. It is
    // positive when Other lies wholly before Self, zero or negative when they touch or overlap, and zero without a usable baseline.
    function GapBefore(const Other: TPdfQuad): Single;
    // The union of two quads of the same line, in whatever order they lie: along the baseline from the earliest start to the
    // latest end of both, and perpendicular to the baseline from the lowest bottom to the highest top of both. Self when the result
    // is not finite.
    function Extend(const Other: TPdfQuad): TPdfQuad;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.FloatGuard;

{ TPdfQuad }

class function TPdfQuad.Create(const P1, P2, P3, P4: TPointF): TPdfQuad;
begin
  Result.P1 := P1;
  Result.P2 := P2;
  Result.P3 := P3;
  Result.P4 := P4;
end;

class function TPdfQuad.IsFinitePoint(const Point: TPointF): Boolean;
begin
  const IsXFinite = (not (IsNaN(Point.X) or IsInfinite(Point.X)));
  const IsYFinite = (not (IsNaN(Point.Y) or IsInfinite(Point.Y)));

  Result := (IsXFinite and IsYFinite);
end;

function TPdfQuad.GetUp: TPointF;
begin
  Result := TPointF.Create(P4.X - P1.X, P4.Y - P1.Y);
end;

function TPdfQuad.Bounds: TRectF;
begin
  const Left = Min(Min(P1.X, P2.X), Min(P3.X, P4.X));
  const Right = Max(Max(P1.X, P2.X), Max(P3.X, P4.X));
  const Top = Min(Min(P1.Y, P2.Y), Min(P3.Y, P4.Y));
  const Bottom = Max(Max(P1.Y, P2.Y), Max(P3.Y, P4.Y));

  Result := TRectF.Create(Left, Top, Right, Bottom);
end;

function TPdfQuad.IsFinite: Boolean;
begin
  Result := (IsFinitePoint(P1) and IsFinitePoint(P2) and IsFinitePoint(P3) and IsFinitePoint(P4));
end;

function TPdfQuad.HeightOver(const Point, Up: TPointF): Single;
begin
  Result := (Point.X - P1.X) * Up.X + (Point.Y - P1.Y) * Up.Y;
end;

function TPdfQuad.TryGetAlong(out Along: TPointF): Boolean;
begin
  const Direction = TPointF.Create(P2.X - P1.X, P2.Y - P1.Y);
  const DirectionLength = Sqrt(Direction.X * Direction.X + Direction.Y * Direction.Y);

  Result := ((DirectionLength > 0) and not IsInfinite(DirectionLength));
  if Result then
  begin
    Along := TPointF.Create(Direction.X / DirectionLength, Direction.Y / DirectionLength);
  end
  else
  begin
    Along := TPointF.Create(0, 0);
  end;
end;

function TPdfQuad.DistanceAlong(const Point, Along: TPointF): Single;
begin
  Result := (Point.X - P1.X) * Along.X + (Point.Y - P1.Y) * Along.Y;
end;

function TPdfQuad.BaselineLength: Single;
begin
  const Previous = TPdfFloatGuard.Enter;
  try
    Result := Sqrt(Sqr(P2.X - P1.X) + Sqr(P2.Y - P1.Y));
  finally
    TPdfFloatGuard.Leave(Previous);
  end;

  if IsNaN(Result) or IsInfinite(Result) then
  begin
    Result := 0;
  end;
end;

function TPdfQuad.GapBefore(const Other: TPdfQuad): Single;
begin
  Result := 0;
  const Previous = TPdfFloatGuard.Enter;
  try
    var Along: TPointF;
    if TryGetAlong(Along) then
    begin
      Result := -Max(DistanceAlong(Other.P1, Along), DistanceAlong(Other.P2, Along));
    end;
  finally
    TPdfFloatGuard.Leave(Previous);
  end;

  if IsNaN(Result) or IsInfinite(Result) then
  begin
    Result := 0;
  end;
end;

// Start is the quad with the earliest start and Finish the one with the latest end; First and Second are the two quads
class function TPdfQuad.Enclose(const Start, Finish, First, Second: TPdfQuad): TPdfQuad;
begin
  var Up := Start.GetUp;
  var UpLength := Sqrt(Up.X * Up.X + Up.Y * Up.Y);
  if UpLength = 0 then
  begin
    Up := Finish.GetUp;
    UpLength := Sqrt(Up.X * Up.X + Up.Y * Up.Y);
  end;

  const HasHeight = ((UpLength > 0) and not IsInfinite(UpLength));
  if not HasHeight then
  begin
    Result := TPdfQuad.Create(Start.P1, Finish.P2, Finish.P3, Start.P4);
    Exit;
  end;

  const Direction = TPointF.Create(Up.X / UpLength, Up.Y / UpLength);
  const FinishBottom = Start.HeightOver(Finish.P2, Direction);
  const Bottom = Min(Min(Min(0, Start.HeightOver(First.P2, Direction)), Min(Start.HeightOver(Second.P1, Direction), Start.HeightOver(Second.P2, Direction))),
                     Start.HeightOver(First.P1, Direction));
  const Top = Max(Max(Start.HeightOver(First.P3, Direction), Start.HeightOver(First.P4, Direction)),
                  Max(Start.HeightOver(Second.P3, Direction), Start.HeightOver(Second.P4, Direction)));

  Result.P1 := TPointF.Create(Start.P1.X + Direction.X * Bottom, Start.P1.Y + Direction.Y * Bottom);
  Result.P2 := TPointF.Create(Finish.P2.X + Direction.X * (Bottom - FinishBottom), Finish.P2.Y + Direction.Y * (Bottom - FinishBottom));
  Result.P3 := TPointF.Create(Finish.P2.X + Direction.X * (Top - FinishBottom), Finish.P2.Y + Direction.Y * (Top - FinishBottom));
  Result.P4 := TPointF.Create(Start.P1.X + Direction.X * Top, Start.P1.Y + Direction.Y * Top);
end;

function TPdfQuad.Join(const Other: TPdfQuad): TPdfQuad;
begin
  var Along: TPointF;
  const HasAlong = (TryGetAlong(Along) or Other.TryGetAlong(Along));
  if not HasAlong then
  begin
    Result := Enclose(Self, Other, Self, Other);
    Exit;
  end;

  const IsOtherFirst = (DistanceAlong(Other.P1, Along) < 0);
  const IsOtherLast = (DistanceAlong(Other.P2, Along) > DistanceAlong(P2, Along));
  var Start := Self;
  if IsOtherFirst then
  begin
    Start := Other;
  end;

  var Finish := Self;
  if IsOtherLast then
  begin
    Finish := Other;
  end;

  Result := Enclose(Start, Finish, Self, Other);
end;

function TPdfQuad.Extend(const Other: TPdfQuad): TPdfQuad;
begin
  const Previous = TPdfFloatGuard.Enter;
  try
    Result := Join(Other);
  finally
    TPdfFloatGuard.Leave(Previous);
  end;

  if not Result.IsFinite then
  begin
    Result := Self;
  end;
end;

end.
