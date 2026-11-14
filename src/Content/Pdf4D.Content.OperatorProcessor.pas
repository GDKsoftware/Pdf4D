// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/OperatorProcessor.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/MissingOperandException.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/state/EmptyGraphicsStackException.java (3.0.8)
unit Pdf4D.Content.OperatorProcessor;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Content.Operator,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base;

type
  EPdfMissingOperandException = class(EPdfParseException);
  EPdfEmptyGraphicsStackException = class(EPdfParseException);

  // The base of the processors of one operator. A processor does not own the engine.
  TOperatorProcessor = class abstract(TOperatorProcessorBase)
  private
    FEngine: TPdfStreamEngine;

  protected
    // Raises EPdfMissingOperandException when there are fewer than Count operands
    procedure RequireOperands(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Count: Integer);

    property Engine: TPdfStreamEngine read FEngine;

  public
    constructor Create(const Engine: TPdfStreamEngine);

    // Whether every operand is an instance of ClassType (true without operands), as checkArrayTypesClass
    class function CheckArrayTypes(const Operands: TArray<TCosBase>; const ClassType: TClass): Boolean;
  end;

implementation

{ TOperatorProcessor }

constructor TOperatorProcessor.Create(const Engine: TPdfStreamEngine);
begin
  if not Assigned(Engine) then
  begin
    raise EArgumentNilException.Create('Engine');
  end;

  inherited Create;
  FEngine := Engine;
end;

class function TOperatorProcessor.CheckArrayTypes(const Operands: TArray<TCosBase>; const ClassType: TClass): Boolean;
begin
  for var Operand in Operands do
  begin
    if not Operand.InheritsFrom(ClassType) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TOperatorProcessor.RequireOperands(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Count: Integer);
begin
  if Length(Operands) < Count then
  begin
    raise EPdfMissingOperandException.CreateFmt('Operator %s has too few operands: %d of %d', [Operator.Name, Length(Operands), Count]);
  end;
end;

end.
