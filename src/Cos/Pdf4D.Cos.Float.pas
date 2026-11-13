// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSFloat.java (3.0.8)
unit Pdf4D.Cos.Float;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Number;

type
  TCosFloat = class(TCosNumber)
  private
    const MinNormalSingle = 1.17549435E-38;
    const MaxSingleValue = 3.4028234663852886E38;
    const MaxFractionDigits = 100;
    // Beyond this power of ten a value is far outside the range of a Single, so it is clamped or becomes 0 without parsing
    const MaxParsedExponent = 50;

  private
    FValue: Single;

    class function TryParseDecimal(const Text: string; out Value: Single): Boolean; static;
    class function TrimJava(const Text: string): string; static;
    class function TryNormalizeDecimal(const Text: string; out Normalized: string; out ApproximateExponent: Integer): Boolean; static;
    class function ParseExponentDigits(const Text: string; const Start: Integer): Integer; static;
    class function CoerceDouble(const Value: Double): Single; static;
    class function ValueOutOfDoubleRange(const Normalized: string; const ApproximateExponent: Integer): Single; static;
    class function TryRepair(const Text: string; out Repaired: string): Boolean; static;
    class function HasMisplacedMinusAfterZero(const Text: string): Boolean; static;
    class function HasMisplacedMinusInFraction(const Text: string): Boolean; static;
    class function AllDigits(const Text: string; const Start: Integer): Boolean; static;

  public
    // Port of the tolerant COSFloat(String) constructor.
    class function Parse(const Text: string): TCosFloat; static;

    constructor Create(const Value: Single);

    function FloatValue: Single; override;
    function IntValue: Integer; override;
    function LongValue: Int64; override;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

{ TCosFloat }

class function TCosFloat.Parse(const Text: string): TCosFloat;
begin
  var Value: Single;
  if TryParseDecimal(Text, Value) then
  begin
    Exit(TCosFloat.Create(Value));
  end;

  var Repaired: string;
  if not TryRepair(Text, Repaired) then
  begin
    raise EPdfParseException.CreateFmt('Error expected floating point number actual=''%s''', [Text]);
  end;

  if not TryParseDecimal(Repaired, Value) then
  begin
    raise EPdfParseException.CreateFmt('Error expected floating point number actual=''%s''', [Repaired]);
  end;

  Result := TCosFloat.Create(Value);
end;

constructor TCosFloat.Create(const Value: Single);
begin
  inherited Create;
  FValue := Value;
end;

function TCosFloat.FloatValue: Single;
begin
  Result := FValue;
end;

function TCosFloat.IntValue: Integer;
begin
  // Saturates like the (int) cast in Java; NaN becomes 0
  if IsNan(FValue) then
  begin
    Exit(0);
  end;

  if FValue >= 2147483648.0 then
  begin
    Exit(High(Integer));
  end;

  if FValue <= -2147483648.0 then
  begin
    Exit(Low(Integer));
  end;

  Result := Trunc(FValue);
end;

function TCosFloat.LongValue: Int64;
begin
  if IsNan(FValue) then
  begin
    Exit(0);
  end;

  if FValue >= 9223372036854775808.0 then
  begin
    Exit(High(Int64));
  end;

  if FValue <= -9223372036854775808.0 then
  begin
    Exit(Low(Int64));
  end;

  Result := Trunc(FValue);
end;

class function TCosFloat.TryParseDecimal(const Text: string; out Value: Single): Boolean;
begin
  Value := 0;

  var Normalized: string;
  var ApproximateExponent: Integer;
  if not TryNormalizeDecimal(TrimJava(Text), Normalized, ApproximateExponent) then
  begin
    Exit(False);
  end;

  var Parsed: Double;
  const OutOfSingleRange = (ApproximateExponent > MaxParsedExponent) or (ApproximateExponent < -MaxParsedExponent);
  if (not OutOfSingleRange) and TryStrToFloat(Normalized, Parsed, TFormatSettings.Invariant) then
  begin
    Value := CoerceDouble(Parsed);
  end
  else
  begin
    Value := ValueOutOfDoubleRange(Normalized, ApproximateExponent);
  end;
  Result := True;
end;

// Java's String.trim removes every character up to and including the space
class function TCosFloat.TrimJava(const Text: string): string;
begin
  var First := 1;
  var Last := System.Length(Text);
  while (First <= Last) and (Text[First] <= ' ') do
  begin
    Inc(First);
  end;

  while (Last >= First) and (Text[Last] <= ' ') do
  begin
    Dec(Last);
  end;

  Result := Copy(Text, First, Last - First + 1);
end;

// Accepts the decimal syntax of Java's Float.parseFloat (sign, digits, fraction, exponent, type suffix).
// NaN, Infinity and hexadecimal floats are not accepted.
class function TCosFloat.TryNormalizeDecimal(const Text: string; out Normalized: string; out ApproximateExponent: Integer): Boolean;
begin
  Normalized := '';
  ApproximateExponent := 0;

  var Last := System.Length(Text);
  if (Last > 1) and CharInSet(Text[Last], ['f', 'F', 'd', 'D']) then
  begin
    Dec(Last);
  end;

  var Index := 1;
  var Sign := '';
  if (Index <= Last) and CharInSet(Text[Index], ['+', '-']) then
  begin
    if Text[Index] = '-' then
    begin
      Sign := '-';
    end;
    Inc(Index);
  end;

  // Scan with indices and copy once: appending a character at a time is quadratic for a hostile long token
  const IntegerStart = Index;
  while (Index <= Last) and CharInSet(Text[Index], ['0'..'9']) do
  begin
    Inc(Index);
  end;
  var IntegerDigits := Copy(Text, IntegerStart, Index - IntegerStart);

  var FractionDigits := '';
  if (Index <= Last) and (Text[Index] = '.') then
  begin
    Inc(Index);
    const FractionStart = Index;
    while (Index <= Last) and CharInSet(Text[Index], ['0'..'9']) do
    begin
      Inc(Index);
    end;
    // Digits beyond this cannot change a Single, and TryStrToFloat misparses digit strings of a few hundred characters
    FractionDigits := Copy(Text, FractionStart, Min(Index - FractionStart, MaxFractionDigits));
  end;

  if (IntegerDigits = '') and (FractionDigits = '') then
  begin
    Exit(False);
  end;

  // Leading zeros carry no value, and TryStrToFloat misparses a digit string of a few hundred characters
  IntegerDigits := IntegerDigits.TrimLeft(['0']);

  var ExponentText := '';
  var ExponentValue := 0;
  if (Index <= Last) and CharInSet(Text[Index], ['e', 'E']) then
  begin
    Inc(Index);
    var ExponentSign := '+';
    if (Index <= Last) and CharInSet(Text[Index], ['+', '-']) then
    begin
      ExponentSign := Text[Index];
      Inc(Index);
    end;

    const DigitsStart = Index;
    while (Index <= Last) and CharInSet(Text[Index], ['0'..'9']) do
    begin
      Inc(Index);
    end;

    if Index = DigitsStart then
    begin
      Exit(False);
    end;

    ExponentValue := ParseExponentDigits(Text, DigitsStart);
    if ExponentSign = '-' then
    begin
      ExponentValue := -ExponentValue;
    end;
    ExponentText := 'E' + ExponentSign + Copy(Text, DigitsStart, Index - DigitsStart);
  end;

  if Index <= Last then
  begin
    Exit(False);
  end;

  if IntegerDigits = '' then
  begin
    IntegerDigits := '0';
  end;

  if FractionDigits = '' then
  begin
    FractionDigits := '0';
  end;

  Normalized := Sign + IntegerDigits + '.' + FractionDigits + ExponentText;

  const SignificantInteger = IntegerDigits.TrimLeft(['0']);
  if SignificantInteger <> '' then
  begin
    ApproximateExponent := ExponentValue + System.Length(SignificantInteger);
  end
  else
  begin
    const SignificantFraction = FractionDigits.TrimLeft(['0']);
    const LeadingFractionZeros = System.Length(FractionDigits) - System.Length(SignificantFraction);
    // A value of zero stays zero whatever its exponent
    if SignificantFraction <> '' then
    begin
      ApproximateExponent := ExponentValue - LeadingFractionZeros;
    end;
  end;
  Result := True;
end;

// Saturates at 9,999,999: only the sign and rough size of an exponent matter once it is out of range
class function TCosFloat.ParseExponentDigits(const Text: string; const Start: Integer): Integer;
begin
  Result := 0;
  var Index := Start;
  while (Index <= System.Length(Text)) and CharInSet(Text[Index], ['0'..'9']) and (Result < 9999999) do
  begin
    Result := Result * 10 + (Ord(Text[Index]) - Ord('0'));
    Inc(Index);
  end;
end;

// Port of COSFloat.coerce: infinity becomes the largest float, values below the smallest normal float become 0
class function TCosFloat.CoerceDouble(const Value: Double): Single;
begin
  if Value > MaxSingleValue then
  begin
    Exit(MaxSingleValue);
  end;

  if Value < -MaxSingleValue then
  begin
    Exit(-MaxSingleValue);
  end;

  Result := Value;
  if Abs(Result) < MinNormalSingle then
  begin
    Result := 0;
  end;
end;

// TryStrToFloat fails on a value outside the range of a Double
class function TCosFloat.ValueOutOfDoubleRange(const Normalized: string; const ApproximateExponent: Integer): Single;
begin
  if ApproximateExponent <= 0 then
  begin
    Exit(0);
  end;

  if Normalized.StartsWith('-') then
  begin
    Result := -MaxSingleValue;
  end
  else
  begin
    Result := MaxSingleValue;
  end;
end;

class function TCosFloat.TryRepair(const Text: string; out Repaired: string): Boolean;
begin
  Result := True;
  if Text.StartsWith('--') then
  begin
    // PDFBOX-4289 has --16.33
    Repaired := Copy(Text, 2, System.Length(Text));
  end
  else if HasMisplacedMinusAfterZero(Text) then
  begin
    // PDFBOX-2990 has 0.00000-33917698, PDFBOX-3500 has 0.-262
    Repaired := '-' + StringReplace(Text, '-', '', []);
  end
  else if HasMisplacedMinusInFraction(Text) then
  begin
    // PDFBOX-5829 has -12.-1
    Repaired := '-' + StringReplace(Text, '-', '', [rfReplaceAll]);
  end
  else
  begin
    Repaired := '';
    Result := False;
  end;
end;

// ^0\.0*-\d+
class function TCosFloat.HasMisplacedMinusAfterZero(const Text: string): Boolean;
begin
  if not Text.StartsWith('0.') then
  begin
    Exit(False);
  end;

  var Index := 3;
  while (Index <= System.Length(Text)) and (Text[Index] = '0') do
  begin
    Inc(Index);
  end;

  Result := (Index <= System.Length(Text)) and (Text[Index] = '-') and AllDigits(Text, Index + 1);
end;

// ^-\d+\.-\d+
class function TCosFloat.HasMisplacedMinusInFraction(const Text: string): Boolean;
begin
  if not Text.StartsWith('-') then
  begin
    Exit(False);
  end;

  var Index := 2;
  while (Index <= System.Length(Text)) and CharInSet(Text[Index], ['0'..'9']) do
  begin
    Inc(Index);
  end;

  Result := (Index > 2) and (Index + 1 <= System.Length(Text)) and (Text[Index] = '.') and
            (Text[Index + 1] = '-') and AllDigits(Text, Index + 2);
end;

// True when Text holds one or more digits from Start to the end
class function TCosFloat.AllDigits(const Text: string; const Start: Integer): Boolean;
begin
  if Start > System.Length(Text) then
  begin
    Exit(False);
  end;

  for var Index := Start to System.Length(Text) do
  begin
    if not CharInSet(Text[Index], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;

  Result := True;
end;

end.
