// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/type1/Type1Lexer.java and Token.java (3.0.8)
unit Pdf4D.FontBox.Type1.Lexer;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log;

const
  // Deeper nesting of { } gives an EPdfParseException. PDFBox has no limit; real fonts nest a few levels at most.
  MaxProcedureDepth = 100;

type
  {$SCOPEDENUMS ON}
  // None is the end of the data (PDFBox returns null)
  TType1TokenKind = (None, Str, Name, Literal, Real, Int, StartArray, EndArray, StartProc, EndProc, StartDict, EndDict,
                     CharString);
  {$SCOPEDENUMS OFF}

  TType1Token = record
    Kind: TType1TokenKind;
    // The text of every kind except CharString; empty for CharString and None
    Text: string;
    // The (still encrypted) bytes of a CharString
    Data: TBytes;

    // A real where an integer should be is accepted, as in PDFBox. Raises EPdfParseException for text that is no number.
    function IntValue: Integer;
    function FloatValue: Single;
    function BooleanValue: Boolean;
    function Describe: string;
  end;

  // Lexer for the ASCII portions of an Adobe Type 1 font. Reads one token ahead, so a first token that is damaged is
  // already reported by the constructor.
  TType1Lexer = class
  private
    FBuffer: TBytes;
    FPosition: Integer;
    FAhead: TType1Token;
    FOpenParens: Integer;
    FProcedureDepth: Integer;
    FLog: TPdfLog;

    class function IsWhitespace(const Value: Integer): Boolean; static;
    class function IsDigit(const Value: Integer): Boolean; static;
    class function IsDelimiter(const Value: Integer): Boolean; static;
    class function MakeToken(const Kind: TType1TokenKind; const Text: string): TType1Token; static;
    class function TryParseRadixNumber(const Text: string; const Radix: Integer; out Value: Integer): Boolean; static;
    class function ParseNumber(const Text: string; const Radix: Integer): Integer; static;

    function HasRemaining: Boolean;
    function GetChar: Integer;
    function ReadToken(const PreviousToken: TType1Token): TType1Token;
    function ReadDelimiterOrName(const Character: Integer; const PreviousToken: TType1Token; out Token: TType1Token): Boolean;
    function ReadBracket(const Character: Integer): TType1Token;
    function ReadTokenAfterSlash: TType1Token;
    function ReadAngleBracket(const Character: Integer): TType1Token;
    function ReadNumberOrName(const PreviousToken: TType1Token): TType1Token;
    function TryReadNumber(out Token: TType1Token): Boolean;
    function ReadRegular: string;
    procedure ReadComment;
    function ReadString: TType1Token;
    procedure ReadEscape(const Builder: TStringBuilder);
    procedure ReadOctalEscape(const FirstDigit: Integer; const Builder: TStringBuilder);
    function ReadCharString(const Count: Integer): TType1Token;

  public
    // The bytes of a header-less PFB segment. The log is optional and not owned.
    constructor Create(const Bytes: TBytes; const Log: TPdfLog = nil);

    // Consumes the next token; a token of kind None at the end
    function NextToken: TType1Token;
    // The next token without consuming it
    function PeekToken: TType1Token;
    function PeekKind(const Kind: TType1TokenKind): Boolean;
  end;

implementation

uses
  System.TypInfo,
  System.Math,
  Pdf4D.Common.Defines;

const
  MaxSingleValue = 3.4028234663852886E+38;
  RadixMinimum = 2;
  RadixMaximum = 36;
  DecimalRadix = 10;
  OctalRadix = 8;
  OctalDigitCount = 3;
  RDName = 'RD';
  MinusBarName = '-|';

{ TType1Token }

function TType1Token.FloatValue: Single;
begin
  var Value: Double;
  const Invariant = TFormatSettings.Invariant;
  if not TryStrToFloat(Text, Value, Invariant) then
  begin
    raise EPdfParseException.CreateFmt('Invalid number "%s" in Type 1 font', [Text]);
  end;

  // Java turns a value beyond the range of a float into an infinity
  if Value > MaxSingleValue then
  begin
    Exit(Single.PositiveInfinity);
  end;
  if Value < -MaxSingleValue then
  begin
    Exit(Single.NegativeInfinity);
  end;
  Result := Value;
end;

function TType1Token.IntValue: Integer;
begin
  const Value = FloatValue;
  // The cast of Java: NaN gives 0 and a value beyond the range of an int stays at the limit
  if IsNaN(Value) then
  begin
    Exit(0);
  end;
  if Value >= 2147483648.0 then
  begin
    Exit(High(Integer));
  end;
  if Value <= -2147483648.0 then
  begin
    Exit(Low(Integer));
  end;
  Result := Trunc(Value);
end;

function TType1Token.BooleanValue: Boolean;
begin
  Result := (Text = 'true');
end;

function TType1Token.Describe: string;
begin
  if Kind = TType1TokenKind.CharString then
  begin
    Exit(Format('Token[kind=CharString, data=%d bytes]', [Length(Data)]));
  end;
  Result := Format('Token[kind=%s, text=%s]', [GetEnumName(TypeInfo(TType1TokenKind), Ord(Kind)), Text]);
end;

{ TType1Lexer }

constructor TType1Lexer.Create(const Bytes: TBytes; const Log: TPdfLog);
begin
  inherited Create;
  FBuffer := Bytes;
  FLog := Log;
  FAhead := ReadToken(MakeToken(TType1TokenKind.None, ''));
end;

class function TType1Lexer.MakeToken(const Kind: TType1TokenKind; const Text: string): TType1Token;
begin
  Result.Kind := Kind;
  Result.Text := Text;
  Result.Data := nil;
end;

class function TType1Lexer.IsWhitespace(const Value: Integer): Boolean;
begin
  // Character.isWhitespace of Java for the characters of a byte: tab to carriage return, the separators 28 to 31 and space
  Result := (((Value >= 9) and (Value <= 13)) or ((Value >= 28) and (Value <= 31)) or (Value = 32));
end;

class function TType1Lexer.IsDigit(const Value: Integer): Boolean;
begin
  Result := ((Value >= Ord('0')) and (Value <= Ord('9')));
end;

class function TType1Lexer.IsDelimiter(const Value: Integer): Boolean;
begin
  Result := (IsWhitespace(Value) or (Value = Ord('(')) or (Value = Ord(')')) or (Value = Ord('<')) or (Value = Ord('>')) or
             (Value = Ord('[')) or (Value = Ord(']')) or (Value = Ord('{')) or (Value = Ord('}')) or (Value = Ord('/')) or
             (Value = Ord('%')));
end;

class function TType1Lexer.ParseNumber(const Text: string; const Radix: Integer): Integer;
begin
  var Value: Integer;
  if not TryParseRadixNumber(Text, Radix, Value) then
  begin
    raise EPdfParseException.CreateFmt('Invalid number "%s" in Type 1 font', [Text]);
  end;
  Result := Value;
end;

// Integer.parseInt of Java: an optional sign, then digits of the radix, within the range of an int
class function TType1Lexer.TryParseRadixNumber(const Text: string; const Radix: Integer; out Value: Integer): Boolean;
begin
  Value := 0;
  const RadixIsValid = ((Radix >= RadixMinimum) and (Radix <= RadixMaximum));
  if (not RadixIsValid) or (Text = '') then
  begin
    Exit(False);
  end;

  var Index := 1;
  var IsNegative := False;
  const HasSign = ((Text[1] = '-') or (Text[1] = '+'));
  if HasSign then
  begin
    IsNegative := (Text[1] = '-');
    Inc(Index);
  end;
  if Index > Length(Text) then
  begin
    Exit(False);
  end;

  var Accumulator: Int64 := 0;
  while Index <= Length(Text) do
  begin
    const Character = Text[Index];
    var Digit: Integer;
    case Character of
      '0'..'9' : Digit := Ord(Character) - Ord('0');
      'a'..'z' : Digit := Ord(Character) - Ord('a') + 10;
      'A'..'Z' : Digit := Ord(Character) - Ord('A') + 10;
    else
      Exit(False);
    end;
    if Digit >= Radix then
    begin
      Exit(False);
    end;

    Accumulator := Accumulator * Radix + Digit;
    const IsTooLarge = (Accumulator > Int64(High(Integer)) + 1);
    if IsTooLarge then
    begin
      Exit(False);
    end;
    Inc(Index);
  end;

  if IsNegative then
  begin
    Accumulator := -Accumulator;
  end;
  if Accumulator > High(Integer) then
  begin
    Exit(False);
  end;
  Value := Integer(Accumulator);
  Result := True;
end;

function TType1Lexer.HasRemaining: Boolean;
begin
  Result := (FPosition < Length(FBuffer));
end;

function TType1Lexer.GetChar: Integer;
begin
  if not HasRemaining then
  begin
    raise EPdfParseException.Create('Premature end of buffer reached');
  end;
  Result := FBuffer[FPosition];
  Inc(FPosition);
end;

function TType1Lexer.NextToken: TType1Token;
begin
  Result := FAhead;
  FAhead := ReadToken(Result);
end;

function TType1Lexer.PeekToken: TType1Token;
begin
  Result := FAhead;
end;

function TType1Lexer.PeekKind(const Kind: TType1TokenKind): Boolean;
begin
  Result := (FAhead.Kind = Kind);
end;

function TType1Lexer.ReadToken(const PreviousToken: TType1Token): TType1Token;
begin
  while HasRemaining do
  begin
    const Character = GetChar;
    var Token: TType1Token;
    if ReadDelimiterOrName(Character, PreviousToken, Token) then
    begin
      Exit(Token);
    end;
  end;
  Result := MakeToken(TType1TokenKind.None, '');
end;

// False when the character was skipped (white space, comment, NUL)
function TType1Lexer.ReadDelimiterOrName(const Character: Integer; const PreviousToken: TType1Token;
                                         out Token: TType1Token): Boolean;
begin
  Result := True;
  case Character of
    Ord('%'):
      begin
        ReadComment;
        Result := False;
      end;
    Ord('('): Token := ReadString;
    Ord(')'): raise EPdfParseException.Create('unexpected closing parenthesis');
    Ord('['), Ord(']'), Ord('{'), Ord('}'): Token := ReadBracket(Character);
    Ord('/'): Token := ReadTokenAfterSlash;
    Ord('<'), Ord('>'): Token := ReadAngleBracket(Character);
  else
    if IsWhitespace(Character) then
    begin
      Result := False;
    end
    else if Character = 0 then
    begin
      if Assigned(FLog) then
      begin
        FLog.Warning('NULL byte in font, skipped');
      end;
      Result := False;
    end
    else
    begin
      Dec(FPosition);
      Token := ReadNumberOrName(PreviousToken);
    end;
  end;
end;

function TType1Lexer.ReadBracket(const Character: Integer): TType1Token;
begin
  case Character of
    Ord('['):
      begin
        Result := MakeToken(TType1TokenKind.StartArray, '[');
      end;
    Ord(']'):
      begin
        Result := MakeToken(TType1TokenKind.EndArray, ']');
      end;
    Ord('{'):
      begin
        Inc(FProcedureDepth);
        if FProcedureDepth > MaxProcedureDepth then
        begin
          raise EPdfParseException.CreateFmt('Procedures in the Type 1 font are nested deeper than %d', [MaxProcedureDepth]);
        end;
        Result := MakeToken(TType1TokenKind.StartProc, '{');
      end;
    Ord('}'):
      begin
        if FProcedureDepth > 0 then
        begin
          Dec(FProcedureDepth);
        end;
        Result := MakeToken(TType1TokenKind.EndProc, '}');
      end;
  else
    raise EPdfParseException.CreateFmt('Unexpected bracket character %d', [Character]);
  end;
end;

function TType1Lexer.ReadTokenAfterSlash: TType1Token;
begin
  const Regular = ReadRegular;
  if Regular = '' then
  begin
    raise EPdfParseException.CreateFmt('Could not read token at position %d', [FPosition]);
  end;
  Result := MakeToken(TType1TokenKind.Literal, Regular);
end;

function TType1Lexer.ReadAngleBracket(const Character: Integer): TType1Token;
begin
  const Second = GetChar;
  const IsDoubled = (Second = Character);
  if IsDoubled then
  begin
    if Character = Ord('<') then
    begin
      Exit(MakeToken(TType1TokenKind.StartDict, '<<'));
    end;
    Exit(MakeToken(TType1TokenKind.EndDict, '>>'));
  end;

  Dec(FPosition);
  Result := MakeToken(TType1TokenKind.Name, Chr(Character));
end;

function TType1Lexer.ReadNumberOrName(const PreviousToken: TType1Token): TType1Token;
begin
  var Number: TType1Token;
  if TryReadNumber(Number) then
  begin
    Exit(Number);
  end;

  const Name = ReadRegular;
  if Name = '' then
  begin
    raise EPdfParseException.CreateFmt('Could not read token at position %d', [FPosition]);
  end;

  const IsCharStringOperator = ((Name = RDName) or (Name = MinusBarName));
  if not IsCharStringOperator then
  begin
    Exit(MakeToken(TType1TokenKind.Name, Name));
  end;

  if PreviousToken.Kind <> TType1TokenKind.Int then
  begin
    raise EPdfParseException.Create('expected INTEGER before -| or RD');
  end;
  Result := ReadCharString(PreviousToken.IntValue);
end;

// Mirrors the number grammar of PDFBox, including the way it runs into the end of the data
function TType1Lexer.TryReadNumber(out Token: TType1Token): Boolean;
begin
  Token := MakeToken(TType1TokenKind.None, '');
  const Start = FPosition;
  const Builder = TStringBuilder.Create;
  try
    var RadixText := '';
    var HasRadix := False;
    var Character := GetChar;
    var HasDigit := False;

    if (Character = Ord('+')) or (Character = Ord('-')) then
    begin
      Builder.Append(Chr(Character));
      Character := GetChar;
    end;

    while IsDigit(Character) do
    begin
      Builder.Append(Chr(Character));
      Character := GetChar;
      HasDigit := True;
    end;

    if Character = Ord('.') then
    begin
      Builder.Append('.');
      Character := GetChar;
    end
    else if Character = Ord('#') then
    begin
      HasRadix := True;
      RadixText := Builder.ToString;
      Builder.Clear;
      Character := GetChar;
    end
    else if (Builder.Length = 0) or (not HasDigit) then
    begin
      FPosition := Start;
      Exit(False);
    end
    else if (Character <> Ord('e')) and (Character <> Ord('E')) then
    begin
      Dec(FPosition);
      Token := MakeToken(TType1TokenKind.Int, Builder.ToString);
      Exit(True);
    end;

    if IsDigit(Character) then
    begin
      Builder.Append(Chr(Character));
      Character := GetChar;
    end
    else if (Character <> Ord('e')) and (Character <> Ord('E')) then
    begin
      FPosition := Start;
      Exit(False);
    end;

    while IsDigit(Character) do
    begin
      Builder.Append(Chr(Character));
      Character := GetChar;
    end;

    if (Character = Ord('E')) or (Character = Ord('e')) then
    begin
      Builder.Append(Chr(Character));
      Character := GetChar;

      if Character = Ord('-') then
      begin
        Builder.Append('-');
        Character := GetChar;
      end;

      if IsDigit(Character) then
      begin
        Builder.Append(Chr(Character));
        Character := GetChar;
      end
      else
      begin
        FPosition := Start;
        Exit(False);
      end;

      while IsDigit(Character) do
      begin
        Builder.Append(Chr(Character));
        Character := GetChar;
      end;
    end;

    Dec(FPosition);
    if HasRadix then
    begin
      const Radix = ParseNumber(RadixText, DecimalRadix);
      const Value = ParseNumber(Builder.ToString, Radix);
      Token := MakeToken(TType1TokenKind.Int, IntToStr(Value));
      Exit(True);
    end;
    Token := MakeToken(TType1TokenKind.Real, Builder.ToString);
    Result := True;
  finally
    Builder.Free;
  end;
end;

function TType1Lexer.ReadRegular: string;
begin
  const Builder = TStringBuilder.Create;
  try
    while HasRemaining do
    begin
      const Character = FBuffer[FPosition];
      if IsDelimiter(Character) then
      begin
        Break;
      end;
      Builder.Append(Chr(Character));
      Inc(FPosition);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TType1Lexer.ReadComment;
begin
  while HasRemaining do
  begin
    const Character = GetChar;
    if (Character = 13) or (Character = 10) then
    begin
      Break;
    end;
  end;
end;

function TType1Lexer.ReadString: TType1Token;
begin
  const Builder = TStringBuilder.Create;
  try
    while HasRemaining do
    begin
      const Character = GetChar;
      case Character of
        Ord('('):
          begin
            Inc(FOpenParens);
            Builder.Append('(');
          end;
        Ord(')'):
          begin
            if FOpenParens = 0 then
            begin
              Exit(MakeToken(TType1TokenKind.Str, Builder.ToString));
            end;
            Builder.Append(')');
            Dec(FOpenParens);
          end;
        Ord('\'):
          begin
            ReadEscape(Builder);
          end;
        13, 10:
          begin
            Builder.Append(#10);
          end;
      else
        Builder.Append(Chr(Character));
      end;
    end;
    // An unterminated string ends the tokens, as in PDFBox
    Result := MakeToken(TType1TokenKind.None, '');
  finally
    Builder.Free;
  end;
end;

procedure TType1Lexer.ReadEscape(const Builder: TStringBuilder);
begin
  const Escaped = GetChar;
  case Escaped of
    Ord('n'), Ord('r'): Builder.Append(#10);
    Ord('t'): Builder.Append(#9);
    Ord('b'): Builder.Append(#8);
    Ord('f'): Builder.Append(#12);
    Ord('\'): Builder.Append('\');
    Ord('('): Builder.Append('(');
    Ord(')'): Builder.Append(')');
  end;

  if IsDigit(Escaped) then
  begin
    ReadOctalEscape(Escaped, Builder);
  end;
end;

procedure TType1Lexer.ReadOctalEscape(const FirstDigit: Integer; const Builder: TStringBuilder);
begin
  var Text: string := Chr(FirstDigit);
  for var Index := 2 to OctalDigitCount do
  begin
    Text := Text + Chr(GetChar);
  end;
  Builder.Append(Chr(ParseNumber(Text, OctalRadix)));
end;

function TType1Lexer.ReadCharString(const Count: Integer): TType1Token;
begin
  if Count < 0 then
  begin
    raise EPdfParseException.CreateFmt('String length %d is negative', [Count]);
  end;
  if Count > Length(FBuffer) then
  begin
    raise EPdfParseException.CreateFmt('String length %d is larger than input', [Count]);
  end;

  // The space after RD
  if not HasRemaining then
  begin
    raise EPdfParseException.Create('Premature end of buffer reached');
  end;
  Inc(FPosition);
  if Count > Length(FBuffer) - FPosition then
  begin
    raise EPdfParseException.Create('Premature end of buffer reached');
  end;

  Result := MakeToken(TType1TokenKind.CharString, '');
  SetLength(Result.Data, Count);
  if Count > 0 then
  begin
    Move(FBuffer[FPosition], Result.Data[0], Count);
  end;
  Inc(FPosition, Count);
end;

end.
