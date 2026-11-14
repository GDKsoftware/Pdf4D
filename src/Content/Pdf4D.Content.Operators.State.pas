// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/Save.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/Restore.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/Concatenate.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/SetGraphicsStateParameters.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/SetMatrix.java (3.0.8)
unit Pdf4D.Content.Operators.State;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.Operator,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base;

type
  TSaveOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TRestoreOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TConcatenateOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TSetGraphicsStateParametersOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tm. It lives in the state package of PDFBox but works on the text matrices.
  TSetMatrixOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TStateOperators = record
    // q, Q, cm and gs. Tm is registered with the text operators.
    class procedure Register(const Engine: TPdfStreamEngine); static;
    // The matrix of six numbers that cm and Tm take. The caller has checked the operands.
    class function MatrixOf(const Operands: TArray<TCosBase>): TPdfMatrix; static;
  end;

implementation

uses
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Number,
  Pdf4D.Model.ExtendedGraphicsState;

{ TStateOperators }

class procedure TStateOperators.Register(const Engine: TPdfStreamEngine);
begin
  Engine.AddOperator(TSaveOperator.Create(Engine));
  Engine.AddOperator(TRestoreOperator.Create(Engine));
  Engine.AddOperator(TConcatenateOperator.Create(Engine));
  Engine.AddOperator(TSetGraphicsStateParametersOperator.Create(Engine));
end;

class function TStateOperators.MatrixOf(const Operands: TArray<TCosBase>): TPdfMatrix;
begin
  Result := TPdfMatrix.Create(TCosNumber(Operands[0]).FloatValue, TCosNumber(Operands[1]).FloatValue, TCosNumber(Operands[2]).FloatValue,
                              TCosNumber(Operands[3]).FloatValue, TCosNumber(Operands[4]).FloatValue, TCosNumber(Operands[5]).FloatValue);
end;

{ TSaveOperator }

function TSaveOperator.Name: string;
begin
  Result := TOperatorNames.Save;
end;

procedure TSaveOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.SaveGraphicsState;
end;

{ TRestoreOperator }

function TRestoreOperator.Name: string;
begin
  Result := TOperatorNames.Restore;
end;

procedure TRestoreOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if not Engine.CanRestoreGraphicsState then
  begin
    // This should not happen, but it does (PDFBOX-161)
    raise EPdfEmptyGraphicsStackException.Create('Cannot execute restore, the graphics stack is empty');
  end;

  Engine.RestoreGraphicsState;
end;

{ TConcatenateOperator }

function TConcatenateOperator.Name: string;
begin
  Result := TOperatorNames.Concat;
end;

procedure TConcatenateOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 6);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    Exit;
  end;

  var Ctm := Engine.GraphicsState.CurrentTransformationMatrix;
  Ctm.ConcatenateWith(TStateOperators.MatrixOf(Operands));
  Engine.GraphicsState.CurrentTransformationMatrix := Ctm;
end;

{ TSetGraphicsStateParametersOperator }

function TSetGraphicsStateParametersOperator.Name: string;
begin
  Result := TOperatorNames.SetGraphicsStateParams;
end;

procedure TSetGraphicsStateParametersOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
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
    Engine.LogError('name for ''gs'' operator not found in resources: /%s', [StateName]);
    Exit;
  end;

  const State = TPDExtendedGraphicsState.Create(Dictionary);
  try
    State.CopyIntoGraphicsState(Engine.GraphicsState, Engine.Resources);
  finally
    State.Free;
  end;
end;

{ TSetMatrixOperator }

function TSetMatrixOperator.Name: string;
begin
  Result := TOperatorNames.SetMatrix;
end;

procedure TSetMatrixOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 6);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    Exit;
  end;

  const Matrix = TStateOperators.MatrixOf(Operands);
  Engine.SetTextMatrix(Matrix);
  Engine.SetTextLineMatrix(Matrix);
end;

end.
