// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.StrokeNormalizer;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path;

type
  // Java2D normalizes the geometry of a stroke before it draws it (RenderingHints.VALUE_STROKE_NORMALIZE, the default, which PDFBox
  // does not change): with anti-aliasing the end points of every segment, in device pixels, move to the centre of the pixel they are in
  // (NormalizingPathIterator.NearestPixelCenter of the Marlin renderer). A line of two pixels at the edge of a page therefore covers
  // one whole pixel and half of the next. The control points of a curve move with the end points on either side of them.
  TPdfStrokeNormalizer = record
  strict private
    type
      TDevicePoint = record
        X: Double;
        Y: Double;
      end;
      TRounding = function(const Value: Double): Double;

    class function Centered(const Value: Double): Double; static;
    class function ClipEdge(const Value: Double): Double; static;
    class function FillEdge(const Value: Double): Double; static;
    class function DevicePoint(const Point: TPointF; const ToDevice: TPdfMatrix; const ResidualX, ResidualY: Double): TDevicePoint; static;
    class function IsUnitScale(const ToDevice: TPdfMatrix): Boolean; static;
    class function IsInvertible(const ToDevice: TPdfMatrix): Boolean; static;
    class function Inverse(const Matrix: TPdfMatrix; const Determinant: Double): TPdfMatrix; static;
    class procedure Rebuild(const Source: TPdfPath; const ToDevice: TPdfMatrix; const ResidualX, ResidualY: Double; const Target: TPdfPath;
                                const Snap: TRounding); static;

  public
    // A new path in the space of Path that the caller frees: Path with the end points of its segments moved to the pixel centres of the
    // device that ToDevice leads to. A transform that cannot be inverted gives a copy of Path.
    class function Normalize(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath; overload; static;
    // The matrix of the device has a Single translation; the exact (double) translation is that plus ResidualX and ResidualY. Java2D
    // works with the double, and a point that lies just below a pixel boundary must not be put on it by the rounding of the Single.
    class function Normalize(const Path: TPdfPath; const ToDevice: TPdfMatrix; const ResidualX, ResidualY: Double): TPdfPath; overload; static;
    // A new path in device pixels that the caller frees, for a clip that is not anti-aliased. In the reference images of PDFBox an edge of
    // such a clip acts as if it lay at floor(x + 0.25), which is what moving the vertices to floor(x + 0.25) + 0.25 and taking the pixels
    // whose centre is inside gives (as ShapeSpanIterator does, from memory); Skia would put it at the nearest pixel boundary.
    class function SnapForClip(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath; static;
    // A new path in device pixels that the caller frees, for a fill without anti-aliasing (PDFBox fills rectangles that way, as Acrobat
    // does). Two regimes are seen in the reference images, and the mechanism that separates them in Java2D is not known:
    //  - with a device matrix whose scale is 1 (72 DPI) the edge of a rectangle lies at ceil(x): the 1296 squares of the QR code of
    //    PDFBOX-6207 differ from the reference in 61 of 19044 pixels with ceil, in 1479 with floor(x + 0.25), in 2766 with the nearest
    //    boundary;
    //  - with another scale (150 DPI) it lies at floor(x + 0.25), the rule of the clip: the 30 strips of generated/render/colors-device.pdf
    //    agree on all their edges.
    class function SnapForFill(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath; static;
  end;

implementation

uses
  System.Math;

const
  PixelCentre = 0.5;
  ClipBias = 0.25;
  // A device value a hair above a whole number (the Single translation of a page matrix gives 0.00001 for the top edge of a page) is that
  // number, as in the double arithmetic of Java2D
  FillBias = 0.001;
  MinDeterminant = 1E-12;

{ TPdfStrokeNormalizer }

class function TPdfStrokeNormalizer.Centered(const Value: Double): Double;
begin
  Result := Floor(Value) + PixelCentre;
end;

class function TPdfStrokeNormalizer.ClipEdge(const Value: Double): Double;
begin
  Result := Floor(Value + ClipBias) + ClipBias;
end;

class function TPdfStrokeNormalizer.FillEdge(const Value: Double): Double;
begin
  Result := Ceil(Value - FillBias);
end;

class function TPdfStrokeNormalizer.IsUnitScale(const ToDevice: TPdfMatrix): Boolean;
begin
  Result := (Abs(ToDevice.ScaleX) = 1) and (Abs(ToDevice.ScaleY) = 1) and (ToDevice.ShearX = 0) and (ToDevice.ShearY = 0);
end;

class function TPdfStrokeNormalizer.SnapForFill(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath;
begin
  Result := TPdfPath.Create;
  try
    if IsUnitScale(ToDevice) then
    begin
      Rebuild(Path, ToDevice, 0, 0, Result, FillEdge);
    end
    else
    begin
      Rebuild(Path, ToDevice, 0, 0, Result, ClipEdge);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfStrokeNormalizer.SnapForClip(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath;
begin
  Result := TPdfPath.Create;
  try
    Rebuild(Path, ToDevice, 0, 0, Result, ClipEdge);
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfStrokeNormalizer.DevicePoint(const Point: TPointF; const ToDevice: TPdfMatrix; const ResidualX, ResidualY: Double): TDevicePoint;
begin
  Result.X := Double(ToDevice.ScaleX) * Point.X + Double(ToDevice.ShearX) * Point.Y + (Double(ToDevice.TranslateX) + ResidualX);
  Result.Y := Double(ToDevice.ShearY) * Point.X + Double(ToDevice.ScaleY) * Point.Y + (Double(ToDevice.TranslateY) + ResidualY);
end;

class function TPdfStrokeNormalizer.IsInvertible(const ToDevice: TPdfMatrix): Boolean;
begin
  const Determinant = Double(ToDevice.ScaleX) * ToDevice.ScaleY - Double(ToDevice.ShearX) * ToDevice.ShearY;
  Result := (Abs(Determinant) > MinDeterminant) and not IsNan(Determinant) and not IsInfinite(Determinant);
end;

class function TPdfStrokeNormalizer.Normalize(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath;
begin
  Result := Normalize(Path, ToDevice, 0, 0);
end;

class function TPdfStrokeNormalizer.Normalize(const Path: TPdfPath; const ToDevice: TPdfMatrix; const ResidualX, ResidualY: Double): TPdfPath;
begin
  if (Path.PointCount = 0) or not IsInvertible(ToDevice) then
  begin
    Exit(Path.Clone);
  end;

  const Determinant = Double(ToDevice.ScaleX) * ToDevice.ScaleY - Double(ToDevice.ShearX) * ToDevice.ShearY;
  Result := TPdfPath.Create;
  try
    Rebuild(Path, ToDevice, ResidualX, ResidualY, Result, Centered);
    Result.Transform(Inverse(ToDevice, Determinant));
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfStrokeNormalizer.Inverse(const Matrix: TPdfMatrix; const Determinant: Double): TPdfMatrix;
begin
  const A = Matrix.ScaleX;
  const B = Matrix.ShearY;
  const C = Matrix.ShearX;
  const D = Matrix.ScaleY;
  const InverseA = D / Determinant;
  const InverseB = -B / Determinant;
  const InverseC = -C / Determinant;
  const InverseD = A / Determinant;
  Result := TPdfMatrix.Create(InverseA, InverseB, InverseC, InverseD,
                              -(InverseA * Matrix.TranslateX + InverseC * Matrix.TranslateY),
                              -(InverseB * Matrix.TranslateX + InverseD * Matrix.TranslateY));
end;

// The path is copied segment by segment in the device space; the adjustment of the end point that came before moves the first control
// point. The points of the device are worked out in double precision, as Java2D does (floats in, a double transform): a point that lies
// just below a pixel boundary in double precision (12 points at 150 DPI is 24.999999 pixels) must not round up to the boundary in single
// precision, because the boundary decides the pixel the point moves to.
class procedure TPdfStrokeNormalizer.Rebuild(const Source: TPdfPath; const ToDevice: TPdfMatrix; const ResidualX, ResidualY: Double; const Target: TPdfPath;
                                             const Snap: TRounding);
begin
  var PointIndex := 0;
  var CurrentX := 0.0;
  var CurrentY := 0.0;
  var StartX := 0.0;
  var StartY := 0.0;
  for var VerbIndex := 0 to Source.VerbCount - 1 do
  begin
    case Source.Verb(VerbIndex) of
      TPdfPathVerb.MoveTo,
      TPdfPathVerb.LineTo:
        begin
          const End1 = DevicePoint(Source.Point(PointIndex), ToDevice, ResidualX, ResidualY);
          Inc(PointIndex);
          const NewX = Snap(End1.X);
          const NewY = Snap(End1.Y);
          if Source.Verb(VerbIndex) = TPdfPathVerb.MoveTo then
          begin
            Target.MoveTo(NewX, NewY);
            StartX := NewX - End1.X;
            StartY := NewY - End1.Y;
          end
          else
          begin
            Target.LineTo(NewX, NewY);
          end;
          CurrentX := NewX - End1.X;
          CurrentY := NewY - End1.Y;
        end;
      TPdfPathVerb.QuadTo:
        begin
          const Control = DevicePoint(Source.Point(PointIndex), ToDevice, ResidualX, ResidualY);
          const End2 = DevicePoint(Source.Point(PointIndex + 1), ToDevice, ResidualX, ResidualY);
          Inc(PointIndex, 2);
          const NewX = Snap(End2.X);
          const NewY = Snap(End2.Y);
          Target.QuadTo(Control.X + (CurrentX + (NewX - End2.X)) / 2, Control.Y + (CurrentY + (NewY - End2.Y)) / 2, NewX, NewY);
          CurrentX := NewX - End2.X;
          CurrentY := NewY - End2.Y;
        end;
      TPdfPathVerb.CubicTo:
        begin
          const Control1 = DevicePoint(Source.Point(PointIndex), ToDevice, ResidualX, ResidualY);
          const Control2 = DevicePoint(Source.Point(PointIndex + 1), ToDevice, ResidualX, ResidualY);
          const End3 = DevicePoint(Source.Point(PointIndex + 2), ToDevice, ResidualX, ResidualY);
          Inc(PointIndex, 3);
          const NewX = Snap(End3.X);
          const NewY = Snap(End3.Y);
          Target.CubicTo(Control1.X + CurrentX, Control1.Y + CurrentY, Control2.X + (NewX - End3.X), Control2.Y + (NewY - End3.Y), NewX, NewY);
          CurrentX := NewX - End3.X;
          CurrentY := NewY - End3.Y;
        end;
      TPdfPathVerb.Close:
        begin
          Target.ClosePath;
          CurrentX := StartX;
          CurrentY := StartY;
        end;
    else
      raise EInvalidOpException.CreateFmt('Unsupported path verb: %d', [Ord(Source.Verb(VerbIndex))]);
    end;
  end;
end;

end.
