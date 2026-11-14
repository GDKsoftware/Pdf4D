// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/form/PDFormXObject.java (3.0.8), the read side
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/form/PDTransparencyGroup.java (3.0.8), as IsTransparencyGroup
unit Pdf4D.Model.FormXObject;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Rectangle;

type
  // A view on a Form XObject stream. It owns nothing; the stream belongs to the document.
  TPDFormXObject = class
  private
    FStream: TCosStream;

  public
    constructor Create(const Stream: TCosStream);

    // The identity when /Matrix is missing or no array of six numbers
    function Matrix: TPdfMatrix;
    function TryGetBBox(out BBox: TPdfRectangle): Boolean;
    // False when there is no /Resources dictionary. See HasEmptyResources for the entry that is no dictionary.
    function TryGetResources(out Resources: TCosDictionary): Boolean;
    // PDFBOX-4372: a /Resources entry that exists but is no dictionary counts as empty resources, not as missing ones
    // (a missing entry makes the engine use the resources of the page). This keeps a form with "/Fm0 Do" from drawing itself.
    function HasEmptyResources: Boolean;
    // /Group << /S /Transparency >>
    function IsTransparencyGroup: Boolean;

    property Stream: TCosStream read FStream;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray;

{ TPDFormXObject }

constructor TPDFormXObject.Create(const Stream: TCosStream);
begin
  if not Assigned(Stream) then
  begin
    raise EArgumentNilException.Create('Stream');
  end;

  inherited Create;
  FStream := Stream;
end;

function TPDFormXObject.Matrix: TPdfMatrix;
begin
  var Value: TCosBase;
  if FStream.TryGetDictionaryObject(TCosNames.Matrix, Value) and (Value is TCosArray) then
  begin
    Result := TPdfMatrix.FromCosArray(TCosArray(Value));
  end
  else
  begin
    Result := TPdfMatrix.Identity;
  end;
end;

function TPDFormXObject.TryGetBBox(out BBox: TPdfRectangle): Boolean;
begin
  var Values: TCosArray;
  Result := FStream.TryGetCosArray(TCosNames.BBox, Values);
  if Result then
  begin
    BBox := TPdfRectangle.FromCosArray(Values);
  end
  else
  begin
    BBox := Default(TPdfRectangle);
  end;
end;

function TPDFormXObject.TryGetResources(out Resources: TCosDictionary): Boolean;
begin
  Result := FStream.TryGetCosDictionary(TCosNames.Resources, Resources);
  if not Result then
  begin
    Resources := nil;
  end;
end;

function TPDFormXObject.HasEmptyResources: Boolean;
begin
  var Resources: TCosDictionary;
  Result := (FStream.ContainsKey(TCosNames.Resources) and not TryGetResources(Resources));
end;

function TPDFormXObject.IsTransparencyGroup: Boolean;
begin
  var Group: TCosDictionary;
  Result := (FStream.TryGetCosDictionary(TCosNames.Group, Group) and (Group.GetNameAsString(TCosNames.S, '') = TCosNames.Transparency));
end;

end.
