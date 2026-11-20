// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/RadialShadingContext.java (3.0.8)
unit Pdf4D.Render.Shading.Radial;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Shading.Context;

type
  // Type 3. Like the axial context it takes the colours from a table of steps. A pixel lies on the circle of two values of the
  // parameter; the larger one in range is used, and failing that a value beyond an end that is extended gives the colour of that end
  // (the cell S3x of generated/render/shadings.pdf shows that PDFBox prefers a value in range to a larger one that is extended). PDFBox does
  // not look at the radius of the circle, so neither does this port: the circles with a negative radius are painted as well.
  TPdfRadialShadingContext = class(TPdfShadingContext)
  private
    FCoords: TArray<Single>;
    FDomain: TArray<Single>;
    FExtendStart: Boolean;
    FExtendEnd: Boolean;
    FX1X0: Single;
    FY1Y0: Single;
    FR1R0: Single;
    FDenominator: Double;
    FFactor: Integer;
    FColorTable: TArray<Integer>;

    procedure BuildColorTable;
    // The two values of the parameter at the point, smaller first. False when the point is on no circle.
    function TryGetParameters(const U, V: Single; out Smaller, Larger: Double): Boolean;
    class function IsInRange(const Parameter: Double): Boolean; static;
    function TryExtend(const Parameter: Double; out InputValue: Double): Boolean;
    function TryGetInputValue(const Smaller, Larger: Double; out InputValue: Double): Boolean;

  protected
    function TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean; override;

  public
    constructor Create(const Shading: TPDShadingType3; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TPdfRadialShadingContext }

constructor TPdfRadialShadingContext.Create(const Shading: TPDShadingType3; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
begin
  inherited Initialize(Shading, ShadingToDevice);
  FCoords := Shading.Coords;
  FDomain := Shading.Domain;
  FExtendStart := Shading.ExtendStart;
  FExtendEnd := Shading.ExtendEnd;
  FX1X0 := FCoords[3] - FCoords[0];
  FY1Y0 := FCoords[4] - FCoords[1];
  FR1R0 := FCoords[5] - FCoords[2];
  FDenominator := Sqr(Double(FX1X0)) + Sqr(Double(FY1Y0)) - Sqr(Double(FR1R0));

  // The worst case for the number of steps is between opposite corners of the area
  const Diagonal = Sqrt(Sqr(Double(DeviceArea.Width)) + Sqr(Double(DeviceArea.Height)));
  FFactor := Ceil(Diagonal);
  BuildColorTable;
end;

procedure TPdfRadialShadingContext.BuildColorTable;
begin
  // Like PDFBox, a table of one colour has black in the other steps
  SetLength(FColorTable, FFactor + 1);
  const DomainLength = FDomain[1] - FDomain[0];
  const HasOneColor = ((FFactor = 0) or (DomainLength = 0));
  if HasOneColor then
  begin
    FColorTable[0] := ConvertToRgb(Shading.EvalFunction([FDomain[0]]));
    Exit;
  end;

  for var Step := 0 to FFactor do
  begin
    const T = Single(FDomain[0] + DomainLength * Step / FFactor);
    FColorTable[Step] := ConvertToRgb(Shading.EvalFunction([T]));
  end;
end;

// The circle through the point has its center at c0 + s (c1 - c0) and its radius at r0 + s (r1 - r0), which gives
// a s^2 + 2 p s + q = 0 for s. Without a quadratic term (a cone with its apex on the circle) the equation is linear, where PDFBox divides
// by zero; the one value is then both the smaller and the larger.
function TPdfRadialShadingContext.TryGetParameters(const U, V: Single; out Smaller, Larger: Double): Boolean;
begin
  const DeltaX = Double(U - FCoords[0]);
  const DeltaY = Double(V - FCoords[1]);
  const P = -DeltaX * FX1X0 - DeltaY * FY1Y0 - Double(FCoords[2]) * FR1R0;
  const Q = Sqr(DeltaX) + Sqr(DeltaY) - Sqr(Double(FCoords[2]));

  if FDenominator = 0 then
  begin
    Result := (P <> 0);
    Smaller := Q / (2 * -P);
    Larger := Smaller;
    Exit;
  end;

  const Discriminant = P * P - FDenominator * Q;
  Result := ((not IsNan(Discriminant)) and (Discriminant >= 0));
  if not Result then
  begin
    Exit;
  end;

  const Root = Sqrt(Discriminant);
  const First = Single((-P + Root) / FDenominator);
  const Second = Single((-P - Root) / FDenominator);
  Smaller := Min(First, Second);
  Larger := Max(First, Second);
end;

class function TPdfRadialShadingContext.IsInRange(const Parameter: Double): Boolean;
begin
  Result := ((Parameter >= 0) and (Parameter <= 1));
end;

// A value beyond an end that is extended takes the colour of that end
function TPdfRadialShadingContext.TryExtend(const Parameter: Double; out InputValue: Double): Boolean;
begin
  InputValue := 0;
  if IsNan(Parameter) then
  begin
    Exit(False);
  end;

  if Parameter < 0 then
  begin
    Exit(FExtendStart);
  end;

  InputValue := 1;
  Result := ((Parameter > 1) and FExtendEnd);
end;

// A value in range is taken before one that the extension brings in range, and the larger of two goes first in both cases
function TPdfRadialShadingContext.TryGetInputValue(const Smaller, Larger: Double; out InputValue: Double): Boolean;
begin
  Result := True;
  if IsInRange(Larger) then
  begin
    InputValue := Larger;
  end
  else if IsInRange(Smaller) then
  begin
    InputValue := Smaller;
  end
  else
  begin
    Result := (TryExtend(Larger, InputValue) or TryExtend(Smaller, InputValue));
  end;
end;

function TPdfRadialShadingContext.TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean;
begin
  var Smaller: Double := 0;
  var Larger: Double := 0;
  var InputValue: Double := 0;
  const IsOnCircle = TryGetParameters(U, V, Smaller, Larger);
  if IsOnCircle and TryGetInputValue(Smaller, Larger, InputValue) then
  begin
    Rgb := FColorTable[Trunc(InputValue * FFactor)];
    Exit(True);
  end;

  Rgb := RgbBackground;
  Result := HasBackground;
end;

end.
