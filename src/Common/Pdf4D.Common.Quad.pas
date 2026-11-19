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

  public
    // Start-bottom, end-bottom, end-top, start-top
    P1, P2, P3, P4: TPointF;

    class function Create(const P1, P2, P3, P4: TPointF): TPdfQuad; static;

    // Axis aligned: Left <= Right and Top <= Bottom, where Top holds the smallest y
    function Bounds: TRectF;
    function IsFinite: Boolean;
    // The union along the baseline of two quads of the same line: P1 and P4 of Self, P2 and P3 of Other, with the larger height
    // of both
    function Extend(const Other: TPdfQuad): TPdfQuad;
  end;

implementation

uses
  System.Math;

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

function TPdfQuad.Extend(const Other: TPdfQuad): TPdfQuad;
begin
  const SelfUp = GetUp;
  const OtherUp = Other.GetUp;
  const SelfHeight = SelfUp.X * SelfUp.X + SelfUp.Y * SelfUp.Y;
  const OtherHeight = OtherUp.X * OtherUp.X + OtherUp.Y * OtherUp.Y;
  const IsOtherTaller = (OtherHeight > SelfHeight);

  var Up := SelfUp;
  if IsOtherTaller then
  begin
    Up := OtherUp;
  end;

  Result.P1 := P1;
  Result.P2 := Other.P2;
  Result.P3 := TPointF.Create(Other.P2.X + Up.X, Other.P2.Y + Up.Y);
  Result.P4 := TPointF.Create(P1.X + Up.X, P1.Y + Up.Y);
end;

end.
