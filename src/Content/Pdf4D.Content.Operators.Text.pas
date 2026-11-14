// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/text/*.java (3.0.8)
unit Pdf4D.Content.Operators.Text;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base;

type
  TBeginTextOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TEndTextOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Td
  TMoveTextOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // TD
  TMoveTextSetLeadingOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // T*
  TNextLineOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tc
  TSetCharSpacingOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tf
  TSetFontAndSizeOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tz
  TSetTextHorizontalScalingOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // TL
  TSetTextLeadingOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tr
  TSetTextRenderingModeOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Ts
  TSetTextRiseOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tw
  TSetWordSpacingOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Tj
  TShowTextOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // TJ
  TShowTextAdjustedOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // '
  TShowTextLineOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // "
  TShowTextLineAndSpaceOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TTextOperators = record
    // The sixteen text operators and Tm
    class procedure Register(const Engine: TPdfStreamEngine); static;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Content.Operators.State,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString,
  Pdf4D.Font.Base;

{ TTextOperators }

class procedure TTextOperators.Register(const Engine: TPdfStreamEngine);
begin
  Engine.AddOperator(TBeginTextOperator.Create(Engine));
  Engine.AddOperator(TEndTextOperator.Create(Engine));
  Engine.AddOperator(TMoveTextOperator.Create(Engine));
  Engine.AddOperator(TMoveTextSetLeadingOperator.Create(Engine));
  Engine.AddOperator(TNextLineOperator.Create(Engine));
  Engine.AddOperator(TSetMatrixOperator.Create(Engine));
  Engine.AddOperator(TSetCharSpacingOperator.Create(Engine));
  Engine.AddOperator(TSetFontAndSizeOperator.Create(Engine));
  Engine.AddOperator(TSetTextHorizontalScalingOperator.Create(Engine));
  Engine.AddOperator(TSetTextLeadingOperator.Create(Engine));
  Engine.AddOperator(TSetTextRenderingModeOperator.Create(Engine));
  Engine.AddOperator(TSetTextRiseOperator.Create(Engine));
  Engine.AddOperator(TSetWordSpacingOperator.Create(Engine));
  Engine.AddOperator(TShowTextOperator.Create(Engine));
  Engine.AddOperator(TShowTextAdjustedOperator.Create(Engine));
  Engine.AddOperator(TShowTextLineOperator.Create(Engine));
  Engine.AddOperator(TShowTextLineAndSpaceOperator.Create(Engine));
end;

{ TBeginTextOperator }

function TBeginTextOperator.Name: string;
begin
  Result := TOperatorNames.BeginText;
end;

procedure TBeginTextOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.SetTextMatrix(TPdfMatrix.Identity);
  Engine.SetTextLineMatrix(TPdfMatrix.Identity);
  Engine.BeginText;
end;

{ TEndTextOperator }

function TEndTextOperator.Name: string;
begin
  Result := TOperatorNames.EndText;
end;

procedure TEndTextOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.ClearTextMatrix;
  Engine.ClearTextLineMatrix;
  Engine.EndText;
end;

{ TMoveTextOperator }

function TMoveTextOperator.Name: string;
begin
  Result := TOperatorNames.MoveText;
end;

procedure TMoveTextOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 2);
  var LineMatrix: TPdfMatrix;
  if not Engine.TryGetTextLineMatrix(LineMatrix) then
  begin
    Engine.LogWarning('TextLineMatrix is null, %s operator will be ignored', [Name]);
    Exit;
  end;

  if not ((Operands[0] is TCosNumber) and (Operands[1] is TCosNumber)) then
  begin
    Exit;
  end;

  LineMatrix.ConcatenateWith(TPdfMatrix.Create(1, 0, 0, 1, TCosNumber(Operands[0]).FloatValue, TCosNumber(Operands[1]).FloatValue));
  Engine.SetTextLineMatrix(LineMatrix);
  Engine.SetTextMatrix(LineMatrix);
end;

{ TMoveTextSetLeadingOperator }

function TMoveTextSetLeadingOperator.Name: string;
begin
  Result := TOperatorNames.MoveTextSetLeading;
end;

procedure TMoveTextSetLeadingOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 2);
  if not (Operands[1] is TCosNumber) then
  begin
    Exit;
  end;

  const Leading = TCosFloat.Create(-TCosNumber(Operands[1]).FloatValue);
  try
    Engine.ProcessOperator(TOperatorNames.SetTextLeading, TArray<TCosBase>.Create(Leading));
  finally
    Leading.Free;
  end;
  Engine.ProcessOperator(TOperatorNames.MoveText, Operands);
end;

{ TNextLineOperator }

function TNextLineOperator.Name: string;
begin
  Result := TOperatorNames.NextLine;
end;

procedure TNextLineOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  // It is -leading and not leading as the specification has it; Acrobat does the same
  const Zero = TCosFloat.Create(0);
  try
    const Offset = TCosFloat.Create(-Engine.GraphicsState.TextState.Leading);
    try
      Engine.ProcessOperator(TOperatorNames.MoveText, TArray<TCosBase>.Create(Zero, Offset));
    finally
      Offset.Free;
    end;
  finally
    Zero.Free;
  end;
end;

{ TSetCharSpacingOperator }

function TSetCharSpacingOperator.Name: string;
begin
  Result := TOperatorNames.SetCharSpacing;
end;

procedure TSetCharSpacingOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  // Some documents give a wrong number of operands: the last one counts
  const Value = Operands[High(Operands)];
  if Value is TCosNumber then
  begin
    Engine.GraphicsState.TextState.CharacterSpacing := TCosNumber(Value).FloatValue;
  end;
end;

{ TSetFontAndSizeOperator }

function TSetFontAndSizeOperator.Name: string;
begin
  Result := TOperatorNames.SetFontAndSize;
end;

procedure TSetFontAndSizeOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 2);
  if not ((Operands[0] is TCosName) and (Operands[1] is TCosNumber)) then
  begin
    Exit;
  end;

  const FontName = TCosName(Operands[0]).Name;
  Engine.GraphicsState.TextState.FontSize := TCosNumber(Operands[1]).FloatValue;
  // The font comes after the size, so that a failure leaves the default font to showText
  var Font: TPDFont;
  if not Engine.Resources.TryGetFont(FontName, Font) then
  begin
    Engine.LogWarning('font ''%s'' not found in resources', [FontName]);
    Font := nil;
  end;
  Engine.GraphicsState.TextState.Font := Font;
end;

{ TSetTextHorizontalScalingOperator }

function TSetTextHorizontalScalingOperator.Name: string;
begin
  Result := TOperatorNames.SetTextHorizontalScaling;
end;

procedure TSetTextHorizontalScalingOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if Operands[0] is TCosNumber then
  begin
    Engine.GraphicsState.TextState.HorizontalScaling := TCosNumber(Operands[0]).FloatValue;
  end;
end;

{ TSetTextLeadingOperator }

function TSetTextLeadingOperator.Name: string;
begin
  Result := TOperatorNames.SetTextLeading;
end;

procedure TSetTextLeadingOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if Operands[0] is TCosNumber then
  begin
    Engine.GraphicsState.TextState.Leading := TCosNumber(Operands[0]).FloatValue;
  end;
end;

{ TSetTextRenderingModeOperator }

function TSetTextRenderingModeOperator.Name: string;
begin
  Result := TOperatorNames.SetTextRenderingMode;
end;

procedure TSetTextRenderingModeOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if not (Operands[0] is TCosNumber) then
  begin
    Exit;
  end;

  var Mode: TRenderingMode;
  if TRenderingMode.TryFromInt(TCosNumber(Operands[0]).IntValue, Mode) then
  begin
    Engine.GraphicsState.TextState.RenderingMode := Mode;
  end;
end;

{ TSetTextRiseOperator }

function TSetTextRiseOperator.Name: string;
begin
  Result := TOperatorNames.SetTextRise;
end;

procedure TSetTextRiseOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if (Length(Operands) > 0) and (Operands[0] is TCosNumber) then
  begin
    Engine.GraphicsState.TextState.Rise := TCosNumber(Operands[0]).FloatValue;
  end;
end;

{ TSetWordSpacingOperator }

function TSetWordSpacingOperator.Name: string;
begin
  Result := TOperatorNames.SetWordSpacing;
end;

procedure TSetWordSpacingOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if (Length(Operands) > 0) and (Operands[0] is TCosNumber) then
  begin
    Engine.GraphicsState.TextState.WordSpacing := TCosNumber(Operands[0]).FloatValue;
  end;
end;

{ TShowTextOperator }

function TShowTextOperator.Name: string;
begin
  Result := TOperatorNames.ShowText;
end;

procedure TShowTextOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if Length(Operands) = 0 then
  begin
    // PDFBox ignores ( )Tj and a Tj without a string alike, without a word
    Engine.LogWarning('Operator %s has no operands and is ignored', [Name]);
    Exit;
  end;

  var Matrix: TPdfMatrix;
  if (Operands[0] is TCosString) and Engine.TryGetTextMatrix(Matrix) then
  begin
    Engine.ShowTextString(TCosString(Operands[0]).Bytes);
  end;
end;

{ TShowTextAdjustedOperator }

function TShowTextAdjustedOperator.Name: string;
begin
  Result := TOperatorNames.ShowTextAdjusted;
end;

procedure TShowTextAdjustedOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if Length(Operands) = 0 then
  begin
    Engine.LogWarning('Operator %s has no operands and is ignored', [Name]);
    Exit;
  end;

  var Matrix: TPdfMatrix;
  if (Operands[0] is TCosArray) and Engine.TryGetTextMatrix(Matrix) then
  begin
    Engine.ShowTextStrings(TCosArray(Operands[0]));
  end;
end;

{ TShowTextLineOperator }

function TShowTextLineOperator.Name: string;
begin
  Result := TOperatorNames.ShowTextLine;
end;

procedure TShowTextLineOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.ProcessOperator(TOperatorNames.NextLine, nil);
  Engine.ProcessOperator(TOperatorNames.ShowText, Operands);
end;

{ TShowTextLineAndSpaceOperator }

function TShowTextLineAndSpaceOperator.Name: string;
begin
  Result := TOperatorNames.ShowTextLineAndSpace;
end;

procedure TShowTextLineAndSpaceOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 3);
  Engine.ProcessOperator(TOperatorNames.SetWordSpacing, Copy(Operands, 0, 1));
  Engine.ProcessOperator(TOperatorNames.SetCharSpacing, Copy(Operands, 1, 1));
  Engine.ProcessOperator(TOperatorNames.ShowTextLine, Copy(Operands, 2, 1));
end;

end.
