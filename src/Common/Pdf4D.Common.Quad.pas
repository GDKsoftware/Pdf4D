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
    function Join(const Other: TPdfQuad): TPdfQuad;

  public
    // Start-bottom, end-bottom, end-top, start-top
    P1, P2, P3, P4: TPointF;

    class function Create(const P1, P2, P3, P4: TPointF): TPdfQuad; static;

    // Axis aligned: Left <= Right and Top <= Bottom, where Top holds the smallest y
    function Bounds: TRectF;
    function IsFinite: Boolean;
    // The union of two quads of the same line: along the baseline from P1 and P4 of Self to P2 and P3 of Other, and perpendicular
    // to the baseline of Self from the lowest bottom to the highest top of both. Self when the result is not finite.
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

function TPdfQuad.Join(const Other: TPdfQuad): TPdfQuad;
begin
  var Up := GetUp;
  var UpLength := Sqrt(Up.X * Up.X + Up.Y * Up.Y);
  if UpLength = 0 then
  begin
    Up := Other.GetUp;
    UpLength := Sqrt(Up.X * Up.X + Up.Y * Up.Y);
  end;

  const HasHeight = ((UpLength > 0) and not IsInfinite(UpLength));
  if not HasHeight then
  begin
    Result := TPdfQuad.Create(P1, Other.P2, Other.P3, P4);
    Exit;
  end;

  const Direction = TPointF.Create(Up.X / UpLength, Up.Y / UpLength);
  const OtherBottom = HeightOver(Other.P2, Direction);
  const Bottom = Min(Min(0, HeightOver(Other.P1, Direction)), OtherBottom);
  const Top = Max(Max(HeightOver(P4, Direction), HeightOver(Other.P3, Direction)), HeightOver(Other.P4, Direction));

  Result.P1 := TPointF.Create(P1.X + Direction.X * Bottom, P1.Y + Direction.Y * Bottom);
  Result.P2 := TPointF.Create(Other.P2.X + Direction.X * (Bottom - OtherBottom), Other.P2.Y + Direction.Y * (Bottom - OtherBottom));
  Result.P3 := TPointF.Create(Other.P2.X + Direction.X * (Top - OtherBottom), Other.P2.Y + Direction.Y * (Top - OtherBottom));
  Result.P4 := TPointF.Create(P1.X + Direction.X * Top, P1.Y + Direction.Y * Top);
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
