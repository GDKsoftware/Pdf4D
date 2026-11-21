// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PDFRenderer.java (3.0.8), the size and transform of renderImage
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PageDrawer.java (3.0.8), the flip and crop box offset of drawPage
unit Pdf4D.Render.PageTransform;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Model.Rectangle;

type
  // Page geometry as PDFRenderer.renderImage and PageDrawer.drawPage use it
  TPdfPageTransform = record
    // Pixels of the whole page: Max(Floor(points * Scale), 1), width and height swapped at 90 and 270 degrees
    Size: TSize;
    // Page user space (points, origin lower left, no rotation, absolute) to pixels of the whole page
    PageToDevice: TPdfMatrix;
    // PDFBox works with a double matrix, whose translation is not a Single (the height of the page times the scale): the translation of
    // PageToDevice plus these is that double value, as far as it is finite. Zero when the Single holds the value.
    TranslationResidualX: Double;
    TranslationResidualY: Double;

    // Rotation is a multiple of 90, negative values and values beyond 360 included; anything else raises EArgumentException.
    // A scale that makes the page larger than the range of Integer gives the largest size; the matrix stays finite.
    class function Create(const CropBox: TPdfRectangle; const Rotation: Integer; const Scale: Single): TPdfPageTransform; static;

    // The page point of a device pixel position. A matrix that cannot be inverted gives the point as it is.
    function DeviceToPage(const Point: TPointF): TPointF;
  end;

implementation

uses
  System.Math,
  System.SysUtils;

const
  RightAngle = 90;
  FullTurn = 360;
  // Just below the largest Single, so that a value that is clamped to it can still take part in a sum
  LargestMatrixValue: Double = 3.0e38;

// PDFBOX-4306: at least one pixel, and the product of two floats is a float. The size is limited to what an Integer holds.
function PixelsOf(const Points, Scale: Single): Integer;
begin
  const Product = Single(Min(Double(Points) * Double(Scale), LargestMatrixValue));
  if not (Product >= 1) then
  begin
    Exit(1);
  end;

  if Product >= High(Integer) then
  begin
    Exit(High(Integer));
  end;
  Result := Floor(Product);
end;

function ClampToMatrixValue(const Value: Double): Single;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;
  Result := Single(Min(Max(Value, -LargestMatrixValue), LargestMatrixValue));
end;

// What the Single leaves of the exact value; nothing when the value does not fit a Single
function ResidualOf(const Exact: Double; const Rounded: Single): Double;
begin
  const IsExactFinite = (not IsNan(Exact)) and (Abs(Exact) <= LargestMatrixValue);
  if not IsExactFinite then
  begin
    Exit(0);
  end;
  Result := Exact - Double(Rounded);
end;

{ TPdfPageTransform }

class function TPdfPageTransform.Create(const CropBox: TPdfRectangle; const Rotation: Integer; const Scale: Single): TPdfPageTransform;
begin
  const Angle = ((Rotation mod FullTurn) + FullTurn) mod FullTurn;
  if (Angle mod RightAngle) <> 0 then
  begin
    raise EArgumentException.CreateFmt('Rotation %d is not a multiple of 90 degrees', [Rotation]);
  end;

  const Width = CropBox.Width;
  const Height = CropBox.Height;
  const IsSideways = ((Angle = 90) or (Angle = 270));
  if IsSideways then
  begin
    Result.Size := TSize.Create(PixelsOf(Height, Scale), PixelsOf(Width, Scale));
  end
  else
  begin
    Result.Size := TSize.Create(PixelsOf(Width, Scale), PixelsOf(Height, Scale));
  end;

  // PDFRenderer.transform puts the scale and the rotation around the page, PageDrawer.drawPage flips the y axis and moves the crop box
  // to the origin. The point of the page goes through the crop box offset, the flip, the rotation and the scale, in that order.
  const LeftEdge: Double = CropBox.LowerLeftX;
  const BottomEdge: Double = CropBox.LowerLeftY;
  var A: Double;
  var B: Double;
  var C: Double;
  var D: Double;
  var E: Double;
  var F: Double;
  case Angle of
    0:
    begin
      A := 1;
      B := 0;
      C := 0;
      D := -1;
      E := -LeftEdge;
      F := Height + BottomEdge;
    end;
    90:
    begin
      A := 0;
      B := 1;
      C := 1;
      D := 0;
      E := -BottomEdge;
      F := -LeftEdge;
    end;
    180:
    begin
      A := -1;
      B := 0;
      C := 0;
      D := 1;
      E := Width + LeftEdge;
      F := -BottomEdge;
    end;
  else
    begin
      A := 0;
      B := -1;
      C := -1;
      D := 0;
      E := Height + BottomEdge;
      F := Width + LeftEdge;
    end;
  end;

  const Factor: Double = Scale;
  Result.TranslationResidualX := 0;
  Result.TranslationResidualY := 0;
  Result.PageToDevice := TPdfMatrix.Create(ClampToMatrixValue(A * Factor), ClampToMatrixValue(B * Factor), ClampToMatrixValue(C * Factor),
                                           ClampToMatrixValue(D * Factor), ClampToMatrixValue(E * Factor), ClampToMatrixValue(F * Factor));
  Result.TranslationResidualX := ResidualOf(E * Factor, Result.PageToDevice.TranslateX);
  Result.TranslationResidualY := ResidualOf(F * Factor, Result.PageToDevice.TranslateY);
end;

function TPdfPageTransform.DeviceToPage(const Point: TPointF): TPointF;
begin
  const A: Double = PageToDevice.ScaleX;
  const B: Double = PageToDevice.ShearY;
  const C: Double = PageToDevice.ShearX;
  const D: Double = PageToDevice.ScaleY;
  const Determinant = A * D - B * C;
  const IsInvertible = ((not IsNan(Determinant)) and (Determinant <> 0));
  if not IsInvertible then
  begin
    Exit(Point);
  end;

  const Dx = Point.X - Double(PageToDevice.TranslateX);
  const Dy = Point.Y - Double(PageToDevice.TranslateY);
  Result.X := (D * Dx - C * Dy) / Determinant;
  Result.Y := (A * Dy - B * Dx) / Determinant;
end;

end.
