// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDPage.java (3.0.8), the read side
unit Pdf4D.Model.Page;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Rectangle,
  Pdf4D.Model.Resources;

type
  // A page of the page tree, which owns it. It holds the page dictionary and does not own that.
  TPDPage = class
  private
    FDictionary: TCosDictionary;
    FContext: TPDDocumentContext;
    FResources: TPDResources;

    function TryGetInheritedBox(const Key: string; out Box: TPdfRectangle): Boolean;
    function GetOwnBox(const Key: string): TPdfRectangle;

  public
    // The page does not own Dictionary or Context
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // Inherited from the page tree, US Letter when there is none
    function MediaBox: TPdfRectangle;
    // Inherited and clipped to the media box, the media box when there is none
    function CropBox: TPdfRectangle;
    // The next three are not inherited. They are clipped to the media box and default to the crop box.
    function BleedBox: TPdfRectangle;
    function TrimBox: TPdfRectangle;
    function ArtBox: TPdfRectangle;

    // Inherited, 0, 90, 180 or 270. An angle that is no multiple of 90 gives 0, like PDFBox.
    function Rotation: Integer;
    // 1 unless the entry is a positive number
    function UserUnit: Single;
    // Inherited. False when the page has no resources dictionary.
    function TryGetResources(out Resources: TCosDictionary): Boolean;
    // The streams of /Contents. Entries that are no stream are left out.
    function ContentStreams: TArray<TCosStream>;
    // PDPage.hasContents: /Contents is a stream with data or an array with items
    function HasContents: Boolean;
    // The inherited resources, made on first use and owned by the page. A page without resources dictionary gives empty
    // resources (PDFBox gives null), so that a caller needs no nil check.
    function Resources: TPDResources;

    property CosObject: TCosDictionary read FDictionary;
    property Context: TPDDocumentContext read FContext;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.PageTree;

{ TPDPage }

constructor TPDPage.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  if Context = nil then
  begin
    raise EArgumentNilException.Create('Context');
  end;

  inherited Create;
  FDictionary := Dictionary;
  FContext := Context;
end;

destructor TPDPage.Destroy;
begin
  FResources.Free;
  inherited;
end;

function TPDPage.TryGetInheritedBox(const Key: string; out Box: TPdfRectangle): Boolean;
begin
  var Value: TCosBase;
  Result := (TPDPageTree.TryGetInheritableAttribute(FDictionary, Key, Value) and (Value is TCosArray));
  if Result then
  begin
    Box := TPdfRectangle.FromCosArray(TCosArray(Value));
  end;
end;

function TPDPage.GetOwnBox(const Key: string): TPdfRectangle;
begin
  var Values: TCosArray;
  if FDictionary.TryGetCosArray(Key, Values) then
  begin
    Result := TPdfRectangle.FromCosArray(Values).ClipTo(MediaBox);
  end
  else
  begin
    Result := CropBox;
  end;
end;

function TPDPage.MediaBox: TPdfRectangle;
begin
  if not TryGetInheritedBox(TCosNames.MediaBox, Result) then
  begin
    Result := TPdfRectangle.Letter;
  end;
end;

function TPDPage.CropBox: TPdfRectangle;
begin
  if TryGetInheritedBox(TCosNames.CropBox, Result) then
  begin
    Result := Result.ClipTo(MediaBox);
  end
  else
  begin
    Result := MediaBox;
  end;
end;

function TPDPage.BleedBox: TPdfRectangle;
begin
  Result := GetOwnBox(TCosNames.BleedBox);
end;

function TPDPage.TrimBox: TPdfRectangle;
begin
  Result := GetOwnBox(TCosNames.TrimBox);
end;

function TPDPage.ArtBox: TPdfRectangle;
begin
  Result := GetOwnBox(TCosNames.ArtBox);
end;

function TPDPage.Rotation: Integer;
begin
  Result := 0;
  var Value: TCosBase;
  if TPDPageTree.TryGetInheritableAttribute(FDictionary, TCosNames.Rotate, Value) and (Value is TCosNumber) then
  begin
    const Angle = TCosNumber(Value).IntValue;
    if Angle mod 90 = 0 then
    begin
      Result := (Angle mod 360 + 360) mod 360;
    end;
  end;
end;

function TPDPage.UserUnit: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.UserUnit, 1.0);
  if not (Result > 0) then
  begin
    Result := 1.0;
  end;
end;

function TPDPage.TryGetResources(out Resources: TCosDictionary): Boolean;
begin
  var Value: TCosBase;
  Result := (TPDPageTree.TryGetInheritableAttribute(FDictionary, TCosNames.Resources, Value) and (Value is TCosDictionary));
  if Result then
  begin
    Resources := TCosDictionary(Value);
  end
  else
  begin
    Resources := nil;
  end;
end;

function TPDPage.HasContents: Boolean;
begin
  Result := False;
  var Value: TCosBase;
  if not FDictionary.TryGetDictionaryObject(TCosNames.Contents, Value) then
  begin
    Exit;
  end;

  if Value is TCosStream then
  begin
    Result := (Length(TCosStream(Value).ReadRawPrefix(1)) > 0);
  end
  else if Value is TCosArray then
  begin
    Result := (TCosArray(Value).Count > 0);
  end;
end;

function TPDPage.Resources: TPDResources;
begin
  if not Assigned(FResources) then
  begin
    var Dictionary: TCosDictionary;
    if not TryGetResources(Dictionary) then
    begin
      Dictionary := nil;
    end;
    FResources := TPDResources.Create(Dictionary, FContext);
  end;
  Result := FResources;
end;

function TPDPage.ContentStreams: TArray<TCosStream>;
begin
  var Value: TCosBase;
  if not FDictionary.TryGetDictionaryObject(TCosNames.Contents, Value) then
  begin
    Exit(nil);
  end;

  if Value is TCosStream then
  begin
    SetLength(Result, 1);
    Result[0] := TCosStream(Value);
    Exit;
  end;

  const Streams = TList<TCosStream>.Create;
  try
    if Value is TCosArray then
    begin
      const Entries = TCosArray(Value);
      for var Index := 0 to Entries.Count - 1 do
      begin
        const Entry = Entries.GetObject(Index);
        if Entry is TCosStream then
        begin
          Streams.Add(TCosStream(Entry));
        end;
      end;
    end;
    Result := Streams.ToArray;
  finally
    Streams.Free;
  end;
end;

end.
