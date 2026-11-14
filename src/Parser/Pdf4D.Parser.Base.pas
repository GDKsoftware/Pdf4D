// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/BaseParser.java (3.0.8)
unit Pdf4D.Parser.Base;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.PdfString,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.IO.RandomAccessRead;

type
  // Turns bytes into direct COS objects. Every object a Parse method returns belongs to the caller, except a
  // TCosObject: that is a proxy of the document. On an error all partly built containers are freed again.
  TBaseParser = class
  private
    const MaxLongDigits = 19;
    const ObjectNumberThreshold: Int64 = 10000000000;
    const GenerationNumberThreshold = 65535;
    const NoNextByte = -2;

  private
    FSource: TRandomAccessRead;
    FDocument: TCosDocument;
    FNestingDepth: Integer;
    FIsArrayLimitLogged: Boolean;

    class function IsHexDigit(const Value: Integer): Boolean; static;
    class function HexValue(const Value: Integer): Integer; static;
    class function IsLinefeed(const Value: Integer): Boolean; static;
    class function IsCarriageReturn(const Value: Integer): Boolean; static;
    class function IsNumberStart(const Value: Integer): Boolean; static;
    class function IsNumberCharacter(const Value: Integer): Boolean; static;
    class function TryParseLong(const Text: string; out Value: Int64): Boolean; static;

    function MaxNestingDepth: Integer;
    procedure GuardNestingDepth;
    procedure LogWarning(const Fmt: string; const Args: array of const);
    procedure LogError(const Fmt: string; const Args: array of const);

    function ParseDirObjectOrMarker(out IsReferenceMarker: Boolean): TCosBase;
    function ParseDirObjectAtToken(out IsReferenceMarker: Boolean): TCosBase;
    function ParseDictionaryOrHexString: TCosBase;
    function ParseKeyword(const Keyword: string; const Value: Boolean): TCosBase;
    function ParseNullKeyword: TCosBase;
    function ParseCosNumber: TCosNumber;
    function ParseUnexpectedToken: TCosBase;

    function ParseCosDictionaryValue: TCosBase;
    function ResolveReference(const ObjectNumber: TCosBase; const NumberOffset: Int64): TCosBase;
    function GetObjectFromPool(const Key: TCosObjectKey): TCosBase;
    procedure ReadDictionaryEntries(const Dictionary: TCosDictionary);
    procedure ReadDictionaryEnd;
    function ReadUntilEndOfCosDictionary: Boolean;
    function ReadMatches(const Rest: string): Boolean;
    function ParseCosDictionaryNameValuePair(const Dictionary: TCosDictionary): Boolean;

    function CheckForEndOfString(const Braces: Integer): Integer;
    function ReadStringEscape(const Bytes: TList<Byte>; var Braces: Integer): Integer;
    function ReadOctalEscape(const Bytes: TList<Byte>; const FirstDigit: Integer): Integer;
    function ReadLineContinuation: Integer;
    function ParseCosHexString: TCosString;
    function ReadHexDigits: string;
    function HexDigitsToBytes(const HexDigits: string): TBytes;

    procedure ReadArrayItems(const Items: TCosArray; const StartPosition: Int64);
    function ReadArrayItem(const Items: TCosArray; const StartPosition: Int64): Boolean;
    function ResolveArrayReference(const Items: TCosArray): TCosBase;
    procedure AddArrayItem(const Items: TCosArray; const Item: TCosBase);

    function SkipLinebreakAfter(const First: Integer): Boolean;
    function ReadStringNumber: string;
    procedure RaiseExpectedNumber(const What, Digits: string);

  protected
    // COSNumber.get: the number that a text stands for
    class function ParseNumber(const Text: string): TCosNumber; static;
    // PDFBox returns null for a skipped unexpected token in a content stream parser and COSNull otherwise
    function ReturnsNilForUnexpectedToken: Boolean; virtual;
    // Items beyond this count are read and dropped, with one log line per parser. Unlimited by default.
    function MaxArrayItems: Integer; virtual;

  public
    class function IsEOL(const Value: Integer): Boolean; static;
    class function IsWhitespace(const Value: Integer): Boolean; static;
    class function IsSpace(const Value: Integer): Boolean; static;
    class function IsDigit(const Value: Integer): Boolean; static;
    class function IsEndOfName(const Value: Integer): Boolean; static;

    // The parser does not own the source. The document may be nil: an object reference then raises.
    constructor Create(const Source: TRandomAccessRead; const Document: TCosDocument);

    // A new object, a TCosObject of the document pool for "n g R" inside a dictionary or array,
    // or nil at the end of the data (and for an unexpected token when ReturnsNilForUnexpectedToken)
    function ParseDirObject: TCosBase;

    function ParseCosDictionary(const IsDirect: Boolean): TCosDictionary;
    function ParseCosArray: TCosArray;
    function ParseCosName: TCosName;
    function ParseCosString: TCosString;

    procedure SkipSpaces;
    procedure SkipWhiteSpaces;
    function SkipLinebreak: Boolean;

    function ReadLong: Int64;
    function ReadInt: Integer;
    function ReadObjectNumber: Int64;
    function ReadGenerationNumber: Integer;
    procedure ReadExpectedString(const Expected: string);
    procedure ReadExpectedChar(const Expected: Char);
    function ReadString: string;
    function ReadLine: string;

    property Source: TRandomAccessRead read FSource;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfObject;

const
  ByteLinefeed = 10;
  ByteCarriageReturn = 13;
  ByteSpace = 32;
  BytePercent = 37;
  ByteNul = 0;
  EndObjKeyword = 'endobj';
  EndStreamKeyword = 'endstream';
  NullKeyword = 'null';
  TrueKeyword = 'true';
  FalseKeyword = 'false';
  StreamTail = 'tream';
  ObjTail = 'bj';

{ TBaseParser }

class function TBaseParser.IsEOL(const Value: Integer): Boolean;
begin
  Result := (IsLinefeed(Value) or IsCarriageReturn(Value));
end;

class function TBaseParser.IsWhitespace(const Value: Integer): Boolean;
begin
  case Value of
    ByteNul, 9, 12, ByteLinefeed, ByteCarriageReturn, ByteSpace : Result := True;
  else
    Result := False;
  end;
end;

class function TBaseParser.IsSpace(const Value: Integer): Boolean;
begin
  Result := (Value = ByteSpace);
end;

class function TBaseParser.IsDigit(const Value: Integer): Boolean;
begin
  Result := ((Value >= Ord('0')) and (Value <= Ord('9')));
end;

class function TBaseParser.IsEndOfName(const Value: Integer): Boolean;
begin
  case Value of
    ByteSpace, ByteCarriageReturn, ByteLinefeed, 9, Ord('>'), Ord('<'), Ord('['), Ord('/'), Ord(']'),
    Ord(')'), Ord('('), ByteNul, 12, BytePercent, -1 : Result := True;
  else
    Result := False;
  end;
end;

class function TBaseParser.IsLinefeed(const Value: Integer): Boolean;
begin
  Result := (Value = ByteLinefeed);
end;

class function TBaseParser.IsCarriageReturn(const Value: Integer): Boolean;
begin
  Result := (Value = ByteCarriageReturn);
end;

class function TBaseParser.IsHexDigit(const Value: Integer): Boolean;
begin
  Result := (IsDigit(Value) or ((Value >= Ord('a')) and (Value <= Ord('f'))) or ((Value >= Ord('A')) and (Value <= Ord('F'))));
end;

class function TBaseParser.HexValue(const Value: Integer): Integer;
begin
  if IsDigit(Value) then
  begin
    Result := Value - Ord('0');
  end
  else if (Value >= Ord('a')) and (Value <= Ord('f')) then
  begin
    Result := Value - Ord('a') + 10;
  end
  else
  begin
    Result := Value - Ord('A') + 10;
  end;
end;

class function TBaseParser.IsNumberStart(const Value: Integer): Boolean;
begin
  Result := (IsDigit(Value) or (Value = Ord('-')) or (Value = Ord('+')) or (Value = Ord('.')));
end;

class function TBaseParser.IsNumberCharacter(const Value: Integer): Boolean;
begin
  Result := (IsNumberStart(Value) or (Value = Ord('E')) or (Value = Ord('e')));
end;

// Java Long.parseLong: an optional sign and at least one digit, without overflow
class function TBaseParser.TryParseLong(const Text: string; out Value: Int64): Boolean;
begin
  Value := 0;
  var Start := 0;
  const IsNegative = ((Text.Length > 0) and (Text.Chars[0] = '-'));
  const HasSign = ((Text.Length > 0) and ((Text.Chars[0] = '-') or (Text.Chars[0] = '+')));
  if HasSign then
  begin
    Start := 1;
  end;

  const HasDigits = (Text.Length > Start);
  if not HasDigits then
  begin
    Exit(False);
  end;

  var Magnitude: UInt64 := 0;
  const MaxMagnitude: UInt64 = UInt64(High(Int64)) + UInt64(Ord(IsNegative));
  for var Index := Start to Text.Length - 1 do
  begin
    const Digit = Ord(Text.Chars[Index]) - Ord('0');
    const IsNoDigit = ((Digit < 0) or (Digit > 9));
    if IsNoDigit then
    begin
      Exit(False);
    end;

    const Overflows = (Magnitude > (MaxMagnitude - UInt64(Digit)) div 10);
    if Overflows then
    begin
      Exit(False);
    end;
    Magnitude := (Magnitude * 10) + UInt64(Digit);
  end;

  if IsNegative and (Magnitude > 0) then
  begin
    // Written so that the magnitude of Low(Int64) does not overflow
    Value := -Int64(Magnitude - 1) - 1;
  end
  else
  begin
    Value := Int64(Magnitude);
  end;
  Result := True;
end;

// Port of COSNumber.get(String)
class function TBaseParser.ParseNumber(const Text: string): TCosNumber;
begin
  if Text.Length = 0 then
  begin
    raise EPdfParseException.Create('Not a number: empty text');
  end;

  if Text.Length = 1 then
  begin
    const Digit = Text.Chars[0];
    if (Digit >= '0') and (Digit <= '9') then
    begin
      Exit(TCosInteger.Create(Ord(Digit) - Ord('0')));
    end;
    // PDFBOX-592: a lone '-' or '.' is 0
    if (Digit = '-') or (Digit = '.') then
    begin
      Exit(TCosInteger.Create(0));
    end;
    raise EPdfParseException.CreateFmt('Not a number: %s', [Text]);
  end;

  const IsFloat = ((Text.IndexOf('.') >= 0) or (Text.IndexOf('e') >= 0));
  if IsFloat then
  begin
    Exit(TCosFloat.Parse(Text));
  end;

  var Value: Int64;
  if TryParseLong(Text, Value) then
  begin
    Exit(TCosInteger.Create(Value));
  end;

  const HasSign = ((Text.Chars[0] = '+') or (Text.Chars[0] = '-'));
  const Digits = Text.Substring(Ord(HasSign));
  for var Digit in Digits do
  begin
    const IsNoDigit = ((Digit < '0') or (Digit > '9'));
    if IsNoDigit then
    begin
      raise EPdfParseException.CreateFmt('Not a number: %s', [Text]);
    end;
  end;

  // A limited integer, marked as invalid
  Result := TCosInteger.CreateOutOfRange(Text.Chars[0] <> '-');
end;

constructor TBaseParser.Create(const Source: TRandomAccessRead; const Document: TCosDocument);
begin
  inherited Create;
  FSource := Source;
  FDocument := Document;
end;

function TBaseParser.MaxNestingDepth: Integer;
begin
  if Assigned(FDocument) then
  begin
    Result := Min(FDocument.Options.MaxNestingDepth, MaximumNestingDepth);
  end
  else
  begin
    Result := DefaultMaxNestingDepth;
  end;
end;

procedure TBaseParser.GuardNestingDepth;
begin
  if FNestingDepth > MaxNestingDepth then
  begin
    raise EPdfParseException.CreateFmt('Reached maximum recursion depth %d', [MaxNestingDepth]);
  end;
end;

procedure TBaseParser.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FDocument) then
  begin
    FDocument.Log.Warning(Fmt, Args);
  end;
end;

procedure TBaseParser.LogError(const Fmt: string; const Args: array of const);
begin
  if Assigned(FDocument) then
  begin
    FDocument.Log.Error(Fmt, Args);
  end;
end;

function TBaseParser.ReturnsNilForUnexpectedToken: Boolean;
begin
  Result := False;
end;

function TBaseParser.ParseDirObject: TCosBase;
begin
  var IsReferenceMarker: Boolean;
  Result := ParseDirObjectOrMarker(IsReferenceMarker);

  // PDFBox gives an empty COSObject for a stray 'R'. It would belong to nobody here: it counts as null.
  if IsReferenceMarker then
  begin
    Result := TCosNull.Create;
  end;
end;

function TBaseParser.ParseDirObjectOrMarker(out IsReferenceMarker: Boolean): TCosBase;
begin
  IsReferenceMarker := False;
  Inc(FNestingDepth);
  try
    GuardNestingDepth;
    SkipSpaces;
    Result := ParseDirObjectAtToken(IsReferenceMarker);
  finally
    Dec(FNestingDepth);
  end;
end;

function TBaseParser.ParseDirObjectAtToken(out IsReferenceMarker: Boolean): TCosBase;
begin
  IsReferenceMarker := False;
  const NextByte = FSource.Peek;
  case NextByte of
    Ord('<') : Result := ParseDictionaryOrHexString;
    Ord('[') : Result := ParseCosArray;
    Ord('(') : Result := ParseCosString;
    Ord('/') : Result := ParseCosName;
    Ord('n') : Result := ParseNullKeyword;
    Ord('t') : Result := ParseKeyword(TrueKeyword, True);
    Ord('f') : Result := ParseKeyword(FalseKeyword, False);
    Ord('R') :
      begin
        FSource.Read;
        IsReferenceMarker := True;
        Result := nil;
      end;
    -1 : Result := nil;
  else
    if IsNumberStart(NextByte) then
    begin
      Result := ParseCosNumber;
    end
    else
    begin
      Result := ParseUnexpectedToken;
    end;
  end;
end;

function TBaseParser.ParseDictionaryOrHexString: TCosBase;
begin
  // Look at the byte after the first '<'
  FSource.Read;
  const SecondByte = FSource.Peek;
  FSource.Rewind(1);

  if SecondByte = Ord('<') then
  begin
    Result := ParseCosDictionary(True);
  end
  else
  begin
    Result := ParseCosString;
  end;
end;

function TBaseParser.ParseNullKeyword: TCosBase;
begin
  ReadExpectedString(NullKeyword);
  Result := TCosNull.Create;
end;

function TBaseParser.ParseKeyword(const Keyword: string; const Value: Boolean): TCosBase;
begin
  ReadExpectedString(Keyword);
  Result := TCosBoolean.Create(Value);
end;

function TBaseParser.ParseCosNumber: TCosNumber;
begin
  const Text = TStringBuilder.Create;
  try
    var NextByte := FSource.Read;
    while IsNumberCharacter(NextByte) do
    begin
      Text.Append(Char(NextByte));
      NextByte := FSource.Read;
    end;
    if NextByte <> -1 then
    begin
      FSource.Rewind(1);
    end;

    // PDFBOX-5025: catch "74191endobj"
    const EndsWithExponent = ((Text.Length > 0) and ((Text[Text.Length - 1] = 'e') or (Text[Text.Length - 1] = 'E')));
    if EndsWithExponent then
    begin
      Text.Length := Text.Length - 1;
      FSource.Rewind(1);
    end;

    Result := ParseNumber(Text.ToString);
  finally
    Text.Free;
  end;
end;

function TBaseParser.ParseUnexpectedToken: TCosBase;
begin
  // Not supposed to happen, but allowed for writers that do not follow the specification
  const StartOffset = FSource.GetPosition;
  const BadToken = ReadString;
  if BadToken.IsEmpty then
  begin
    raise EPdfParseException.CreateFmt('Unknown dir object at offset %d (start offset: %d)', [FSource.GetPosition, StartOffset]);
  end;

  // An endstream or endobj is put back, so that the caller sees it
  if (BadToken = EndObjKeyword) or (BadToken = EndStreamKeyword) then
  begin
    FSource.Rewind(BadToken.Length);
    Exit(nil);
  end;

  LogWarning('Skipped unexpected dir object = ''%s'' at offset %d (start offset: %d)', [BadToken, FSource.GetPosition, StartOffset]);
  if ReturnsNilForUnexpectedToken then
  begin
    Result := nil;
  end
  else
  begin
    Result := TCosNull.Create;
  end;
end;

function TBaseParser.ParseCosDictionary(const IsDirect: Boolean): TCosDictionary;
begin
  Inc(FNestingDepth);
  try
    GuardNestingDepth;
    ReadExpectedChar('<');
    ReadExpectedChar('<');
    SkipSpaces;

    Result := TCosDictionary.Create;
    try
      Result.Direct := IsDirect;
      ReadDictionaryEntries(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Dec(FNestingDepth);
  end;
end;

procedure TBaseParser.ReadDictionaryEntries(const Dictionary: TCosDictionary);
begin
  while True do
  begin
    SkipSpaces;
    const NextByte = FSource.Peek;
    if NextByte = Ord('>') then
    begin
      ReadDictionaryEnd;
      Exit;
    end
    else if NextByte = Ord('/') then
    begin
      // Most likely the dictionary is corrupted when this fails: return everything read so far
      if not ParseCosDictionaryNameValuePair(Dictionary) then
      begin
        Exit;
      end;
    end
    else
    begin
      LogWarning('Invalid dictionary, found byte %d but expected ''/'' at offset %d', [NextByte, FSource.GetPosition]);
      const CouldNotRecover = ReadUntilEndOfCosDictionary;
      if CouldNotRecover then
      begin
        Exit;
      end;
    end;
  end;
end;

procedure TBaseParser.ReadDictionaryEnd;
begin
  try
    ReadExpectedChar('>');
    ReadExpectedChar('>');
  except
    on EPdfParseException do
    begin
      LogWarning('Invalid dictionary, can''t find end of dictionary at offset %d', [FSource.GetPosition]);
    end;
  end;
end;

// Keeps reading until the end of the dictionary or the data, or until a '/' follows. True when the caller
// cannot continue with the dictionary.
function TBaseParser.ReadUntilEndOfCosDictionary: Boolean;
begin
  var NextByte := FSource.Read;
  while (NextByte <> -1) and (NextByte <> Ord('/')) and (NextByte <> Ord('>')) do
  begin
    // Besides '/' and '>' an endstream or endobj ends the dictionary
    if NextByte = Ord('e') then
    begin
      NextByte := FSource.Read;
      if NextByte = Ord('n') then
      begin
        NextByte := FSource.Read;
        if NextByte = Ord('d') then
        begin
          NextByte := FSource.Read;
          const IsStream = ((NextByte = Ord('s')) and ReadMatches(StreamTail));
          const IsObj = (not IsStream and (NextByte = Ord('o')) and ReadMatches(ObjTail));
          if IsStream or IsObj then
          begin
            Exit(True);
          end;
        end;
      end;
    end;
    NextByte := FSource.Read;
  end;

  if NextByte = -1 then
  begin
    Exit(True);
  end;

  FSource.Rewind(1);
  Result := False;
end;

// Stops at the first byte that differs, which is consumed
function TBaseParser.ReadMatches(const Rest: string): Boolean;
begin
  for var Expected in Rest do
  begin
    if FSource.Read <> Ord(Expected) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TBaseParser.ParseCosDictionaryNameValuePair(const Dictionary: TCosDictionary): Boolean;
begin
  const Key = ParseCosName;
  try
    if Key.Name.IsEmpty then
    begin
      LogWarning('Empty COSName at offset %d', [FSource.GetPosition]);
    end;

    const Value = ParseCosDictionaryValue;
    SkipSpaces;
    if not Assigned(Value) then
    begin
      LogWarning('Bad dictionary declaration at offset %d', [FSource.GetPosition]);
      Exit(False);
    end;

    const IsOutOfRangeNumber = ((Value is TCosInteger) and not TCosInteger(Value).IsValid);
    if IsOutOfRangeNumber then
    begin
      LogWarning('Skipped out of range number value at offset %d', [FSource.GetPosition]);
      Value.Free;
    end
    else
    begin
      // Labelled as direct, to avoid signature problems
      Value.Direct := True;
      Dictionary.SetItem(Key.Name, Value);
    end;
    Result := True;
  finally
    Key.Free;
  end;
end;

function TBaseParser.ParseCosDictionaryValue: TCosBase;
begin
  const NumberOffset = FSource.GetPosition;
  const Value = ParseDirObject;
  if not Assigned(Value) then
  begin
    SkipSpaces;
    Exit(nil);
  end;

  try
    SkipSpaces;
    // Proceed when the object is a number and the next token is a number as well
    const IsReferenceCandidate = ((Value is TCosNumber) and IsDigit(FSource.Peek));
    if IsReferenceCandidate then
    begin
      Result := ResolveReference(Value, NumberOffset);
      Value.Free;
    end
    else
    begin
      Result := Value;
    end;
  except
    Value.Free;
    raise;
  end;
end;

// Reads the rest of "n g R". The object number stays with the caller.
function TBaseParser.ResolveReference(const ObjectNumber: TCosBase; const NumberOffset: Int64): TCosBase;
begin
  const GenerationOffset = FSource.GetPosition;
  const GenerationNumber = ParseDirObject;
  try
    SkipSpaces;
    ReadExpectedChar('R');

    if not (ObjectNumber is TCosInteger) then
    begin
      LogError('expected number, actual=%s at offset %d', [ObjectNumber.ClassName, NumberOffset]);
      Exit(TCosNull.Create);
    end;

    if not (GenerationNumber is TCosInteger) then
    begin
      LogError('expected number, actual=%s at offset %d', [GenerationNumber.ClassName, GenerationOffset]);
      Exit(TCosNull.Create);
    end;

    const ObjectNumberValue = TCosInteger(ObjectNumber).LongValue;
    if ObjectNumberValue <= 0 then
    begin
      LogWarning('invalid object number value =%d at offset %d', [ObjectNumberValue, NumberOffset]);
      Exit(TCosNull.Create);
    end;

    const GenerationNumberValue = TCosInteger(GenerationNumber).IntValue;
    if GenerationNumberValue < 0 then
    begin
      LogError('invalid generation number value =%d at offset %d', [GenerationNumberValue, NumberOffset]);
      Exit(TCosNull.Create);
    end;

    Result := GetObjectFromPool(TCosObjectKey.Make(ObjectNumberValue, GenerationNumberValue));
  finally
    GenerationNumber.Free;
  end;
end;

function TBaseParser.GetObjectFromPool(const Key: TCosObjectKey): TCosBase;
begin
  if not Assigned(FDocument) then
  begin
    raise EPdfParseException.CreateFmt('object reference %s at offset %d in content stream', [Key.ToString, FSource.GetPosition]);
  end;

  Result := FDocument.GetObjectFromPool(Key);
end;

function TBaseParser.ParseCosName: TCosName;
begin
  ReadExpectedChar('/');

  const Bytes = TList<Byte>.Create;
  try
    var NextByte := FSource.Read;
    while not IsEndOfName(NextByte) do
    begin
      if NextByte = Ord('#') then
      begin
        const FirstDigit = FSource.Read;
        const SecondDigit = FSource.Read;
        // Before PDF 1.2 the '#' was not special and many writers ignore the escape: it is an escape only
        // when two hex digits follow
        if IsHexDigit(FirstDigit) and IsHexDigit(SecondDigit) then
        begin
          Bytes.Add(Byte((HexValue(FirstDigit) * 16) + HexValue(SecondDigit)));
          NextByte := FSource.Read;
        end
        else
        begin
          const IsPrematureEnd = ((SecondDigit = -1) or (FirstDigit = -1));
          if IsPrematureEnd then
          begin
            LogError('Premature EOF in BaseParser#parseCOSName', []);
            NextByte := -1;
            Break;
          end;

          FSource.Rewind(1);
          NextByte := FirstDigit;
          Bytes.Add(Ord('#'));
        end;
      end
      else
      begin
        Bytes.Add(Byte(NextByte));
        NextByte := FSource.Read;
      end;
    end;

    if NextByte <> -1 then
    begin
      FSource.Rewind(1);
    end;

    Result := TCosName.Create(TCosName.DecodeBytes(Bytes.ToArray));
  finally
    Bytes.Free;
  end;
end;

function TBaseParser.ParseCosString: TCosString;
begin
  const FirstByte = FSource.Read;
  if FirstByte = Ord('<') then
  begin
    Exit(ParseCosHexString);
  end;

  if FirstByte <> Ord('(') then
  begin
    raise EPdfParseException.CreateFmt('parseCOSString string should start with ''('' or ''<'' and not byte %d at offset %d', [FirstByte, FSource.GetPosition]);
  end;

  const Bytes = TList<Byte>.Create;
  try
    var Braces := 1;
    var NextByte := FSource.Read;
    while (Braces > 0) and (NextByte <> -1) do
    begin
      var FollowingByte := NoNextByte;

      if NextByte = Ord(')') then
      begin
        Dec(Braces);
        Braces := CheckForEndOfString(Braces);
        if Braces <> 0 then
        begin
          Bytes.Add(Byte(NextByte));
        end;
      end
      else if NextByte = Ord('(') then
      begin
        Inc(Braces);
        Bytes.Add(Byte(NextByte));
      end
      else if NextByte = Ord('\') then
      begin
        FollowingByte := ReadStringEscape(Bytes, Braces);
      end
      else
      begin
        Bytes.Add(Byte(NextByte));
      end;

      if FollowingByte <> NoNextByte then
      begin
        NextByte := FollowingByte;
      end
      else
      begin
        NextByte := FSource.Read;
      end;
    end;

    if NextByte <> -1 then
    begin
      FSource.Rewind(1);
    end;

    Result := TCosString.Create(Bytes.ToArray, False);
  finally
    Bytes.Free;
  end;
end;

// The string "(c:\) /Producer" and an unbalanced "((Test)" are writer bugs: a closing parenthesis followed by the
// start of the next object ends the string even when parentheses are still open.
function TBaseParser.CheckForEndOfString(const Braces: Integer): Integer;
begin
  if Braces = 0 then
  begin
    Exit(0);
  end;

  var NextThree: TBytes;
  SetLength(NextThree, 3);
  const AmountRead = FSource.Read(NextThree, 0, 3);
  if AmountRead > 0 then
  begin
    FSource.Rewind(AmountRead);
  end;
  if AmountRead < 3 then
  begin
    Exit(Braces);
  end;

  // The end is: an end of line and then '/' or '>'
  const IsEndOfLine = ((NextThree[0] = ByteCarriageReturn) or (NextThree[0] = ByteLinefeed));
  const StartsNextToken = ((NextThree[1] = Ord('/')) or (NextThree[1] = Ord('>')));
  const IsCrLf = ((NextThree[0] = ByteCarriageReturn) and (NextThree[1] = ByteLinefeed));
  const StartsNextTokenAfterCrLf = ((NextThree[2] = Ord('/')) or (NextThree[2] = Ord('>')));
  if (IsEndOfLine and StartsNextToken) or (IsCrLf and StartsNextTokenAfterCrLf) then
  begin
    Exit(0);
  end;

  Result := Braces;
end;

// Handles the byte after a backslash. Gives the byte that follows the escape when it was read already,
// NoNextByte when the caller has to read it.
function TBaseParser.ReadStringEscape(const Bytes: TList<Byte>; var Braces: Integer): Integer;
begin
  Result := NoNextByte;

  const EscapedByte = FSource.Read;
  case EscapedByte of
    Ord('n') : Bytes.Add(10);
    Ord('r') : Bytes.Add(13);
    Ord('t') : Bytes.Add(9);
    Ord('b') : Bytes.Add(8);
    Ord('f') : Bytes.Add(12);
    Ord(')') :
      begin
        // PDFBox 276: /Title (c:\)
        Braces := CheckForEndOfString(Braces);
        if Braces <> 0 then
        begin
          Bytes.Add(Byte(EscapedByte));
        end
        else
        begin
          Bytes.Add(Ord('\'));
        end;
      end;
    Ord('('), Ord('\') : Bytes.Add(Byte(EscapedByte));
    ByteLinefeed, ByteCarriageReturn : Result := ReadLineContinuation;
    Ord('0')..Ord('7') : Result := ReadOctalEscape(Bytes, EscapedByte);
  else
    // The backslash is dropped, see 7.3.4.2 Literal Strings. At the end of the data this writes byte $FF, like PDFBox.
    Bytes.Add(Byte(EscapedByte));
  end;
end;

// A backslash before an end of line is a line break in the source: it and all following end of line bytes are ignored
function TBaseParser.ReadLineContinuation: Integer;
begin
  Result := FSource.Read;
  while IsEOL(Result) and (Result <> -1) do
  begin
    Result := FSource.Read;
  end;
end;

// One to three octal digits. Gives the byte after the escape.
function TBaseParser.ReadOctalEscape(const Bytes: TList<Byte>; const FirstDigit: Integer): Integer;
begin
  var Value := FirstDigit - Ord('0');

  var NextByte := FSource.Read;
  const HasSecondDigit = ((NextByte >= Ord('0')) and (NextByte <= Ord('7')));
  if HasSecondDigit then
  begin
    Value := (Value * 8) + (NextByte - Ord('0'));
    NextByte := FSource.Read;
    const HasThirdDigit = ((NextByte >= Ord('0')) and (NextByte <= Ord('7')));
    if HasThirdDigit then
    begin
      Value := (Value * 8) + (NextByte - Ord('0'));
      Result := NoNextByte;
    end
    else
    begin
      Result := NextByte;
    end;
  end
  else
  begin
    Result := NextByte;
  end;

  // A value above 255 keeps its low byte
  Bytes.Add(Byte(Value and $FF));
end;

// The opening '<' was read already. Fail fast: an invalid byte ends the digits, to find the next object start.
function TBaseParser.ParseCosHexString: TCosString;
begin
  Result := TCosString.Create(HexDigitsToBytes(ReadHexDigits), True);
end;

function TBaseParser.ReadHexDigits: string;
begin
  const Digits = TStringBuilder.Create;
  try
    while True do
    begin
      const NextByte = FSource.Read;
      if IsHexDigit(NextByte) then
      begin
        Digits.Append(Char(NextByte));
      end
      else if NextByte = Ord('>') then
      begin
        Break;
      end
      else if NextByte < 0 then
      begin
        raise EPdfParseException.Create('Missing closing bracket for hex string. Reached EOS.');
      end
      else if (NextByte = ByteSpace) or (NextByte = ByteLinefeed) or (NextByte = 9) or (NextByte = ByteCarriageReturn) or
              (NextByte = 8) or (NextByte = 12) then
      begin
        Continue;
      end
      else
      begin
        // Discard the last digit when it is not part of a pair
        if Digits.Length mod 2 <> 0 then
        begin
          Digits.Length := Digits.Length - 1;
        end;

        var SkippedByte := FSource.Read;
        while (SkippedByte <> Ord('>')) and (SkippedByte >= 0) do
        begin
          SkippedByte := FSource.Read;
        end;
        if SkippedByte < 0 then
        begin
          raise EPdfParseException.Create('Missing closing bracket for hex string. Reached EOS.');
        end;
        Break;
      end;
    end;

    Result := Digits.ToString;
  finally
    Digits.Free;
  end;
end;

// Port of COSString.parseHex for digits that are valid already: an odd last digit counts as the high nibble
function TBaseParser.HexDigitsToBytes(const HexDigits: string): TBytes;
begin
  SetLength(Result, (HexDigits.Length + 1) div 2);
  for var Index := 0 to High(Result) do
  begin
    const HighDigit = HexValue(Ord(HexDigits.Chars[Index * 2]));
    const HasLowDigit = (Index * 2 + 1 < HexDigits.Length);
    var LowDigit := 0;
    if HasLowDigit then
    begin
      LowDigit := HexValue(Ord(HexDigits.Chars[Index * 2 + 1]));
    end;
    Result[Index] := Byte((HighDigit * 16) + LowDigit);
  end;
end;

function TBaseParser.ParseCosArray: TCosArray;
begin
  Inc(FNestingDepth);
  try
    GuardNestingDepth;
    const StartPosition = FSource.GetPosition;
    ReadExpectedChar('[');

    Result := TCosArray.Create;
    try
      ReadArrayItems(Result, StartPosition);
    except
      Result.Free;
      raise;
    end;
  finally
    Dec(FNestingDepth);
  end;
end;

procedure TBaseParser.ReadArrayItems(const Items: TCosArray; const StartPosition: Int64);
begin
  SkipSpaces;
  while True do
  begin
    const NextByte = FSource.Peek;
    const HasMoreItems = ((NextByte > 0) and (NextByte <> Ord(']')));
    if not HasMoreItems then
    begin
      Break;
    end;

    if not ReadArrayItem(Items, StartPosition) then
    begin
      Exit;
    end;
    SkipSpaces;
  end;

  // The closing ']'
  FSource.Read;
  SkipSpaces;
end;

// False when the array has to end here, without a closing bracket
function TBaseParser.ReadArrayItem(const Items: TCosArray; const StartPosition: Int64): Boolean;
begin
  var IsReferenceMarker: Boolean;
  var Item := ParseDirObjectOrMarker(IsReferenceMarker);
  if IsReferenceMarker then
  begin
    // The "n g" before the 'R' are the last two integers of the array. PDFBOX-385
    Item := ResolveArrayReference(Items);
  end;

  if Assigned(Item) then
  begin
    AddArrayItem(Items, Item);
    Exit(True);
  end;

  // It could be a bad object in the array, which is just skipped
  LogWarning('Corrupt array element at offset %d, start offset: %d', [FSource.GetPosition, StartPosition]);
  const NextToken = ReadString;
  // A corrupt element followed by another array most likely means that the whole array is corrupt
  if NextToken.IsEmpty and (FSource.Peek = Ord('[')) then
  begin
    Exit(False);
  end;

  FSource.Rewind(NextToken.Length);
  // An "endobj" or "endstream" means that the array has ended
  Result := not ((NextToken = EndObjKeyword) or (NextToken = EndStreamKeyword));
end;

function TBaseParser.MaxArrayItems: Integer;
begin
  Result := High(Integer);
end;

procedure TBaseParser.AddArrayItem(const Items: TCosArray; const Item: TCosBase);
begin
  if Items.Count < MaxArrayItems then
  begin
    Items.Add(Item);
    Exit;
  end;

  if not FIsArrayLimitLogged then
  begin
    FIsArrayLimitLogged := True;
    LogWarning('An array has more than %d items, the rest is dropped', [MaxArrayItems]);
  end;
  // A TCosObject belongs to the document
  if not (Item is TCosObject) then
  begin
    Item.Free;
  end;
end;

function TBaseParser.ResolveArrayReference(const Items: TCosArray): TCosBase;
begin
  Result := nil;

  const HasGenerationNumber = ((Items.Count > 1) and (Items.Get(Items.Count - 1) is TCosInteger));
  if not HasGenerationNumber then
  begin
    Exit;
  end;

  const GenerationNumber = TCosInteger(Items.RemoveLast);
  try
    const HasObjectNumber = ((Items.Count > 0) and (Items.Get(Items.Count - 1) is TCosInteger));
    if not HasObjectNumber then
    begin
      Exit;
    end;

    const ObjectNumber = TCosInteger(Items.RemoveLast);
    try
      const IsValidKey = ((ObjectNumber.LongValue >= 0) and (GenerationNumber.IntValue >= 0));
      if IsValidKey then
      begin
        Result := GetObjectFromPool(TCosObjectKey.Make(ObjectNumber.LongValue, GenerationNumber.IntValue));
      end
      else
      begin
        LogWarning('Invalid value(s) for an object key %d %d', [ObjectNumber.LongValue, GenerationNumber.IntValue]);
      end;
    finally
      ObjectNumber.Free;
    end;
  finally
    GenerationNumber.Free;
  end;
end;

procedure TBaseParser.SkipSpaces;
begin
  var NextByte := FSource.Read;
  while IsWhitespace(NextByte) or (NextByte = BytePercent) do
  begin
    if NextByte = BytePercent then
    begin
      // Skip past the comment
      NextByte := FSource.Read;
      while not IsEOL(NextByte) and (NextByte <> -1) do
      begin
        NextByte := FSource.Read;
      end;
    end
    else
    begin
      NextByte := FSource.Read;
    end;
  end;

  if NextByte <> -1 then
  begin
    FSource.Rewind(1);
  end;
end;

// The spaces and one line break after the keyword "stream". See brother_scan_cover.pdf: some writers add spaces.
procedure TBaseParser.SkipWhiteSpaces;
begin
  var NextByte := FSource.Read;
  while NextByte = ByteSpace do
  begin
    NextByte := FSource.Read;
  end;

  // PDFBox rewinds at the end of the data too, which steps back over a byte that is not part of the break
  if not SkipLinebreakAfter(NextByte) and (NextByte <> -1) then
  begin
    FSource.Rewind(1);
  end;
end;

function TBaseParser.SkipLinebreak: Boolean;
begin
  const NextByte = FSource.Read;
  Result := SkipLinebreakAfter(NextByte);
  if not Result and (NextByte <> -1) then
  begin
    FSource.Rewind(1);
  end;
end;

// A line break is a CR, an LF or a CRLF
function TBaseParser.SkipLinebreakAfter(const First: Integer): Boolean;
begin
  if IsCarriageReturn(First) then
  begin
    const Following = FSource.Read;
    if not IsLinefeed(Following) and (Following <> -1) then
    begin
      FSource.Rewind(1);
    end;
    Result := True;
  end
  else
  begin
    Result := IsLinefeed(First);
  end;
end;

function TBaseParser.ReadLong: Int64;
begin
  SkipSpaces;
  const Digits = ReadStringNumber;
  if not TryParseLong(Digits, Result) then
  begin
    RaiseExpectedNumber('a long type', Digits);
  end;
end;

function TBaseParser.ReadInt: Integer;
begin
  SkipSpaces;
  const Digits = ReadStringNumber;

  var Value: Int64;
  const FitsInteger = (TryParseLong(Digits, Value) and (Value >= Low(Integer)) and (Value <= High(Integer)));
  if not FitsInteger then
  begin
    RaiseExpectedNumber('an integer type', Digits);
  end;
  Result := Integer(Value);
end;

procedure TBaseParser.RaiseExpectedNumber(const What, Digits: string);
begin
  FSource.Rewind(Digits.Length);
  raise EPdfParseException.CreateFmt('Error: Expected %s at offset %d, instead got ''%s''', [What, FSource.GetPosition, Digits]);
end;

function TBaseParser.ReadObjectNumber: Int64;
begin
  Result := ReadLong;
  if (Result < 0) or (Result >= ObjectNumberThreshold) then
  begin
    raise EPdfParseException.CreateFmt('Object Number ''%d'' has more than 10 digits or is negative', [Result]);
  end;
end;

function TBaseParser.ReadGenerationNumber: Integer;
begin
  Result := ReadInt;
  if (Result < 0) or (Result > GenerationNumberThreshold) then
  begin
    raise EPdfParseException.CreateFmt('Generation Number ''%d'' has more than 5 digits', [Result]);
  end;
end;

// The digits of a token for ReadInt and ReadLong: any non digit ends it
function TBaseParser.ReadStringNumber: string;
begin
  const Digits = TStringBuilder.Create;
  try
    var NextByte := FSource.Read;
    while IsDigit(NextByte) do
    begin
      Digits.Append(Char(NextByte));
      if Digits.Length > MaxLongDigits then
      begin
        raise EPdfParseException.CreateFmt('Number ''%s'' is getting too long, stop reading at offset %d', [Digits.ToString, FSource.GetPosition]);
      end;
      NextByte := FSource.Read;
    end;

    if NextByte <> -1 then
    begin
      FSource.Rewind(1);
    end;
    Result := Digits.ToString;
  finally
    Digits.Free;
  end;
end;

// Skips the spaces before and after the text too
procedure TBaseParser.ReadExpectedString(const Expected: string);
begin
  SkipSpaces;
  for var ExpectedChar in Expected do
  begin
    if FSource.Read <> Ord(ExpectedChar) then
    begin
      raise EPdfParseException.CreateFmt('Expected string ''%s'' but missed at character ''%s'' at offset %d', [Expected, ExpectedChar, FSource.GetPosition]);
    end;
  end;
  SkipSpaces;
end;

procedure TBaseParser.ReadExpectedChar(const Expected: Char);
begin
  const ActualByte = FSource.Read;
  if ActualByte <> Ord(Expected) then
  begin
    raise EPdfParseException.CreateFmt('expected=''%s'' actual byte=%d at offset %d', [Expected, ActualByte, FSource.GetPosition]);
  end;
end;

function TBaseParser.ReadString: string;
begin
  SkipSpaces;

  const Text = TStringBuilder.Create;
  try
    var NextByte := FSource.Read;
    while not IsEndOfName(NextByte) do
    begin
      Text.Append(Char(NextByte));
      NextByte := FSource.Read;
    end;

    if NextByte <> -1 then
    begin
      FSource.Rewind(1);
    end;
    Result := Text.ToString;
  finally
    Text.Free;
  end;
end;

function TBaseParser.ReadLine: string;
begin
  if FSource.IsEOF then
  begin
    raise EPdfParseException.CreateFmt('Error: End-of-File, expected line at offset %d', [FSource.GetPosition]);
  end;

  const Text = TStringBuilder.Create;
  try
    var NextByte := FSource.Read;
    while NextByte <> -1 do
    begin
      // CR and LF are valid ends of line
      if IsEOL(NextByte) then
      begin
        Break;
      end;
      Text.Append(Char(NextByte));
      NextByte := FSource.Read;
    end;

    // CR+LF is also a valid end of line
    if IsCarriageReturn(NextByte) and IsLinefeed(FSource.Peek) then
    begin
      FSource.Read;
    end;
    Result := Text.ToString;
  finally
    Text.Free;
  end;
end;

end.
