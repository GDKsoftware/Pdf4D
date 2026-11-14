// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Attachment;

interface

uses
  System.SysUtils,
  Pdf4D.Api.Attachment.Interfaces,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Model.EmbeddedFile;

type
  TPdfAttachment = class(TInterfacedObject, IPdfAttachment)
  private
    FHandle: IPdfDocumentHandle;
    FFile: TPDEmbeddedFile;

  public
    constructor Create(const Handle: IPdfDocumentHandle; const EmbeddedFile: TPDEmbeddedFile);

    // The files of a list of the model as API objects
    class function Wrap(const Handle: IPdfDocumentHandle; const Files: TArray<TPDEmbeddedFile>): TArray<IPdfAttachment>; static;

    function FileName: string;
    function Description: string;
    function TryGetSize(out Size: Int64): Boolean;
    function Data: TBytes;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TPdfAttachment }

constructor TPdfAttachment.Create(const Handle: IPdfDocumentHandle; const EmbeddedFile: TPDEmbeddedFile);
begin
  inherited Create;
  FHandle := Handle;
  FFile := EmbeddedFile;
end;

class function TPdfAttachment.Wrap(const Handle: IPdfDocumentHandle; const Files: TArray<TPDEmbeddedFile>): TArray<IPdfAttachment>;
begin
  SetLength(Result, Length(Files));
  for var Position := 0 to High(Files) do
  begin
    Result[Position] := TPdfAttachment.Create(Handle, Files[Position]);
  end;
end;

function TPdfAttachment.FileName: string;
begin
  Result := FFile.FileName;
end;

function TPdfAttachment.Description: string;
begin
  Result := FFile.Description;
end;

function TPdfAttachment.TryGetSize(out Size: Int64): Boolean;
begin
  var Stated: Integer;
  Result := FFile.TryGetSize(Stated);
  if Result then
  begin
    Size := Stated;
  end;
end;

function TPdfAttachment.Data: TBytes;
begin
  try
    Result := FFile.GetData;
  except
    on Failure: EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      if not TPdfFailure.IsInputFailure(Failure) then
      begin
        raise;
      end;
      raise EPdfParseException.CreateFmt('The attachment "%s" cannot be read: %s', [FFile.Key, Failure.Message]);
    end;
  end;
end;

end.
