// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/color/*.java (3.0.8)
unit Pdf4D.Render.Operators.Color;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Graphics.Color,
  Pdf4D.Render.GraphicsEngine;

type
  // The base of the colour operators: finding a colour space by name and setting a colour from the operands
  TColorOperatorProcessor = class abstract(TGraphicsOperatorProcessor)
  protected
    // The colour space of a name of /ColorSpace in the resources, or a device name. A space that is not supported yet is logged and
    // replaced by DeviceGray; a name that is no colour space raises EPdfParseException.
    function ResolveColorSpace(const SpaceName: string): TPDColorSpace;
    // The colour that the operands, which are all numbers, make in Space
    function MakeColor(const Space: TPDColorSpace; const Operands: TArray<TCosBase>): TPDColor;
  end;

  // The operators of the two kinds (stroking and non-stroking) of colour differ only in the part of the state they work on
  TSetColorOperator = class abstract(TColorOperatorProcessor)
  protected
    function GetColorSpace: TPDColorSpace; virtual; abstract;
    procedure SetColor(const Color: TPDColor); virtual; abstract;

  public
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // SC
  TSetStrokingColorOperator = class(TSetColorOperator)
  protected
    function GetColorSpace: TPDColorSpace; override;
    procedure SetColor(const Color: TPDColor); override;

  public
    function Name: string; override;
  end;

  // SCN
  TSetStrokingColorNOperator = class(TSetStrokingColorOperator)
  public
    function Name: string; override;
  end;

  // sc
  TSetNonStrokingColorOperator = class(TSetColorOperator)
  protected
    function GetColorSpace: TPDColorSpace; override;
    procedure SetColor(const Color: TPDColor); override;

  public
    function Name: string; override;
  end;

  // scn
  TSetNonStrokingColorNOperator = class(TSetNonStrokingColorOperator)
  public
    function Name: string; override;
  end;

  // CS
  TSetStrokingColorSpaceOperator = class(TColorOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // cs
  TSetNonStrokingColorSpaceOperator = class(TColorOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // G
  TSetStrokingDeviceGrayColorOperator = class(TSetStrokingColorOperator)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // RG
  TSetStrokingDeviceRGBColorOperator = class(TSetStrokingColorOperator)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // K
  TSetStrokingDeviceCMYKColorOperator = class(TSetStrokingColorOperator)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // g
  TSetNonStrokingDeviceGrayColorOperator = class(TSetNonStrokingColorOperator)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // rg
  TSetNonStrokingDeviceRGBColorOperator = class(TSetNonStrokingColorOperator)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // k
  TSetNonStrokingDeviceCMYKColorOperator = class(TSetNonStrokingColorOperator)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TColorOperators = record
    class procedure Register(const Engine: TPdfGraphicsEngine); static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.Color.Factory,
  Pdf4D.Graphics.State;

resourcestring
  ColorSpaceNotSupported = 'The colour space /%s is not supported yet, DeviceGray is used instead: %s';
  PatternColorNotSupported = 'Pattern colours are not supported yet: %s skipped';

{ TColorOperators }

class procedure TColorOperators.Register(const Engine: TPdfGraphicsEngine);
begin
  Engine.AddOperator(TSetStrokingColorSpaceOperator.Create(Engine));
  Engine.AddOperator(TSetNonStrokingColorSpaceOperator.Create(Engine));
  Engine.AddOperator(TSetStrokingColorOperator.Create(Engine));
  Engine.AddOperator(TSetNonStrokingColorOperator.Create(Engine));
  Engine.AddOperator(TSetStrokingColorNOperator.Create(Engine));
  Engine.AddOperator(TSetNonStrokingColorNOperator.Create(Engine));
  Engine.AddOperator(TSetStrokingDeviceGrayColorOperator.Create(Engine));
  Engine.AddOperator(TSetNonStrokingDeviceGrayColorOperator.Create(Engine));
  Engine.AddOperator(TSetStrokingDeviceRGBColorOperator.Create(Engine));
  Engine.AddOperator(TSetNonStrokingDeviceRGBColorOperator.Create(Engine));
  Engine.AddOperator(TSetStrokingDeviceCMYKColorOperator.Create(Engine));
  Engine.AddOperator(TSetNonStrokingDeviceCMYKColorOperator.Create(Engine));
end;

{ TColorOperatorProcessor }

function TColorOperatorProcessor.ResolveColorSpace(const SpaceName: string): TPDColorSpace;
begin
  const NameOperand = TCosName.Create(SpaceName);
  try
    try
      Result := TPDColorSpaceFactory.Create(NameOperand, Engine.Resources);
    except
      on Failure: EPdfUnsupportedFeatureException do
      begin
        Engine.LogWarning(ColorSpaceNotSupported, [SpaceName, Failure.Message]);
        Result := TPDDeviceGray.Instance;
      end;
    end;
  finally
    NameOperand.Free;
  end;
end;

function TColorOperatorProcessor.MakeColor(const Space: TPDColorSpace; const Operands: TArray<TCosBase>): TPDColor;
begin
  var Components: TArray<Single>;
  SetLength(Components, Length(Operands));
  for var Index := 0 to High(Operands) do
  begin
    Components[Index] := NumberAt(Operands, Index);
  end;

  Result := TPDColor.Create(Space, Components);
end;

{ TSetColorOperator }

procedure TSetColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const IsPatternColor = ((Length(Operands) > 0) and (Operands[High(Operands)] is TCosName));
  if IsPatternColor then
  begin
    Engine.LogWarning(PatternColorNotSupported, [Operator.Name]);
    Exit;
  end;

  const Space = GetColorSpace;
  RequireOperands(Operator, Operands, Space.NumberOfComponents);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    // The colour has no colour space, which the device paints as transparent
    SetColor(TPDColor.Create(nil, nil));
    Exit;
  end;

  SetColor(MakeColor(Space, Operands));
end;

{ TSetStrokingColorOperator }

function TSetStrokingColorOperator.Name: string;
begin
  Result := TOperatorNames.StrokingColor;
end;

function TSetStrokingColorOperator.GetColorSpace: TPDColorSpace;
begin
  Result := GraphicsEngine.RenderState.StrokingColorSpace;
end;

procedure TSetStrokingColorOperator.SetColor(const Color: TPDColor);
begin
  GraphicsEngine.RenderState.StrokingColor := Color;
end;

{ TSetStrokingColorNOperator }

function TSetStrokingColorNOperator.Name: string;
begin
  Result := TOperatorNames.StrokingColorN;
end;

{ TSetNonStrokingColorOperator }

function TSetNonStrokingColorOperator.Name: string;
begin
  Result := TOperatorNames.NonStrokingColor;
end;

function TSetNonStrokingColorOperator.GetColorSpace: TPDColorSpace;
begin
  Result := GraphicsEngine.RenderState.NonStrokingColorSpace;
end;

procedure TSetNonStrokingColorOperator.SetColor(const Color: TPDColor);
begin
  GraphicsEngine.RenderState.NonStrokingColor := Color;
end;

{ TSetNonStrokingColorNOperator }

function TSetNonStrokingColorNOperator.Name: string;
begin
  Result := TOperatorNames.NonStrokingColorN;
end;

{ TSetStrokingColorSpaceOperator }

function TSetStrokingColorSpaceOperator.Name: string;
begin
  Result := TOperatorNames.StrokingColorSpace;
end;

procedure TSetStrokingColorSpaceOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const HasName = ((Length(Operands) > 0) and (Operands[0] is TCosName));
  if not HasName then
  begin
    Exit;
  end;

  const Space = ResolveColorSpace(TCosName(Operands[0]).Name);
  GraphicsEngine.RenderState.StrokingColorSpace := Space;
  GraphicsEngine.RenderState.StrokingColor := Space.InitialColor;
end;

{ TSetNonStrokingColorSpaceOperator }

function TSetNonStrokingColorSpaceOperator.Name: string;
begin
  Result := TOperatorNames.NonStrokingColorSpace;
end;

procedure TSetNonStrokingColorSpaceOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const HasName = ((Length(Operands) > 0) and (Operands[0] is TCosName));
  if not HasName then
  begin
    Exit;
  end;

  const Space = ResolveColorSpace(TCosName(Operands[0]).Name);
  GraphicsEngine.RenderState.NonStrokingColorSpace := Space;
  GraphicsEngine.RenderState.NonStrokingColor := Space.InitialColor;
end;

{ TSetStrokingDeviceGrayColorOperator }

function TSetStrokingDeviceGrayColorOperator.Name: string;
begin
  Result := TOperatorNames.StrokingColorGray;
end;

procedure TSetStrokingDeviceGrayColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.RenderState.StrokingColorSpace := ResolveColorSpace(TCosNames.DeviceGray);
  inherited Process(Operator, Operands);
end;

{ TSetStrokingDeviceRGBColorOperator }

function TSetStrokingDeviceRGBColorOperator.Name: string;
begin
  Result := TOperatorNames.StrokingColorRgb;
end;

procedure TSetStrokingDeviceRGBColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.RenderState.StrokingColorSpace := ResolveColorSpace(TCosNames.DeviceRGB);
  inherited Process(Operator, Operands);
end;

{ TSetStrokingDeviceCMYKColorOperator }

function TSetStrokingDeviceCMYKColorOperator.Name: string;
begin
  Result := TOperatorNames.StrokingColorCmyk;
end;

procedure TSetStrokingDeviceCMYKColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.RenderState.StrokingColorSpace := ResolveColorSpace(TCosNames.DeviceCMYK);
  inherited Process(Operator, Operands);
end;

{ TSetNonStrokingDeviceGrayColorOperator }

function TSetNonStrokingDeviceGrayColorOperator.Name: string;
begin
  Result := TOperatorNames.NonStrokingGray;
end;

procedure TSetNonStrokingDeviceGrayColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.RenderState.NonStrokingColorSpace := ResolveColorSpace(TCosNames.DeviceGray);
  inherited Process(Operator, Operands);
end;

{ TSetNonStrokingDeviceRGBColorOperator }

function TSetNonStrokingDeviceRGBColorOperator.Name: string;
begin
  Result := TOperatorNames.NonStrokingRgb;
end;

procedure TSetNonStrokingDeviceRGBColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.RenderState.NonStrokingColorSpace := ResolveColorSpace(TCosNames.DeviceRGB);
  inherited Process(Operator, Operands);
end;

{ TSetNonStrokingDeviceCMYKColorOperator }

function TSetNonStrokingDeviceCMYKColorOperator.Name: string;
begin
  Result := TOperatorNames.NonStrokingCmyk;
end;

procedure TSetNonStrokingDeviceCMYKColorOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.RenderState.NonStrokingColorSpace := ResolveColorSpace(TCosNames.DeviceCMYK);
  inherited Process(Operator, Operands);
end;

end.
