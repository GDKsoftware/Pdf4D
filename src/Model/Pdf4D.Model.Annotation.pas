// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/annotation/PDAnnotation.java (3.0.8), the read side: createAnnotation
// (as IsKnownType), getRectangle, the flags, getOptionalContent and getNormalAppearanceStream
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/annotation/PDAppearanceDictionary.java (3.0.8), getNormalAppearance
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/annotation/PDAppearanceEntry.java (3.0.8), isSubDictionary and getSubDictionary
unit Pdf4D.Model.Annotation;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Rectangle;

type
  // A view on the dictionary of an annotation; it owns nothing, the dictionary belongs to the document. Only the read side of
  // PDAnnotation is ported: PDFBox makes appearances for some annotations without /AP (constructAppearances), this does not.
  TPDAnnotation = class
  private
    const FlagInvisible = 1;
    const FlagHidden = 2;
    const FlagPrinted = 4;
    const FlagNoRotate = 16;
    const FlagNoView = 32;

  private
    FDictionary: TCosDictionary;

    function HasFlag(const Flag: Integer): Boolean;
    function TryGetNormalAppearanceEntry(out Entry: TCosDictionary): Boolean;

  public
    // The annotation does not own Dictionary
    constructor Create(const Dictionary: TCosDictionary);

    // The name in /Subtype, empty when there is none
    function SubType: string;
    // PDAnnotation.getRectangle has no counterpart for a missing or invalid /Rect (it gives null): HasRect says whether there is one,
    // Rect gives an empty rectangle without it
    function HasRect: Boolean;
    function Rect: TPdfRectangle;
    // The entry /F, 0 when it is no number
    function Flags: Integer;
    function IsHidden: Boolean;
    function IsPrinted: Boolean;
    function IsNoView: Boolean;
    function IsNoRotate: Boolean;
    function IsInvisible: Boolean;
    // False for the subtypes that PDFBox makes a PDAnnotationUnknown of: a subtype that is missing or not one of the 19 it knows
    function IsKnownType: Boolean;
    // The stream of /AP /N, or the entry of that subdictionary that /AS names. False without /AP /N, without a state (PDFBox looks up
    // null then), and when the entry is no stream.
    function TryGetNormalAppearance(out Appearance: TCosStream): Boolean;
    // /OC when it is a dictionary
    function TryGetOptionalContent(out Value: TCosDictionary): Boolean;

    property CosObject: TCosDictionary read FDictionary;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray;

const
  KnownSubTypes: array[0..18] of string = ('FileAttachment', 'Line', 'Link', 'Popup', 'Stamp', 'Square', 'Circle', 'Polygon', 'PolyLine', 'Ink', 'Text',
                                           'Highlight', 'Underline', 'StrikeOut', 'Squiggly', 'Widget', 'FreeText', 'Caret', 'Sound');
  RectangleValueCount = 4;

{ TPDAnnotation }

constructor TPDAnnotation.Create(const Dictionary: TCosDictionary);
begin
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('Dictionary');
  end;

  inherited Create;
  FDictionary := Dictionary;
end;

function TPDAnnotation.SubType: string;
begin
  Result := FDictionary.GetNameAsString(TCosNames.Subtype, '');
end;

function TPDAnnotation.HasRect: Boolean;
begin
  var Values: TCosArray;
  Result := (FDictionary.TryGetCosArray(TCosNames.Rect, Values) and (Values.Count = RectangleValueCount));
  for var Index := 0 to RectangleValueCount - 1 do
  begin
    Result := (Result and (Values.GetObject(Index) is TCosNumber));
  end;
end;

function TPDAnnotation.Rect: TPdfRectangle;
begin
  var Values: TCosArray;
  if HasRect and FDictionary.TryGetCosArray(TCosNames.Rect, Values) then
  begin
    Result := TPdfRectangle.FromCosArray(Values);
  end
  else
  begin
    Result := Default(TPdfRectangle);
  end;
end;

function TPDAnnotation.Flags: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.F, 0);
end;

function TPDAnnotation.HasFlag(const Flag: Integer): Boolean;
begin
  Result := ((Flags and Flag) = Flag);
end;

function TPDAnnotation.IsHidden: Boolean;
begin
  Result := HasFlag(FlagHidden);
end;

function TPDAnnotation.IsPrinted: Boolean;
begin
  Result := HasFlag(FlagPrinted);
end;

function TPDAnnotation.IsNoView: Boolean;
begin
  Result := HasFlag(FlagNoView);
end;

function TPDAnnotation.IsNoRotate: Boolean;
begin
  Result := HasFlag(FlagNoRotate);
end;

function TPDAnnotation.IsInvisible: Boolean;
begin
  Result := HasFlag(FlagInvisible);
end;

function TPDAnnotation.IsKnownType: Boolean;
begin
  Result := False;
  const Name = SubType;
  for var Known in KnownSubTypes do
  begin
    Result := (Result or (Known = Name));
  end;
end;

function TPDAnnotation.TryGetNormalAppearanceEntry(out Entry: TCosDictionary): Boolean;
begin
  var Appearance: TCosDictionary;
  Result := (FDictionary.TryGetCosDictionary(TCosNames.AP, Appearance) and Appearance.TryGetCosDictionary(TCosNames.N, Entry));
  if not Result then
  begin
    Entry := nil;
  end;
end;

function TPDAnnotation.TryGetNormalAppearance(out Appearance: TCosStream): Boolean;
begin
  Appearance := nil;
  var Entry: TCosDictionary;
  if not TryGetNormalAppearanceEntry(Entry) then
  begin
    Exit(False);
  end;

  if Entry is TCosStream then
  begin
    Appearance := TCosStream(Entry);
    Exit(True);
  end;

  // A subdictionary: the entry that /AS names. PDAnnotation.getAppearanceState is getCOSName, so only a name counts.
  var State: TCosBase;
  const HasState = (FDictionary.TryGetDictionaryObject(TCosNames.AS_, State) and (State is TCosName));
  Result := (HasState and Entry.TryGetCosStream(TCosName(State).Name, Appearance));
end;

function TPDAnnotation.TryGetOptionalContent(out Value: TCosDictionary): Boolean;
begin
  Result := FDictionary.TryGetCosDictionary(TCosNames.OC, Value);
  if not Result then
  begin
    Value := nil;
  end;
end;

end.
