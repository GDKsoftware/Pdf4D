// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/type1/Type1Parser.java (3.0.8)
unit Pdf4D.FontBox.Type1.Parser;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.Encoding,
  Pdf4D.FontBox.Type1.Lexer;

const
  // The depth to which the value of a dictionary entry may be wrapped in systemdict procedures
  MaxValueDepth = 100;

type
  TType1Tokens = TArray<TType1Token>;

  // What the parser reads from a Type 1 font program. The fields are those of Type1Font in PDFBox.
  TType1FontData = class
  public
    FontName: string;
    // nil when the font declares no encoding; a built-in encoding belongs to this object
    Encoding: TFontBoxEncoding;
    OwnsEncoding: Boolean;
    PaintType: Integer;
    FontType: Integer;
    FontMatrix: TArray<Single>;
    FontBBox: TArray<Single>;
    UniqueID: Integer;
    StrokeWidth: Single;
    FontID: string;

    Version: string;
    Notice: string;
    FullName: string;
    FamilyName: string;
    Weight: string;
    ItalicAngle: Single;
    IsFixedPitch: Boolean;
    UnderlinePosition: Single;
    UnderlineThickness: Single;

    BlueValues: TArray<Single>;
    OtherBlues: TArray<Single>;
    FamilyBlues: TArray<Single>;
    FamilyOtherBlues: TArray<Single>;
    BlueScale: Single;
    BlueShift: Integer;
    BlueFuzz: Integer;
    StdHW: TArray<Single>;
    StdVW: TArray<Single>;
    StemSnapH: TArray<Single>;
    StemSnapV: TArray<Single>;
    ForceBold: Boolean;
    LanguageGroup: Integer;

    // An entry that the font does not define is empty
    Subrs: TList<TBytes>;
    CharStrings: TDictionary<string, TBytes>;

    constructor Create;
    destructor Destroy; override;
  end;

  // Parses the ASCII and the encrypted binary segment of a Type 1 font
  TType1Parser = class
  private
    FLexer: TType1Lexer;
    FFont: TType1FontData;
    FLog: TPdfLog;
    FDataLength: Integer;

    class function Decrypt(const CipherBytes: TBytes; const Key, RandomByteCount: Integer): TBytes; static;
    class function IsBinary(const Bytes: TBytes): Boolean; static;
    class function HexToBinary(const Bytes: TBytes): TBytes; static;
    class function HexDigit(const Value: Byte): Integer; static;
    class function ArrayToNumbers(const Value: TType1Tokens): TArray<Single>; static;
    class function FirstToken(const Value: TType1Tokens): TType1Token; static;

    function ReadKind(const Kind: TType1TokenKind): TType1Token; overload;
    procedure ReadKind(const Kind: TType1TokenKind; const Name: string); overload;
    function ReadMaybe(const Kind: TType1TokenKind; const Name: string): Boolean;
    function PeekIs(const Kind: TType1TokenKind; const Name: string): Boolean;
    function PeekText: string;

    procedure ParseAscii(const Bytes: TBytes);
    procedure SkipSyntheticFontHeader;
    procedure ReadFontDictionaryEntry(const Key: string);
    procedure ReadSimpleValue(const Key: string);
    procedure ReadEncoding;
    procedure ReadBuiltInEncoding;
    procedure SetEncoding(const Encoding: TFontBoxEncoding; const OwnsEncoding: Boolean);
    procedure ReadFontInfo(const FontInfo: TDictionary<string, TType1Tokens>);
    function ReadSimpleDict: TDictionary<string, TType1Tokens>;
    procedure SkipSimpleDict;
    function ReadDictValue: TType1Tokens;
    function ReadValue(const Depth: Integer): TType1Tokens;
    function ReadArrayValue(const Value: TList<TType1Token>): Boolean;
    procedure ReadPostScriptWrapper(const Value: TList<TType1Token>; const Depth: Integer);
    function ReadProc: TType1Tokens;
    procedure ReadProcVoid;

    procedure ParseBinary(const Bytes: TBytes);
    procedure FindPrivateDict;
    function ReadPrivateDict: Integer;
    procedure ReadPrivateEntry(const Key: string; var LenIV: Integer);
    procedure ReadNDEntry;
    procedure ReadNPEntry;
    procedure ReadRDEntry;
    procedure ReadPrivate(const Key: string; const Value: TType1Tokens);
    procedure ReadSubrs(const LenIV: Integer);
    procedure ReadOtherSubrs;
    procedure ReadCharStrings(const LenIV: Integer);
    procedure ReadDef;
    procedure ReadPut;

  public
    destructor Destroy; override;

    // The caller owns the result. The log is optional and not owned.
    function Parse(const Segment1, Segment2: TBytes; const Log: TPdfLog = nil): TType1FontData;
  end;

implementation

uses
  System.Math,
  System.TypInfo,
  Pdf4D.Common.Defines;

const
  EexecKey = 55665;
  CharstringKey = 4330;
  EexecRandomBytes = 4;
  DefaultLenIV = 4;
  NoEncryptionLenIV = -1;
  MultiplyConstant = 52845;
  AddConstant = 22719;
  HexRadix = 16;
  BinaryCheckLength = 4;

  NameFontInfo = 'FontInfo';
  NameFontInfoLower = 'Fontinfo';
  NameDict = 'dict';
  NameDup = 'dup';
  NameBegin = 'begin';
  NameEnd = 'end';
  NameDef = 'def';
  NameReadonly = 'readonly';
  NameNoaccess = 'noaccess';
  NameExecuteonly = 'executeonly';
  NamePut = 'put';
  NameCurrentdict = 'currentdict';
  NameCurrentfile = 'currentfile';
  NameEexec = 'eexec';
  NameArray = 'array';
  NamePrivate = 'Private';
  NameCharStrings = 'CharStrings';
  NameStandardEncoding = 'StandardEncoding';

{ TType1FontData }

constructor TType1FontData.Create;
begin
  inherited Create;
  Subrs := TList<TBytes>.Create;
  CharStrings := TDictionary<string, TBytes>.Create;
end;

destructor TType1FontData.Destroy;
begin
  if OwnsEncoding then
  begin
    Encoding.Free;
  end;
  CharStrings.Free;
  Subrs.Free;
  inherited;
end;

{ TType1Parser }

destructor TType1Parser.Destroy;
begin
  FLexer.Free;
  inherited;
end;

function TType1Parser.Parse(const Segment1, Segment2: TBytes; const Log: TPdfLog): TType1FontData;
begin
  FLog := Log;
  FFont := TType1FontData.Create;
  try
    ParseAscii(Segment1);
    if Length(Segment2) > 0 then
    begin
      ParseBinary(Segment2);
    end;
    Result := FFont;
  except
    FFont.Free;
    raise;
  end;
  FFont := nil;
  FreeAndNil(FLexer);
end;

class function TType1Parser.FirstToken(const Value: TType1Tokens): TType1Token;
begin
  if Length(Value) = 0 then
  begin
    raise EPdfParseException.Create('A Type 1 font entry has no value');
  end;
  Result := Value[0];
end;

class function TType1Parser.ArrayToNumbers(const Value: TType1Tokens): TArray<Single>;
begin
  // The first and the last token are the brackets
  const Count = Max(0, Length(Value) - 2);
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    const Token = Value[Index + 1];
    case Token.Kind of
      TType1TokenKind.Real : Result[Index] := Token.FloatValue;
      TType1TokenKind.Int  : Result[Index] := Token.IntValue;
    else
      raise EPdfParseException.CreateFmt('Expected INTEGER or REAL but got %s at array position %d',
                                         [Token.Describe, Index + 1]);
    end;
  end;
end;

function TType1Parser.PeekText: string;
begin
  Result := FLexer.PeekToken.Text;
end;

function TType1Parser.PeekIs(const Kind: TType1TokenKind; const Name: string): Boolean;
begin
  Result := (FLexer.PeekKind(Kind) and (PeekText = Name));
end;

function TType1Parser.ReadKind(const Kind: TType1TokenKind): TType1Token;
begin
  Result := FLexer.NextToken;
  if Result.Kind <> Kind then
  begin
    raise EPdfParseException.CreateFmt('Found %s but expected %s', [Result.Describe, GetEnumName(TypeInfo(TType1TokenKind), Ord(Kind))]);
  end;
end;

procedure TType1Parser.ReadKind(const Kind: TType1TokenKind; const Name: string);
begin
  const Token = ReadKind(Kind);
  if Token.Text <> Name then
  begin
    raise EPdfParseException.CreateFmt('Found %s but expected %s', [Token.Describe, Name]);
  end;
end;

function TType1Parser.ReadMaybe(const Kind: TType1TokenKind; const Name: string): Boolean;
begin
  Result := PeekIs(Kind, Name);
  if Result then
  begin
    FLexer.NextToken;
  end;
end;

procedure TType1Parser.ParseAscii(const Bytes: TBytes);
begin
  if Length(Bytes) = 0 then
  begin
    raise EPdfParseException.Create('ASCII segment of type 1 font is empty');
  end;

  // %!FontType1-1.0 or %!PS-AdobeFont-1.0; the test is as loose as in PDFBox
  const StartIsValid = ((Length(Bytes) >= 2) and ((Bytes[0] = Ord('%')) or (Bytes[1] = Ord('!'))));
  if not StartIsValid then
  begin
    raise EPdfParseException.Create('Invalid start of ASCII segment of type 1 font');
  end;

  FLexer.Free;
  FLexer := TType1Lexer.Create(Bytes, FLog);
  if FLexer.PeekToken.Kind = TType1TokenKind.None then
  begin
    raise EPdfParseException.Create('ASCII segment of type 1 font has no tokens');
  end;
  if PeekText = 'FontDirectory' then
  begin
    SkipSyntheticFontHeader;
  end;

  const EntryCount = ReadKind(TType1TokenKind.Int).IntValue;
  ReadKind(TType1TokenKind.Name, NameDict);
  // Found in some TeX fonts
  ReadMaybe(TType1TokenKind.Name, NameDup);
  ReadKind(TType1TokenKind.Name, NameBegin);

  for var Index := 0 to EntryCount - 1 do
  begin
    const Token = FLexer.PeekToken;
    const IsEnd = ((Token.Kind = TType1TokenKind.None) or
                   ((Token.Kind = TType1TokenKind.Name) and ((Token.Text = NameCurrentdict) or (Token.Text = NameEnd))));
    if IsEnd then
    begin
      Break;
    end;

    ReadFontDictionaryEntry(ReadKind(TType1TokenKind.Literal).Text);
  end;

  ReadMaybe(TType1TokenKind.Name, NameCurrentdict);
  ReadKind(TType1TokenKind.Name, NameEnd);
  ReadKind(TType1TokenKind.Name, NameCurrentfile);
  ReadKind(TType1TokenKind.Name, NameEexec);
end;

// A (corrupt?) synthetic font
procedure TType1Parser.SkipSyntheticFontHeader;
begin
  ReadKind(TType1TokenKind.Name, 'FontDirectory');
  ReadKind(TType1TokenKind.Literal);
  ReadKind(TType1TokenKind.Name, 'known');
  ReadKind(TType1TokenKind.StartProc);
  ReadProcVoid;
  ReadKind(TType1TokenKind.StartProc);
  ReadProcVoid;
  ReadKind(TType1TokenKind.Name, 'ifelse');
end;

procedure TType1Parser.ReadFontDictionaryEntry(const Key: string);
begin
  if (Key = NameFontInfo) or (Key = NameFontInfoLower) then
  begin
    const FontInfo = ReadSimpleDict;
    try
      ReadFontInfo(FontInfo);
    finally
      FontInfo.Free;
    end;
  end
  else if Key = 'Metrics' then
  begin
    SkipSimpleDict;
  end
  else if Key = 'Encoding' then
  begin
    ReadEncoding;
  end
  else
  begin
    ReadSimpleValue(Key);
  end;
end;

procedure TType1Parser.ReadSimpleValue(const Key: string);
begin
  const Value = ReadDictValue;
  if Key = 'FontName' then
  begin
    FFont.FontName := FirstToken(Value).Text;
  end
  else if Key = 'PaintType' then
  begin
    FFont.PaintType := FirstToken(Value).IntValue;
  end
  else if Key = 'FontType' then
  begin
    FFont.FontType := FirstToken(Value).IntValue;
  end
  else if Key = 'FontMatrix' then
  begin
    FFont.FontMatrix := ArrayToNumbers(Value);
  end
  else if Key = 'FontBBox' then
  begin
    FFont.FontBBox := ArrayToNumbers(Value);
  end
  else if Key = 'UniqueID' then
  begin
    FFont.UniqueID := FirstToken(Value).IntValue;
  end
  else if Key = 'StrokeWidth' then
  begin
    FFont.StrokeWidth := FirstToken(Value).FloatValue;
  end
  else if Key = 'FID' then
  begin
    FFont.FontID := FirstToken(Value).Text;
  end;
end;

procedure TType1Parser.ReadEncoding;
begin
  if not FLexer.PeekKind(TType1TokenKind.Name) then
  begin
    ReadBuiltInEncoding;
    Exit;
  end;

  const Name = FLexer.NextToken.Text;
  if Name <> NameStandardEncoding then
  begin
    raise EPdfParseException.CreateFmt('Unknown encoding: %s', [Name]);
  end;
  SetEncoding(TFontBoxStandardEncoding.Instance, False);
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  ReadKind(TType1TokenKind.Name, NameDef);
end;

procedure TType1Parser.SetEncoding(const Encoding: TFontBoxEncoding; const OwnsEncoding: Boolean);
begin
  if FFont.OwnsEncoding then
  begin
    FFont.Encoding.Free;
  end;
  FFont.Encoding := Encoding;
  FFont.OwnsEncoding := OwnsEncoding;
end;

procedure TType1Parser.ReadBuiltInEncoding;
begin
  ReadKind(TType1TokenKind.Int);
  ReadMaybe(TType1TokenKind.Name, NameArray);

  // 0 1 255 {1 index exch /.notdef put } for. Readonly and def end it as well: some fonts have no dup values (PDFBOX-2134).
  while not (FLexer.PeekKind(TType1TokenKind.Name) and ((PeekText = NameDup) or (PeekText = NameReadonly) or (PeekText = NameDef))) do
  begin
    if FLexer.NextToken.Kind = TType1TokenKind.None then
    begin
      raise EPdfParseException.Create('Incomplete data while reading encoding of type 1 font');
    end;
  end;

  const CodeToName = TDictionary<Integer, string>.Create;
  try
    while PeekIs(TType1TokenKind.Name, NameDup) do
    begin
      ReadKind(TType1TokenKind.Name, NameDup);
      const Code = ReadKind(TType1TokenKind.Int).IntValue;
      const Name = ReadKind(TType1TokenKind.Literal).Text;
      ReadKind(TType1TokenKind.Name, NamePut);
      CodeToName.AddOrSetValue(Code, Name);
    end;

    SetEncoding(TFontBoxBuiltInEncoding.Create(CodeToName), True);
  finally
    CodeToName.Free;
  end;
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  ReadKind(TType1TokenKind.Name, NameDef);
end;

procedure TType1Parser.ReadFontInfo(const FontInfo: TDictionary<string, TType1Tokens>);
begin
  for var Pair in FontInfo do
  begin
    const Key = Pair.Key;
    const Value = Pair.Value;
    if Key = 'version' then
    begin
      FFont.Version := FirstToken(Value).Text;
    end
    else if Key = 'Notice' then
    begin
      FFont.Notice := FirstToken(Value).Text;
    end
    else if Key = 'FullName' then
    begin
      FFont.FullName := FirstToken(Value).Text;
    end
    else if Key = 'FamilyName' then
    begin
      FFont.FamilyName := FirstToken(Value).Text;
    end
    else if Key = 'Weight' then
    begin
      FFont.Weight := FirstToken(Value).Text;
    end
    else if Key = 'ItalicAngle' then
    begin
      FFont.ItalicAngle := FirstToken(Value).FloatValue;
    end
    else if Key = 'isFixedPitch' then
    begin
      FFont.IsFixedPitch := FirstToken(Value).BooleanValue;
    end
    else if Key = 'UnderlinePosition' then
    begin
      FFont.UnderlinePosition := FirstToken(Value).FloatValue;
    end
    else if Key = 'UnderlineThickness' then
    begin
      FFont.UnderlineThickness := FirstToken(Value).FloatValue;
    end;
  end;
end;

function TType1Parser.ReadSimpleDict: TDictionary<string, TType1Tokens>;
begin
  Result := TDictionary<string, TType1Tokens>.Create;
  try
    const EntryCount = ReadKind(TType1TokenKind.Int).IntValue;
    ReadKind(TType1TokenKind.Name, NameDict);
    ReadMaybe(TType1TokenKind.Name, NameDup);
    // PDFBOX-5942: an empty dict
    if ReadMaybe(TType1TokenKind.Name, NameDef) then
    begin
      Exit;
    end;
    ReadKind(TType1TokenKind.Name, NameBegin);

    for var Index := 0 to EntryCount - 1 do
    begin
      if FLexer.PeekToken.Kind = TType1TokenKind.None then
      begin
        Break;
      end;

      if FLexer.PeekKind(TType1TokenKind.Name) and (PeekText <> NameEnd) then
      begin
        ReadKind(TType1TokenKind.Name);
      end;
      // Premature end
      if FLexer.PeekToken.Kind = TType1TokenKind.None then
      begin
        Break;
      end;
      if PeekIs(TType1TokenKind.Name, NameEnd) then
      begin
        Break;
      end;

      const Key = ReadKind(TType1TokenKind.Literal).Text;
      Result.AddOrSetValue(Key, ReadDictValue);
    end;
    ReadKind(TType1TokenKind.Name, NameEnd);
    ReadMaybe(TType1TokenKind.Name, NameReadonly);
    ReadKind(TType1TokenKind.Name, NameDef);
  except
    Result.Free;
    raise;
  end;
end;

procedure TType1Parser.SkipSimpleDict;
begin
  ReadSimpleDict.Free;
end;

function TType1Parser.ReadDictValue: TType1Tokens;
begin
  Result := ReadValue(0);
  ReadDef;
end;

function TType1Parser.ReadValue(const Depth: Integer): TType1Tokens;
begin
  if Depth > MaxValueDepth then
  begin
    raise EPdfParseException.CreateFmt('Type 1 font values are wrapped deeper than %d', [MaxValueDepth]);
  end;

  const Value = TList<TType1Token>.Create;
  try
    const Token = FLexer.NextToken;
    if FLexer.PeekToken.Kind = TType1TokenKind.None then
    begin
      Exit(nil);
    end;
    Value.Add(Token);

    case Token.Kind of
      TType1TokenKind.StartArray:
        begin
          const IsClosed = ReadArrayValue(Value);
          if not IsClosed then
          begin
            Exit(Value.ToArray);
          end;
        end;
      TType1TokenKind.StartProc:
        begin
          Value.AddRange(ReadProc);
        end;
      TType1TokenKind.StartDict:
        begin
          // Skip "/GlyphNames2HostCode << >> def"
          ReadKind(TType1TokenKind.EndDict);
          Exit(Value.ToArray);
        end;
    end;
    ReadPostScriptWrapper(Value, Depth);
    Result := Value.ToArray;
  finally
    Value.Free;
  end;
end;

// False when the data ends before the closing bracket
function TType1Parser.ReadArrayValue(const Value: TList<TType1Token>): Boolean;
begin
  var OpenArray := 1;
  Result := True;
  while True do
  begin
    if FLexer.PeekToken.Kind = TType1TokenKind.None then
    begin
      Exit(False);
    end;

    if FLexer.PeekKind(TType1TokenKind.StartArray) then
    begin
      Inc(OpenArray);
    end;

    const Token = FLexer.NextToken;
    Value.Add(Token);
    if Token.Kind = TType1TokenKind.EndArray then
    begin
      Dec(OpenArray);
      if OpenArray = 0 then
      begin
        Break;
      end;
    end;
  end;
end;

// The postscript wrapper is not in the Type 1 spec
procedure TType1Parser.ReadPostScriptWrapper(const Value: TList<TType1Token>; const Depth: Integer);
begin
  if FLexer.PeekToken.Kind = TType1TokenKind.None then
  begin
    raise EPdfParseException.Create('Missing start token for the system dictionary');
  end;
  if PeekText <> 'systemdict' then
  begin
    Exit;
  end;

  ReadKind(TType1TokenKind.Name, 'systemdict');
  ReadKind(TType1TokenKind.Literal, 'internaldict');
  ReadKind(TType1TokenKind.Name, 'known');
  ReadKind(TType1TokenKind.StartProc);
  ReadProcVoid;
  ReadKind(TType1TokenKind.StartProc);
  ReadProcVoid;
  ReadKind(TType1TokenKind.Name, 'ifelse');

  // Replace the value
  ReadKind(TType1TokenKind.StartProc);
  ReadKind(TType1TokenKind.Name, 'pop');
  Value.Clear;
  Value.AddRange(ReadValue(Depth + 1));
  ReadKind(TType1TokenKind.EndProc);
  ReadKind(TType1TokenKind.Name, 'if');
end;

function TType1Parser.ReadProc: TType1Tokens;
begin
  const Value = TList<TType1Token>.Create;
  try
    var OpenProc := 1;
    while True do
    begin
      if FLexer.PeekToken.Kind = TType1TokenKind.None then
      begin
        raise EPdfParseException.Create('Malformed procedure: missing token');
      end;
      if FLexer.PeekKind(TType1TokenKind.StartProc) then
      begin
        Inc(OpenProc);
      end;

      const Token = FLexer.NextToken;
      Value.Add(Token);
      if Token.Kind = TType1TokenKind.EndProc then
      begin
        Dec(OpenProc);
        if OpenProc = 0 then
        begin
          Break;
        end;
      end;
    end;

    if PeekIs(TType1TokenKind.Name, NameExecuteonly) then
    begin
      Value.Add(FLexer.NextToken);
    end;
    Result := Value.ToArray;
  finally
    Value.Free;
  end;
end;

procedure TType1Parser.ReadProcVoid;
begin
  var OpenProc := 1;
  while True do
  begin
    if FLexer.PeekToken.Kind = TType1TokenKind.None then
    begin
      raise EPdfParseException.Create('Malformed procedure: missing token');
    end;
    if FLexer.PeekKind(TType1TokenKind.StartProc) then
    begin
      Inc(OpenProc);
    end;

    const Token = FLexer.NextToken;
    if Token.Kind = TType1TokenKind.EndProc then
    begin
      Dec(OpenProc);
      if OpenProc = 0 then
      begin
        Break;
      end;
    end;
  end;
  ReadMaybe(TType1TokenKind.Name, NameExecuteonly);
end;

class function TType1Parser.HexDigit(const Value: Byte): Integer;
begin
  case Value of
    Ord('0')..Ord('9') : Result := Value - Ord('0');
    Ord('a')..Ord('f') : Result := Value - Ord('a') + 10;
    Ord('A')..Ord('F') : Result := Value - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

// Binary or hex encoded; see 7.2 eexec encryption in the Type 1 Font Format specification
class function TType1Parser.IsBinary(const Bytes: TBytes): Boolean;
begin
  if Length(Bytes) < BinaryCheckLength then
  begin
    Exit(True);
  end;

  // At least one of the first 4 ciphertext bytes must not be a white space or an ASCII hexadecimal digit
  for var Index := 0 to BinaryCheckLength - 1 do
  begin
    const Value = Bytes[Index];
    const IsSpace = ((Value = $0A) or (Value = $0D) or (Value = $20) or (Value = 9));
    if (not IsSpace) and (HexDigit(Value) = -1) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TType1Parser.HexToBinary(const Bytes: TBytes): TBytes;
begin
  var DigitCount := 0;
  for var Value in Bytes do
  begin
    if HexDigit(Value) <> -1 then
    begin
      Inc(DigitCount);
    end;
  end;

  SetLength(Result, DigitCount div 2);
  var ResultIndex := 0;
  var Previous := -1;
  for var Value in Bytes do
  begin
    const Digit = HexDigit(Value);
    if Digit = -1 then
    begin
      Continue;
    end;

    if Previous = -1 then
    begin
      Previous := Digit;
    end
    else
    begin
      Result[ResultIndex] := Previous * HexRadix + Digit;
      Inc(ResultIndex);
      Previous := -1;
    end;
  end;
end;

class function TType1Parser.Decrypt(const CipherBytes: TBytes; const Key, RandomByteCount: Integer): TBytes;
begin
  // A lenIV of -1 means no encryption (not documented)
  if RandomByteCount = NoEncryptionLenIV then
  begin
    Exit(CipherBytes);
  end;
  if RandomByteCount < NoEncryptionLenIV then
  begin
    raise EPdfParseException.CreateFmt('Invalid lenIV %d in Type 1 font', [RandomByteCount]);
  end;

  // Empty charstrings and charstrings of insufficient length
  if (Length(CipherBytes) = 0) or (RandomByteCount > Length(CipherBytes)) then
  begin
    Exit(nil);
  end;

  var CurrentKey := Key;
  SetLength(Result, Length(CipherBytes) - RandomByteCount);
  for var Index := 0 to High(CipherBytes) do
  begin
    const Cipher = CipherBytes[Index];
    if Index >= RandomByteCount then
    begin
      Result[Index - RandomByteCount] := Cipher xor (CurrentKey shr 8);
    end;
    // Java keeps the low 16 bits of an int that wraps around; 64 bits give the same 16 bits
    CurrentKey := Integer(((Int64(Cipher) + CurrentKey) * MultiplyConstant + AddConstant) and $FFFF);
  end;
end;

procedure TType1Parser.ParseBinary(const Bytes: TBytes);
begin
  // Sometimes fonts use the hex format, so this is converted before decryption
  var Decrypted: TBytes;
  if IsBinary(Bytes) then
  begin
    Decrypted := Decrypt(Bytes, EexecKey, EexecRandomBytes);
  end
  else
  begin
    Decrypted := Decrypt(HexToBinary(Bytes), EexecKey, EexecRandomBytes);
  end;
  FDataLength := Length(Decrypted);

  FLexer.Free;
  FLexer := nil;
  FLexer := TType1Lexer.Create(Decrypted, FLog);
  FindPrivateDict;

  var LenIV := DefaultLenIV;
  const EntryCount = ReadPrivateDict;
  for var Index := 0 to EntryCount - 1 do
  begin
    // Premature end
    if not FLexer.PeekKind(TType1TokenKind.Literal) then
    begin
      Break;
    end;

    ReadPrivateEntry(ReadKind(TType1TokenKind.Literal).Text, LenIV);
  end;

  // Some fonts have "2 index" here, others have "end noaccess put" sometimes followed by "put".
  // Either way, skip until the /CharStrings dict is found
  while not (FLexer.PeekKind(TType1TokenKind.Literal) and (PeekText = NameCharStrings)) do
  begin
    if FLexer.NextToken.Kind = TType1TokenKind.None then
    begin
      raise EPdfParseException.Create('Missing ''CharStrings'' dictionary in type 1 font');
    end;
  end;

  ReadKind(TType1TokenKind.Literal, NameCharStrings);
  ReadCharStrings(LenIV);
end;

// The presence of begin before Private is not checked, as in PDFBox
procedure TType1Parser.FindPrivateDict;
begin
  while (FLexer.PeekToken.Kind <> TType1TokenKind.None) and (PeekText <> NamePrivate) do
  begin
    FLexer.NextToken;
  end;
  if FLexer.PeekToken.Kind = TType1TokenKind.None then
  begin
    raise EPdfParseException.Create('/Private token not found');
  end;
end;

// Returns the number of entries the dict announces
function TType1Parser.ReadPrivateDict: Integer;
begin
  ReadKind(TType1TokenKind.Literal, NamePrivate);
  Result := ReadKind(TType1TokenKind.Int).IntValue;
  ReadKind(TType1TokenKind.Name, NameDict);
  // Could also be "/Private 10 dict def Private begin" instead of the dup
  ReadMaybe(TType1TokenKind.Name, NameDup);
  ReadKind(TType1TokenKind.Name, NameBegin);
end;

procedure TType1Parser.ReadPrivateEntry(const Key: string; var LenIV: Integer);
begin
  if Key = 'Subrs' then
  begin
    ReadSubrs(LenIV);
  end
  else if Key = 'OtherSubrs' then
  begin
    ReadOtherSubrs;
  end
  else if Key = 'lenIV' then
  begin
    LenIV := FirstToken(ReadDictValue).IntValue;
  end
  else if Key = 'ND' then
  begin
    ReadNDEntry;
  end
  else if Key = 'NP' then
  begin
    ReadNPEntry;
  end
  else if Key = 'RD' then
  begin
    ReadRDEntry;
  end
  else
  begin
    ReadPrivate(Key, ReadDictValue);
  end;
end;

procedure TType1Parser.ReadNDEntry;
begin
  ReadKind(TType1TokenKind.StartProc);
  // The access restrictions are not mandatory
  ReadMaybe(TType1TokenKind.Name, NameNoaccess);
  ReadKind(TType1TokenKind.Name, NameDef);
  ReadKind(TType1TokenKind.EndProc);
  ReadMaybe(TType1TokenKind.Name, NameExecuteonly);
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  ReadKind(TType1TokenKind.Name, NameDef);
end;

procedure TType1Parser.ReadNPEntry;
begin
  ReadKind(TType1TokenKind.StartProc);
  ReadMaybe(TType1TokenKind.Name, NameNoaccess);
  ReadKind(TType1TokenKind.Name);
  ReadKind(TType1TokenKind.EndProc);
  ReadMaybe(TType1TokenKind.Name, NameExecuteonly);
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  ReadKind(TType1TokenKind.Name, NameDef);
end;

// /RD {string currentfile exch readstring pop} bind executeonly def
procedure TType1Parser.ReadRDEntry;
begin
  ReadKind(TType1TokenKind.StartProc);
  ReadProcVoid;
  ReadMaybe(TType1TokenKind.Name, 'bind');
  ReadMaybe(TType1TokenKind.Name, NameExecuteonly);
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  ReadKind(TType1TokenKind.Name, NameDef);
end;

procedure TType1Parser.ReadPrivate(const Key: string; const Value: TType1Tokens);
begin
  if Key = 'BlueValues' then
  begin
    FFont.BlueValues := ArrayToNumbers(Value);
  end
  else if Key = 'OtherBlues' then
  begin
    FFont.OtherBlues := ArrayToNumbers(Value);
  end
  else if Key = 'FamilyBlues' then
  begin
    FFont.FamilyBlues := ArrayToNumbers(Value);
  end
  else if Key = 'FamilyOtherBlues' then
  begin
    FFont.FamilyOtherBlues := ArrayToNumbers(Value);
  end
  else if Key = 'BlueScale' then
  begin
    FFont.BlueScale := FirstToken(Value).FloatValue;
  end
  else if Key = 'BlueShift' then
  begin
    FFont.BlueShift := FirstToken(Value).IntValue;
  end
  else if Key = 'BlueFuzz' then
  begin
    FFont.BlueFuzz := FirstToken(Value).IntValue;
  end
  else if Key = 'StdHW' then
  begin
    FFont.StdHW := ArrayToNumbers(Value);
  end
  else if Key = 'StdVW' then
  begin
    FFont.StdVW := ArrayToNumbers(Value);
  end
  else if Key = 'StemSnapH' then
  begin
    FFont.StemSnapH := ArrayToNumbers(Value);
  end
  else if Key = 'StemSnapV' then
  begin
    FFont.StemSnapV := ArrayToNumbers(Value);
  end
  else if Key = 'ForceBold' then
  begin
    FFont.ForceBold := FirstToken(Value).BooleanValue;
  end
  else if Key = 'LanguageGroup' then
  begin
    FFont.LanguageGroup := FirstToken(Value).IntValue;
  end;
end;

procedure TType1Parser.ReadSubrs(const LenIV: Integer);
begin
  // Allocate the size; the array indexes may not be in order. A count beyond what the data could hold is damaged.
  const Count = ReadKind(TType1TokenKind.Int).IntValue;
  if Count > FDataLength then
  begin
    raise EPdfParseException.CreateFmt('The Subrs count %d is larger than the font data', [Count]);
  end;
  for var Index := 0 to Count - 1 do
  begin
    FFont.Subrs.Add(nil);
  end;
  ReadKind(TType1TokenKind.Name, NameArray);

  for var Index := 0 to Count - 1 do
  begin
    // Premature end
    if not PeekIs(TType1TokenKind.Name, NameDup) then
    begin
      Break;
    end;

    ReadKind(TType1TokenKind.Name, NameDup);
    const SubrIndex = ReadKind(TType1TokenKind.Int).IntValue;
    ReadKind(TType1TokenKind.Int);
    // RD
    const CharString = ReadKind(TType1TokenKind.CharString);
    if SubrIndex >= FFont.Subrs.Count then
    begin
      // PDFBox leaves it out
    end
    else if SubrIndex < 0 then
    begin
      raise EPdfParseException.CreateFmt('The Subrs index %d is negative', [SubrIndex]);
    end
    else
    begin
      FFont.Subrs[SubrIndex] := Decrypt(CharString.Data, CharstringKey, LenIV);
    end;
    ReadPut;
  end;
  ReadDef;
end;

// OtherSubrs are embedded PostScript procedures which we can safely ignore
procedure TType1Parser.ReadOtherSubrs;
begin
  if FLexer.PeekToken.Kind = TType1TokenKind.None then
  begin
    raise EPdfParseException.Create('Missing start token of OtherSubrs procedure');
  end;

  if FLexer.PeekKind(TType1TokenKind.StartArray) then
  begin
    ReadValue(0);
    ReadDef;
    Exit;
  end;

  const Count = ReadKind(TType1TokenKind.Int).IntValue;
  ReadKind(TType1TokenKind.Name, NameArray);
  for var Index := 0 to Count - 1 do
  begin
    ReadKind(TType1TokenKind.Name, NameDup);
    // The index
    ReadKind(TType1TokenKind.Int);
    // The PostScript
    ReadValue(0);
    ReadPut;
  end;
  ReadDef;
end;

procedure TType1Parser.ReadCharStrings(const LenIV: Integer);
begin
  const Count = ReadKind(TType1TokenKind.Int).IntValue;
  ReadKind(TType1TokenKind.Name, NameDict);
  // Could also be a sequence ending in "CharStrings begin" instead of the "dup begin"
  ReadKind(TType1TokenKind.Name, NameDup);
  ReadKind(TType1TokenKind.Name, NameBegin);

  for var Index := 0 to Count - 1 do
  begin
    // Premature end
    if FLexer.PeekToken.Kind = TType1TokenKind.None then
    begin
      Break;
    end;
    if PeekIs(TType1TokenKind.Name, NameEnd) then
    begin
      Break;
    end;

    const Name = ReadKind(TType1TokenKind.Literal).Text;
    // RD
    ReadKind(TType1TokenKind.Int);
    const CharString = ReadKind(TType1TokenKind.CharString);
    FFont.CharStrings.AddOrSetValue(Name, Decrypt(CharString.Data, CharstringKey, LenIV));
    ReadDef;
  end;

  // Some fonts have one "end", others two
  ReadKind(TType1TokenKind.Name, NameEnd);
end;

procedure TType1Parser.ReadDef;
begin
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  // Allows "noaccess ND" (not in the Type 1 spec)
  ReadMaybe(TType1TokenKind.Name, NameNoaccess);
  var Token := ReadKind(TType1TokenKind.Name);
  if (Token.Text = 'ND') or (Token.Text = '|-') then
  begin
    Exit;
  end;
  if Token.Text = NameNoaccess then
  begin
    Token := ReadKind(TType1TokenKind.Name);
  end;
  if Token.Text = NameDef then
  begin
    Exit;
  end;
  raise EPdfParseException.CreateFmt('Found %s but expected ND', [Token.Describe]);
end;

procedure TType1Parser.ReadPut;
begin
  ReadMaybe(TType1TokenKind.Name, NameReadonly);
  var Token := ReadKind(TType1TokenKind.Name);
  if (Token.Text = 'NP') or (Token.Text = '|') then
  begin
    Exit;
  end;
  if Token.Text = NameNoaccess then
  begin
    Token := ReadKind(TType1TokenKind.Name);
  end;
  if Token.Text = NamePut then
  begin
    Exit;
  end;
  raise EPdfParseException.CreateFmt('Found %s but expected NP', [Token.Describe]);
end;

end.
