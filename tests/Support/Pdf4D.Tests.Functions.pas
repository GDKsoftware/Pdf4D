// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Functions;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.DocumentContext;

type
  // What one "in:" line of a reference file says
  TFunctionEvaluation = record
    Input: TArray<Single>;
    Expected: TArray<Single>;
    // "out: !": PDFBox fails on this input, so only "does not raise" can be checked
    HasFailedInPdfBox: Boolean;
  end;

  // A "case:" block of a reference file (docs/golden-format.md): the keys of a function and its evaluations
  TFunctionCase = class
  private
    FName: string;
    FKeys: TDictionary<string, string>;
    FSubFunctions: TList<string>;
    FEvaluations: TList<TFunctionEvaluation>;
    FHasFailedToCreateInPdfBox: Boolean;

  public
    constructor Create(const Name: string);
    destructor Destroy; override;

    property Name: string read FName;
    property Keys: TDictionary<string, string> read FKeys;
    // The "sub2:" lines of a type 3 function
    property SubFunctions: TList<string> read FSubFunctions;
    property Evaluations: TList<TFunctionEvaluation> read FEvaluations;
    property HasFailedToCreateInPdfBox: Boolean read FHasFailedToCreateInPdfBox write FHasFailedToCreateInPdfBox;
  end;

  // Makes function dictionaries and streams for the tests, and the context with a log that collects the messages
  TFunctionTestBuilder = class
  private
    FOwned: TObjectList<TObject>;
    FMessages: TList<string>;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;

    procedure FillDictionary(const Dictionary: TCosDictionary; const FunctionType: Integer; const Entries: array of string);
    function NewSubFunctions(const SubFunctions: TList<string>): TCosArray;
    class function BytesOfCase(const FunctionCase: TFunctionCase): TBytes; static;
    class function ArrayKeyName(const Key: string): string; static;

  public
    constructor Create;
    destructor Destroy; override;

    // The numbers of Text, separated by blanks, as an array that the caller hands to a dictionary
    class function NewArray(const Text: string): TCosArray; static;
    class function ParseSingle(const Text: string): Single; static;
    class function ParseSingles(const Text: string): TArray<Single>; static;

    // A dictionary the builder owns, with /FunctionType and the entries that Entries names (key and text of an array, in pairs)
    function NewDictionary(const FunctionType: Integer; const Entries: array of string): TCosDictionary;
    // The same, as a stream that holds Data
    function NewStream(const FunctionType: Integer; const Entries: array of string; const Data: TBytes): TCosStream;
    // A type 4 function with this program (the text between and including the braces)
    function NewType4(const Domain, Range, Code: string): TCosStream;
    // A type 2 function
    function NewType2(const Domain, C0, C1: string; const Exponent: Single): TCosDictionary;
    // A type 3 function: the builder hands the sub functions (made by this builder) over to it
    function NewType3(const Domain, Bounds, Encode: string; const SubFunctions: array of TCosDictionary): TCosDictionary;
    // The function that a case of a reference file describes
    function NewFromCase(const FunctionCase: TFunctionCase): TCosDictionary;

    function WarningCount: Integer;

    property Context: TPDDocumentContext read FContext;
    property Messages: TList<string> read FMessages;
  end;

  TFunctionReferences = class
  private
    class procedure ReadLine(const Line: string; var Current: TFunctionCase; const Cases: TObjectList<TFunctionCase>); static;
    class function ReadEvaluation(const Text: string): TFunctionEvaluation; static;

  public
    // tests/reference/functions, found from the folder of the program
    class function Folder: string; static;
    // The cases of one reference file; the caller owns the objects
    class function ReadCases(const FileName: string): TObjectList<TFunctionCase>; static;
    class function Files: TArray<string>; static;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names;

const
  ReferenceFolderName = 'functions';

{ TFunctionCase }

constructor TFunctionCase.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
  FKeys := TDictionary<string, string>.Create;
  FSubFunctions := TList<string>.Create;
  FEvaluations := TList<TFunctionEvaluation>.Create;
end;

destructor TFunctionCase.Destroy;
begin
  FEvaluations.Free;
  FSubFunctions.Free;
  FKeys.Free;
  inherited;
end;

{ TFunctionTestBuilder }

constructor TFunctionTestBuilder.Create;
begin
  inherited Create;
  FOwned := TObjectList<TObject>.Create(True);
  FMessages := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      if Level = TPdfLogLevel.Warning then
      begin
        FMessages.Add(Message);
      end;
    end);
  FContext := TPDDocumentContext.Create(FLog, TPdfLoadOptions.Default);
end;

destructor TFunctionTestBuilder.Destroy;
begin
  FContext.Free;
  FLog.Free;
  FMessages.Free;
  FOwned.Free;
  inherited;
end;

class function TFunctionTestBuilder.ParseSingle(const Text: string): Single;
begin
  if Text = 'NaN' then
  begin
    Exit(NaN);
  end;
  if Text = 'Infinity' then
  begin
    Exit(Infinity);
  end;
  if Text = '-Infinity' then
  begin
    Exit(NegInfinity);
  end;
  Result := StrToFloat(Text, TFormatSettings.Invariant);
end;

class function TFunctionTestBuilder.ParseSingles(const Text: string): TArray<Single>;
begin
  const Parts = Text.Split([' '], TStringSplitOptions.ExcludeEmpty);
  SetLength(Result, Length(Parts));
  for var Index := 0 to Length(Parts) - 1 do
  begin
    Result[Index] := ParseSingle(Parts[Index]);
  end;
end;

class function TFunctionTestBuilder.NewArray(const Text: string): TCosArray;
begin
  Result := TCosArray.Create;
  try
    for var Value in ParseSingles(Text) do
    begin
      Result.Add(TCosFloat.Create(Value));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TFunctionTestBuilder.NewDictionary(const FunctionType: Integer; const Entries: array of string): TCosDictionary;
begin
  Result := TCosDictionary.Create;
  FOwned.Add(Result);
  FillDictionary(Result, FunctionType, Entries);
end;

function TFunctionTestBuilder.NewStream(const FunctionType: Integer; const Entries: array of string; const Data: TBytes): TCosStream;
begin
  Result := TCosStream.Create;
  FOwned.Add(Result);
  FillDictionary(Result, FunctionType, Entries);
  Result.SetRawData(Data);
end;

function TFunctionTestBuilder.NewType4(const Domain, Range, Code: string): TCosStream;
begin
  Result := NewStream(4, [TCosNames.Domain, Domain, TCosNames.Range, Range], TEncoding.ASCII.GetBytes(Code));
end;

function TFunctionTestBuilder.NewType2(const Domain, C0, C1: string; const Exponent: Single): TCosDictionary;
begin
  Result := NewDictionary(2, [TCosNames.Domain, Domain, TCosNames.C0, C0, TCosNames.C1, C1]);
  Result.SetItem(TCosNames.N, TCosFloat.Create(Exponent));
end;

function TFunctionTestBuilder.NewType3(const Domain, Bounds, Encode: string; const SubFunctions: array of TCosDictionary): TCosDictionary;
begin
  Result := NewDictionary(3, [TCosNames.Domain, Domain, TCosNames.Bounds, Bounds, TCosNames.Encode, Encode]);
  const Functions = TCosArray.Create;
  Result.SetItem(TCosNames.Functions, Functions);
  for var SubFunction in SubFunctions do
  begin
    FOwned.Extract(SubFunction);
    Functions.Add(SubFunction);
  end;
end;

function TFunctionTestBuilder.WarningCount: Integer;
begin
  Result := FMessages.Count;
end;

procedure TFunctionTestBuilder.FillDictionary(const Dictionary: TCosDictionary; const FunctionType: Integer; const Entries: array of string);
begin
  Dictionary.SetItem(TCosNames.FunctionType, TCosInteger.Create(FunctionType));
  var Index := 0;
  while Index < Length(Entries) do
  begin
    Dictionary.SetItem(Entries[Index], NewArray(Entries[Index + 1]));
    Inc(Index, 2);
  end;
end;

class function TFunctionTestBuilder.ArrayKeyName(const Key: string): string;
begin
  if Key = 'domain' then
  begin
    Exit(TCosNames.Domain);
  end;
  if Key = 'range' then
  begin
    Exit(TCosNames.Range);
  end;
  if Key = 'size' then
  begin
    Exit(TCosNames.Size);
  end;
  if Key = 'encode' then
  begin
    Exit(TCosNames.Encode);
  end;
  if Key = 'decode' then
  begin
    Exit(TCosNames.Decode);
  end;
  if Key = 'c0' then
  begin
    Exit(TCosNames.C0);
  end;
  if Key = 'c1' then
  begin
    Exit(TCosNames.C1);
  end;
  if Key = 'bounds' then
  begin
    Exit(TCosNames.Bounds);
  end;
  Result := '';
end;

// The samples of a type 0 function are hex digits (a half byte at the end is dropped, like the oracle does), the program of a
// type 4 function is the text of "code:" where \n stands for a line break
class function TFunctionTestBuilder.BytesOfCase(const FunctionCase: TFunctionCase): TBytes;
begin
  var Text: string;
  if FunctionCase.Keys.TryGetValue('code', Text) then
  begin
    Exit(TEncoding.ASCII.GetBytes(Text.Replace('\n', #10)));
  end;

  FunctionCase.Keys.TryGetValue('samples', Text);
  const Hex = Text.Replace(' ', '');
  SetLength(Result, Hex.Length div 2);
  for var Index := 0 to Length(Result) - 1 do
  begin
    Result[Index] := StrToInt('$' + Hex.Substring(2 * Index, 2));
  end;
end;

function TFunctionTestBuilder.NewSubFunctions(const SubFunctions: TList<string>): TCosArray;
begin
  Result := TCosArray.Create;
  try
    for var Description in SubFunctions do
    begin
      const Parts = Description.Split(['|']);
      const Child = TCosDictionary.Create;
      Result.Add(Child);
      FillDictionary(Child, 2, [TCosNames.Domain, '0 1', TCosNames.C0, Parts[0], TCosNames.C1, Parts[1]]);
      Child.SetItem(TCosNames.N, TCosFloat.Create(ParseSingle(Parts[2].Trim)));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TFunctionTestBuilder.NewFromCase(const FunctionCase: TFunctionCase): TCosDictionary;
begin
  const FunctionType = StrToInt(FunctionCase.Keys['type']);
  if FunctionType in [0, 4] then
  begin
    Result := NewStream(FunctionType, [], BytesOfCase(FunctionCase));
  end
  else
  begin
    Result := NewDictionary(FunctionType, []);
  end;

  for var Pair in FunctionCase.Keys do
  begin
    const KeyName = ArrayKeyName(Pair.Key);
    if KeyName <> '' then
    begin
      Result.SetItem(KeyName, NewArray(Pair.Value));
    end;
  end;
  var Text: string;
  if FunctionCase.Keys.TryGetValue('n', Text) then
  begin
    Result.SetItem(TCosNames.N, TCosFloat.Create(ParseSingle(Text)));
  end;
  if FunctionCase.Keys.TryGetValue('bps', Text) then
  begin
    Result.SetItem(TCosNames.BitsPerSample, TCosInteger.Create(StrToInt(Text)));
  end;
  if FunctionType = 3 then
  begin
    Result.SetItem(TCosNames.Functions, NewSubFunctions(FunctionCase.SubFunctions));
  end;
end;

{ TFunctionReferences }

class function TFunctionReferences.Folder: string;
begin
  var Current := TPath.GetDirectoryName(ParamStr(0));
  while Current <> '' do
  begin
    for var Candidate in [TPath.Combine(Current, 'reference'), TPath.Combine(TPath.Combine(Current, 'tests'), 'reference')] do
    begin
      const Found = TPath.Combine(Candidate, ReferenceFolderName);
      if TDirectory.Exists(Found) then
      begin
        Exit(Found);
      end;
    end;

    const Parent = TPath.GetDirectoryName(Current);
    if Parent = Current then
    begin
      Break;
    end;
    Current := Parent;
  end;
  raise EFileNotFoundException.Create('The folder tests/reference/functions was not found');
end;

class function TFunctionReferences.Files: TArray<string>;
begin
  Result := TDirectory.GetFiles(Folder, '*.txt');
  TArray.Sort<string>(Result);
end;

class function TFunctionReferences.ReadEvaluation(const Text: string): TFunctionEvaluation;
begin
  const OutMarker = ' out:';
  const MarkerPosition = Text.IndexOf(OutMarker);
  Result.Input := TFunctionTestBuilder.ParseSingles(Text.Substring(0, MarkerPosition));
  const Outputs = Text.Substring(MarkerPosition + OutMarker.Length).Trim;
  Result.HasFailedInPdfBox := (Outputs = '!');
  if Result.HasFailedInPdfBox then
  begin
    Result.Expected := nil;
  end
  else
  begin
    Result.Expected := TFunctionTestBuilder.ParseSingles(Outputs);
  end;
end;

class procedure TFunctionReferences.ReadLine(const Line: string; var Current: TFunctionCase; const Cases: TObjectList<TFunctionCase>);
begin
  const Colon = Line.IndexOf(':');
  const Key = Line.Substring(0, Colon).Trim;
  const Value = Line.Substring(Colon + 1).Trim;
  if Key = 'case' then
  begin
    Current := TFunctionCase.Create(Value);
    Cases.Add(Current);
  end
  else if Key = 'create' then
  begin
    Current.HasFailedToCreateInPdfBox := True;
  end
  else if Key = 'in' then
  begin
    Current.Evaluations.Add(ReadEvaluation(' ' + Value));
  end
  else if Key = 'sub2' then
  begin
    Current.SubFunctions.Add(Value);
  end
  else
  begin
    Current.Keys.AddOrSetValue(Key, Value);
  end;
end;

class function TFunctionReferences.ReadCases(const FileName: string): TObjectList<TFunctionCase>;
begin
  Result := TObjectList<TFunctionCase>.Create(True);
  try
    var Current: TFunctionCase := nil;
    for var Line in TFile.ReadAllLines(FileName, TEncoding.UTF8) do
    begin
      if (Line.Trim <> '') and not Line.StartsWith('#') then
      begin
        ReadLine(Line.Trim, Current, Result);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
