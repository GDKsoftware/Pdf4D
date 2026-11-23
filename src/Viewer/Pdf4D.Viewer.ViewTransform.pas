// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ViewTransform;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Quad,
  Pdf4D.Render.PageTransform,
  Pdf4D.Viewer.Types;

type
  // The transform from PDF user space to the pixels of one page on the screen. It is the transform of the renderer for the same
  // scale and rotation, so what the viewer computes lies exactly on what the renderer draws.
  TPdfViewTransform = record
  private
    FScale: Single;
    FViewRotation: Integer;
    FPageTransform: TPdfPageTransform;

    class function LimitedPixel(const Value: Double): Single; static;

  public
    // The checks of Create, for a caller that takes the same arguments without making a transform
    class procedure ValidateArguments(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single); static;
    // Raises EArgumentException when ViewRotation is not 0, 90, 180 or 270, or when Zoom or PixelsPerInch is not above zero
    class function Create(const Page: TPdfPageInfo; const ViewRotation: Integer; const Zoom, PixelsPerInch: Single): TPdfViewTransform; static;

    // Zoom * PixelsPerInch / 72: the render scale
    function Scale: Single;
    // The ExtraRotation of the render
    function ViewRotation: Integer;
    // The pixels of the whole page
    function Size: TSize;
    // View coordinates are pixels of this page with the origin at the top left
    function PageToView(const Point: TPointF): TPointF;
    function ViewToPage(const Point: TPointF): TPointF;
    // The corners P1 to P4, in that order
    function QuadToView(const Quad: TPdfQuad): TArray<TPointF>;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  PointsPerInch = 72;
  FullTurn = 360;
  RightAngle = 90;
  // Beyond the largest size that TPdfPageTransform allows (High(Integer), about 2.1E9 pixels), and far below what a Single holds
  MaxViewPixel = 4.0E9;

{ TPdfViewTransform }

class procedure TPdfViewTransform.ValidateArguments(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single);
begin
  const IsRightAngle = ((ViewRotation mod RightAngle) = 0);
  const IsInTurn = ((ViewRotation >= 0) and (ViewRotation < FullTurn));
  if not (IsRightAngle and IsInTurn) then
  begin
    raise EArgumentException.CreateFmt('View rotation %d is not 0, 90, 180 or 270', [ViewRotation]);
  end;

  const IsZoomValid = ((Zoom > 0) and not IsInfinite(Zoom));
  if not IsZoomValid then
  begin
    raise EArgumentException.CreateFmt('Zoom %g is not above zero', [Double(Zoom)]);
  end;

  const IsPixelsPerInchValid = ((PixelsPerInch > 0) and not IsInfinite(PixelsPerInch));
  if not IsPixelsPerInchValid then
  begin
    raise EArgumentException.CreateFmt('Pixels per inch %g is not above zero', [Double(PixelsPerInch)]);
  end;
end;

class function TPdfViewTransform.Create(const Page: TPdfPageInfo; const ViewRotation: Integer; const Zoom, PixelsPerInch: Single): TPdfViewTransform;
begin
  ValidateArguments(ViewRotation, Zoom, PixelsPerInch);

  Result.FScale := Zoom * PixelsPerInch / PointsPerInch;
  Result.FViewRotation := ViewRotation;
  Result.FPageTransform := TPdfPageTransform.Create(Page.CropBox, (Page.Rotation + ViewRotation) mod FullTurn, Result.FScale);
end;

function TPdfViewTransform.Scale: Single;
begin
  Result := FScale;
end;

function TPdfViewTransform.ViewRotation: Integer;
begin
  Result := FViewRotation;
end;

function TPdfViewTransform.Size: TSize;
begin
  Result := FPageTransform.Size;
end;

function TPdfViewTransform.PageToView(const Point: TPointF): TPointF;
begin
  const Matrix = FPageTransform.PageToDevice;
  const X: Double = Point.X;
  const Y: Double = Point.Y;
  Result.X := LimitedPixel(X * Matrix.ScaleX + Y * Matrix.ShearX + Matrix.TranslateX);
  Result.Y := LimitedPixel(X * Matrix.ShearY + Y * Matrix.ScaleY + Matrix.TranslateY);
end;

// A point far outside the page is clamped, so that it fits a Single and does not turn into an infinity or an overflow; NaN stays NaN
class function TPdfViewTransform.LimitedPixel(const Value: Double): Single;
begin
  if IsNan(Value) then
  begin
    Exit(NaN);
  end;

  Result := EnsureRange(Value, -MaxViewPixel, MaxViewPixel);
end;

function TPdfViewTransform.ViewToPage(const Point: TPointF): TPointF;
begin
  Result := FPageTransform.DeviceToPage(Point);
end;

function TPdfViewTransform.QuadToView(const Quad: TPdfQuad): TArray<TPointF>;
begin
  Result := [PageToView(Quad.P1), PageToView(Quad.P2), PageToView(Quad.P3), PageToView(Quad.P4)];
end;

end.
