// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDResources.java (3.0.8), the read side that text extraction uses
unit Pdf4D.Model.Resources;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Model.DocumentContext;

type
  // A view on a resource dictionary of a page or a form. It owns nothing: the dictionary belongs to the document, and
  // the fonts belong to the document context, which caches them on the identity of their font dictionary (the
  // ResourceCache of PDFBox, for direct and indirect fonts alike).
  TPDResources = class
  private
    FDictionary: TCosDictionary;
    FContext: TPDDocumentContext;

    function TryGetResource(const Category, Name: string; out Value: TCosBase): Boolean;
    function TryCreateFont(const Name: string; const FontDictionary: TCosDictionary; out Font: TPDFont): Boolean;
    procedure LogWarning(const Fmt: string; const Args: array of const);

  public
    // Dictionary is not owned and may be nil: such resources are empty. Context is required and is not owned.
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);

    // PDResources.getFont. False when there is no such font entry or it is no dictionary. A font that cannot be made is
    // logged once and gives False, like the null of PDFBox; the context remembers that failure.
    function TryGetFont(const Name: string; out Font: TPDFont): Boolean;
    // PDResources.getXObject without the wrapper: the stream of the entry. An entry that is no stream is logged and gives
    // False. The caller looks at /Subtype.
    function TryGetXObject(const Name: string; out XObject: TCosStream): Boolean;
    function IsImageXObject(const Name: string): Boolean;
    function TryGetExtGState(const Name: string; out State: TCosDictionary): Boolean;
    function TryGetProperties(const Name: string; out Properties: TCosDictionary): Boolean;
    // The entry of /ColorSpace as it is in the file, resolved but not made into a colour space (that is the factory of the
    // renderer, which is not part of the core). PDResources.hasColorSpace is the same question.
    function TryGetColorSpace(const Name: string; out Value: TCosBase): Boolean;

    property CosObject: TCosDictionary read FDictionary;
    property Context: TPDDocumentContext read FContext;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Font.Factory;

{ TPDResources }

constructor TPDResources.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  if not Assigned(Context) then
  begin
    raise EArgumentNilException.Create('Context');
  end;

  inherited Create;
  FDictionary := Dictionary;
  FContext := Context;
end;

procedure TPDResources.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FContext.Log) then
  begin
    FContext.Log.Warning(Fmt, Args);
  end;
end;

function TPDResources.TryGetResource(const Category, Name: string; out Value: TCosBase): Boolean;
begin
  Value := nil;
  var Entries: TCosDictionary;
  Result := (Assigned(FDictionary) and FDictionary.TryGetCosDictionary(Category, Entries) and Entries.TryGetDictionaryObject(Name, Value));
end;

function TPDResources.TryCreateFont(const Name: string; const FontDictionary: TCosDictionary; out Font: TPDFont): Boolean;
begin
  Font := nil;
  try
    Font := TPDFontFactory.GetFont(FontDictionary, FContext);
    Result := True;
  except
    on Error: Exception do
    begin
      const IsRecoverable = ((Error is EPdfException) or TPdfFailure.IsInputFailure(Error));
      if not IsRecoverable then
      begin
        raise;
      end;
      if Assigned(FContext.Log) then
      begin
        FContext.Log.Error('Could not read font ''%s'': %s', [Name, Error.Message]);
      end;
      Result := False;
    end;
  end;
end;

function TPDResources.TryGetFont(const Name: string; out Font: TPDFont): Boolean;
begin
  Font := nil;
  var Value: TCosBase;
  const IsFontDictionary = (TryGetResource(TCosNames.Font, Name, Value) and (Value is TCosDictionary));
  if not IsFontDictionary then
  begin
    Exit(False);
  end;

  if TPDFontFactory.HasFailed(TCosDictionary(Value), FContext) then
  begin
    Exit(False);
  end;

  Result := TryCreateFont(Name, TCosDictionary(Value), Font);
end;

function TPDResources.TryGetXObject(const Name: string; out XObject: TCosStream): Boolean;
begin
  XObject := nil;
  var Value: TCosBase;
  if not TryGetResource(TCosNames.XObject, Name, Value) then
  begin
    Exit(False);
  end;

  Result := (Value is TCosStream);
  if Result then
  begin
    XObject := TCosStream(Value);
  end
  else
  begin
    LogWarning('XObject ''%s'' is not a stream and is skipped', [Name]);
  end;
end;

function TPDResources.IsImageXObject(const Name: string): Boolean;
begin
  var Value: TCosBase;
  Result := (TryGetResource(TCosNames.XObject, Name, Value) and (Value is TCosStream));
  if Result then
  begin
    Result := (TCosStream(Value).GetNameAsString(TCosNames.Subtype, '') = TCosNames.Image);
  end;
end;

function TPDResources.TryGetExtGState(const Name: string; out State: TCosDictionary): Boolean;
begin
  State := nil;
  var Value: TCosBase;
  Result := (TryGetResource(TCosNames.ExtGState, Name, Value) and (Value is TCosDictionary));
  if Result then
  begin
    State := TCosDictionary(Value);
  end;
end;

function TPDResources.TryGetColorSpace(const Name: string; out Value: TCosBase): Boolean;
begin
  Result := TryGetResource(TCosNames.ColorSpace, Name, Value);
end;

function TPDResources.TryGetProperties(const Name: string; out Properties: TCosDictionary): Boolean;
begin
  Properties := nil;
  var Value: TCosBase;
  Result := (TryGetResource(TCosNames.Properties, Name, Value) and (Value is TCosDictionary));
  if Result then
  begin
    Properties := TCosDictionary(Value);
  end;
end;

end.
