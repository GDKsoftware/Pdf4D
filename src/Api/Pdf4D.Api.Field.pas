// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Api.Field;

interface

uses
  System.SysUtils,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Api.Field.Interfaces,
  Pdf4D.Model.Field;

type
  TPdfField = class(TInterfacedObject, IPdfField)
  private
    FHandle: IPdfDocumentHandle;
    FField: TPDField;

    procedure LogFailure(const What: string; const Failure: Exception);

  public
    constructor Create(const Handle: IPdfDocumentHandle; const Field: TPDField);

    // The fields of a list of the model as API objects
    class function Wrap(const Handle: IPdfDocumentHandle; const Fields: TArray<TPDField>): TArray<IPdfField>; static;

    function Kind: TPdfFieldKind;
    function Name: string;
    function FullyQualifiedName: string;
    function Value: string;
    function Values: TArray<string>;
    function Children: TArray<IPdfField>;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TPdfField }

constructor TPdfField.Create(const Handle: IPdfDocumentHandle; const Field: TPDField);
begin
  inherited Create;
  FHandle := Handle;
  FField := Field;
end;

class function TPdfField.Wrap(const Handle: IPdfDocumentHandle; const Fields: TArray<TPDField>): TArray<IPdfField>;
begin
  SetLength(Result, Length(Fields));
  for var Position := 0 to High(Fields) do
  begin
    Result[Position] := TPdfField.Create(Handle, Fields[Position]);
  end;
end;

procedure TPdfField.LogFailure(const What: string; const Failure: Exception);
begin
  FHandle.Log.Error('Field "%s": %s cannot be read: %s', [FField.FullyQualifiedName, What, Failure.Message]);
end;

function TPdfField.Kind: TPdfFieldKind;
begin
  Result := FField.Kind;
end;

function TPdfField.Name: string;
begin
  Result := FField.PartialName;
end;

function TPdfField.FullyQualifiedName: string;
begin
  Result := FField.FullyQualifiedName;
end;

function TPdfField.Value: string;
begin
  try
    Result := FField.ValueAsString;
  except
    on Failure: EPdfException do
    begin
      LogFailure('the value', Failure);
      Result := '';
    end;
  end;
end;

function TPdfField.Values: TArray<string>;
begin
  try
    Result := FField.Values;
  except
    on Failure: EPdfException do
    begin
      LogFailure('the values', Failure);
      Result := nil;
    end;
  end;
end;

function TPdfField.Children: TArray<IPdfField>;
begin
  try
    Result := Wrap(FHandle, FField.Children);
  except
    on Failure: EPdfException do
    begin
      LogFailure('the children', Failure);
      Result := nil;
    end;
  end;
end;

end.
