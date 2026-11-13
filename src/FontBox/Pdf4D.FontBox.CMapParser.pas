// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cmap/CMapParser.java (3.0.8)
unit Pdf4D.FontBox.CMapParser;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.CMap,
  Pdf4D.IO.RandomAccessRead;

type
  {$SCOPEDENUMS ON}
  TCMapTokenKind = (EndOfData, OperatorName, LiteralName, IntegerNumber, FloatNumber, TextValue, ByteString, ByteList, DictionaryValue);
  {$SCOPEDENUMS OFF}

  // One token of the PostScript-like syntax of a CMap. A list keeps only its byte strings, the one thing that is used
  // of it; a dictionary keeps nothing.
  TCMapToken = record
    Kind: TCMapTokenKind;
    Text: string;
    IntegerValue: Integer;
    FloatValue: Double;
    Data: TBytes;
    // The byte strings of a list
    Items: TArray<TBytes>;
    // All elements of a list, also those that are not byte strings
    ItemCount: Integer;
    HasOtherItems: Boolean;

    function IsNumber: Boolean;
    function IsText(const Expected: string): Boolean;
  end;

  // Parses CMaps, embedded ones (ToUnicode, a CMap stream) and the predefined ones of the resources
  TCMapParser = class
  private
    const MaxTokenNesting = 100;
    const MaxUseCMapDepth = 8;
    const TokenBufferSize = 512;

  private
    FStrictMode: Boolean;
    FLog: TPdfLog;
    FTokenBuffer: TBytes;
    FTokenNesting: Integer;
    FUseCMapDepth: Integer;
    FHasWarnedAboutLimit: Boolean;
    FHasWarnedAboutLength: Boolean;

    class function IsWhitespaceOrEOF(const Value: Integer): Boolean; static;
    class function IsDelimiter(const Value: Integer): Boolean; static;
    class function IsDigit(const Value: Integer): Boolean; static;
    class function AreBytesEqual(const First, Second: TBytes): Boolean; static;
    class function ToIntSaturated(const Value: Double): Integer; static;
    class function CreateStringFromBytes(const Value: TBytes): string; static;
    class function Increment(const Data: TBytes; const Position: Integer; const UseStrictMode: Boolean): Boolean; static;

    procedure Warn(const Message: string); overload;
    procedure Warn(const Fmt: string; const Args: array of const); overload;
    procedure WarnAboutLimit;
    procedure WarnAboutLength;

    function ParseNextToken(const Source: TRandomAccessRead): TCMapToken;
    function ParseInteger(const Source: TRandomAccessRead): Integer;
    function ParseByteArray(const Source: TRandomAccessRead): TBytes;
    function ReadArray(const Source: TRandomAccessRead): TCMapToken;
    function ReadString(const Source: TRandomAccessRead): TCMapToken;
    function ReadLine(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
    function ReadLiteralName(const Source: TRandomAccessRead): TCMapToken;
    function ReadOperator(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
    function ReadNumber(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
    function ReadDictionary(const Source: TRandomAccessRead): TCMapToken;
    function ReadHexString(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
    procedure ReadDictionaryEntries(const Source: TRandomAccessRead);
    procedure ReadUntilEndOfLine(const Source: TRandomAccessRead; const Builder: TStringBuilder);
    procedure EnterNesting;

    function ParseSource(const Source: TRandomAccessRead): TCMap;
    procedure ParseOperator(const Op: string; const PreviousToken: TCMapToken; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseCountedOperator(const Op: string; const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseUseCMap(const UseCMapName: string; const Result: TCMap);
    procedure ParseLiteralName(const Literal: string; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseVersion(const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseIntegerField(const Source: TRandomAccessRead; const Result: TCMap; const Field: string);
    procedure ParseTextField(const Source: TRandomAccessRead; const Result: TCMap; const Field: string);
    procedure CheckExpectedOperator(const Token: TCMapToken; const ExpectedOperatorName, RangeName: string);
    procedure ParseBegincodespacerange(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseBeginbfchar(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseBegincidrange(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseBegincidchar(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseBeginbfrange(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
    procedure ParseBfRangeValue(const Token: TCMapToken; const StartCode: TBytes; const Start, EndCode: Integer; const Result: TCMap);
    procedure AddCharMapping(const Result: TCMap; const Code: TBytes; const Value: string);
    procedure AddMappingFrombfrangeList(const Result: TCMap; const StartCode: TBytes; const Token: TCMapToken);
    procedure AddMappingFrombfrange(const Result: TCMap; const StartCode: TBytes; const Values: Integer; const TokenBytes: TBytes);
    procedure AddIdentityBfRange(const Result: TCMap; const StartCode, TokenBytes: TBytes);

  public
    constructor Create(const StrictMode: Boolean); overload;
    // Log is not owned and may be nil
    constructor Create(const StrictMode: Boolean; const Log: TPdfLog); overload;
    destructor Destroy; override;

    // The caller owns the result. Raises EPdfParseException for a CMap that cannot be read.
    function Parse(const Source: TRandomAccessRead): TCMap;
    // Parses the predefined CMap of that name from the resources, in non-strict mode. The caller owns the result.
    function ParsePredefined(const Name: string): TCMap;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Resources.CMap;

const
  MarkEndOfDictionary = '>>';
  MarkEndOfArray = ']';
  OperatorEndCMap = 'endcmap';
  OperatorUseCMap = 'usecmap';
  OperatorBeginCodespaceRange = 'begincodespacerange';
  OperatorEndCodespaceRange = 'endcodespacerange';
  OperatorBeginBfChar = 'beginbfchar';
  OperatorEndBfChar = 'endbfchar';
  OperatorBeginBfRange = 'beginbfrange';
  OperatorEndBfRange = 'endbfrange';
  OperatorBeginCidChar = 'begincidchar';
  OperatorEndCidChar = 'endcidchar';
  OperatorBeginCidRange = 'begincidrange';
  OperatorEndCidRange = 'endcidrange';
  FieldWMode = 'WMode';
  FieldCMapName = 'CMapName';
  FieldCMapVersion = 'CMapVersion';
  FieldCMapType = 'CMapType';
  FieldRegistry = 'Registry';
  FieldOrdering = 'Ordering';
  FieldSupplement = 'Supplement';
  MaxByteValue = $FF;
  ByteTab = $09;
  ByteSpace = $20;
  ByteReturn = $0D;
  ByteLineFeed = $0A;
  EndOfStream = -1;

{ TCMapToken }

function TCMapToken.IsNumber: Boolean;
begin
  Result := ((Kind = TCMapTokenKind.IntegerNumber) or (Kind = TCMapTokenKind.FloatNumber));
end;

function TCMapToken.IsText(const Expected: string): Boolean;
begin
  Result := ((Kind = TCMapTokenKind.TextValue) and (Text = Expected));
end;

{ TCMapParser }

constructor TCMapParser.Create(const StrictMode: Boolean);
begin
  Create(StrictMode, nil);
end;

constructor TCMapParser.Create(const StrictMode: Boolean; const Log: TPdfLog);
begin
  inherited Create;
  FStrictMode := StrictMode;
  FLog := Log;
  SetLength(FTokenBuffer, TokenBufferSize);
end;

destructor TCMapParser.Destroy;
begin
  FTokenBuffer := nil;
  inherited;
end;

function TCMapParser.ParsePredefined(const Name: string): TCMap;
begin
  var Data: TBytes;
  if not TPdfCMapResources.TryLoad(Name, Data) then
  begin
    raise EPdfParseException.CreateFmt('Could not find the predefined CMap %s', [Name]);
  end;

  FStrictMode := False;
  const Source = TRandomAccessRead.FromBytes(Data);
  try
    Result := Parse(Source);
  finally
    Source.Free;
  end;
end;

function TCMapParser.Parse(const Source: TRandomAccessRead): TCMap;
begin
  FHasWarnedAboutLimit := False;
  FHasWarnedAboutLength := False;
  FTokenNesting := 0;
  FUseCMapDepth := 0;
  Result := ParseSource(Source);
end;

function TCMapParser.ParseSource(const Source: TRandomAccessRead): TCMap;
begin
  Result := TCMap.Create;
  try
    var PreviousToken := Default(TCMapToken);
    var Token := ParseNextToken(Source);
    while Token.Kind <> TCMapTokenKind.EndOfData do
    begin
      if Token.Kind = TCMapTokenKind.OperatorName then
      begin
        if Token.Text = OperatorEndCMap then
        begin
          Break;
        end;
        ParseOperator(Token.Text, PreviousToken, Source, Result);
      end
      else if Token.Kind = TCMapTokenKind.LiteralName then
      begin
        ParseLiteralName(Token.Text, Source, Result);
      end;
      PreviousToken := Token;
      Token := ParseNextToken(Source);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TCMapParser.ParseOperator(const Op: string; const PreviousToken: TCMapToken; const Source: TRandomAccessRead; const Result: TCMap);
begin
  if (Op = OperatorUseCMap) and (PreviousToken.Kind = TCMapTokenKind.LiteralName) then
  begin
    ParseUseCMap(PreviousToken.Text, Result);
  end
  else if PreviousToken.IsNumber then
  begin
    var Count := PreviousToken.IntegerValue;
    if PreviousToken.Kind = TCMapTokenKind.FloatNumber then
    begin
      Count := ToIntSaturated(PreviousToken.FloatValue);
    end;
    const IsCidRangeOfFloat = ((Op = OperatorBeginCidRange) and (PreviousToken.Kind <> TCMapTokenKind.IntegerNumber));
    if not IsCidRangeOfFloat then
    begin
      ParseCountedOperator(Op, Count, Source, Result);
    end;
  end;
end;

procedure TCMapParser.ParseCountedOperator(const Op: string; const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
begin
  if Op = OperatorBeginCodespaceRange then
  begin
    ParseBegincodespacerange(Count, Source, Result);
  end
  else if Op = OperatorBeginBfChar then
  begin
    ParseBeginbfchar(Count, Source, Result);
  end
  else if Op = OperatorBeginBfRange then
  begin
    ParseBeginbfrange(Count, Source, Result);
  end
  else if Op = OperatorBeginCidChar then
  begin
    ParseBegincidchar(Count, Source, Result);
  end
  else if Op = OperatorBeginCidRange then
  begin
    ParseBegincidrange(Count, Source, Result);
  end;
end;

procedure TCMapParser.ParseUseCMap(const UseCMapName: string; const Result: TCMap);
begin
  var Data: TBytes;
  if not TPdfCMapResources.TryLoad(UseCMapName, Data) then
  begin
    raise EPdfParseException.CreateFmt('Could not find the referenced CMap %s', [UseCMapName]);
  end;

  if FUseCMapDepth >= MaxUseCMapDepth then
  begin
    Warn('CMap %s is used too deeply, usecmap is ignored', [UseCMapName]);
    Exit;
  end;

  const Source = TRandomAccessRead.FromBytes(Data);
  try
    Inc(FUseCMapDepth);
    try
      const UsedCMap = ParseSource(Source);
      try
        Result.UseCMap(UsedCMap);
      finally
        UsedCMap.Free;
      end;
    finally
      Dec(FUseCMapDepth);
    end;
  finally
    Source.Free;
  end;

  if Result.IsFull then
  begin
    WarnAboutLimit;
  end;
end;

procedure TCMapParser.ParseLiteralName(const Literal: string; const Source: TRandomAccessRead; const Result: TCMap);
begin
  if Literal = FieldWMode then
  begin
    ParseIntegerField(Source, Result, FieldWMode);
  end
  else if Literal = FieldCMapName then
  begin
    const Next = ParseNextToken(Source);
    if Next.Kind = TCMapTokenKind.LiteralName then
    begin
      Result.Name := Next.Text;
    end;
  end
  else if Literal = FieldCMapVersion then
  begin
    ParseVersion(Source, Result);
  end
  else if Literal = FieldCMapType then
  begin
    ParseIntegerField(Source, Result, FieldCMapType);
  end
  else if (Literal = FieldRegistry) or (Literal = FieldOrdering) then
  begin
    ParseTextField(Source, Result, Literal);
  end
  else if Literal = FieldSupplement then
  begin
    ParseIntegerField(Source, Result, FieldSupplement);
  end;
end;

procedure TCMapParser.ParseVersion(const Source: TRandomAccessRead; const Result: TCMap);
begin
  const Next = ParseNextToken(Source);
  case Next.Kind of
    TCMapTokenKind.IntegerNumber:
    begin
      Result.Version := IntToStr(Next.IntegerValue);
    end;
    TCMapTokenKind.FloatNumber:
    begin
      // Java prints a double with at least one decimal
      var Version := Next.FloatValue.ToString(TFormatSettings.Invariant);
      if not Version.Contains('.') then
      begin
        Version := Version + '.0';
      end;
      Result.Version := Version;
    end;
    TCMapTokenKind.TextValue:
    begin
      Result.Version := Next.Text;
    end;
  else
    // Any other token is no version and is dropped
  end;
end;

procedure TCMapParser.ParseIntegerField(const Source: TRandomAccessRead; const Result: TCMap; const Field: string);
begin
  const Next = ParseNextToken(Source);
  if Next.Kind <> TCMapTokenKind.IntegerNumber then
  begin
    Exit;
  end;

  if Field = FieldWMode then
  begin
    Result.WMode := Next.IntegerValue;
  end
  else if Field = FieldCMapType then
  begin
    Result.CMapType := Next.IntegerValue;
  end
  else if Field = FieldSupplement then
  begin
    Result.Supplement := Next.IntegerValue;
  end;
end;

procedure TCMapParser.ParseTextField(const Source: TRandomAccessRead; const Result: TCMap; const Field: string);
begin
  const Next = ParseNextToken(Source);
  if Next.Kind <> TCMapTokenKind.TextValue then
  begin
    Exit;
  end;

  if Field = FieldRegistry then
  begin
    Result.Registry := Next.Text;
  end
  else
  begin
    Result.Ordering := Next.Text;
  end;
end;

procedure TCMapParser.CheckExpectedOperator(const Token: TCMapToken; const ExpectedOperatorName, RangeName: string);
begin
  if Token.Text <> ExpectedOperatorName then
  begin
    raise EPdfParseException.CreateFmt('Error : ~%s contains an unexpected operator : %s', [RangeName, Token.Text]);
  end;
end;

procedure TCMapParser.ParseBegincodespacerange(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
begin
  for var Index := 1 to Count do
  begin
    const NextToken = ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.OperatorName then
    begin
      CheckExpectedOperator(NextToken, OperatorEndCodespaceRange, 'codespacerange');
      Break;
    end;
    if NextToken.Kind <> TCMapTokenKind.ByteString then
    begin
      raise EPdfParseException.Create('start range missing');
    end;

    const EndRange = ParseByteArray(Source);
    try
      Result.AddCodespaceRange(TCodespaceRange.Create(NextToken.Data, EndRange));
    except
      on Error: EArgumentException do
      begin
        raise EPdfParseException.Create(Error.Message);
      end;
    end;
  end;
end;

procedure TCMapParser.ParseBeginbfchar(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
begin
  for var Index := 1 to Count do
  begin
    var NextToken := ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.OperatorName then
    begin
      CheckExpectedOperator(NextToken, OperatorEndBfChar, 'bfchar');
      Break;
    end;
    if NextToken.Kind <> TCMapTokenKind.ByteString then
    begin
      raise EPdfParseException.Create('input code missing');
    end;

    const InputCode = NextToken.Data;
    NextToken := ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.ByteString then
    begin
      AddCharMapping(Result, InputCode, CreateStringFromBytes(NextToken.Data));
    end
    else if NextToken.Kind = TCMapTokenKind.LiteralName then
    begin
      AddCharMapping(Result, InputCode, NextToken.Text);
    end
    else
    begin
      raise EPdfParseException.Create('Error parsing CMap beginbfchar, expected a string or a name');
    end;
  end;
end;

procedure TCMapParser.ParseBegincidrange(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
begin
  for var Index := 1 to Count do
  begin
    const NextToken = ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.OperatorName then
    begin
      CheckExpectedOperator(NextToken, OperatorEndCidRange, 'cidrange');
      Break;
    end;
    if NextToken.Kind <> TCMapTokenKind.ByteString then
    begin
      raise EPdfParseException.Create('start code missing');
    end;

    const StartCode = NextToken.Data;
    const EndCode = ParseByteArray(Source);
    const MappedCode = ParseInteger(Source);
    if Length(StartCode) <> Length(EndCode) then
    begin
      raise EPdfParseException.Create('Error : ~cidrange values must not have different byte lengths');
    end;

    if AreBytesEqual(StartCode, EndCode) then
    begin
      Result.AddCIDMapping(StartCode, MappedCode);
    end
    else
    begin
      Result.AddCIDRangeMapping(StartCode, EndCode, MappedCode);
    end;

    if Result.IsFull then
    begin
      WarnAboutLimit;
      Exit;
    end;
  end;
end;

procedure TCMapParser.ParseBegincidchar(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
begin
  for var Index := 1 to Count do
  begin
    const NextToken = ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.OperatorName then
    begin
      CheckExpectedOperator(NextToken, OperatorEndCidChar, 'cidchar');
      Break;
    end;
    if NextToken.Kind <> TCMapTokenKind.ByteString then
    begin
      raise EPdfParseException.Create('input code missing');
    end;

    const MappedCID = ParseInteger(Source);
    Result.AddCIDMapping(NextToken.Data, MappedCID);

    if Result.IsFull then
    begin
      WarnAboutLimit;
      Exit;
    end;
  end;
end;

procedure TCMapParser.ParseBeginbfrange(const Count: Integer; const Source: TRandomAccessRead; const Result: TCMap);
begin
  for var Index := 1 to Count do
  begin
    var NextToken := ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.OperatorName then
    begin
      CheckExpectedOperator(NextToken, OperatorEndBfRange, 'bfrange');
      Break;
    end;
    if NextToken.Kind <> TCMapTokenKind.ByteString then
    begin
      raise EPdfParseException.Create('start code missing');
    end;

    const StartCode = NextToken.Data;
    NextToken := ParseNextToken(Source);
    if NextToken.Kind = TCMapTokenKind.OperatorName then
    begin
      CheckExpectedOperator(NextToken, OperatorEndBfRange, 'bfrange');
      Break;
    end;
    if NextToken.Kind <> TCMapTokenKind.ByteString then
    begin
      raise EPdfParseException.Create('end code missing');
    end;

    const Start = TCMap.ToInt(StartCode);
    const EndCode = TCMap.ToInt(NextToken.Data);
    if EndCode < Start then
    begin
      Warn('The bfrange from %d to %d ends before it starts, the rest of the bfrange is ignored', [Start, EndCode]);
      Break;
    end;

    ParseBfRangeValue(ParseNextToken(Source), StartCode, Start, EndCode, Result);
    if Result.IsFull then
    begin
      WarnAboutLimit;
      Exit;
    end;
  end;
end;

procedure TCMapParser.ParseBfRangeValue(const Token: TCMapToken; const StartCode: TBytes; const Start, EndCode: Integer; const Result: TCMap);
begin
  // The Java code subtracts in int arithmetic, so a range over the sign bit wraps
  const Span = Integer(Cardinal((Int64(EndCode) - Start) and $FFFFFFFF));
  if Token.Kind = TCMapTokenKind.ByteList then
  begin
    const HasEnoughItems = ((Token.ItemCount > 0) and (Token.ItemCount >= Span));
    if HasEnoughItems then
    begin
      AddMappingFrombfrangeList(Result, StartCode, Token);
    end;
  end
  else if (Token.Kind = TCMapTokenKind.ByteString) and (Length(Token.Data) > 0) then
  begin
    const IsIdentityOfAllCodes = ((Length(Token.Data) = 2) and (Length(StartCode) >= 2) and (Start = 0) and (EndCode = $FFFF) and
                                  (Token.Data[0] = 0) and (Token.Data[1] = 0));
    if IsIdentityOfAllCodes then
    begin
      AddIdentityBfRange(Result, StartCode, Token.Data);
    end
    else
    begin
      AddMappingFrombfrange(Result, StartCode, Integer(Cardinal((Int64(Span) + 1) and $FFFFFFFF)), Token.Data);
    end;
  end;
end;

procedure TCMapParser.AddCharMapping(const Result: TCMap; const Code: TBytes; const Value: string);
begin
  const HasSupportedLength = ((Length(Code) >= 1) and (Length(Code) <= 4));
  if not HasSupportedLength then
  begin
    WarnAboutLength;
  end;
  Result.AddCharMapping(Code, Value);
end;

procedure TCMapParser.AddMappingFrombfrangeList(const Result: TCMap; const StartCode: TBytes; const Token: TCMapToken);
begin
  if Token.HasOtherItems then
  begin
    raise EPdfParseException.Create('Error parsing CMap bfrange, an array item is not a string');
  end;

  const Code = Copy(StartCode);
  for var Item in Token.Items do
  begin
    AddCharMapping(Result, Code, CreateStringFromBytes(Item));
    Increment(Code, Length(Code) - 1, False);
    if Result.IsFull then
    begin
      Exit;
    end;
  end;
end;

procedure TCMapParser.AddMappingFrombfrange(const Result: TCMap; const StartCode: TBytes; const Values: Integer; const TokenBytes: TBytes);
begin
  const Code = Copy(StartCode);
  const Value = Copy(TokenBytes);
  for var Index := 1 to Values do
  begin
    if Result.IsFull then
    begin
      Exit;
    end;

    AddCharMapping(Result, Code, CreateStringFromBytes(Value));
    if not Increment(Value, Length(Value) - 1, FStrictMode) then
    begin
      Break;
    end;
    Increment(Code, Length(Code) - 1, False);
  end;
end;

procedure TCMapParser.AddIdentityBfRange(const Result: TCMap; const StartCode, TokenBytes: TBytes);
begin
  const Code = Copy(StartCode);
  const Value = Copy(TokenBytes);
  for var HighByte := 0 to 255 do
  begin
    Code[0] := HighByte;
    Code[1] := 0;
    Value[0] := HighByte;
    Value[1] := 0;
    AddMappingFrombfrange(Result, Code, 256, Value);
  end;
end;

procedure TCMapParser.EnterNesting;
begin
  if FTokenNesting >= MaxTokenNesting then
  begin
    raise EPdfParseException.CreateFmt('CMap tokens are nested deeper than %d levels', [MaxTokenNesting]);
  end;
end;

function TCMapParser.ParseNextToken(const Source: TRandomAccessRead): TCMapToken;
begin
  Result := Default(TCMapToken);
  var NextByte := Source.Read;
  while (NextByte = ByteTab) or (NextByte = ByteSpace) or (NextByte = ByteReturn) or (NextByte = ByteLineFeed) do
  begin
    NextByte := Source.Read;
  end;

  case NextByte of
    Ord('%'):
    begin
      Result := ReadLine(Source, NextByte);
    end;
    Ord('('):
    begin
      Result := ReadString(Source);
    end;
    Ord('>'):
    begin
      if Source.Read <> Ord('>') then
      begin
        raise EPdfParseException.Create('Error: expected the end of a dictionary.');
      end;
      Result.Kind := TCMapTokenKind.TextValue;
      Result.Text := MarkEndOfDictionary;
    end;
    Ord(']'):
    begin
      Result.Kind := TCMapTokenKind.TextValue;
      Result.Text := MarkEndOfArray;
    end;
    Ord('['):
    begin
      Result := ReadArray(Source);
    end;
    Ord('<'):
    begin
      Result := ReadDictionary(Source);
    end;
    Ord('/'):
    begin
      Result := ReadLiteralName(Source);
    end;
    EndOfStream:
    begin
      Result.Kind := TCMapTokenKind.EndOfData;
    end;
    Ord('0')..Ord('9'):
    begin
      Result := ReadNumber(Source, NextByte);
    end;
  else
    Result := ReadOperator(Source, NextByte);
  end;
end;

function TCMapParser.ParseInteger(const Source: TRandomAccessRead): Integer;
begin
  const NextToken = ParseNextToken(Source);
  if NextToken.Kind = TCMapTokenKind.EndOfData then
  begin
    raise EPdfParseException.Create('expected integer value is missing');
  end;
  if NextToken.Kind <> TCMapTokenKind.IntegerNumber then
  begin
    raise EPdfParseException.Create('invalid type for next token');
  end;
  Result := NextToken.IntegerValue;
end;

function TCMapParser.ParseByteArray(const Source: TRandomAccessRead): TBytes;
begin
  const NextToken = ParseNextToken(Source);
  if NextToken.Kind = TCMapTokenKind.EndOfData then
  begin
    raise EPdfParseException.Create('expected byte[] value is missing');
  end;
  if NextToken.Kind <> TCMapTokenKind.ByteString then
  begin
    raise EPdfParseException.Create('invalid type for next token');
  end;
  Result := NextToken.Data;
end;

function TCMapParser.ReadArray(const Source: TRandomAccessRead): TCMapToken;
begin
  EnterNesting;
  Inc(FTokenNesting);
  try
    Result := Default(TCMapToken);
    Result.Kind := TCMapTokenKind.ByteList;
    var ByteItemCount := 0;
    var NextToken := ParseNextToken(Source);
    while (NextToken.Kind <> TCMapTokenKind.EndOfData) and (not NextToken.IsText(MarkEndOfArray)) do
    begin
      if NextToken.Kind = TCMapTokenKind.ByteString then
      begin
        if ByteItemCount = Length(Result.Items) then
        begin
          SetLength(Result.Items, Max(16, ByteItemCount * 2));
        end;
        Result.Items[ByteItemCount] := NextToken.Data;
        Inc(ByteItemCount);
      end
      else
      begin
        Result.HasOtherItems := True;
      end;
      Inc(Result.ItemCount);
      NextToken := ParseNextToken(Source);
    end;
    SetLength(Result.Items, ByteItemCount);
  finally
    Dec(FTokenNesting);
  end;
end;

function TCMapParser.ReadString(const Source: TRandomAccessRead): TCMapToken;
begin
  Result := Default(TCMapToken);
  Result.Kind := TCMapTokenKind.TextValue;
  const Builder = TStringBuilder.Create;
  try
    var StringByte := Source.Read;
    while (StringByte <> EndOfStream) and (StringByte <> Ord(')')) do
    begin
      Builder.Append(Char(StringByte));
      StringByte := Source.Read;
    end;
    Result.Text := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TCMapParser.ReadLine(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
begin
  Result := Default(TCMapToken);
  Result.Kind := TCMapTokenKind.TextValue;
  const Builder = TStringBuilder.Create;
  try
    Builder.Append(Char(FirstByte));
    ReadUntilEndOfLine(Source, Builder);
    Result.Text := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TCMapParser.ReadUntilEndOfLine(const Source: TRandomAccessRead; const Builder: TStringBuilder);
begin
  var NextByte := Source.Read;
  while (NextByte <> EndOfStream) and (NextByte <> ByteReturn) and (NextByte <> ByteLineFeed) do
  begin
    Builder.Append(Char(NextByte));
    NextByte := Source.Read;
  end;
end;

function TCMapParser.ReadLiteralName(const Source: TRandomAccessRead): TCMapToken;
begin
  Result := Default(TCMapToken);
  Result.Kind := TCMapTokenKind.LiteralName;
  const Builder = TStringBuilder.Create;
  try
    var StringByte := Source.Read;
    while (not IsWhitespaceOrEOF(StringByte)) and (not IsDelimiter(StringByte)) do
    begin
      Builder.Append(Char(StringByte));
      StringByte := Source.Read;
    end;
    if IsDelimiter(StringByte) then
    begin
      Source.Rewind(1);
    end;
    Result.Text := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TCMapParser.ReadOperator(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
begin
  Result := Default(TCMapToken);
  Result.Kind := TCMapTokenKind.OperatorName;
  const Builder = TStringBuilder.Create;
  try
    Builder.Append(Char(FirstByte));
    var NextByte := Source.Read;
    while (not IsWhitespaceOrEOF(NextByte)) and (not IsDelimiter(NextByte)) and (not IsDigit(NextByte)) do
    begin
      Builder.Append(Char(NextByte));
      NextByte := Source.Read;
    end;
    if IsDelimiter(NextByte) or IsDigit(NextByte) then
    begin
      Source.Rewind(1);
    end;
    Result.Text := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TCMapParser.ReadNumber(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
begin
  Result := Default(TCMapToken);
  const Builder = TStringBuilder.Create;
  try
    Builder.Append(Char(FirstByte));
    var NextByte := Source.Read;
    while (not IsWhitespaceOrEOF(NextByte)) and (IsDigit(NextByte) or (NextByte = Ord('.'))) do
    begin
      Builder.Append(Char(NextByte));
      NextByte := Source.Read;
    end;
    if NextByte <> EndOfStream then
    begin
      Source.Rewind(1);
    end;

    const Value = Builder.ToString;
    if Value.Contains('.') then
    begin
      Result.Kind := TCMapTokenKind.FloatNumber;
      var FloatText := Value;
      if Value.EndsWith('.') then
      begin
        FloatText := Value + '0';
      end;
      if not TryStrToFloat(FloatText, Result.FloatValue, TFormatSettings.Invariant) then
      begin
        raise EPdfParseException.CreateFmt('Invalid number ''%s''', [Value]);
      end;
    end
    else
    begin
      Result.Kind := TCMapTokenKind.IntegerNumber;
      if not TryStrToInt(Value, Result.IntegerValue) then
      begin
        raise EPdfParseException.CreateFmt('Invalid number ''%s''', [Value]);
      end;
    end;
  finally
    Builder.Free;
  end;
end;

function TCMapParser.ReadDictionary(const Source: TRandomAccessRead): TCMapToken;
begin
  const TheNextByte = Source.Read;
  if TheNextByte <> Ord('<') then
  begin
    Exit(ReadHexString(Source, TheNextByte));
  end;

  EnterNesting;
  Inc(FTokenNesting);
  try
    ReadDictionaryEntries(Source);
  finally
    Dec(FTokenNesting);
  end;
  Result := Default(TCMapToken);
  Result.Kind := TCMapTokenKind.DictionaryValue;
end;

procedure TCMapParser.ReadDictionaryEntries(const Source: TRandomAccessRead);
begin
  var Key := ParseNextToken(Source);
  while (Key.Kind = TCMapTokenKind.LiteralName) and (Key.Text <> MarkEndOfDictionary) do
  begin
    // The value is read to move on; a dictionary of a CMap is not used
    ParseNextToken(Source);
    Key := ParseNextToken(Source);
  end;
end;

function TCMapParser.ReadHexString(const Source: TRandomAccessRead; const FirstByte: Integer): TCMapToken;
begin
  Result := Default(TCMapToken);
  Result.Kind := TCMapTokenKind.ByteString;
  var Multiplier := 16;
  var BufferIndex := -1;
  var TheNextByte := FirstByte;
  while (TheNextByte <> EndOfStream) and (TheNextByte <> Ord('>')) do
  begin
    if IsWhitespaceOrEOF(TheNextByte) then
    begin
      TheNextByte := Source.Read;
      Continue;
    end;

    var IntValue: Integer;
    if (TheNextByte >= Ord('0')) and (TheNextByte <= Ord('9')) then
    begin
      IntValue := TheNextByte - Ord('0');
    end
    else if (TheNextByte >= Ord('A')) and (TheNextByte <= Ord('F')) then
    begin
      IntValue := 10 + TheNextByte - Ord('A');
    end
    else if (TheNextByte >= Ord('a')) and (TheNextByte <= Ord('f')) then
    begin
      IntValue := 10 + TheNextByte - Ord('a');
    end
    else
    begin
      raise EPdfParseException.CreateFmt('Error: expected hex character and not %s:%d', [Char(TheNextByte), TheNextByte]);
    end;

    IntValue := IntValue * Multiplier;
    if Multiplier = 16 then
    begin
      Inc(BufferIndex);
      if BufferIndex >= Length(FTokenBuffer) then
      begin
        raise EPdfParseException.CreateFmt('cmap token is larger than buffer size %d', [Length(FTokenBuffer)]);
      end;
      FTokenBuffer[BufferIndex] := 0;
      Multiplier := 1;
    end
    else
    begin
      Multiplier := 16;
    end;
    FTokenBuffer[BufferIndex] := FTokenBuffer[BufferIndex] + IntValue;
    TheNextByte := Source.Read;
  end;

  SetLength(Result.Data, BufferIndex + 1);
  if BufferIndex >= 0 then
  begin
    Move(FTokenBuffer[0], Result.Data[0], BufferIndex + 1);
  end;
end;

class function TCMapParser.IsWhitespaceOrEOF(const Value: Integer): Boolean;
begin
  Result := ((Value = EndOfStream) or (Value = ByteSpace) or (Value = ByteReturn) or (Value = ByteLineFeed));
end;

class function TCMapParser.IsDelimiter(const Value: Integer): Boolean;
begin
  case Value of
    Ord('('), Ord(')'), Ord('<'), Ord('>'), Ord('['), Ord(']'), Ord('{'), Ord('}'), Ord('/'), Ord('%'):
    begin
      Result := True;
    end;
  else
    Result := False;
  end;
end;

class function TCMapParser.AreBytesEqual(const First, Second: TBytes): Boolean;
begin
  Result := (Length(First) = Length(Second));
  for var Index := 0 to Length(First) - 1 do
  begin
    if not Result then
    begin
      Exit;
    end;
    Result := (First[Index] = Second[Index]);
  end;
end;

class function TCMapParser.IsDigit(const Value: Integer): Boolean;
begin
  Result := ((Value >= Ord('0')) and (Value <= Ord('9')));
end;

class function TCMapParser.ToIntSaturated(const Value: Double): Integer;
begin
  if Value >= MaxInt then
  begin
    Exit(MaxInt);
  end;
  Result := Trunc(Value);
end;

class function TCMapParser.Increment(const Data: TBytes; const Position: Integer; const UseStrictMode: Boolean): Boolean;
begin
  var Index := Position;
  while True do
  begin
    if Index < 0 then
    begin
      Exit(False);
    end;

    const IsCarry = ((Index > 0) and (Data[Index] = MaxByteValue));
    if not IsCarry then
    begin
      Data[Index] := Byte(Data[Index] + 1);
      Exit(True);
    end;

    if UseStrictMode then
    begin
      Exit(False);
    end;
    Data[Index] := 0;
    Dec(Index);
  end;
end;

class function TCMapParser.CreateStringFromBytes(const Value: TBytes): string;
begin
  if Length(Value) <= 2 then
  begin
    TCMapStrings.TryGetMapping(Value, Result);
  end
  else
  begin
    Result := TCMapStrings.DecodeUtf16BigEndian(Value);
  end;
end;

procedure TCMapParser.Warn(const Message: string);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Message);
  end;
end;

procedure TCMapParser.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

procedure TCMapParser.WarnAboutLimit;
begin
  if not FHasWarnedAboutLimit then
  begin
    FHasWarnedAboutLimit := True;
    Warn('The CMap has reached the limit of %d mappings, the rest is ignored', [MaxCMapMappings]);
  end;
end;

procedure TCMapParser.WarnAboutLength;
begin
  if not FHasWarnedAboutLength then
  begin
    FHasWarnedAboutLength := True;
    Warn('Mappings with more than 4 bytes aren''t supported yet');
  end;
end;

end.
