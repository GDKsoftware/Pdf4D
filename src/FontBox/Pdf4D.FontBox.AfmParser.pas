// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/afm/AFMParser.java (3.0.8)
unit Pdf4D.FontBox.AfmParser;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Afm;

type
  // Splits one line of an AFM file into tokens, like java.util.StringTokenizer
  TAfmLineTokens = class
  private
    FLine: string;
    FDelimiters: TSysCharSet;
    FPosition: Integer;

    procedure SkipDelimiters;

  public
    constructor Create(const Line: string; const Delimiters: TSysCharSet);

    function HasMoreTokens: Boolean;
    // Raises EPdfParseException when there are no tokens left
    function NextToken: string;
  end;

  // Parses the text of an AFM (Adobe Font Metrics) file. Every problem in the data ends in an EPdfParseException.
  TAFMParser = class
  private
    FData: TBytes;
    FPosition: Integer;
    FCharMetricsRead: Boolean;

    function IsAtEnd: Boolean;
    procedure SkipWhitespace;
    function ReadKey: string;
    function ReadKernKey: string;
    function ReadString: string;
    function ReadLine: string;
    procedure ReadCommand(const ExpectedCommand: string);
    function ReadBoolean: Boolean;
    function ReadInt: Integer;
    function ReadFloat: Single;
    function ReadFloatPair: TArray<Single>;
    function SliceToString(const Start, Finish: Integer): string;

    function ParseInt(const Text: string; const Radix: Integer = 10): Integer;
    function ParseFloat(const Text: string): Single;
    function ParseFloatPair(const Tokens: TAfmLineTokens): TArray<Single>;
    function ParseBoundingBox(const Tokens: TAfmLineTokens): TBoundingBox;
    function HexToString(const HexText: string): string;
    procedure VerifySemicolon(const Tokens: TAfmLineTokens);

    procedure ParseFontMetric(const ReducedDataset: Boolean; const Metrics: TFontMetrics);
    procedure ParseKey(const Command: string; const ReducedDataset: Boolean; const Metrics: TFontMetrics);
    function TryParseTextKey(const Command: string; const Metrics: TFontMetrics): Boolean;
    function TryParseNumberKey(const Command: string; const Metrics: TFontMetrics): Boolean;
    function TryParseFloatKey(const Command: string; const Metrics: TFontMetrics): Boolean;
    function TryParseSectionKey(const Command: string; const ReducedDataset: Boolean; const Metrics: TFontMetrics): Boolean;
    procedure ParseFontBBox(const Metrics: TFontMetrics);

    procedure ParseKernData(const Metrics: TFontMetrics);
    procedure ParseTrackKern(const Metrics: TFontMetrics);
    procedure ParseKernPairs(const Metrics: TFontMetrics; const Kind: Integer);
    function ParseKernPair: TKernPair;
    procedure ParseComposites(const Metrics: TFontMetrics);
    function ParseComposite: TComposite;
    procedure ParseCompositeParts(const Composite: TComposite; const Tokens: TAfmLineTokens);
    procedure ParseCharMetrics(const Metrics: TFontMetrics);
    function ParseCharMetric: TCharMetric;
    procedure ParseCharMetricCommand(const Command: string; const Tokens: TAfmLineTokens; const Metric: TCharMetric);
    function TryParseCharMetricSimple(const Command: string; const Tokens: TAfmLineTokens; const Metric: TCharMetric): Boolean;
    function TryParseCharMetricPair(const Command: string; const Tokens: TAfmLineTokens; const Metric: TCharMetric): Boolean;

  public
    constructor Create(const Data: TBytes);

    // The caller owns the result. With ReducedDataset the kerning data and the composites are skipped.
    function Parse(const ReducedDataset: Boolean): TFontMetrics;
  end;

implementation

uses
  Pdf4D.Common.Defines;

const
  CommentKey            = 'Comment';
  StartFontMetricsKey   = 'StartFontMetrics';
  EndFontMetricsKey     = 'EndFontMetrics';
  FontNameKey           = 'FontName';
  FullNameKey           = 'FullName';
  FamilyNameKey         = 'FamilyName';
  WeightKey             = 'Weight';
  FontBBoxKey           = 'FontBBox';
  VersionKey            = 'Version';
  NoticeKey             = 'Notice';
  EncodingSchemeKey     = 'EncodingScheme';
  MappingSchemeKey      = 'MappingScheme';
  EscCharKey            = 'EscChar';
  CharacterSetKey       = 'CharacterSet';
  CharactersKey         = 'Characters';
  IsBaseFontKey         = 'IsBaseFont';
  VVectorKey            = 'VVector';
  IsFixedVKey           = 'IsFixedV';
  CapHeightKey          = 'CapHeight';
  XHeightKey            = 'XHeight';
  AscenderKey           = 'Ascender';
  DescenderKey          = 'Descender';
  StdHWKey              = 'StdHW';
  StdVWKey              = 'StdVW';
  UnderlinePositionKey  = 'UnderlinePosition';
  UnderlineThicknessKey = 'UnderlineThickness';
  ItalicAngleKey        = 'ItalicAngle';
  CharWidthKey          = 'CharWidth';
  IsFixedPitchKey       = 'IsFixedPitch';
  StartCharMetricsKey   = 'StartCharMetrics';
  EndCharMetricsKey     = 'EndCharMetrics';
  StartKernDataKey      = 'StartKernData';
  EndKernDataKey        = 'EndKernData';
  StartTrackKernKey     = 'StartTrackKern';
  EndTrackKernKey       = 'EndTrackKern';
  StartKernPairsKey     = 'StartKernPairs';
  StartKernPairs0Key    = 'StartKernPairs0';
  StartKernPairs1Key    = 'StartKernPairs1';
  EndKernPairsKey       = 'EndKernPairs';
  StartCompositesKey    = 'StartComposites';
  EndCompositesKey      = 'EndComposites';
  KernPairKPKey         = 'KP';
  KernPairKPHKey        = 'KPH';
  KernPairKPXKey        = 'KPX';
  KernPairKPYKey        = 'KPY';
  CompositeCCKey        = 'CC';
  CompositePCCKey       = 'PCC';

  CharMetricsCKey       = 'C';
  CharMetricsCHKey      = 'CH';
  CharMetricsWXKey      = 'WX';
  CharMetricsW0XKey     = 'W0X';
  CharMetricsW1XKey     = 'W1X';
  CharMetricsWYKey      = 'WY';
  CharMetricsW0YKey     = 'W0Y';
  CharMetricsW1YKey     = 'W1Y';
  CharMetricsWKey       = 'W';
  CharMetricsW0Key      = 'W0';
  CharMetricsW1Key      = 'W1';
  CharMetricsVVKey      = 'VV';
  CharMetricsNKey       = 'N';
  CharMetricsBKey       = 'B';
  CharMetricsLKey       = 'L';

  HexRadix = 16;
  DecimalRadix = 10;
  Semicolon = ';';

  KernPairsKind  = 0;
  KernPairs0Kind = 1;
  KernPairs1Kind = 2;

  TrueText = 'true';

type
  TAfmSyntax = record
    class function IsWhitespace(const Value: Byte): Boolean; static;
    class function IsEndOfLine(const Value: Byte): Boolean; static;
    class function TryDigitValue(const Digit: Char; out Value: Integer): Boolean; static;
    class function TryParseInteger(const Text: string; const Radix: Integer; out Value: Integer): Boolean; static;
    class function IsFloatText(const Text: string): Boolean; static;
  end;

{ TAfmSyntax }

class function TAfmSyntax.IsWhitespace(const Value: Byte): Boolean;
begin
  Result := ((Value = 32) or (Value = 9) or (Value = 13) or (Value = 10));
end;

class function TAfmSyntax.IsEndOfLine(const Value: Byte): Boolean;
begin
  Result := ((Value = 13) or (Value = 10));
end;

class function TAfmSyntax.TryDigitValue(const Digit: Char; out Value: Integer): Boolean;
begin
  Result := True;
  if (Digit >= '0') and (Digit <= '9') then
  begin
    Value := Ord(Digit) - Ord('0');
  end
  else if (Digit >= 'a') and (Digit <= 'z') then
  begin
    Value := Ord(Digit) - Ord('a') + 10;
  end
  else if (Digit >= 'A') and (Digit <= 'Z') then
  begin
    Value := Ord(Digit) - Ord('A') + 10;
  end
  else
  begin
    Result := False;
  end;
end;

class function TAfmSyntax.TryParseInteger(const Text: string; const Radix: Integer; out Value: Integer): Boolean;
begin
  Value := 0;
  var Index := 1;
  var IsNegative := False;
  const HasSign = ((Text <> '') and ((Text[1] = '-') or (Text[1] = '+')));
  if HasSign then
  begin
    IsNegative := (Text[1] = '-');
    Index := 2;
  end;

  const HasNoDigits = (Index > Length(Text));
  if HasNoDigits then
  begin
    Exit(False);
  end;

  var Magnitude: Int64 := 0;
  while Index <= Length(Text) do
  begin
    var Digit: Integer;
    if (not TAfmSyntax.TryDigitValue(Text[Index], Digit)) or (Digit >= Radix) then
    begin
      Exit(False);
    end;
    Magnitude := (Magnitude * Radix) + Digit;
    if Magnitude > Int64(High(Integer)) + 1 then
    begin
      Exit(False);
    end;
    Inc(Index);
  end;

  if IsNegative then
  begin
    Magnitude := -Magnitude;
  end;
  const IsInRange = ((Magnitude >= Low(Integer)) and (Magnitude <= High(Integer)));
  if not IsInRange then
  begin
    Exit(False);
  end;
  Value := Integer(Magnitude);
  Result := True;
end;

class function TAfmSyntax.IsFloatText(const Text: string): Boolean;
begin
  Result := (Text <> '');
  for var Character in Text do
  begin
    const IsFloatCharacter = (((Character >= '0') and (Character <= '9')) or CharInSet(Character, ['+', '-', '.', 'e', 'E']));
    if not IsFloatCharacter then
    begin
      Exit(False);
    end;
  end;
end;

{ TAfmLineTokens }

constructor TAfmLineTokens.Create(const Line: string; const Delimiters: TSysCharSet);
begin
  inherited Create;
  FLine := Line;
  FDelimiters := Delimiters;
  FPosition := 1;
end;

procedure TAfmLineTokens.SkipDelimiters;
begin
  while (FPosition <= Length(FLine)) and CharInSet(FLine[FPosition], FDelimiters) do
  begin
    Inc(FPosition);
  end;
end;

function TAfmLineTokens.HasMoreTokens: Boolean;
begin
  SkipDelimiters;
  Result := (FPosition <= Length(FLine));
end;

function TAfmLineTokens.NextToken: string;
begin
  if not HasMoreTokens then
  begin
    raise EPdfParseException.CreateFmt('Error parsing AFM document: a token is missing in the line "%s"', [FLine]);
  end;

  const Start = FPosition;
  while (FPosition <= Length(FLine)) and not CharInSet(FLine[FPosition], FDelimiters) do
  begin
    Inc(FPosition);
  end;
  Result := Copy(FLine, Start, FPosition - Start);
end;

{ TAFMParser }

constructor TAFMParser.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
end;

function TAFMParser.Parse(const ReducedDataset: Boolean): TFontMetrics;
begin
  FPosition := 0;
  FCharMetricsRead := False;
  Result := TFontMetrics.Create;
  try
    ParseFontMetric(ReducedDataset, Result);
  except
    Result.Free;
    raise;
  end;
end;

function TAFMParser.IsAtEnd: Boolean;
begin
  Result := (FPosition >= Length(FData));
end;

procedure TAFMParser.SkipWhitespace;
begin
  while (not IsAtEnd) and TAfmSyntax.IsWhitespace(FData[FPosition]) do
  begin
    Inc(FPosition);
  end;
end;

function TAFMParser.SliceToString(const Start, Finish: Integer): string;
begin
  SetLength(Result, Finish - Start);
  for var Index := 0 to Finish - Start - 1 do
  begin
    Result[Index + 1] := Char(FData[Start + Index]);
  end;
end;

function TAFMParser.ReadKey: string;
begin
  SkipWhitespace;
  if IsAtEnd then
  begin
    raise EPdfParseException.Create('Unknown AFM key: the data ends before EndFontMetrics');
  end;
  Result := ReadString;
end;

function TAFMParser.ReadKernKey: string;
begin
  SkipWhitespace;
  if IsAtEnd then
  begin
    raise EPdfParseException.Create('Unknown kerning data type: the data ends before EndKernData');
  end;
  Result := ReadString;
end;

function TAFMParser.ReadString: string;
begin
  SkipWhitespace;
  if IsAtEnd then
  begin
    raise EPdfParseException.Create('Error parsing AFM document: unexpected end of data');
  end;

  const Start = FPosition;
  while (not IsAtEnd) and (not TAfmSyntax.IsWhitespace(FData[FPosition])) do
  begin
    Inc(FPosition);
  end;
  Result := SliceToString(Start, FPosition);
end;

function TAFMParser.ReadLine: string;
begin
  SkipWhitespace;
  if IsAtEnd then
  begin
    raise EPdfParseException.Create('Error parsing AFM document: unexpected end of data');
  end;

  const Start = FPosition;
  while (not IsAtEnd) and (not TAfmSyntax.IsEndOfLine(FData[FPosition])) do
  begin
    Inc(FPosition);
  end;
  Result := SliceToString(Start, FPosition);
end;

procedure TAFMParser.ReadCommand(const ExpectedCommand: string);
begin
  const Command = ReadString;
  if Command <> ExpectedCommand then
  begin
    raise EPdfParseException.CreateFmt('Error: Expected ''%s'' actual ''%s''', [ExpectedCommand, Command]);
  end;
end;

function TAFMParser.ReadBoolean: Boolean;
begin
  Result := SameText(ReadString, TrueText);
end;

function TAFMParser.ReadInt: Integer;
begin
  Result := ParseInt(ReadString);
end;

function TAFMParser.ReadFloat: Single;
begin
  Result := ParseFloat(ReadString);
end;

function TAFMParser.ReadFloatPair: TArray<Single>;
begin
  SetLength(Result, 2);
  Result[0] := ReadFloat;
  Result[1] := ReadFloat;
end;

function TAFMParser.ParseInt(const Text: string; const Radix: Integer): Integer;
begin
  if not TAfmSyntax.TryParseInteger(Text, Radix, Result) then
  begin
    raise EPdfParseException.CreateFmt('Error parsing AFM document: not an integer: "%s"', [Text]);
  end;
end;

function TAFMParser.ParseFloat(const Text: string): Single;
begin
  if (not TAfmSyntax.IsFloatText(Text)) or (not TryStrToFloat(Text, Result, TFormatSettings.Invariant)) then
  begin
    raise EPdfParseException.CreateFmt('Error parsing AFM document: not a number: "%s"', [Text]);
  end;
end;

function TAFMParser.ParseFloatPair(const Tokens: TAfmLineTokens): TArray<Single>;
begin
  SetLength(Result, 2);
  Result[0] := ParseFloat(Tokens.NextToken);
  Result[1] := ParseFloat(Tokens.NextToken);
end;

function TAFMParser.ParseBoundingBox(const Tokens: TAfmLineTokens): TBoundingBox;
begin
  const LowerLeftX = ParseFloat(Tokens.NextToken);
  const LowerLeftY = ParseFloat(Tokens.NextToken);
  const UpperRightX = ParseFloat(Tokens.NextToken);
  const UpperRightY = ParseFloat(Tokens.NextToken);
  Result := TBoundingBox.Create(LowerLeftX, LowerLeftY, UpperRightX, UpperRightY);
end;

function TAFMParser.HexToString(const HexText: string): string;
begin
  const IsEnclosed = ((Length(HexText) >= 2) and (HexText[1] = '<') and (HexText[Length(HexText)] = '>'));
  if not IsEnclosed then
  begin
    raise EPdfParseException.CreateFmt('Error: expected a hex string enclosed by angle brackets, not "%s"', [HexText]);
  end;

  const Digits = Copy(HexText, 2, Length(HexText) - 2);
  if Odd(Length(Digits)) then
  begin
    raise EPdfParseException.CreateFmt('Error: the hex string "%s" has an odd number of digits', [HexText]);
  end;

  SetLength(Result, Length(Digits) div 2);
  for var Index := 0 to Length(Result) - 1 do
  begin
    Result[Index + 1] := Char(ParseInt(Copy(Digits, (Index * 2) + 1, 2), HexRadix));
  end;
end;

procedure TAFMParser.VerifySemicolon(const Tokens: TAfmLineTokens);
begin
  if not Tokens.HasMoreTokens then
  begin
    raise EPdfParseException.Create('CharMetrics is missing a semicolon after a command');
  end;

  const Token = Tokens.NextToken;
  if Token <> Semicolon then
  begin
    raise EPdfParseException.CreateFmt('Error: Expected semicolon in stream actual=''%s''', [Token]);
  end;
end;

procedure TAFMParser.ParseFontMetric(const ReducedDataset: Boolean; const Metrics: TFontMetrics);
begin
  ReadCommand(StartFontMetricsKey);
  Metrics.AFMVersion := ReadFloat;

  var Command := ReadKey;
  while Command <> EndFontMetricsKey do
  begin
    ParseKey(Command, ReducedDataset, Metrics);
    Command := ReadKey;
  end;
end;

procedure TAFMParser.ParseKey(const Command: string; const ReducedDataset: Boolean; const Metrics: TFontMetrics);
begin
  if TryParseTextKey(Command, Metrics) or
     TryParseNumberKey(Command, Metrics) or
     TryParseFloatKey(Command, Metrics) or
     TryParseSectionKey(Command, ReducedDataset, Metrics) then
  begin
    Exit;
  end;

  const IsIgnorable = (ReducedDataset and FCharMetricsRead);
  if not IsIgnorable then
  begin
    raise EPdfParseException.CreateFmt('Unknown AFM key ''%s''', [Command]);
  end;
end;

function TAFMParser.TryParseTextKey(const Command: string; const Metrics: TFontMetrics): Boolean;
begin
  Result := True;
  if Command = FontNameKey then
  begin
    Metrics.FontName := ReadLine;
  end
  else if Command = FullNameKey then
  begin
    Metrics.FullName := ReadLine;
  end
  else if Command = FamilyNameKey then
  begin
    Metrics.FamilyName := ReadLine;
  end
  else if Command = WeightKey then
  begin
    Metrics.Weight := ReadLine;
  end
  else if Command = VersionKey then
  begin
    Metrics.FontVersion := ReadLine;
  end
  else if Command = NoticeKey then
  begin
    Metrics.Notice := ReadLine;
  end
  else if Command = EncodingSchemeKey then
  begin
    Metrics.EncodingScheme := ReadLine;
  end
  else if Command = CharacterSetKey then
  begin
    Metrics.CharacterSet := ReadLine;
  end
  else if Command = CommentKey then
  begin
    Metrics.AddComment(ReadLine);
  end
  else
  begin
    Result := False;
  end;
end;

function TAFMParser.TryParseNumberKey(const Command: string; const Metrics: TFontMetrics): Boolean;
begin
  Result := True;
  if Command = MappingSchemeKey then
  begin
    Metrics.MappingScheme := ReadInt;
  end
  else if Command = EscCharKey then
  begin
    Metrics.EscChar := ReadInt;
  end
  else if Command = CharactersKey then
  begin
    Metrics.Characters := ReadInt;
  end
  else if Command = IsBaseFontKey then
  begin
    Metrics.IsBaseFont := ReadBoolean;
  end
  else if Command = IsFixedVKey then
  begin
    Metrics.IsFixedV := ReadBoolean;
  end
  else if Command = IsFixedPitchKey then
  begin
    Metrics.IsFixedPitch := ReadBoolean;
  end
  else if Command = VVectorKey then
  begin
    Metrics.VVector := ReadFloatPair;
  end
  else if Command = CharWidthKey then
  begin
    Metrics.CharWidth := ReadFloatPair;
  end
  else if Command = FontBBoxKey then
  begin
    ParseFontBBox(Metrics);
  end
  else
  begin
    Result := False;
  end;
end;

function TAFMParser.TryParseFloatKey(const Command: string; const Metrics: TFontMetrics): Boolean;
begin
  Result := True;
  if Command = CapHeightKey then
  begin
    Metrics.CapHeight := ReadFloat;
  end
  else if Command = XHeightKey then
  begin
    Metrics.XHeight := ReadFloat;
  end
  else if Command = AscenderKey then
  begin
    Metrics.Ascender := ReadFloat;
  end
  else if Command = DescenderKey then
  begin
    Metrics.Descender := ReadFloat;
  end
  else if Command = StdHWKey then
  begin
    Metrics.StandardHorizontalWidth := ReadFloat;
  end
  else if Command = StdVWKey then
  begin
    Metrics.StandardVerticalWidth := ReadFloat;
  end
  else if Command = UnderlinePositionKey then
  begin
    Metrics.UnderlinePosition := ReadFloat;
  end
  else if Command = UnderlineThicknessKey then
  begin
    Metrics.UnderlineThickness := ReadFloat;
  end
  else if Command = ItalicAngleKey then
  begin
    Metrics.ItalicAngle := ReadFloat;
  end
  else
  begin
    Result := False;
  end;
end;

function TAFMParser.TryParseSectionKey(const Command: string; const ReducedDataset: Boolean; const Metrics: TFontMetrics): Boolean;
begin
  Result := True;
  if Command = StartCharMetricsKey then
  begin
    ParseCharMetrics(Metrics);
  end
  else if Command = StartKernDataKey then
  begin
    if not ReducedDataset then
    begin
      ParseKernData(Metrics);
    end;
  end
  else if Command = StartCompositesKey then
  begin
    if not ReducedDataset then
    begin
      ParseComposites(Metrics);
    end;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAFMParser.ParseFontBBox(const Metrics: TFontMetrics);
begin
  const LowerLeftX = ReadFloat;
  const LowerLeftY = ReadFloat;
  const UpperRightX = ReadFloat;
  const UpperRightY = ReadFloat;
  Metrics.FontBBox := TBoundingBox.Create(LowerLeftX, LowerLeftY, UpperRightX, UpperRightY);
end;

procedure TAFMParser.ParseKernData(const Metrics: TFontMetrics);
begin
  var Command := ReadKernKey;
  while Command <> EndKernDataKey do
  begin
    if Command = StartTrackKernKey then
    begin
      ParseTrackKern(Metrics);
    end
    else if Command = StartKernPairsKey then
    begin
      ParseKernPairs(Metrics, KernPairsKind);
    end
    else if Command = StartKernPairs0Key then
    begin
      ParseKernPairs(Metrics, KernPairs0Kind);
    end
    else if Command = StartKernPairs1Key then
    begin
      ParseKernPairs(Metrics, KernPairs1Kind);
    end
    else
    begin
      raise EPdfParseException.CreateFmt('Unknown kerning data type ''%s''', [Command]);
    end;
    Command := ReadKernKey;
  end;
end;

procedure TAFMParser.ParseTrackKern(const Metrics: TFontMetrics);
begin
  const Count = ReadInt;
  for var Index := 1 to Count do
  begin
    const Degree = ReadInt;
    const MinPointSize = ReadFloat;
    const MinKern = ReadFloat;
    const MaxPointSize = ReadFloat;
    const MaxKern = ReadFloat;
    Metrics.AddTrackKern(TTrackKern.Create(Degree, MinPointSize, MinKern, MaxPointSize, MaxKern));
  end;
  ReadCommand(EndTrackKernKey);
end;

procedure TAFMParser.ParseKernPairs(const Metrics: TFontMetrics; const Kind: Integer);
begin
  const Count = ReadInt;
  for var Index := 1 to Count do
  begin
    const KernPair = ParseKernPair;
    case Kind of
      KernPairsKind  : Metrics.AddKernPair(KernPair);
      KernPairs0Kind : Metrics.AddKernPair0(KernPair);
      KernPairs1Kind : Metrics.AddKernPair1(KernPair);
    else
      raise EPdfParseException.CreateFmt('Unsupported kern pair kind %d', [Kind]);
    end;
  end;
  ReadCommand(EndKernPairsKey);
end;

function TAFMParser.ParseKernPair: TKernPair;
begin
  const Command = ReadString;
  if Command = KernPairKPKey then
  begin
    const First = ReadString;
    const Second = ReadString;
    const X = ReadFloat;
    const Y = ReadFloat;
    Result := TKernPair.Create(First, Second, X, Y);
  end
  else if Command = KernPairKPHKey then
  begin
    const First = HexToString(ReadString);
    const Second = HexToString(ReadString);
    const X = ReadFloat;
    const Y = ReadFloat;
    Result := TKernPair.Create(First, Second, X, Y);
  end
  else if Command = KernPairKPXKey then
  begin
    const First = ReadString;
    const Second = ReadString;
    const X = ReadFloat;
    Result := TKernPair.Create(First, Second, X, 0);
  end
  else if Command = KernPairKPYKey then
  begin
    const First = ReadString;
    const Second = ReadString;
    const Y = ReadFloat;
    Result := TKernPair.Create(First, Second, 0, Y);
  end
  else
  begin
    raise EPdfParseException.CreateFmt('Error expected kern pair command actual=''%s''', [Command]);
  end;
end;

procedure TAFMParser.ParseComposites(const Metrics: TFontMetrics);
begin
  const Count = ReadInt;
  for var Index := 1 to Count do
  begin
    Metrics.AddComposite(ParseComposite);
  end;
  ReadCommand(EndCompositesKey);
end;

function TAFMParser.ParseComposite: TComposite;
begin
  const Tokens = TAfmLineTokens.Create(ReadLine, [' ', ';']);
  try
    const Marker = Tokens.NextToken;
    if Marker <> CompositeCCKey then
    begin
      raise EPdfParseException.CreateFmt('Expected ''%s'' actual=''%s''', [CompositeCCKey, Marker]);
    end;

    Result := TComposite.Create(Tokens.NextToken);
    try
      ParseCompositeParts(Result, Tokens);
    except
      Result.Free;
      raise;
    end;
  finally
    Tokens.Free;
  end;
end;

procedure TAFMParser.ParseCompositeParts(const Composite: TComposite; const Tokens: TAfmLineTokens);
begin
  const PartCount = ParseInt(Tokens.NextToken);
  for var Index := 1 to PartCount do
  begin
    const Marker = Tokens.NextToken;
    if Marker <> CompositePCCKey then
    begin
      raise EPdfParseException.CreateFmt('Expected ''%s'' actual=''%s''', [CompositePCCKey, Marker]);
    end;

    const PartName = Tokens.NextToken;
    const X = ParseInt(Tokens.NextToken);
    const Y = ParseInt(Tokens.NextToken);
    Composite.AddPart(TCompositePart.Create(PartName, X, Y));
  end;
end;

procedure TAFMParser.ParseCharMetrics(const Metrics: TFontMetrics);
begin
  const Count = ReadInt;
  for var Index := 1 to Count do
  begin
    Metrics.AddCharMetric(ParseCharMetric);
  end;
  ReadCommand(EndCharMetricsKey);
  FCharMetricsRead := True;
end;

function TAFMParser.ParseCharMetric: TCharMetric;
begin
  const Tokens = TAfmLineTokens.Create(ReadLine, [' ', #9, #10, #13, #12]);
  try
    Result := TCharMetric.Create;
    try
      while Tokens.HasMoreTokens do
      begin
        ParseCharMetricCommand(Tokens.NextToken, Tokens, Result);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Tokens.Free;
  end;
end;

procedure TAFMParser.ParseCharMetricCommand(const Command: string; const Tokens: TAfmLineTokens; const Metric: TCharMetric);
begin
  if Command = CharMetricsBKey then
  begin
    Metric.BoundingBox := ParseBoundingBox(Tokens);
  end
  else if Command = CharMetricsNKey then
  begin
    Metric.Name := Tokens.NextToken;
  end
  else if Command = CharMetricsLKey then
  begin
    const Successor = Tokens.NextToken;
    const Ligature = Tokens.NextToken;
    Metric.AddLigature(TLigature.Create(Successor, Ligature));
  end
  else if not (TryParseCharMetricSimple(Command, Tokens, Metric) or TryParseCharMetricPair(Command, Tokens, Metric)) then
  begin
    raise EPdfParseException.CreateFmt('Unknown CharMetrics command ''%s''', [Command]);
  end;

  VerifySemicolon(Tokens);
end;

function TAFMParser.TryParseCharMetricSimple(const Command: string; const Tokens: TAfmLineTokens; const Metric: TCharMetric): Boolean;
begin
  Result := True;
  if Command = CharMetricsCKey then
  begin
    Metric.CharacterCode := ParseInt(Tokens.NextToken);
  end
  else if Command = CharMetricsCHKey then
  begin
    Metric.CharacterCode := ParseInt(Tokens.NextToken, HexRadix);
  end
  else if Command = CharMetricsWXKey then
  begin
    Metric.Wx := ParseFloat(Tokens.NextToken);
  end
  else if Command = CharMetricsW0XKey then
  begin
    Metric.W0x := ParseFloat(Tokens.NextToken);
  end
  else if Command = CharMetricsW1XKey then
  begin
    Metric.W1x := ParseFloat(Tokens.NextToken);
  end
  else if Command = CharMetricsWYKey then
  begin
    Metric.Wy := ParseFloat(Tokens.NextToken);
  end
  else if Command = CharMetricsW0YKey then
  begin
    Metric.W0y := ParseFloat(Tokens.NextToken);
  end
  else if Command = CharMetricsW1YKey then
  begin
    Metric.W1y := ParseFloat(Tokens.NextToken);
  end
  else
  begin
    Result := False;
  end;
end;

function TAFMParser.TryParseCharMetricPair(const Command: string; const Tokens: TAfmLineTokens; const Metric: TCharMetric): Boolean;
begin
  Result := True;
  if Command = CharMetricsWKey then
  begin
    Metric.W := ParseFloatPair(Tokens);
  end
  else if Command = CharMetricsW0Key then
  begin
    Metric.W0 := ParseFloatPair(Tokens);
  end
  else if Command = CharMetricsW1Key then
  begin
    Metric.W1 := ParseFloatPair(Tokens);
  end
  else if Command = CharMetricsVVKey then
  begin
    Metric.Vv := ParseFloatPair(Tokens);
  end
  else
  begin
    Result := False;
  end;
end;

end.
