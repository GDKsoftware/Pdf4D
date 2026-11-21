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

    class function Centered(const Value: Double): Double; static;
    class function DevicePoint(const Point: TPointF; const ToDevice: TPdfMatrix): TDevicePoint; static;
    class function IsInvertible(const ToDevice: TPdfMatrix): Boolean; static;
    class function Inverse(const Matrix: TPdfMatrix; const Determinant: Double): TPdfMatrix; static;
    class procedure Rebuild(const Source: TPdfPath; const ToDevice: TPdfMatrix; const Target: TPdfPath); static;

  public
    // A new path in the space of Path that the caller frees: Path with the end points of its segments moved to the pixel centres of the
    // device that ToDevice leads to. A transform that cannot be inverted gives a copy of Path.
    class function Normalize(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath; static;
  end;

implementation

uses
  System.Math;

const
  PixelCentre = 0.5;
  MinDeterminant = 1E-12;

{ TPdfStrokeNormalizer }

class function TPdfStrokeNormalizer.Centered(const Value: Double): Double;
begin
  Result := Floor(Value) + PixelCentre;
end;

class function TPdfStrokeNormalizer.DevicePoint(const Point: TPointF; const ToDevice: TPdfMatrix): TDevicePoint;
begin
  Result.X := Double(ToDevice.ScaleX) * Point.X + Double(ToDevice.ShearX) * Point.Y + ToDevice.TranslateX;
  Result.Y := Double(ToDevice.ShearY) * Point.X + Double(ToDevice.ScaleY) * Point.Y + ToDevice.TranslateY;
end;

class function TPdfStrokeNormalizer.IsInvertible(const ToDevice: TPdfMatrix): Boolean;
begin
  const Determinant = Double(ToDevice.ScaleX) * ToDevice.ScaleY - Double(ToDevice.ShearX) * ToDevice.ShearY;
  Result := (Abs(Determinant) > MinDeterminant) and not IsNan(Determinant) and not IsInfinite(Determinant);
end;

class function TPdfStrokeNormalizer.Normalize(const Path: TPdfPath; const ToDevice: TPdfMatrix): TPdfPath;
begin
  if (Path.PointCount = 0) or not IsInvertible(ToDevice) then
  begin
    Exit(Path.Clone);
  end;

  const Determinant = Double(ToDevice.ScaleX) * ToDevice.ScaleY - Double(ToDevice.ShearX) * ToDevice.ShearY;
  Result := TPdfPath.Create;
  try
    Rebuild(Path, ToDevice, Result);
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
class procedure TPdfStrokeNormalizer.Rebuild(const Source: TPdfPath; const ToDevice: TPdfMatrix; const Target: TPdfPath);
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
          const End1 = DevicePoint(Source.Point(PointIndex), ToDevice);
          Inc(PointIndex);
          const NewX = Centered(End1.X);
          const NewY = Centered(End1.Y);
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
          const Control = DevicePoint(Source.Point(PointIndex), ToDevice);
          const End2 = DevicePoint(Source.Point(PointIndex + 1), ToDevice);
          Inc(PointIndex, 2);
          const NewX = Centered(End2.X);
          const NewY = Centered(End2.Y);
          Target.QuadTo(Control.X + (CurrentX + (NewX - End2.X)) / 2, Control.Y + (CurrentY + (NewY - End2.Y)) / 2, NewX, NewY);
          CurrentX := NewX - End2.X;
          CurrentY := NewY - End2.Y;
        end;
      TPdfPathVerb.CubicTo:
        begin
          const Control1 = DevicePoint(Source.Point(PointIndex), ToDevice);
          const Control2 = DevicePoint(Source.Point(PointIndex + 1), ToDevice);
          const End3 = DevicePoint(Source.Point(PointIndex + 2), ToDevice);
          Inc(PointIndex, 3);
          const NewX = Centered(End3.X);
          const NewY = Centered(End3.Y);
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
