// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: the object resolving part of pdfbox/src/main/java/org/apache/pdfbox/cos/ICOSParser.java (3.0.8)
unit Pdf4D.Cos.Resolver.Interfaces;

interface

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.ObjectKey;

type
  ICosObjectResolver = interface
    ['{6D0C2B0E-3C55-4A39-9A63-5E1B7F4D2A10}']
    // Loads the object. The caller (a TCosObject) takes ownership of the result. A failed load gives a TCosNull, like PDFBox.
    function ResolveObject(const Key: TCosObjectKey): TCosBase;
  end;

  // Base class for implementors: the object is owned by hand and never by reference counting, so the
  // interface references that other objects hold must not free it.
  TCosObjectResolverBase = class(TObject, ICosObjectResolver)
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;

  public
    function ResolveObject(const Key: TCosObjectKey): TCosBase; virtual; abstract;
  end;

implementation

{ TCosObjectResolverBase }

function TCosObjectResolverBase.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
  begin
    Result := 0;
  end
  else
  begin
    Result := HResult($80004002);
  end;
end;

function TCosObjectResolverBase._AddRef: Integer;
begin
  Result := -1;
end;

function TCosObjectResolverBase._Release: Integer;
begin
  Result := -1;
end;

end.
