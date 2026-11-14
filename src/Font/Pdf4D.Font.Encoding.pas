// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/encoding/Encoding.java, DictionaryEncoding.java,
// BuiltInEncoding.java and Type1Encoding.java (3.0.8)
unit Pdf4D.Font.Encoding;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.FontBox.Afm,
  Pdf4D.FontBox.Encoding;

type
  // A PostScript encoding vector: maps character codes to glyph names. After construction the maps must not be
  // changed, which is what makes the shared instances safe.
  TPdfEncoding = class abstract
  private
    FCodeToName: TDictionary<Integer, string>;
    FNameToCode: TDictionary<string, Integer>;

  protected
    // An existing reverse mapping is kept
    procedure Add(const Code: Integer; const Name: string);
    // An existing reverse mapping is replaced
    procedure Overwrite(const Code: Integer; const Name: string);
    procedure AddAllFrom(const Source: TPdfEncoding);

  public
    constructor Create;
    destructor Destroy; override;

    // The shared encoding for StandardEncoding, WinAnsiEncoding, MacRomanEncoding and MacExpertEncoding. The caller
    // does not own it.
    class function TryGetInstance(const Name: string; out Encoding: TPdfEncoding): Boolean; static;

    // The name of the code, or .notdef when the encoding has none
    function GetName(const Code: Integer): string;
    function Contains(const Name: string): Boolean; overload;
    function Contains(const Code: Integer): Boolean; overload;
    function EncodingName: string; virtual; abstract;
    // The maps belong to the encoding and must not be changed. More than one name may map to the same code.
    function CodeToNameMap: TDictionary<Integer, string>;
    function NameToCodeMap: TDictionary<string, Integer>;
  end;

  // The encoding of a font program, made from a code to name mapping
  TBuiltInEncoding = class(TPdfEncoding)
  public
    // Copies the mapping
    constructor Create(const CodeToName: TDictionary<Integer, string>);

    function EncodingName: string; override;
  end;

  TType1Encoding = class(TPdfEncoding)
  public
    // The caller owns the new encoding
    class function FromFontBox(const Encoding: TFontBoxEncoding): TType1Encoding; static;
    // The caller owns the new encoding. The codes and names are those of the character metrics of an AFM.
    class function FromMetrics(const Metrics: TFontMetrics): TType1Encoding; static;

    function EncodingName: string; override;
  end;

  // The encoding of a font dictionary: a base encoding with a /Differences array on top
  TDictionaryEncoding = class(TPdfEncoding)
  private
    FDictionary: TCosDictionary;
    FBaseEncoding: TPdfEncoding;
    FDifferences: TDictionary<Integer, string>;

    procedure ApplyDifferences;
    procedure CopyBaseEncoding;
    function TryGetNamedBase(out Base: TPdfEncoding): Boolean;
    function SelectBaseEncoding(const IsNonSymbolic: Boolean; const BuiltIn: TPdfEncoding): TPdfEncoding;

  public
    // For a font of the PDF. The dictionary is not owned and must outlive the encoding. BuiltIn is the font's own
    // encoding, which a symbolic font needs as the base; it is not owned either. Raises EPdfException for a symbolic
    // font without a built-in encoding.
    constructor Create(const Dictionary: TCosDictionary; const IsNonSymbolic: Boolean; const BuiltIn: TPdfEncoding);
    // For a Type 3 font: the Differences array is the complete encoding
    constructor CreateForType3(const Dictionary: TCosDictionary);
    destructor Destroy; override;

    function EncodingName: string; override;
    // The map belongs to the encoding
    function Differences: TDictionary<Integer, string>;

    // Not owned, nil for a Type 3 font
    property BaseEncoding: TPdfEncoding read FBaseEncoding;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Font.Encoding.Tables;

{ TPdfEncoding }

constructor TPdfEncoding.Create;
begin
  inherited Create;
  FCodeToName := TDictionary<Integer, string>.Create(250);
  FNameToCode := TDictionary<string, Integer>.Create(250);
end;

destructor TPdfEncoding.Destroy;
begin
  FNameToCode.Free;
  FCodeToName.Free;
  inherited;
end;

class function TPdfEncoding.TryGetInstance(const Name: string; out Encoding: TPdfEncoding): Boolean;
begin
  Result := True;
  if Name = TCosNames.StandardEncoding then
  begin
    Encoding := TStandardEncoding.Instance;
  end
  else if Name = TCosNames.WinAnsiEncoding then
  begin
    Encoding := TWinAnsiEncoding.Instance;
  end
  else if Name = TCosNames.MacRomanEncoding then
  begin
    Encoding := TMacRomanEncoding.Instance;
  end
  else if Name = TCosNames.MacExpertEncoding then
  begin
    Encoding := TMacExpertEncoding.Instance;
  end
  else
  begin
    Encoding := nil;
    Result := False;
  end;
end;

procedure TPdfEncoding.Add(const Code: Integer; const Name: string);
begin
  FCodeToName.AddOrSetValue(Code, Name);
  FNameToCode.TryAdd(Name, Code);
end;

procedure TPdfEncoding.Overwrite(const Code: Integer; const Name: string);
begin
  var OldName: string;
  if FCodeToName.TryGetValue(Code, OldName) then
  begin
    var OldCode: Integer;
    if FNameToCode.TryGetValue(OldName, OldCode) and (OldCode = Code) then
    begin
      FNameToCode.Remove(OldName);
    end;
  end;
  FNameToCode.AddOrSetValue(Name, Code);
  FCodeToName.AddOrSetValue(Code, Name);
end;

procedure TPdfEncoding.AddAllFrom(const Source: TPdfEncoding);
begin
  for var Pair in Source.FCodeToName do
  begin
    FCodeToName.AddOrSetValue(Pair.Key, Pair.Value);
  end;
  for var Pair in Source.FNameToCode do
  begin
    FNameToCode.AddOrSetValue(Pair.Key, Pair.Value);
  end;
end;

function TPdfEncoding.GetName(const Code: Integer): string;
begin
  if not FCodeToName.TryGetValue(Code, Result) then
  begin
    Result := '.notdef';
  end;
end;

function TPdfEncoding.Contains(const Name: string): Boolean;
begin
  Result := FNameToCode.ContainsKey(Name);
end;

function TPdfEncoding.Contains(const Code: Integer): Boolean;
begin
  Result := FCodeToName.ContainsKey(Code);
end;

function TPdfEncoding.CodeToNameMap: TDictionary<Integer, string>;
begin
  Result := FCodeToName;
end;

function TPdfEncoding.NameToCodeMap: TDictionary<string, Integer>;
begin
  Result := FNameToCode;
end;

{ TBuiltInEncoding }

constructor TBuiltInEncoding.Create(const CodeToName: TDictionary<Integer, string>);
begin
  inherited Create;
  for var Pair in CodeToName do
  begin
    Add(Pair.Key, Pair.Value);
  end;
end;

function TBuiltInEncoding.EncodingName: string;
begin
  Result := 'built-in (TTF)';
end;

{ TType1Encoding }

class function TType1Encoding.FromFontBox(const Encoding: TFontBoxEncoding): TType1Encoding;
begin
  Result := TType1Encoding.Create;
  try
    for var Pair in Encoding.CodeToNameMap do
    begin
      Result.Add(Pair.Key, Pair.Value);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TType1Encoding.FromMetrics(const Metrics: TFontMetrics): TType1Encoding;
begin
  Result := TType1Encoding.Create;
  try
    for var Metric in Metrics.CharMetrics do
    begin
      Result.Add(Metric.CharacterCode, Metric.Name);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TType1Encoding.EncodingName: string;
begin
  Result := 'built-in (Type 1)';
end;

{ TDictionaryEncoding }

constructor TDictionaryEncoding.Create(const Dictionary: TCosDictionary; const IsNonSymbolic: Boolean; const BuiltIn: TPdfEncoding);
begin
  inherited Create;
  FDifferences := TDictionary<Integer, string>.Create;
  FDictionary := Dictionary;
  FBaseEncoding := SelectBaseEncoding(IsNonSymbolic, BuiltIn);
  CopyBaseEncoding;
  ApplyDifferences;
end;

constructor TDictionaryEncoding.CreateForType3(const Dictionary: TCosDictionary);
begin
  inherited Create;
  FDifferences := TDictionary<Integer, string>.Create;
  FDictionary := Dictionary;
  // A name that is not an encoding leaves the base empty
  if TryGetNamedBase(FBaseEncoding) then
  begin
    // The specification says the Differences array is the complete encoding, but other viewers read the base as well
    CopyBaseEncoding;
  end;
  ApplyDifferences;
end;

destructor TDictionaryEncoding.Destroy;
begin
  FDifferences.Free;
  inherited;
end;

function TDictionaryEncoding.TryGetNamedBase(out Base: TPdfEncoding): Boolean;
begin
  var Value: TCosBase;
  Base := nil;
  Result := FDictionary.TryGetDictionaryObject(TCosNames.BaseEncoding, Value) and (Value is TCosName);
  if Result then
  begin
    Result := TPdfEncoding.TryGetInstance(TCosName(Value).Name, Base);
  end;
end;

function TDictionaryEncoding.SelectBaseEncoding(const IsNonSymbolic: Boolean; const BuiltIn: TPdfEncoding): TPdfEncoding;
begin
  if TryGetNamedBase(Result) then
  begin
    Exit;
  end;

  if IsNonSymbolic then
  begin
    // A non-symbolic font without a usable base encoding uses StandardEncoding
    Result := TStandardEncoding.Instance;
  end
  else if Assigned(BuiltIn) then
  begin
    // A symbolic font uses its own encoding
    Result := BuiltIn;
  end
  else
  begin
    raise EPdfException.Create('A symbolic font must have a built-in encoding');
  end;
end;

procedure TDictionaryEncoding.CopyBaseEncoding;
begin
  if Assigned(FBaseEncoding) then
  begin
    AddAllFrom(FBaseEncoding);
  end;
end;

procedure TDictionaryEncoding.ApplyDifferences;
begin
  var DiffArray: TCosArray;
  if not FDictionary.TryGetCosArray(TCosNames.Differences, DiffArray) then
  begin
    Exit;
  end;

  var CurrentIndex := -1;
  for var Position := 0 to DiffArray.Count - 1 do
  begin
    const Next = DiffArray.GetObject(Position);
    if Next is TCosNumber then
    begin
      CurrentIndex := TCosNumber(Next).IntValue;
    end
    else if Next is TCosName then
    begin
      const GlyphName = TCosName(Next).Name;
      Overwrite(CurrentIndex, GlyphName);
      FDifferences.AddOrSetValue(CurrentIndex, GlyphName);
      // Java's int wraps here
      if CurrentIndex = High(Integer) then
      begin
        CurrentIndex := Low(Integer);
      end
      else
      begin
        Inc(CurrentIndex);
      end;
    end;
  end;
end;

function TDictionaryEncoding.EncodingName: string;
begin
  if not Assigned(FBaseEncoding) then
  begin
    // The Differences array of a Type 3 font is the complete encoding
    Exit('differences');
  end;
  Result := FBaseEncoding.EncodingName + ' with differences';
end;

function TDictionaryEncoding.Differences: TDictionary<Integer, string>;
begin
  Result := FDifferences;
end;

end.
