// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/Type1ShadingContext.java (3.0.8)
unit Pdf4D.Render.Shading.&Function;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Shading.Context;

type
  // Type 1: the function is evaluated for every pixel, at the point of the Domain that lies under it
  TPdfFunctionShadingContext = class(TPdfShadingContext)
  private
    FDomain: TArray<Single>;

  protected
    function TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean; override;

  public
    // The /Matrix of the shading is applied before ShadingToDevice
    constructor Create(const Shading: TPDShadingType1; const ShadingToDevice: TPdfMatrix);
  end;

implementation

{ TPdfFunctionShadingContext }

constructor TPdfFunctionShadingContext.Create(const Shading: TPDShadingType1; const ShadingToDevice: TPdfMatrix);
begin
  inherited Initialize(Shading, Shading.Matrix.Multiply(ShadingToDevice));
  FDomain := Shading.Domain;
end;

function TPdfFunctionShadingContext.TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean;
begin
  const IsOutsideDomain = ((U < FDomain[0]) or (U > FDomain[1]) or (V < FDomain[2]) or (V > FDomain[3]));
  if IsOutsideDomain then
  begin
    Rgb := RgbBackground;
    Exit(HasBackground);
  end;

  Rgb := ConvertToRgb(Shading.EvalFunction([U, V]));
  Result := True;
end;

end.
