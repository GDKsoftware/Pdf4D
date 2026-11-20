// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/*.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDExtendedGraphicsState.java (3.0.8), copyIntoGraphicsState
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/RenderingIntent.java (3.0.8), fromString
unit Pdf4D.Render.Operators.State;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.ExtendedGraphicsState,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.GraphicsEngine;

type
  // i
  TSetFlatnessOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // J
  TSetLineCapStyleOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // d
  TSetLineDashPatternOperator = class(TGraphicsOperatorProcessor)
  private
    function HasOnlyNumbers(const DashArray: TCosArray): Boolean;

  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // j
  TSetLineJoinStyleOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // M
  TSetLineMiterLimitOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // w
  TSetLineWidthOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // ri
  TSetRenderingIntentOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // gs: every key of the ExtGState, where the core operator only copies /Font
  TSetRenderGraphicsStateParametersOperator = class(TGraphicsOperatorProcessor)
  private
    procedure ApplyState(const Dictionary: TCosDictionary);
    procedure ApplyKey(const Key: string; const Dictionary: TCosDictionary; const State: TPDExtendedGraphicsState);
    procedure ApplyLineStyle(const Key: string; const State: TPDExtendedGraphicsState);
    procedure ApplyDashPattern(const State: TPDExtendedGraphicsState);
    procedure ApplyAlpha(const Key: string; const State: TPDExtendedGraphicsState);
    procedure ApplySoftMask(const State: TPDExtendedGraphicsState);
    procedure ApplyTransfer(const Key: string; const Dictionary: TCosDictionary; const State: TPDExtendedGraphicsState);

  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TRenderStateOperators = record
    // q, Q and cm of the core, and the operators of the line style, rendering intent, flatness and ExtGState. Tm is registered with
    // the text operators.
    class procedure Register(const Engine: TPdfGraphicsEngine); static;
    // RenderingIntent.fromString: one of the four names as it is, RelativeColorimetric for another
    class function IntentOf(const IntentName: string): string; static;
    // BlendMode.getInstance for a name that Pdf4D.Model.ExtendedGraphicsState has made one of the known names; Normal for another
    class function BlendModeOf(const BlendModeName: string): TPdfBlendMode; static;
  end;

implementation

uses
  Pdf4D.Content.Operators.State,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Graphics.LineDash,
  Pdf4D.Graphics.State;

resourcestring
  DashArrayHasNoNumber = 'dash array has a non number element, ignored';
  ExtGStateNotFound = 'name for ''gs'' operator not found in resources: /%s';
  DashPatternInvalid = 'The /D entry of an ExtGState is no dash array with a phase, ignored';
  SoftMaskNotSupported = 'Soft masks are not supported yet: the /SMask of an ExtGState is ignored';

const
  IntentNames: array[0..3] of string = (TCosNames.AbsoluteColorimetric, TCosNames.RelativeColorimetric, TCosNames.Saturation, TCosNames.Perceptual);
  BlendModeNames: array[TPdfBlendMode] of string = (TCosNames.Normal, TCosNames.Multiply, TCosNames.Screen, TCosNames.Overlay, TCosNames.Darken,
                                                    TCosNames.Lighten, TCosNames.ColorDodge, TCosNames.ColorBurn, TCosNames.HardLight,
                                                    TCosNames.SoftLight, TCosNames.Difference, TCosNames.Exclusion, TCosNames.Hue,
                                                    TCosNames.Saturation, TCosNames.Color, TCosNames.Luminosity);
  NoSoftMask = 'None';
  DefaultLineWidth = 1;
  DefaultMiterLimit = 10;
  DefaultAlpha = 1;
  DefaultFlatness = 1;
  DashOperands = 2;

{ TRenderStateOperators }

class procedure TRenderStateOperators.Register(const Engine: TPdfGraphicsEngine);
begin
  TStateOperators.Register(Engine);
  Engine.AddOperator(TSetFlatnessOperator.Create(Engine));
  Engine.AddOperator(TSetLineCapStyleOperator.Create(Engine));
  Engine.AddOperator(TSetLineDashPatternOperator.Create(Engine));
  Engine.AddOperator(TSetLineJoinStyleOperator.Create(Engine));
  Engine.AddOperator(TSetLineMiterLimitOperator.Create(Engine));
  Engine.AddOperator(TSetLineWidthOperator.Create(Engine));
  Engine.AddOperator(TSetRenderingIntentOperator.Create(Engine));
  Engine.AddOperator(TSetRenderGraphicsStateParametersOperator.Create(Engine));
end;

class function TRenderStateOperators.IntentOf(const IntentName: string): string;
begin
  for var Known in IntentNames do
  begin
    if Known = IntentName then
    begin
      Exit(Known);
    end;
  end;

  Result := TCosNames.RelativeColorimetric;
end;

class function TRenderStateOperators.BlendModeOf(const BlendModeName: string): TPdfBlendMode;
begin
  for var Mode := Low(TPdfBlendMode) to High(TPdfBlendMode) do
  begin
    if BlendModeNames[Mode] = BlendModeName then
    begin
      Exit(Mode);
    end;
  end;

  Result := TPdfBlendMode.Normal;
end;

{ TSetFlatnessOperator }

function TSetFlatnessOperator.Name: string;
begin
  Result := TOperatorNames.SetFlatness;
end;

procedure TSetFlatnessOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if CheckArrayTypes(Operands, TCosNumber) then
  begin
    GraphicsEngine.RenderState.Flatness := NumberAt(Operands, 0);
  end;
end;

{ TSetLineCapStyleOperator }

function TSetLineCapStyleOperator.Name: string;
begin
  Result := TOperatorNames.SetLineCapStyle;
end;

procedure TSetLineCapStyleOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if CheckArrayTypes(Operands, TCosNumber) then
  begin
    GraphicsEngine.RenderState.LineCap := TCosNumber(Operands[0]).IntValue;
  end;
end;

{ TSetLineDashPatternOperator }

function TSetLineDashPatternOperator.Name: string;
begin
  Result := TOperatorNames.SetLineDashPattern;
end;

// Looks at the items up to the first one that is not 0, like SetLineDashPattern does
function TSetLineDashPatternOperator.HasOnlyNumbers(const DashArray: TCosArray): Boolean;
begin
  for var Item in DashArray do
  begin
    if not (Item is TCosNumber) then
    begin
      Engine.LogWarning(DashArrayHasNoNumber, []);
      Exit(False);
    end;

    const IsNonZero = (TCosNumber(Item).FloatValue <> 0);
    if IsNonZero then
    begin
      Exit(True);
    end;
  end;

  Result := True;
end;

procedure TSetLineDashPatternOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, DashOperands);
  const IsPattern = ((Operands[0] is TCosArray) and (Operands[1] is TCosNumber));
  if not IsPattern then
  begin
    Exit;
  end;

  const Phase = TCosNumber(Operands[1]).IntValue;
  if HasOnlyNumbers(TCosArray(Operands[0])) then
  begin
    GraphicsEngine.RenderState.DashPattern := TPDLineDashPattern.Create(TCosArray(Operands[0]), Phase);
    Exit;
  end;

  const NoDashes = TCosArray.Create;
  try
    GraphicsEngine.RenderState.DashPattern := TPDLineDashPattern.Create(NoDashes, Phase);
  finally
    NoDashes.Free;
  end;
end;

{ TSetLineJoinStyleOperator }

function TSetLineJoinStyleOperator.Name: string;
begin
  Result := TOperatorNames.SetLineJoinStyle;
end;

procedure TSetLineJoinStyleOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if CheckArrayTypes(Operands, TCosNumber) then
  begin
    GraphicsEngine.RenderState.LineJoin := TCosNumber(Operands[0]).IntValue;
  end;
end;

{ TSetLineMiterLimitOperator }

function TSetLineMiterLimitOperator.Name: string;
begin
  Result := TOperatorNames.SetLineMiterLimit;
end;

procedure TSetLineMiterLimitOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if CheckArrayTypes(Operands, TCosNumber) then
  begin
    GraphicsEngine.RenderState.MiterLimit := NumberAt(Operands, 0);
  end;
end;

{ TSetLineWidthOperator }

function TSetLineWidthOperator.Name: string;
begin
  Result := TOperatorNames.SetLineWidth;
end;

procedure TSetLineWidthOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if CheckArrayTypes(Operands, TCosNumber) then
  begin
    GraphicsEngine.RenderState.LineWidth := NumberAt(Operands, 0);
  end;
end;

{ TSetRenderingIntentOperator }

function TSetRenderingIntentOperator.Name: string;
begin
  Result := TOperatorNames.SetRenderingIntent;
end;

procedure TSetRenderingIntentOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if Operands[0] is TCosName then
  begin
    GraphicsEngine.RenderState.RenderingIntent := TRenderStateOperators.IntentOf(TCosName(Operands[0]).Name);
  end;
end;

{ TSetRenderGraphicsStateParametersOperator }

function TSetRenderGraphicsStateParametersOperator.Name: string;
begin
  Result := TOperatorNames.SetGraphicsStateParams;
end;

procedure TSetRenderGraphicsStateParametersOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if not (Operands[0] is TCosName) then
  begin
    Exit;
  end;

  const StateName = TCosName(Operands[0]).Name;
  var Dictionary: TCosDictionary;
  if not Engine.Resources.TryGetExtGState(StateName, Dictionary) then
  begin
    Engine.LogError(ExtGStateNotFound, [StateName]);
    Exit;
  end;

  ApplyState(Dictionary);
end;

procedure TSetRenderGraphicsStateParametersOperator.ApplyState(const Dictionary: TCosDictionary);
begin
  const State = TPDExtendedGraphicsState.Create(Dictionary);
  try
    for var Key in Dictionary.Keys do
    begin
      ApplyKey(Key, Dictionary, State);
    end;
  finally
    State.Free;
  end;
end;

procedure TSetRenderGraphicsStateParametersOperator.ApplyKey(const Key: string; const Dictionary: TCosDictionary; const State: TPDExtendedGraphicsState);
begin
  const RenderState = GraphicsEngine.RenderState;
  var Value: Single;
  var Intent: string;

  if (Key = TCosNames.LW) or (Key = TCosNames.LC) or (Key = TCosNames.LJ) or (Key = TCosNames.ML) then
  begin
    ApplyLineStyle(Key, State);
  end
  else if Key = TCosNames.D then
  begin
    ApplyDashPattern(State);
  end
  else if Key = TCosNames.RI then
  begin
    if State.TryGetRenderingIntent(Intent) then
    begin
      RenderState.RenderingIntent := TRenderStateOperators.IntentOf(Intent);
    end
    else
    begin
      RenderState.RenderingIntent := '';
    end;
  end
  else if Key = TCosNames.Font then
  begin
    State.CopyIntoGraphicsState(RenderState, Engine.Resources);
  end
  else if Key = TCosNames.FL then
  begin
    RenderState.Flatness := DefaultFlatness;
    if State.TryGetFlatnessTolerance(Value) then
    begin
      RenderState.Flatness := Value;
    end;
  end
  else if Key = TCosNames.SA then
  begin
    RenderState.StrokeAdjustment := State.GetAutomaticStrokeAdjustment;
  end
  else if (Key = TCosNames.CA) or (Key = TCosNames.CaNs) then
  begin
    ApplyAlpha(Key, State);
  end
  else if Key = TCosNames.AIS then
  begin
    RenderState.AlphaSource := State.GetAlphaSourceFlag;
  end
  else if Key = TCosNames.TK then
  begin
    RenderState.TextState.Knockout := State.GetTextKnockoutFlag;
  end
  else if Key = TCosNames.SMask then
  begin
    ApplySoftMask(State);
  end
  else if Key = TCosNames.BM then
  begin
    RenderState.BlendMode := TRenderStateOperators.BlendModeOf(State.GetBlendModeName);
  end
  else if (Key = TCosNames.TR) or (Key = TCosNames.TR2) then
  begin
    ApplyTransfer(Key, Dictionary, State);
  end;
end;

procedure TSetRenderGraphicsStateParametersOperator.ApplyLineStyle(const Key: string; const State: TPDExtendedGraphicsState);
begin
  const RenderState = GraphicsEngine.RenderState;
  var Value: Single;

  if Key = TCosNames.LW then
  begin
    RenderState.LineWidth := DefaultLineWidth;
    if State.TryGetLineWidth(Value) then
    begin
      RenderState.LineWidth := Value;
    end;
  end
  else if Key = TCosNames.LC then
  begin
    RenderState.LineCap := State.GetLineCapStyle;
  end
  else if Key = TCosNames.LJ then
  begin
    RenderState.LineJoin := State.GetLineJoinStyle;
  end
  else
  begin
    RenderState.MiterLimit := DefaultMiterLimit;
    if State.TryGetMiterLimit(Value) then
    begin
      RenderState.MiterLimit := Value;
    end;
  end;
end;

// PDFBox stores a null pattern here and fails later; Pdf4D keeps the pattern that was set
procedure TSetRenderGraphicsStateParametersOperator.ApplyDashPattern(const State: TPDExtendedGraphicsState);
begin
  var DashArray: TCosArray;
  var Phase: Integer;
  if State.TryGetLineDashPattern(DashArray, Phase) then
  begin
    GraphicsEngine.RenderState.DashPattern := TPDLineDashPattern.Create(DashArray, Phase);
  end
  else
  begin
    Engine.LogWarning(DashPatternInvalid, []);
  end;
end;

procedure TSetRenderGraphicsStateParametersOperator.ApplyAlpha(const Key: string; const State: TPDExtendedGraphicsState);
begin
  const RenderState = GraphicsEngine.RenderState;
  var Alpha: Single := DefaultAlpha;
  if Key = TCosNames.CA then
  begin
    if State.TryGetStrokingAlphaConstant(Alpha) then
    begin
      RenderState.AlphaConstant := Alpha;
    end
    else
    begin
      RenderState.AlphaConstant := DefaultAlpha;
    end;
  end
  else
  begin
    if State.TryGetNonStrokingAlphaConstant(Alpha) then
    begin
      RenderState.NonStrokeAlphaConstant := Alpha;
    end
    else
    begin
      RenderState.NonStrokeAlphaConstant := DefaultAlpha;
    end;
  end;
end;

// The soft mask itself is kept in the state when soft masks are drawn
procedure TSetRenderGraphicsStateParametersOperator.ApplySoftMask(const State: TPDExtendedGraphicsState);
begin
  var SoftMask: TCosBase;
  const HasSoftMask = (State.TryGetSoftMask(SoftMask) and (not ((SoftMask is TCosName) and (TCosName(SoftMask).Name = NoSoftMask))));
  if HasSoftMask then
  begin
    Engine.LogWarning(SoftMaskNotSupported, []);
  end;
end;

procedure TSetRenderGraphicsStateParametersOperator.ApplyTransfer(const Key: string; const Dictionary: TCosDictionary; const State: TPDExtendedGraphicsState);
begin
  if Key = TCosNames.TR then
  begin
    // TR2 takes precedence when both are there
    if not Dictionary.ContainsKey(TCosNames.TR2) then
    begin
      GraphicsEngine.RenderState.Transfer := State.GetTransfer;
    end;
  end
  else
  begin
    GraphicsEngine.RenderState.Transfer := State.GetTransfer2;
  end;
end;

end.
