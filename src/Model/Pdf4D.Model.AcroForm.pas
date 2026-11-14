// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/form/PDAcroForm.java and PDFieldTree.java (3.0.8),
// the read side
unit Pdf4D.Model.AcroForm;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Field;

type
  // The interactive form (/AcroForm). It owns all fields that it gives out. Unlike PDFBox it applies no fix ups.
  TPDAcroForm = class
  private
    FDictionary: TCosDictionary;
    FPool: TPDFieldPool;
    FFields: TArray<TPDField>;
    FFieldsBuilt: Boolean;

    procedure BuildFields;
    function GetFields: TArray<TPDField>;

  public
    // The dictionary is not owned. Log may be nil.
    constructor Create(const Dictionary: TCosDictionary; const Log: TPdfLog);
    destructor Destroy; override;

    // Port of PDFieldTree: all fields in document order, depth first, a non terminal field before its children. A field
    // that is met a second time below another field is left out. A field of /Fields that is met again is listed again but its
    // kids are not walked again. A tree that is too deep is cut off. Walks without recursion.
    function GetFieldTree: TArray<TPDField>;

    // Port of getField: the first field of the tree with this fully qualified name
    function TryGetField(const FullyQualifiedName: string; out Field: TPDField): Boolean;

    // The fields of the form itself, as /Fields lists them (port of getFields)
    property Fields: TArray<TPDField> read GetFields;
    property CosObject: TCosDictionary read FDictionary;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray;

{ TPDAcroForm }

constructor TPDAcroForm.Create(const Dictionary: TCosDictionary; const Log: TPdfLog);
begin
  inherited Create;
  FDictionary := Dictionary;
  FPool := TPDFieldPool.Create(Dictionary, Log);
end;

destructor TPDAcroForm.Destroy;
begin
  FPool.Free;
  inherited;
end;

procedure TPDAcroForm.BuildFields;
begin
  FFieldsBuilt := True;
  var Items: TCosArray;
  if not FDictionary.TryGetCosArray(TCosNames.Fields, Items) then
  begin
    Exit;
  end;

  const Found = TList<TPDField>.Create;
  try
    for var Index := 0 to Items.Count - 1 do
    begin
      const Element = Items.GetObject(Index);
      var Field: TPDField;
      if (Element is TCosDictionary) and TPDField.TryCreate(FPool, TCosDictionary(Element), nil, Field) then
      begin
        Found.Add(Field);
      end;
    end;
    FFields := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPDAcroForm.GetFields: TArray<TPDField>;
begin
  if not FFieldsBuilt then
  begin
    BuildFields;
  end;
  Result := FFields;
end;

function TPDAcroForm.GetFieldTree: TArray<TPDField>;
begin
  const Ordered = TList<TPDField>.Create;
  const Pending = TStack<TPDField>.Create;
  // By identity of the dictionary, because a field object is made for each time that a dictionary is met
  const Seen = TDictionary<TCosDictionary, Boolean>.Create;
  try
    const Roots = GetFields;
    for var Index := High(Roots) downto 0 do
    begin
      Pending.Push(Roots[Index]);
    end;

    while Pending.Count > 0 do
    begin
      const Field = Pending.Pop;
      const IsRepeated = Seen.ContainsKey(Field.CosObject);
      if IsRepeated and Assigned(Field.Parent) then
      begin
        if Assigned(FPool.Log) then
        begin
          FPool.Log.Error('Child of field ''%s'' already exists elsewhere, ignored to avoid recursion', [Field.Parent.FullyQualifiedName]);
        end;
        Continue;
      end;

      Ordered.Add(Field);
      // A field of the form itself is listed again, as PDFBox does, but its kids were met the first time and are skipped
      // there: not expanding them again keeps the work and the memory linear for a /Fields array that repeats a field
      if IsRepeated then
      begin
        Continue;
      end;
      Seen.Add(Field.CosObject, True);

      const Children = Field.Children;
      for var Index := High(Children) downto 0 do
      begin
        Pending.Push(Children[Index]);
      end;
    end;
    Result := Ordered.ToArray;
  finally
    Seen.Free;
    Pending.Free;
    Ordered.Free;
  end;
end;

function TPDAcroForm.TryGetField(const FullyQualifiedName: string; out Field: TPDField): Boolean;
begin
  Field := nil;
  for var Candidate in GetFieldTree do
  begin
    var Name: string;
    if Candidate.TryGetFullyQualifiedName(Name) and (Name = FullyQualifiedName) then
    begin
      Field := Candidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
