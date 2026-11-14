// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/PDFStreamParser.java (3.0.8)
unit Pdf4D.Parser.ContentStream;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name,
  Pdf4D.Content.Operator,
  Pdf4D.Parser.Base;

type
  // Turns the bytes of a content stream into operands (TCosBase) and operators (TContentOperator). Every token
  // belongs to the caller. An operand with an indirect reference inside an array or a dictionary holds a proxy that
  // belongs to the parser: such a token must not outlive the parser.
  TPdfStreamParser = class(TBaseParser)
  private
    const BinaryCheckLength = 10;
    // A hostile stream can hold an "EI" every few bytes: only the first ones go to the log, the rest as a count
    const MaxIgnoredEIWarnings = 5;

  private
    FDocument: TCosDocument;
    FOwnedLog: TPdfLog;
    FLog: TPdfLog;
    FMaxInlineImageSize: Integer;
    FBinaryCheck: TBytes;
    FInlineImageDepth: Integer;
    FInlineOffset: Int64;
    FIsClosed: Boolean;
    FIgnoredEICount: Integer;

    class function CreateDocument(const Data: TBytes; const Options: TPdfLoadOptions; const Log: TPdfLog): TCosDocument; static;
    class function IsNumberText(const Text: string): Boolean; static;
    class function IsSpaceOrReturn(const Value: Integer): Boolean; static;
    class function IsBinaryByte(const Value: Byte): Boolean; static;
    class function IsOperatorBlank(const Value: Byte): Boolean; static;
    class function ByteText(const Value: Integer): string; static;

    procedure Close;
    procedure ReportSuppressedEIWarnings;
    function PositionText: string;
    function TokenText(const Token: TObject): string;

    function ParseAngleBracket: TObject;
    function ParseArrayToken: TObject;
    function ParseNullOrOperator: TObject;
    function ParseBooleanOrOperator: TObject;
    function ParseNumberToken: TObject;
    function ParseBeginOperator: TObject;
    function ParseInlineImageData: TObject;
    function ParseOperatorToken: TObject;

    procedure ParseInlineImage(const BeginOperator: TContentOperator);
    function TryReadImageParameter(const Parameters: TCosDictionary; const Key: TCosName): Boolean;
    procedure FinishInlineImage(const BeginOperator: TContentOperator; const Token: TObject);

    function ReadInlineImageBytes(out ImageData: TBytes): Boolean;
    function IsEndOfInlineImage(const LastByte, CurrentByte: Integer): Boolean;
    function HasNextSpaceOrReturn: Boolean;
    function HasNoFollowingBinData: Boolean;
    function ReadOperator: string;

  protected
    function ReturnsNilForUnexpectedToken: Boolean; override;

  public
    // The parser owns its own reader of Data. The messages go to Log, which the caller keeps (nil: Options.OnLog).
    constructor Create(const Data: TBytes; const Options: TPdfLoadOptions; const Log: TPdfLog);
    destructor Destroy; override;

    // The next token, nil at the end of the stream
    function ParseNextToken: TObject;
    // All tokens. The list owns them. A parse error frees the tokens read so far and is raised.
    function Parse: TObjectList<TObject>;
  end;

implementation

uses
  System.Classes,
  System.Math,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Null,
  Pdf4D.IO.RandomAccessRead;

const
  ByteSpace = 32;
  ByteCarriageReturn = 13;
  ByteLinefeed = 10;
  ByteTab = 9;
  ByteNul = 0;
  InlineImageGrowthStep = 4096;

{ TPdfStreamParser }

class function TPdfStreamParser.CreateDocument(const Data: TBytes; const Options: TPdfLoadOptions; const Log: TPdfLog): TCosDocument;
begin
  var DocumentOptions := Options;
  DocumentOptions.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      case Level of
        TPdfLogLevel.Debug   : Log.Debug(Message);
        TPdfLogLevel.Info    : Log.Info(Message);
        TPdfLogLevel.Warning : Log.Warning(Message);
        TPdfLogLevel.Error   : Log.Error(Message);
      else
        Log.Warning(Message);
      end;
    end;

  Result := TCosDocument.Create(TRandomAccessRead.FromBytes(Data), DocumentOptions);
end;

constructor TPdfStreamParser.Create(const Data: TBytes; const Options: TPdfLoadOptions; const Log: TPdfLog);
begin
  if not Assigned(Log) then
  begin
    FOwnedLog := TPdfLog.Create(Options.OnLog);
    FLog := FOwnedLog;
  end
  else
  begin
    FLog := Log;
  end;

  FDocument := CreateDocument(Data, Options, FLog);
  inherited Create(FDocument.Source, FDocument);
  FMaxInlineImageSize := Options.MaxInlineImageSize;
  SetLength(FBinaryCheck, BinaryCheckLength);
end;

destructor TPdfStreamParser.Destroy;
begin
  FDocument.Free;
  FOwnedLog.Free;
  inherited;
end;

class function TPdfStreamParser.IsNumberText(const Text: string): Boolean;
begin
  // ^\d*(\.\d*)?$
  var Index := 0;
  while (Index < Text.Length) and IsDigit(Ord(Text.Chars[Index])) do
  begin
    Inc(Index);
  end;

  if (Index < Text.Length) and (Text.Chars[Index] = '.') then
  begin
    Inc(Index);
    while (Index < Text.Length) and IsDigit(Ord(Text.Chars[Index])) do
    begin
      Inc(Index);
    end;
  end;

  Result := (Index = Text.Length);
end;

class function TPdfStreamParser.IsSpaceOrReturn(const Value: Integer): Boolean;
begin
  Result := ((Value = ByteLinefeed) or (Value = ByteCarriageReturn) or (Value = ByteSpace));
end;

// A control character other than tab, LF and CR, or a byte above 127 (a signed byte in Java)
class function TPdfStreamParser.IsBinaryByte(const Value: Byte): Boolean;
begin
  Result := (((Value <> 0) and (Value < $09)) or ((Value > $0A) and (Value < $20) and (Value <> $0D)) or (Value >= $80));
end;

class function TPdfStreamParser.IsOperatorBlank(const Value: Byte): Boolean;
begin
  Result := ((Value = ByteNul) or (Value = ByteTab) or (Value = ByteSpace) or (Value = ByteLinefeed) or (Value = ByteCarriageReturn));
end;

class function TPdfStreamParser.ByteText(const Value: Integer): string;
begin
  if Value < 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := Char(Value);
  end;
end;

procedure TPdfStreamParser.Close;
begin
  FIsClosed := True;
end;

procedure TPdfStreamParser.ReportSuppressedEIWarnings;
begin
  if FIgnoredEICount > MaxIgnoredEIWarnings then
  begin
    FLog.Warning('ignored %d ''EI'' in the middle of this inline image, %d of them without a log line',
                 [FIgnoredEICount, FIgnoredEICount - MaxIgnoredEIWarnings]);
  end;
  FIgnoredEICount := 0;
end;

function TPdfStreamParser.PositionText: string;
begin
  if FIsClosed then
  begin
    Result := 'EOF';
  end
  else
  begin
    Result := IntToStr(Source.GetPosition);
  end;
end;

function TPdfStreamParser.TokenText(const Token: TObject): string;
begin
  if not Assigned(Token) then
  begin
    Result := 'null';
  end
  else
  begin
    Result := Token.ClassName;
  end;
end;

function TPdfStreamParser.Parse: TObjectList<TObject>;
begin
  Result := TObjectList<TObject>.Create(True);
  try
    var Token := ParseNextToken;
    while Assigned(Token) do
    begin
      Result.Add(Token);
      Token := ParseNextToken;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPdfStreamParser.ReturnsNilForUnexpectedToken: Boolean;
begin
  Result := True;
end;

function TPdfStreamParser.ParseNextToken: TObject;
begin
  Result := nil;
  if FIsClosed then
  begin
    Exit;
  end;

  SkipSpaces;
  if Source.IsEOF then
  begin
    Close;
    Exit;
  end;

  case Char(Source.Peek) of
    '<'                                      : Result := ParseAngleBracket;
    '['                                      : Result := ParseArrayToken;
    '('                                      : Result := ParseCosString;
    '/'                                      : Result := ParseCosName;
    'n'                                      : Result := ParseNullOrOperator;
    't', 'f'                                 : Result := ParseBooleanOrOperator;
    '0'..'9', '-', '+', '.'                  : Result := ParseNumberToken;
    'B'                                      : Result := ParseBeginOperator;
    'I'                                      : Result := ParseInlineImageData;
    ']'                                      :
      begin
        // a ']' without its '[': the file is corrupt, but the parser continues
        Source.Read;
        Result := TCosNull.Create;
      end;
  else
    Result := ParseOperatorToken;
  end;
end;

function TPdfStreamParser.ParseAngleBracket: TObject;
begin
  Source.Read;
  const SecondByte = Source.Peek;
  Source.Rewind(1);

  const IsDictionary = (SecondByte = Ord('<'));
  if not IsDictionary then
  begin
    Exit(ParseCosString);
  end;

  try
    Result := ParseCosDictionary(True);
  except
    on Failure: EPdfException do
    begin
      FLog.Warning('Stop reading invalid dictionary from content stream at offset %d', [Source.GetPosition]);
      Close;
      Result := nil;
    end;
  end;
end;

function TPdfStreamParser.ParseArrayToken: TObject;
begin
  try
    Result := ParseCosArray;
  except
    on Failure: EPdfException do
    begin
      FLog.Warning('Stop reading invalid array from content stream at offset %d', [Source.GetPosition]);
      Close;
      Result := nil;
    end;
  end;
end;

function TPdfStreamParser.ParseNullOrOperator: TObject;
begin
  const Text = ReadString;
  if Text = 'null' then
  begin
    Result := TCosNull.Create;
  end
  else
  begin
    Result := TContentOperator.Create(Text);
  end;
end;

function TPdfStreamParser.ParseBooleanOrOperator: TObject;
begin
  const Text = ReadString;
  if Text = 'true' then
  begin
    Result := TCosBoolean.Create(True);
  end
  else if Text = 'false' then
  begin
    Result := TCosBoolean.Create(False);
  end
  else
  begin
    Result := TContentOperator.Create(Text);
  end;
end;

function TPdfStreamParser.ParseNumberToken: TObject;
begin
  // Only one '.' and one '-' at the start of a number
  const FirstByte = Source.Read;
  const Text = TStringBuilder.Create;
  try
    Text.Append(Char(FirstByte));

    // Ignore a double negative (this is consistent with Adobe Reader)
    if (FirstByte = Ord('-')) and (Source.Peek = FirstByte) then
    begin
      Source.Read;
    end;

    var IsDotNotRead := (FirstByte <> Ord('.'));
    var NextByte := Source.Peek;
    while IsDigit(NextByte) or (IsDotNotRead and (NextByte = Ord('.'))) or (NextByte = Ord('-')) do
    begin
      // PDFBOX-4064: ignore a '-' in the middle of a number
      if NextByte <> Ord('-') then
      begin
        Text.Append(Char(NextByte));
      end;
      Source.Read;

      if IsDotNotRead and (NextByte = Ord('.')) then
      begin
        IsDotNotRead := False;
      end;
      NextByte := Source.Peek;
    end;

    const NumberText = Text.ToString;
    if NumberText = '+' then
    begin
      // PDFBOX-5906
      FLog.Warning('isolated ''+'' is ignored');
      Exit(TCosNull.Create);
    end;
    Result := ParseNumber(NumberText);
  finally
    Text.Free;
  end;
end;

function TPdfStreamParser.ParseBeginOperator: TObject;
begin
  const OperatorName = ReadString;
  const BeginOperator = TContentOperator.Create(OperatorName);
  try
    if OperatorName = TOperatorNames.BeginInlineImage then
    begin
      ParseInlineImage(BeginOperator);
    end;
  except
    BeginOperator.Free;
    raise;
  end;
  Result := BeginOperator;
end;

procedure TPdfStreamParser.ParseInlineImage(const BeginOperator: TContentOperator);
begin
  Inc(FInlineImageDepth);
  if FInlineImageDepth > 1 then
  begin
    // PDFBOX-6038
    raise EPdfParseException.CreateFmt('Nested ''%s'' operator not allowed at offset %d, first: %d',
                                       [TOperatorNames.BeginInlineImage, Source.GetPosition, FInlineOffset]);
  end;
  FInlineOffset := Source.GetPosition;

  const Parameters = TCosDictionary.Create;
  BeginOperator.ImageParameters := Parameters;

  var Token := ParseNextToken;
  try
    while Token is TCosName do
    begin
      if not TryReadImageParameter(Parameters, TCosName(Token)) then
      begin
        Break;
      end;
      FreeAndNil(Token);
      Token := ParseNextToken;
    end;

    // the final token will be the image data, maybe??
    FinishInlineImage(BeginOperator, Token);
  finally
    Token.Free;
  end;
end;

function TPdfStreamParser.TryReadImageParameter(const Parameters: TCosDictionary; const Key: TCosName): Boolean;
begin
  const Value = ParseNextToken;
  Result := (Value is TCosBase);
  if Result then
  begin
    Parameters.SetItem(Key.Name, TCosBase(Value));
  end
  else
  begin
    Value.Free;
    FLog.Warning('Unexpected token in inline image dictionary at offset %s', [PositionText]);
  end;
end;

procedure TPdfStreamParser.FinishInlineImage(const BeginOperator: TContentOperator; const Token: TObject);
begin
  if Token is TContentOperator then
  begin
    const ImageData = TContentOperator(Token).ImageData;
    if Length(ImageData) = 0 then
    begin
      FLog.Warning('empty inline image at stream offset %s', [PositionText]);
    end;
    BeginOperator.ImageData := ImageData;
    Dec(FInlineImageDepth);
  end
  else
  begin
    FLog.Warning('nextToken %s at position %s, expected %s?!', [TokenText(Token), PositionText, TOperatorNames.BeginInlineImageData]);
  end;
end;

function TPdfStreamParser.ParseInlineImageData: TObject;
begin
  // the special case of the ID operator
  const FirstByte = Source.Read;
  const SecondByte = Source.Read;
  const IsImageDataOperator = ((FirstByte = Ord('I')) and (SecondByte = Ord('D')));
  if not IsImageDataOperator then
  begin
    const CurrentPosition = Source.GetPosition;
    Close;
    raise EPdfParseException.CreateFmt('Error: Expected operator ''ID'' actual=''%s%s'' at stream offset %d',
                                       [ByteText(FirstByte), ByteText(SecondByte), CurrentPosition]);
  end;

  // skip one line break (CR, LF or CRLF) or any one-byte whitespace
  if not SkipLinebreak and IsWhitespace(Source.Peek) then
  begin
    Source.Read;
  end;

  var ImageData: TBytes;
  if not ReadInlineImageBytes(ImageData) then
  begin
    Exit(nil);
  end;

  // the EI operator isn't unread, as it won't be processed anyway
  const ImageDataOperator = TContentOperator.Create(TOperatorNames.BeginInlineImageData);
  ImageDataOperator.ImageData := ImageData;
  Result := ImageDataOperator;
end;

// False when the data is larger than the limit: the stream ends then
function TPdfStreamParser.ReadInlineImageBytes(out ImageData: TBytes): Boolean;
begin
  var Count := 0;
  FIgnoredEICount := 0;
  var LastByte := Source.Read;
  var CurrentByte := Source.Read;

  // PDF spec is kinda unclear about this. Should a whitespace always appear before EI? Not sure, so that we just read
  // until EI<whitespace>. Be aware not all kind of whitespaces are allowed here. see PDFBOX-1561
  var FoundEnd := IsEndOfInlineImage(LastByte, CurrentByte);
  while not FoundEnd and not Source.IsEOF do
  begin
    if Count >= FMaxInlineImageSize then
    begin
      FLog.Error('Inline image data larger than %d bytes at stream offset %d: the content stream ends here',
                 [FMaxInlineImageSize, Source.GetPosition]);
      Close;
      ReportSuppressedEIWarnings;
      ImageData := nil;
      Exit(False);
    end;

    if Count = Length(ImageData) then
    begin
      const NewLength = Min(Int64(Count) + InlineImageGrowthStep + (Count div 2), Int64(FMaxInlineImageSize));
      SetLength(ImageData, Integer(NewLength));
    end;
    ImageData[Count] := Byte(LastByte);
    Inc(Count);

    LastByte := CurrentByte;
    CurrentByte := Source.Read;
    FoundEnd := IsEndOfInlineImage(LastByte, CurrentByte);
  end;

  if not FoundEnd then
  begin
    FLog.Warning('Inline image without ''EI'' at stream offset %d', [Source.GetPosition]);
  end;
  ReportSuppressedEIWarnings;
  SetLength(ImageData, Count);
  Result := True;
end;

function TPdfStreamParser.IsEndOfInlineImage(const LastByte, CurrentByte: Integer): Boolean;
begin
  Result := ((LastByte = Ord('E')) and (CurrentByte = Ord('I')) and HasNextSpaceOrReturn and HasNoFollowingBinData);
end;

function TPdfStreamParser.HasNextSpaceOrReturn: Boolean;
begin
  Result := IsSpaceOrReturn(Source.Peek);
end;

// Looks up an amount of bytes if they contain only ASCII characters (no control sequences etc.), and that these
// ASCII characters begin with a sequence of 1-3 non-blank characters between blanks
function TPdfStreamParser.HasNoFollowingBinData: Boolean;
begin
  const ReadBytes = Source.Read(FBinaryCheck, 0, BinaryCheckLength);
  var HasNoBinData := True;
  var StartOperatorIndex := -1;
  var EndOperatorIndex := -1;
  var OperatorText := '';

  if ReadBytes > 0 then
  begin
    for var Index := 0 to ReadBytes - 1 do
    begin
      const Value = FBinaryCheck[Index];
      if IsBinaryByte(Value) then
      begin
        HasNoBinData := False;
        Break;
      end;

      // find the start of a PDF operator
      if (StartOperatorIndex = -1) and not IsOperatorBlank(Value) then
      begin
        StartOperatorIndex := Index;
      end
      else if (StartOperatorIndex <> -1) and (EndOperatorIndex = -1) and IsOperatorBlank(Value) then
      begin
        EndOperatorIndex := Index;
      end;
    end;

    // PDFBOX-3742: just assuming that 1-3 non blanks is a PDF operator isn't enough
    if HasNoBinData and (EndOperatorIndex <> -1) and (StartOperatorIndex <> -1) then
    begin
      // usually, the operator here is Q, sometimes EMC (PDFBOX-2376), S (PDFBOX-3784), or a number (PDFBOX-5957)
      OperatorText := TEncoding.ASCII.GetString(FBinaryCheck, StartOperatorIndex, EndOperatorIndex - StartOperatorIndex);
      const IsKnownOperator = ((OperatorText = TOperatorNames.Restore) or (OperatorText = TOperatorNames.EndMarkedContent) or
                               (OperatorText = TOperatorNames.StrokePath) or IsNumberText(OperatorText));
      if not IsKnownOperator then
      begin
        HasNoBinData := False;
      end;
    end;

    // only if not close to EOF
    if HasNoBinData and (StartOperatorIndex <> -1) and (ReadBytes = BinaryCheckLength) then
    begin
      if EndOperatorIndex = -1 then
      begin
        EndOperatorIndex := BinaryCheckLength;
        OperatorText := TEncoding.ASCII.GetString(FBinaryCheck, StartOperatorIndex, EndOperatorIndex - StartOperatorIndex);
      end;

      // look for token of 3 chars max or a number
      if ((EndOperatorIndex - StartOperatorIndex) > 3) and not IsNumberText(OperatorText) then
      begin
        HasNoBinData := False;
      end;
    end;
    Source.Rewind(ReadBytes);
  end;

  if not HasNoBinData then
  begin
    Inc(FIgnoredEICount);
    if FIgnoredEICount <= MaxIgnoredEIWarnings then
    begin
      FLog.Warning('ignoring ''EI'' assumed to be in the middle of inline image at stream offset %d, s = ''%s''',
                   [Source.GetPosition, OperatorText]);
    end;
  end;
  Result := HasNoBinData;
end;

function TPdfStreamParser.ParseOperatorToken: TObject;
begin
  const OperatorName = ReadOperator.Trim;
  if OperatorName.Length > 0 then
  begin
    Result := TContentOperator.Create(OperatorName);
  end
  else
  begin
    Result := nil;
  end;
end;

function TPdfStreamParser.ReadOperator: string;
begin
  SkipSpaces;

  const Text = TStringBuilder.Create(4);
  try
    var NextByte := Source.Peek;
    while (NextByte <> -1) and not IsWhitespace(NextByte) and (NextByte <> Ord('[')) and (NextByte <> Ord('<')) and
          (NextByte <> Ord('(')) and (NextByte <> Ord('/')) and (NextByte <> Ord('%')) and not IsDigit(NextByte) do
    begin
      const CurrentByte = Source.Read;
      NextByte := Source.Peek;
      Text.Append(Char(CurrentByte));

      // Type3 Glyph description has operators with a number in the name
      if (CurrentByte = Ord('d')) and ((NextByte = Ord('0')) or (NextByte = Ord('1'))) then
      begin
        Text.Append(Char(Source.Read));
        NextByte := Source.Peek;
      end;
    end;
    Result := Text.ToString;
  finally
    Text.Free;
  end;
end;

end.
