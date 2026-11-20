// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/AxialShadingContext.java (3.0.8)
unit Pdf4D.Render.Shading.Axial;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Shading.Context;

type
  // Type 2. The colours along the axis come from a table of Factor + 1 steps, with Factor the length of the diagonal of the area in
  // pixels, like PDFBox: a pixel gets the colour of the step below its position.
  TPdfAxialShadingContext = class(TPdfShadingContext)
  private
    FCoords: TArray<Single>;
    FDomain: TArray<Single>;
    FExtendStart: Boolean;
    FExtendEnd: Boolean;
    FX1X0: Single;
    FY1Y0: Single;
    FDenominator: Double;
    FFactor: Integer;
    FColorTable: TArray<Integer>;

    procedure BuildColorTable;
    // The position along the axis, 0..1 inside the shading. False when the pixel has none.
    function TryGetInputValue(const U, V: Single; out InputValue: Double): Boolean;

  protected
    function TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean; override;

  public
    constructor Create(const Shading: TPDShadingType2; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TPdfAxialShadingContext }

constructor TPdfAxialShadingContext.Create(const Shading: TPDShadingType2; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
begin
  inherited Initialize(Shading, ShadingToDevice);
  FCoords := Shading.Coords;
  FDomain := Shading.Domain;
  FExtendStart := Shading.ExtendStart;
  FExtendEnd := Shading.ExtendEnd;
  FX1X0 := FCoords[2] - FCoords[0];
  FY1Y0 := FCoords[3] - FCoords[1];
  FDenominator := Sqr(Double(FX1X0)) + Sqr(Double(FY1Y0));

  // The worst case for the number of steps is between opposite corners of the area
  const Diagonal = Sqrt(Sqr(Double(DeviceArea.Width)) + Sqr(Double(DeviceArea.Height)));
  FFactor := Ceil(Diagonal);
  BuildColorTable;
end;

procedure TPdfAxialShadingContext.BuildColorTable;
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

function TPdfAxialShadingContext.TryGetInputValue(const U, V: Single; out InputValue: Double): Boolean;
begin
  InputValue := FX1X0 * (U - FCoords[0]) + FY1Y0 * (V - FCoords[1]);
  if FDenominator = 0 then
  begin
    // Start and end are the same point (PDFBOX-1442)
    Exit(False);
  end;

  InputValue := InputValue / FDenominator;
  if IsNan(InputValue) then
  begin
    Exit(False);
  end;

  if InputValue < 0 then
  begin
    Result := FExtendStart;
    InputValue := 0;
  end
  else if InputValue > 1 then
  begin
    Result := FExtendEnd;
    InputValue := 1;
  end
  else
  begin
    Result := True;
  end;
end;

function TPdfAxialShadingContext.TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean;
begin
  var InputValue: Double;
  if TryGetInputValue(U, V, InputValue) then
  begin
    Rgb := FColorTable[Trunc(InputValue * FFactor)];
    Exit(True);
  end;

  Rgb := RgbBackground;
  Result := HasBackground;
end;

end.
