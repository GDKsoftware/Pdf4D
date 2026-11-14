// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/DrawObject.java (3.0.8)
unit Pdf4D.Content.Operators.DrawObject;

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base,
  Pdf4D.Model.FormXObject;

type
  // Do for text extraction: images are skipped and forms are run
  TDrawObjectOperator = class(TOperatorProcessor)
  private
    procedure DrawForm(const Form: TPDFormXObject);

  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TDrawObjectOperators = record
    class procedure Register(const Engine: TPdfStreamEngine); static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names;

{ TDrawObjectOperators }

class procedure TDrawObjectOperators.Register(const Engine: TPdfStreamEngine);
begin
  Engine.AddOperator(TDrawObjectOperator.Create(Engine));
end;

{ TDrawObjectOperator }

function TDrawObjectOperator.Name: string;
begin
  Result := TOperatorNames.DrawObject;
end;

procedure TDrawObjectOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, 1);
  if not (Operands[0] is TCosName) then
  begin
    Exit;
  end;

  const XObjectName = TCosName(Operands[0]).Name;
  // Images are not decoded for text extraction
  if Engine.Resources.IsImageXObject(XObjectName) then
  begin
    Exit;
  end;

  var Stream: TCosStream;
  if not Engine.Resources.TryGetXObject(XObjectName, Stream) then
  begin
    Engine.LogError('Missing XObject: %s', [XObjectName]);
    Exit;
  end;

  const Subtype = Stream.GetNameAsString(TCosNames.Subtype, '');
  if Subtype <> TCosNames.Form then
  begin
    raise EPdfParseException.CreateFmt('Invalid XObject Subtype: %s', [Subtype]);
  end;

  const Form = TPDFormXObject.Create(Stream);
  try
    DrawForm(Form);
  finally
    Form.Free;
  end;
end;

procedure TDrawObjectOperator.DrawForm(const Form: TPDFormXObject);
begin
  Engine.IncreaseLevel;
  try
    if Engine.Level > Engine.Options.MaxFormXObjectDepth then
    begin
      Engine.LogError('recursion is too deep, skipping form XObject', []);
      Exit;
    end;

    if Form.IsTransparencyGroup then
    begin
      Engine.ShowTransparencyGroup(Form);
    end
    else
    begin
      Engine.ShowForm(Form);
    end;
  finally
    Engine.DecreaseLevel;
  end;
end;

end.
