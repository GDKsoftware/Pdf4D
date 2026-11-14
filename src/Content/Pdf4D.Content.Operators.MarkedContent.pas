// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/markedcontent/BeginMarkedContentSequence.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/markedcontent/BeginMarkedContentSequenceWithProperties.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/markedcontent/EndMarkedContentSequence.java (3.0.8)
unit Pdf4D.Content.Operators.MarkedContent;

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base;

type
  // BMC
  TBeginMarkedContentSequenceOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // BDC
  TBeginMarkedContentSequenceWithPropertiesOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // EMC
  TEndMarkedContentSequenceOperator = class(TOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TMarkedContentOperators = record
    // Only the text stripper registers these
    class procedure Register(const Engine: TPdfStreamEngine); static;
  end;

implementation

uses
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name;

{ TMarkedContentOperators }

class procedure TMarkedContentOperators.Register(const Engine: TPdfStreamEngine);
begin
  Engine.AddOperator(TBeginMarkedContentSequenceOperator.Create(Engine));
  Engine.AddOperator(TBeginMarkedContentSequenceWithPropertiesOperator.Create(Engine));
  Engine.AddOperator(TEndMarkedContentSequenceOperator.Create(Engine));
end;

{ TBeginMarkedContentSequenceOperator }

function TBeginMarkedContentSequenceOperator.Name: string;
begin
  Result := TOperatorNames.BeginMarkedContent;
end;

procedure TBeginMarkedContentSequenceOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  var Tag := '';
  for var Operand in Operands do
  begin
    if Operand is TCosName then
    begin
      Tag := TCosName(Operand).Name;
    end;
  end;
  Engine.BeginMarkedContentSequence(Tag, nil);
end;

{ TBeginMarkedContentSequenceWithPropertiesOperator }

function TBeginMarkedContentSequenceWithPropertiesOperator.Name: string;
begin
  Result := TOperatorNames.BeginMarkedContentSeq;
end;

procedure TBeginMarkedContentSequenceWithPropertiesOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 2);
  if not (Operands[0] is TCosName) then
  begin
    Exit;
  end;

  var Properties: TCosDictionary := nil;
  if Operands[1] is TCosName then
  begin
    // PDFBOX-5980: the properties are a name in the resources
    if not Engine.Resources.TryGetProperties(TCosName(Operands[1]).Name, Properties) then
    begin
      Properties := nil;
    end;
  end
  else if Operands[1] is TCosDictionary then
  begin
    Properties := TCosDictionary(Operands[1]);
  end;

  if Assigned(Properties) then
  begin
    Engine.BeginMarkedContentSequence(TCosName(Operands[0]).Name, Properties);
  end;
end;

{ TEndMarkedContentSequenceOperator }

function TEndMarkedContentSequenceOperator.Name: string;
begin
  Result := TOperatorNames.EndMarkedContent;
end;

procedure TEndMarkedContentSequenceOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.EndMarkedContentSequence;
end;

end.
