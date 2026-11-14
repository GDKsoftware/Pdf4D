// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/form/PDFieldFactory.java,
// PDField.java, PDTerminalField.java, PDNonTerminalField.java, PDVariableText.java, PDTextField.java, PDButton.java,
// PDCheckBox.java, PDRadioButton.java, PDPushButton.java, PDChoice.java, PDComboBox.java, PDListBox.java and
// PDSignatureField.java (3.0.8), the read side
unit Pdf4D.Model.Field;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary;

type
  {$SCOPEDENUMS ON}
  TPdfFieldKind = (Text, CheckBox, RadioButton, PushButton, ComboBox, ListBox, Signature, NonTerminal);
  {$SCOPEDENUMS OFF}

  TPDField = class;

  // Owns the fields of one form and holds what they share: the dictionary of the form, where the inheritance of
  // attributes ends, and the log.
  TPDFieldPool = class
  private
    FFormDictionary: TCosDictionary;
    FLog: TPdfLog;
    FFields: TObjectList<TPDField>;

  public
    // Neither the dictionary nor the log is owned. Log may be nil.
    constructor Create(const FormDictionary: TCosDictionary; const Log: TPdfLog);
    destructor Destroy; override;

    function Adopt(const Field: TPDField): TPDField;

    property FormDictionary: TCosDictionary read FFormDictionary;
    property Log: TPdfLog read FLog;
  end;

  // A field of a form. PDFBox has a class per kind of field, here Kind tells which of them it would be. The properties
  // that do not belong to the kind give the value of an empty one (an empty string or array). The pool owns the field.
  TPDField = class
  private
    FPool: TPDFieldPool;
    FDictionary: TCosDictionary;
    FParent: TPDField;
    FKind: TPdfFieldKind;
    FDepth: Integer;
    FChildren: TArray<TPDField>;
    FChildrenBuilt: Boolean;

    constructor Create(const Pool: TPDFieldPool; const Dictionary: TCosDictionary; const Parent: TPDField; const Kind: TPdfFieldKind);

    class function HasFieldKid(const Dictionary: TCosDictionary): Boolean; static;
    class function TryFindFieldType(const Dictionary: TCosDictionary; out FieldType: string): Boolean; static;
    class function KindOfButton(const Flags: Integer): TPdfFieldKind; static;
    class function KindOfFieldType(const Dictionary: TCosDictionary; const FieldType: string; out Kind: TPdfFieldKind): Boolean; static;
    class function TryParseJavaInt(const Text: string; out Value: Integer): Boolean; static;
    class function StringOrStream(const Value: TCosBase): string; static;
    class function StringsOf(const Value: TCosBase): TArray<string>; static;

    procedure BuildChildren;
    function GetChildren: TArray<TPDField>;
    function TryGetInheritableAttribute(const Key: string; out Value: TCosBase): Boolean;
    function GetPartialName: string;
    function GetAlternateName: string;
    function GetFlags: Integer;
    function GetValueAsString: string;
    function GetValues: TArray<string>;
    function GetExportValues: TArray<string>;
    function GetOnValues: TArray<string>;
    function IsButton: Boolean;
    function ButtonValue: string;
    function TextValue: string;
    function ChoiceValueAsString: string;
    function Widgets: TArray<TCosDictionary>;
    function OnValueOfWidget(const Widget: TCosDictionary): string;

  public
    // Port of PDFieldFactory.createField. False when the dictionary is no field (PDFBox gives null). The pool owns the
    // new field. Parent is nil for a field of the form itself.
    class function TryCreate(const Pool: TPDFieldPool; const Dictionary: TCosDictionary; const Parent: TPDField; out Field: TPDField): Boolean; static;

    // Port of PDField.getFullyQualifiedName: the partial names of the field and its parents joined with a dot. False when
    // none of them has a name (PDFBox gives null).
    function TryGetFullyQualifiedName(out Name: string): Boolean;

    // Port of getValueAsString of the class of the kind: a text field gives the string (or the text of the stream) of /V,
    // a check box and a radio button the on value or Off, a combo box and a list box the values as Java prints a list ("[a, b]").
    // A push button, a signature field and a non terminal field give an empty string. Raises EPdfParseException for an
    // /Opt or /V array of choice or button that holds something else than strings (where PDFBox throws).
    property ValueAsString: string read GetValueAsString;

    // Port of PDChoice.getValue: /V of the field itself (not inherited) as a string or an array of strings. Raises
    // EPdfParseException when the /V array holds something else than direct strings (PDFBox throws a ClassCastException).
    property Values: TArray<string> read GetValues;

    // Port of PDButton.getExportValues: /Opt, inherited. Empty for a push button and other kinds. Raises EPdfParseException
    // when the /Opt array holds something else than direct strings.
    property ExportValues: TArray<string> read GetExportValues;

    // Port of PDButton.getOnValues for a check box and a radio button: the export values, or else for each widget the first
    // entry of its normal appearance (/AP /N) that is a stream and not /Off ('' when there is none). Order of first
    // occurrence, without doubles. Raises EPdfParseException for an export value array that is not made of direct strings
    // and for a normal appearance that is a stream.
    property OnValues: TArray<string> read GetOnValues;

    property Kind: TPdfFieldKind read FKind;
    property PartialName: string read GetPartialName;
    function FullyQualifiedName: string;
    property AlternateName: string read GetAlternateName;
    // Port of getFieldFlags: /Ff, for a terminal field inherited from its parents, for a non terminal field its own
    property Flags: Integer read GetFlags;
    // The fields below a non terminal field (empty for the other kinds), created once. A kid that is no field is left out.
    property Children: TArray<TPDField> read GetChildren;
    property Parent: TPDField read FParent;
    property Depth: Integer read FDepth;
    property CosObject: TCosDictionary read FDictionary;
  end;

const
  // The longest chain of fields (and of /Parent entries) that is followed. Real forms are a few levels deep.
  MaxFieldDepth = 256;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString;

const
  FlagRadio = 1 shl 15;
  FlagPushButton = 1 shl 16;
  FlagCombo = 1 shl 17;

{ TPDFieldPool }

constructor TPDFieldPool.Create(const FormDictionary: TCosDictionary; const Log: TPdfLog);
begin
  inherited Create;
  FFormDictionary := FormDictionary;
  FLog := Log;
  FFields := TObjectList<TPDField>.Create(True);
end;

destructor TPDFieldPool.Destroy;
begin
  FFields.Free;
  inherited;
end;

function TPDFieldPool.Adopt(const Field: TPDField): TPDField;
begin
  FFields.Add(Field);
  Result := Field;
end;

{ TPDField }

constructor TPDField.Create(const Pool: TPDFieldPool; const Dictionary: TCosDictionary; const Parent: TPDField; const Kind: TPdfFieldKind);
begin
  inherited Create;
  FPool := Pool;
  FDictionary := Dictionary;
  FParent := Parent;
  FKind := Kind;
  if Assigned(Parent) then
  begin
    FDepth := Parent.Depth + 1;
  end;
end;

class function TPDField.TryCreate(const Pool: TPDFieldPool; const Dictionary: TCosDictionary; const Parent: TPDField;
                                  out Field: TPDField): Boolean;
begin
  Field := nil;

  // A field with kids that have a name is non terminal, whatever its type: it may have properties that apply to others
  var Kind := TPdfFieldKind.NonTerminal;
  if not HasFieldKid(Dictionary) then
  begin
    var FieldType: string;
    const HasType = TryFindFieldType(Dictionary, FieldType);
    // An erroneous non-field object, see PDFBOX-2885
    if not (HasType and KindOfFieldType(Dictionary, FieldType, Kind)) then
    begin
      Exit(False);
    end;
  end;

  Field := Pool.Adopt(TPDField.Create(Pool, Dictionary, Parent, Kind));
  Result := True;
end;

class function TPDField.HasFieldKid(const Dictionary: TCosDictionary): Boolean;
begin
  var Kids: TCosArray;
  Result := False;
  if not Dictionary.TryGetCosArray(TCosNames.Kids, Kids) then
  begin
    Exit;
  end;

  for var Index := 0 to Kids.Count - 1 do
  begin
    const Kid = Kids.GetObject(Index);
    var Name: string;
    if (Kid is TCosDictionary) and TCosDictionary(Kid).TryGetString(TCosNames.T, Name) then
    begin
      Exit(True);
    end;
  end;
end;

// Port of findFieldType. Instead of a set of the dictionaries seen, the number of steps is limited, which also stops a
// cycle (PDFBOX-5896) and keeps the work for all the fields linear.
class function TPDField.TryFindFieldType(const Dictionary: TCosDictionary; out FieldType: string): Boolean;
begin
  var Current := Dictionary;
  FieldType := '';
  for var Step := 0 to MaxFieldDepth do
  begin
    var Value: TCosBase;
    if Current.TryGetDictionaryObject(TCosNames.FT, Value) then
    begin
      if Value is TCosName then
      begin
        FieldType := TCosName(Value).Name;
        Exit(True);
      end;
      if Value is TCosString then
      begin
        FieldType := TCosString(Value).GetString;
        Exit(True);
      end;
    end;

    // getCOSDictionary(PARENT, P): /P is only looked at when there is no /Parent
    if not Current.TryGetDictionaryObject(TCosNames.Parent, Value) then
    begin
      Current.TryGetDictionaryObject(TCosNames.P, Value);
    end;
    if not (Value is TCosDictionary) then
    begin
      Exit(False);
    end;
    Current := TCosDictionary(Value);
  end;
  Result := False;
end;

class function TPDField.KindOfFieldType(const Dictionary: TCosDictionary; const FieldType: string; out Kind: TPdfFieldKind): Boolean;
begin
  // The flags of the field itself count here, they are not inherited
  const Flags = Dictionary.GetInt(TCosNames.Ff, 0);
  Result := True;
  if FieldType = TCosNames.Ch then
  begin
    if (Flags and FlagCombo) <> 0 then
    begin
      Kind := TPdfFieldKind.ComboBox;
    end
    else
    begin
      Kind := TPdfFieldKind.ListBox;
    end;
  end
  else if FieldType = TCosNames.Tx then
  begin
    Kind := TPdfFieldKind.Text;
  end
  else if FieldType = TCosNames.Sig then
  begin
    Kind := TPdfFieldKind.Signature;
  end
  else if FieldType = TCosNames.Btn then
  begin
    Kind := KindOfButton(Flags);
  end
  else
  begin
    Kind := TPdfFieldKind.NonTerminal;
    Result := False;
  end;
end;

class function TPDField.KindOfButton(const Flags: Integer): TPdfFieldKind;
begin
  if (Flags and FlagRadio) <> 0 then
  begin
    Result := TPdfFieldKind.RadioButton;
  end
  else if (Flags and FlagPushButton) <> 0 then
  begin
    Result := TPdfFieldKind.PushButton;
  end
  else
  begin
    Result := TPdfFieldKind.CheckBox;
  end;
end;

procedure TPDField.BuildChildren;
begin
  FChildrenBuilt := True;
  if FKind <> TPdfFieldKind.NonTerminal then
  begin
    Exit;
  end;

  if FDepth >= MaxFieldDepth then
  begin
    if Assigned(FPool.Log) then
    begin
      FPool.Log.Warning('The fields are nested too deep, the kids of a field are skipped');
    end;
    Exit;
  end;

  var Kids: TCosArray;
  if not FDictionary.TryGetCosArray(TCosNames.Kids, Kids) then
  begin
    Exit;
  end;

  const Found = TList<TPDField>.Create;
  try
    for var Index := 0 to Kids.Count - 1 do
    begin
      const Kid = Kids.GetObject(Index);
      if not (Kid is TCosDictionary) then
      begin
        Continue;
      end;

      if Kid = FDictionary then
      begin
        if Assigned(FPool.Log) then
        begin
          FPool.Log.Warning('Child field is same object as parent');
        end;
        Continue;
      end;

      var Child: TPDField;
      if TryCreate(FPool, TCosDictionary(Kid), Self, Child) then
      begin
        Found.Add(Child);
      end;
    end;
    FChildren := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPDField.GetChildren: TArray<TPDField>;
begin
  if not FChildrenBuilt then
  begin
    BuildChildren;
  end;
  Result := FChildren;
end;

// Port of getInheritableAttribute: the field, then its parents, then the dictionary of the form. A key that is there with
// a null value ends the search without a value.
function TPDField.TryGetInheritableAttribute(const Key: string; out Value: TCosBase): Boolean;
begin
  var Field := Self;
  while Assigned(Field) do
  begin
    if Field.FDictionary.ContainsKey(Key) then
    begin
      Exit(Field.FDictionary.TryGetDictionaryObject(Key, Value));
    end;
    Field := Field.FParent;
  end;
  Result := FPool.FormDictionary.TryGetDictionaryObject(Key, Value);
end;

function TPDField.TryGetFullyQualifiedName(out Name: string): Boolean;
begin
  const Parts = TList<string>.Create;
  try
    var Field := Self;
    while Assigned(Field) do
    begin
      var Part: string;
      if Field.FDictionary.TryGetString(TCosNames.T, Part) then
      begin
        Parts.Add(Part);
      end;
      Field := Field.FParent;
    end;

    Result := (Parts.Count > 0);
    Name := '';
    const Builder = TStringBuilder.Create;
    try
      for var Index := Parts.Count - 1 downto 0 do
      begin
        Builder.Append(Parts[Index]);
        if Index > 0 then
        begin
          Builder.Append('.');
        end;
      end;
      Name := Builder.ToString;
    finally
      Builder.Free;
    end;
  finally
    Parts.Free;
  end;
end;

function TPDField.FullyQualifiedName: string;
begin
  TryGetFullyQualifiedName(Result);
end;

function TPDField.GetPartialName: string;
begin
  Result := FDictionary.GetString(TCosNames.T, '');
end;

function TPDField.GetAlternateName: string;
begin
  Result := FDictionary.GetString(TCosNames.TU, '');
end;

function TPDField.GetFlags: Integer;
begin
  if FKind = TPdfFieldKind.NonTerminal then
  begin
    Exit(FDictionary.GetInt(TCosNames.Ff, 0));
  end;

  var Value: TCosBase;
  if FDictionary.TryGetDictionaryObject(TCosNames.Ff, Value) and (Value is TCosNumber) then
  begin
    Exit(TCosNumber(Value).IntValue);
  end;

  // The parent of a field is always a non terminal field, which gives only its own flags
  if Assigned(FParent) then
  begin
    Exit(FParent.GetFlags);
  end;
  Result := 0;
end;

class function TPDField.StringOrStream(const Value: TCosBase): string;
begin
  Result := '';
  if Value is TCosString then
  begin
    Result := TCosString(Value).GetString;
  end
  else if Value is TCosStream then
  begin
    // Port of COSStream.toTextString: a stream that cannot be read gives an empty string
    try
      const Data = TCosStream(Value).CreateDecodedStream;
      try
        var Bytes: TBytes;
        SetLength(Bytes, Data.Size);
        if Length(Bytes) > 0 then
        begin
          Data.Position := 0;
          Data.ReadBuffer(Bytes[0], Length(Bytes));
        end;
        const Text = TCosString.Create(Bytes, False);
        try
          Result := Text.GetString;
        finally
          Text.Free;
        end;
      finally
        Data.Free;
      end;
    except
      on EPdfException do
      begin
        Result := '';
      end;
    end;
  end;
end;

// Port of COSArray.toCOSStringStringList: the items as they are in the array, an indirect reference is no string there
class function TPDField.StringsOf(const Value: TCosBase): TArray<string>;
begin
  const Items = TCosArray(Value);
  SetLength(Result, Items.Count);
  for var Index := 0 to Items.Count - 1 do
  begin
    const Item = Items.Get(Index);
    if not (Item is TCosString) then
    begin
      raise EPdfParseException.CreateFmt('The array holds no string at position %d', [Index]);
    end;
    Result[Index] := TCosString(Item).GetString;
  end;
end;

function TPDField.IsButton: Boolean;
begin
  Result := FKind in [TPdfFieldKind.CheckBox, TPdfFieldKind.RadioButton];
end;

function TPDField.TextValue: string;
begin
  var Value: TCosBase;
  if TryGetInheritableAttribute(TCosNames.V, Value) then
  begin
    Result := StringOrStream(Value);
  end
  else
  begin
    Result := '';
  end;
end;

// Java's Integer.parseInt(text, 10) for ASCII digits: an optional sign, then at least one digit, within the Integer range
class function TPDField.TryParseJavaInt(const Text: string; out Value: Integer): Boolean;
begin
  Value := 0;
  var Start := 1;
  var IsNegative := False;
  if (Text.Length > 0) and ((Text[1] = '-') or (Text[1] = '+')) then
  begin
    IsNegative := (Text[1] = '-');
    Start := 2;
  end;
  if Start > Text.Length then
  begin
    Exit(False);
  end;

  var Accumulated: Int64 := 0;
  for var Position := Start to Text.Length do
  begin
    const Character = Text[Position];
    if (Character < '0') or (Character > '9') then
    begin
      Exit(False);
    end;
    Accumulated := Accumulated * 10 + (Ord(Character) - Ord('0'));
    if Accumulated > Int64(High(Integer)) + 1 then
    begin
      Exit(False);
    end;
  end;

  if IsNegative then
  begin
    Accumulated := -Accumulated;
  end;
  if (Accumulated < Low(Integer)) or (Accumulated > High(Integer)) then
  begin
    Exit(False);
  end;
  Value := Integer(Accumulated);
  Result := True;
end;

// Port of PDButton.getValue
function TPDField.ButtonValue: string;
begin
  var Value: TCosBase;
  if not (TryGetInheritableAttribute(TCosNames.V, Value) and (Value is TCosName)) then
  begin
    Exit(TCosNames.Off);
  end;

  Result := TCosName(Value).Name;
  const Options = GetExportValues;
  var Index: Integer;
  const IsIndex = ((Length(Options) > 0) and TryParseJavaInt(Result, Index) and (Index >= 0) and (Index < Length(Options)));
  if IsIndex then
  begin
    Result := Options[Index];
  end;
end;

function TPDField.GetExportValues: TArray<string>;
begin
  Result := nil;
  if not IsButton then
  begin
    Exit;
  end;

  var Value: TCosBase;
  if not TryGetInheritableAttribute(TCosNames.Opt, Value) then
  begin
    Exit;
  end;

  if Value is TCosString then
  begin
    const Text = TCosString(Value).GetString;
    if Text <> '' then
    begin
      Result := [Text];
    end;
  end
  else if Value is TCosArray then
  begin
    Result := StringsOf(Value);
  end;
end;

// Port of PDChoice.getValueFor(V)
function TPDField.GetValues: TArray<string>;
begin
  Result := nil;
  if not (FKind in [TPdfFieldKind.ComboBox, TPdfFieldKind.ListBox]) then
  begin
    Exit;
  end;

  var Value: TCosBase;
  if not FDictionary.TryGetDictionaryObject(TCosNames.V, Value) then
  begin
    Exit;
  end;

  if Value is TCosString then
  begin
    Result := [TCosString(Value).GetString];
  end
  else if Value is TCosArray then
  begin
    Result := StringsOf(Value);
  end;
end;

// Port of PDChoice.getValueAsString: Arrays.toString of the values
function TPDField.ChoiceValueAsString: string;
begin
  Result := '[' + string.Join(', ', GetValues) + ']';
end;

function TPDField.GetValueAsString: string;
begin
  case FKind of
    TPdfFieldKind.Text                                      : Result := TextValue;
    TPdfFieldKind.CheckBox, TPdfFieldKind.RadioButton       : Result := ButtonValue;
    TPdfFieldKind.ComboBox, TPdfFieldKind.ListBox           : Result := ChoiceValueAsString;
    TPdfFieldKind.PushButton, TPdfFieldKind.Signature,
    TPdfFieldKind.NonTerminal                               : Result := '';
  else
    raise ENotSupportedException.CreateFmt('Unsupported field kind: %d', [Ord(FKind)]);
  end;
end;

// Port of PDTerminalField.getWidgets
function TPDField.Widgets: TArray<TCosDictionary>;
begin
  var Kids: TCosArray;
  if not FDictionary.TryGetCosArray(TCosNames.Kids, Kids) then
  begin
    SetLength(Result, 1);
    Result[0] := FDictionary;
    Exit;
  end;

  const Found = TList<TCosDictionary>.Create;
  try
    for var Index := 0 to Kids.Count - 1 do
    begin
      const Kid = Kids.GetObject(Index);
      if Kid is TCosDictionary then
      begin
        Found.Add(TCosDictionary(Kid));
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

// Port of PDButton.getOnValueForWidget: the first entry of the normal appearance that is not /Off. PDFBox keeps the
// entries in a HashMap, so the first of several is arbitrary there, here it is the first in the dictionary.
function TPDField.OnValueOfWidget(const Widget: TCosDictionary): string;
begin
  Result := '';
  var Appearance: TCosDictionary;
  var Normal: TCosDictionary;
  if not (Widget.TryGetCosDictionary(TCosNames.AP, Appearance) and Appearance.TryGetCosDictionary(TCosNames.N, Normal)) then
  begin
    Exit;
  end;

  if Normal is TCosStream then
  begin
    raise EPdfParseException.Create('The normal appearance is a stream, not a subdictionary');
  end;

  for var Key in Normal.Keys do
  begin
    var Appearances: TCosStream;
    if (Key <> TCosNames.Off) and Normal.TryGetCosStream(Key, Appearances) then
    begin
      Exit(Key);
    end;
  end;
end;

function TPDField.GetOnValues: TArray<string>;
begin
  Result := nil;
  if not IsButton then
  begin
    Exit;
  end;

  const Candidates = TList<string>.Create;
  const Seen = TDictionary<string, Boolean>.Create;
  const Distinct = TList<string>.Create;
  try
    Candidates.AddRange(GetExportValues);
    if Candidates.Count = 0 then
    begin
      for var Widget in Widgets do
      begin
        Candidates.Add(OnValueOfWidget(Widget));
      end;
    end;

    for var Candidate in Candidates do
    begin
      if not Seen.ContainsKey(Candidate) then
      begin
        Seen.Add(Candidate, True);
        Distinct.Add(Candidate);
      end;
    end;
    Result := Distinct.ToArray;
  finally
    Distinct.Free;
    Seen.Free;
    Candidates.Free;
  end;
end;

end.
