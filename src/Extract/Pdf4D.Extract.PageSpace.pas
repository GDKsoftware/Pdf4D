// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.PageSpace;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Quad,
  Pdf4D.Model.Rectangle;

type
  // Page coordinates as the page is shown: points, origin at the upper left of the CropBox, /Rotate applied, y downwards. It is the
  // page transform of the renderer at scale 1.
  TPdfPageSpace = record
  private
    FPageToShown: TPdfMatrix;
    FWidth: Single;
    FHeight: Single;

  public
    // Rotation: a multiple of 90 (negative values and values beyond 360 included); any other value counts as 0, as TPDPage.Rotation does
    class function Create(const CropBox: TPdfRectangle; const Rotation: Integer): TPdfPageSpace; static;

    // The size of the shown page: width and height swap at 90 and 270 degrees
    function Width: Single;
    function Height: Single;
    // A point in PDF user space (absolute, origin lower left) in page coordinates
    function ToPage(const UserPoint: TPointF): TPointF;
    // Axis aligned, in page coordinates: Left <= Right and Top <= Bottom
    function BoundsOf(const Quad: TPdfQuad): TRectF; overload;
    function BoundsOf(const Points: array of TPointF): TRectF; overload;
  end;

implementation

uses
  System.Math,
  Pdf4D.Render.PageTransform;

const
  RightAngle = 90;
  FullTurn = 360;

{ TPdfPageSpace }

class function TPdfPageSpace.Create(const CropBox: TPdfRectangle; const Rotation: Integer): TPdfPageSpace;
begin
  var Angle := ((Rotation mod FullTurn) + FullTurn) mod FullTurn;
  if (Angle mod RightAngle) <> 0 then
  begin
    Angle := 0;
  end;

  const Transform = TPdfPageTransform.Create(CropBox, Angle, 1);
  Result.FPageToShown := Transform.PageToDevice;

  const IsSideways = ((Angle = 90) or (Angle = 270));
  if IsSideways then
  begin
    Result.FWidth := CropBox.Height;
    Result.FHeight := CropBox.Width;
  end
  else
  begin
    Result.FWidth := CropBox.Width;
    Result.FHeight := CropBox.Height;
  end;
end;

function TPdfPageSpace.Width: Single;
begin
  Result := FWidth;
end;

function TPdfPageSpace.Height: Single;
begin
  Result := FHeight;
end;

function TPdfPageSpace.ToPage(const UserPoint: TPointF): TPointF;
begin
  Result := FPageToShown.TransformPoint(UserPoint.X, UserPoint.Y);
end;

function TPdfPageSpace.BoundsOf(const Quad: TPdfQuad): TRectF;
begin
  Result := BoundsOf([Quad.P1, Quad.P2, Quad.P3, Quad.P4]);
end;

function TPdfPageSpace.BoundsOf(const Points: array of TPointF): TRectF;
begin
  if Length(Points) = 0 then
  begin
    Exit(TRectF.Create(0, 0, 0, 0));
  end;

  var Shown := ToPage(Points[0]);
  var Left := Shown.X;
  var Right := Shown.X;
  var Top := Shown.Y;
  var Bottom := Shown.Y;
  for var Index := 1 to High(Points) do
  begin
    Shown := ToPage(Points[Index]);
    Left := Min(Left, Shown.X);
    Right := Max(Right, Shown.X);
    Top := Min(Top, Shown.Y);
    Bottom := Max(Bottom, Shown.Y);
  end;
  Result := TRectF.Create(Left, Top, Right, Bottom);
end;

end.
