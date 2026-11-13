// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.DocumentHandle;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Log,
  Pdf4D.Model.Document;

type
  // What every API object holds to keep the document alive. The handle never holds an API object, so there is no cycle.
  IPdfDocumentHandle = interface
    ['{9B4E1C63-D2A8-4075-A6F1-0C5D8B37E9A2}']

    function Document: TPDDocument;
    function Log: TPdfLog;
    function PageLabel(const Index: Integer): string;
  end;

  // Owns the document and, when the document was loaded from a file, the stream
  TPdfDocumentHandle = class(TInterfacedObject, IPdfDocumentHandle)
  private
    FDocument: TPDDocument;
    FOwnedStream: TStream;
    FLabels: TArray<string>;
    FAreLabelsBuilt: Boolean;

    procedure BuildLabels;
    function ReadLabels: TArray<string>;

  public
    // OwnedStream may be nil. Both are freed with the handle, the document first.
    constructor Create(const Document: TPDDocument; const OwnedStream: TStream);
    destructor Destroy; override;

    function Document: TPDDocument;
    function Log: TPdfLog;
    function PageLabel(const Index: Integer): string;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.PageLabels;

{ TPdfDocumentHandle }

constructor TPdfDocumentHandle.Create(const Document: TPDDocument; const OwnedStream: TStream);
begin
  inherited Create;
  FDocument := Document;
  FOwnedStream := OwnedStream;
end;

destructor TPdfDocumentHandle.Destroy;
begin
  FDocument.Free;
  FOwnedStream.Free;
  inherited;
end;

function TPdfDocumentHandle.Document: TPDDocument;
begin
  Result := FDocument;
end;

function TPdfDocumentHandle.Log: TPdfLog;
begin
  Result := FDocument.CosDocument.Log;
end;

function TPdfDocumentHandle.PageLabel(const Index: Integer): string;
begin
  BuildLabels;

  const IsKnown = ((Index >= 0) and (Index < Length(FLabels)));
  if IsKnown then
  begin
    Result := FLabels[Index];
  end
  else
  begin
    Result := '';
  end;
end;

procedure TPdfDocumentHandle.BuildLabels;
begin
  if not FAreLabelsBuilt then
  begin
    FLabels := ReadLabels;
    FAreLabelsBuilt := True;
  end;
end;

// A document whose labels cannot be made still has pages: the labels are empty and the problem goes to the log
function TPdfDocumentHandle.ReadLabels: TArray<string>;
begin
  Result := nil;

  var Dictionary: TCosDictionary;
  if not FDocument.Catalog.TryGetPageLabels(Dictionary) then
  begin
    Exit;
  end;

  try
    const PageLabels = TPDPageLabels.Create(FDocument, Dictionary);
    try
      Result := PageLabels.GetLabelsByPageIndices;
    finally
      PageLabels.Free;
    end;
  except
    on Failure: EPdfException do
    begin
      Log.Error('The page labels cannot be made: %s', [Failure.Message]);
      Result := nil;
    end;
  end;
end;

end.
