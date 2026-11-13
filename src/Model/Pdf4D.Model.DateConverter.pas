// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/util/DateConverter.java (3.0.8), toCalendar and toISO8601
unit Pdf4D.Model.DateConverter;

interface

uses
  System.SysUtils;

type
  // Reads the dates of a PDF as leniently as PDFBox does. A TDateTime has no time zone, so the value is the wall clock
  // time that the text gives, and the offset to UTC of that wall clock comes next to it.
  TDateConverter = record
    // Port of DateConverter.toCalendar(String). False when the text is no date. The time zone offset is in minutes.
    class function TryParse(const Text: string; out Value: TDateTime; out OffsetMinutes: Integer): Boolean; static;

    // Port of DateConverter.toISO8601: yyyy-MM-ddTHH:mm:ss+HH:MM
    class function ToIso8601(const Value: TDateTime; const OffsetMinutes: Integer): string; static;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  System.Generics.Collections;

const
  MillisPerMinute = 60 * 1000;
  MillisPerHour = 60 * MillisPerMinute;
  HalfDay = Int64(12) * MillisPerHour;
  FullDay = 2 * HalfDay;
  NoTimeZoneHours = -999;
  PdfDatePrefix = 'D:';
  Digits = ['0'..'9'];
  Quote = '''';

  AlphaStartFormats: array[0..6] of string = (
    'EEEE, dd MMM yy hh:mm:ss a',
    'EEEE, MMM dd, yy hh:mm:ss a',
    'EEEE, MMM dd, yy ''at'' hh:mma',
    'EEEE, MMM dd, yy',
    'EEEE MMM dd, yy HH:mm:ss',
    'EEEE MMM dd HH:mm:ss z yy',
    'EEEE MMM dd HH:mm:ss yy'
  );

  DigitStartFormats: array[0..7] of string = (
    'dd MMM yy HH:mm:ss',
    'dd MMM yy HH:mm',
    'yyyy MMM d',
    'yyyymmddhh:mm:ss',
    'H:m M/d/yy',
    'M/d/yy HH:mm:ss',
    'M/d/yy HH:mm',
    'M/d/yy'
  );

  MonthNames: array[0..11] of string = (
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'
  );
  ShortMonthNames: array[0..11] of string = (
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  );
  // Index 0 is Sunday, as in java.util.Calendar
  WeekdayNames: array[0..6] of string = (
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  );
  ShortWeekdayNames: array[0..6] of string = (
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  );
  AmPmNames: array[0..1] of string = ('AM', 'PM');

type
  // What java.util.GregorianCalendar holds in DateConverter: the wall clock time and the offset of its time zone
  TParsedDate = record
    Year: Integer;
    Month: Integer;
    Day: Integer;
    Hour: Integer;
    Minute: Integer;
    Second: Integer;
    OffsetMillis: Integer;

    class function Start: TParsedDate; static;
    function IsValid: Boolean;
  end;

  // The time zones that Java knows by name and that have no daylight saving time. Java's other zone names (PST, CST,
  // Europe/Paris and so on) need a time zone database and count as unknown here.
  TZoneNames = record
    class function TryGetOffset(const Name: string; out OffsetMillis: Integer): Boolean; static;
  end;

  // The fields that a SimpleDateFormat pattern sets, before they are checked like a non lenient calendar does
  TSimpleFields = record
    HasYear: Boolean;
    Year: Integer;
    AmbiguousYear: Boolean;
    HasMonth: Boolean;
    Month: Integer;
    HasDay: Boolean;
    Day: Integer;
    HasHourOfDay: Boolean;
    HourOfDay: Integer;
    HasHour12: Boolean;
    Hour12: Integer;
    HasAmPm: Boolean;
    AmPm: Integer;
    Minute: Integer;
    Second: Integer;
    HasDayOfWeek: Boolean;
    DayOfWeek: Integer;
    HasZone: Boolean;
    ZoneOffsetMillis: Integer;
  end;

  TPatternToken = record
    IsField: Boolean;
    Letter: Char;
    Count: Integer;
  end;

  // Port of the parsing half of java.text.SimpleDateFormat for the patterns of DateConverter, with English names
  TSimpleDateFormatParser = class
  private
    FText: string;
    // 1 based
    FPosition: Integer;
    FFields: TSimpleFields;
    FCenturyStart: TDateTime;

    class function Compile(const Pattern: string): TArray<TPatternToken>; static;
    class function IsFieldLetter(const Letter: Char): Boolean; static;

    function SkipBlanks: Boolean;
    function MatchLiteral(const Literal: Char): Boolean;
    function ParseNumber(const Count: Integer; const ObeyCount: Boolean; out Value: Integer; out DigitCount: Integer): Boolean;
    function ParsePlainNumber(const Count: Integer; const ObeyCount: Boolean; var Target: Integer): Boolean;
    function MatchString(const Names: array of string; out Index: Integer): Boolean;
    function ParseField(const Letter: Char; const Count: Integer; const ObeyCount: Boolean): Boolean;
    function ParseYear(const Count: Integer; const ObeyCount: Boolean): Boolean;
    function ParseMonth(const Count: Integer; const ObeyCount: Boolean): Boolean;
    function ParseHour12(const Count: Integer; const ObeyCount: Boolean): Boolean;
    function ParseDayOfWeek: Boolean;
    function ParseAmPm: Boolean;
    function ParseZone: Boolean;
    function ParseGmtZone: Boolean;
    function ParseNumericZone(const Start: Integer; const Sign: Integer; const WithColon: Boolean): Boolean;
    function ParseNamedZone: Boolean;
    function Establish(out Date: TParsedDate): Boolean;
    function ResolveHour: Integer;
    function WeekdayMatches(const Date: TParsedDate): Boolean;
    procedure ApplyAmbiguousYear(var Date: TParsedDate);

  public
    constructor Create(const Text: string);

    // False when the pattern does not fit or a value is out of range. Position (0 based) moves only on success.
    function Parse(const Pattern: string; var Position: Integer; out Date: TParsedDate): Boolean;
  end;

  TDateTextParser = class
  private
    FText: string;

    function TryBigEndianDate(var Where: Integer; out Date: TParsedDate): Boolean;
    function TrySimpleDate(const Patterns: array of string; var Where: Integer; out Date: TParsedDate): Boolean;
    function TryTimeZoneOffset(var Date: TParsedDate; var InitialWhere: Integer): Boolean;

  public
    constructor Create(const Text: string);

    class function ParseTimeField(const Text: string; var Where: Integer; const MaxLength: Integer; const Remedy: Integer): Integer; static;
    class function SkipOptionals(const Text: string; var Where: Integer; const Optionals: string): Char; static;
    class function SkipString(const Text: string; const Victim: string; var Where: Integer): Boolean; static;
    class function RestrainTimeZoneOffset(const ProposedOffset: Int64): Integer; static;

    function TryParseDate(var InitialWhere: Integer; out Date: TParsedDate): Boolean;
  end;

{ TParsedDate }

class function TParsedDate.Start: TParsedDate;
begin
  Result.Year := 1970;
  Result.Month := 1;
  Result.Day := 1;
  Result.Hour := 0;
  Result.Minute := 0;
  Result.Second := 0;
  Result.OffsetMillis := 0;
end;

function TParsedDate.IsValid: Boolean;
begin
  Result := ((Year >= 1) and (Year <= 9999) and (Month >= 1) and (Month <= 12) and (Day >= 1) and
             (Hour >= 0) and (Hour <= 23) and (Minute >= 0) and (Minute <= 59) and (Second >= 0) and (Second <= 59));
  if Result then
  begin
    Result := (Day <= DaysInAMonth(Year, Month));
  end;
end;

{ TZoneNames }

class function TZoneNames.TryGetOffset(const Name: string; out OffsetMillis: Integer): Boolean;
begin
  Result := True;
  if (Name = 'UTC') or (Name = 'GMT') then
  begin
    OffsetMillis := 0;
  end
  else if Name = 'EST' then
  begin
    OffsetMillis := -5 * MillisPerHour;
  end
  else if Name = 'MST' then
  begin
    OffsetMillis := -7 * MillisPerHour;
  end
  else if Name = 'HST' then
  begin
    OffsetMillis := -10 * MillisPerHour;
  end
  else
  begin
    OffsetMillis := 0;
    Result := False;
  end;
end;

{ TSimpleDateFormatParser }

constructor TSimpleDateFormatParser.Create(const Text: string);
begin
  inherited Create;
  FText := Text;
  // Two digit years fall in the 80 years before today and the 20 years after it
  FCenturyStart := IncYear(Now, -80);
end;

class function TSimpleDateFormatParser.IsFieldLetter(const Letter: Char): Boolean;
begin
  Result := CharInSet(Letter, ['E', 'd', 'M', 'y', 'H', 'h', 'm', 's', 'a', 'z']);
end;

class function TSimpleDateFormatParser.Compile(const Pattern: string): TArray<TPatternToken>;
begin
  const Tokens = TList<TPatternToken>.Create;
  try
    var Index := 1;
    while Index <= Pattern.Length do
    begin
      const Current = Pattern[Index];
      var Token: TPatternToken;
      Token.Letter := Current;
      Token.Count := 1;
      Token.IsField := False;
      if Current = Quote then
      begin
        Inc(Index);
        while (Index <= Pattern.Length) and (Pattern[Index] <> Quote) do
        begin
          Token.Letter := Pattern[Index];
          Tokens.Add(Token);
          Inc(Index);
        end;
      end
      else if IsFieldLetter(Current) then
      begin
        Token.IsField := True;
        while (Index < Pattern.Length) and (Pattern[Index + 1] = Current) do
        begin
          Inc(Token.Count);
          Inc(Index);
        end;
        Tokens.Add(Token);
      end
      else
      begin
        Tokens.Add(Token);
      end;
      Inc(Index);
    end;
    Result := Tokens.ToArray;
  finally
    Tokens.Free;
  end;
end;

function TSimpleDateFormatParser.SkipBlanks: Boolean;
begin
  while (FPosition <= FText.Length) and ((FText[FPosition] = ' ') or (FText[FPosition] = #9)) do
  begin
    Inc(FPosition);
  end;
  Result := (FPosition <= FText.Length);
end;

function TSimpleDateFormatParser.MatchLiteral(const Literal: Char): Boolean;
begin
  Result := ((FPosition <= FText.Length) and (FText[FPosition] = Literal));
  if Result then
  begin
    Inc(FPosition);
  end;
end;

function TSimpleDateFormatParser.ParseNumber(const Count: Integer; const ObeyCount: Boolean; out Value: Integer; out DigitCount: Integer): Boolean;
begin
  Value := 0;
  DigitCount := 0;
  var LastPosition := FText.Length;
  if ObeyCount then
  begin
    if (FPosition + Count - 1) > FText.Length then
    begin
      Exit(False);
    end;
    LastPosition := FPosition + Count - 1;
  end;

  var Index := FPosition;
  while (Index <= LastPosition) and CharInSet(FText[Index], Digits) do
  begin
    if DigitCount >= 9 then
    begin
      Exit(False);
    end;
    Value := Value * 10 + (Ord(FText[Index]) - Ord('0'));
    Inc(DigitCount);
    Inc(Index);
  end;

  Result := (DigitCount > 0);
  if Result then
  begin
    FPosition := Index;
  end;
end;

function TSimpleDateFormatParser.ParsePlainNumber(const Count: Integer; const ObeyCount: Boolean; var Target: Integer): Boolean;
begin
  var DigitCount: Integer;
  Result := ParseNumber(Count, ObeyCount, Target, DigitCount);
end;

// Port of SimpleDateFormat.matchString: the longest name that the text starts with, ignoring case
function TSimpleDateFormatParser.MatchString(const Names: array of string; out Index: Integer): Boolean;
begin
  Index := -1;
  var BestLength := 0;
  for var Candidate := 0 to High(Names) do
  begin
    const NameLength = Names[Candidate].Length;
    const Fits = ((NameLength > BestLength) and (NameLength <= FText.Length - FPosition + 1));
    if Fits and SameText(Copy(FText, FPosition, NameLength), Names[Candidate]) then
    begin
      Index := Candidate;
      BestLength := NameLength;
    end;
  end;

  Result := (Index >= 0);
  if Result then
  begin
    Inc(FPosition, BestLength);
  end;
end;

function TSimpleDateFormatParser.ParseYear(const Count: Integer; const ObeyCount: Boolean): Boolean;
begin
  var Value, DigitCount: Integer;
  Result := ParseNumber(Count, ObeyCount, Value, DigitCount);
  if not Result then
  begin
    Exit;
  end;

  if (Count <= 2) and (DigitCount = 2) then
  begin
    const CenturyStartYear = YearOf(FCenturyStart);
    const AmbiguousTwoDigitYear = CenturyStartYear mod 100;
    FFields.AmbiguousYear := (Value = AmbiguousTwoDigitYear);
    if Value < AmbiguousTwoDigitYear then
    begin
      Value := Value + 100;
    end;
    Value := Value + (CenturyStartYear div 100) * 100;
  end;

  FFields.HasYear := True;
  FFields.Year := Value;
end;

function TSimpleDateFormatParser.ParseMonth(const Count: Integer; const ObeyCount: Boolean): Boolean;
begin
  if Count <= 2 then
  begin
    FFields.HasMonth := True;
    Result := ParsePlainNumber(Count, ObeyCount, FFields.Month);
    Exit;
  end;

  var Index: Integer;
  Result := (MatchString(MonthNames, Index) or MatchString(ShortMonthNames, Index));
  if Result then
  begin
    FFields.HasMonth := True;
    FFields.Month := Index + 1;
  end;
end;

function TSimpleDateFormatParser.ParseHour12(const Count: Integer; const ObeyCount: Boolean): Boolean;
begin
  var Value: Integer;
  Result := (ParsePlainNumber(Count, ObeyCount, Value) and (Value >= 1) and (Value <= 12));
  if Result then
  begin
    FFields.HasHour12 := True;
    FFields.Hour12 := Value mod 12;
  end;
end;

function TSimpleDateFormatParser.ParseDayOfWeek: Boolean;
begin
  var Index: Integer;
  Result := (MatchString(WeekdayNames, Index) or MatchString(ShortWeekdayNames, Index));
  if Result then
  begin
    FFields.HasDayOfWeek := True;
    FFields.DayOfWeek := Index;
  end;
end;

function TSimpleDateFormatParser.ParseAmPm: Boolean;
begin
  var Index: Integer;
  Result := MatchString(AmPmNames, Index);
  if Result then
  begin
    FFields.HasAmPm := True;
    FFields.AmPm := Index;
  end;
end;

// Port of SimpleDateFormat.subParseNumericZone: hh:mm with a colon, hhmm without
function TSimpleDateFormatParser.ParseNumericZone(const Start: Integer; const Sign: Integer; const WithColon: Boolean): Boolean;
begin
  var Index := Start;
  Result := False;
  if (Index > FText.Length) or not CharInSet(FText[Index], Digits) then
  begin
    Exit;
  end;

  var Hours := Ord(FText[Index]) - Ord('0');
  Inc(Index);
  if (Index <= FText.Length) and CharInSet(FText[Index], Digits) then
  begin
    Hours := Hours * 10 + (Ord(FText[Index]) - Ord('0'));
    Inc(Index);
  end
  else if not WithColon then
  begin
    Exit;
  end;

  if (Hours > 23) or (Index > FText.Length) then
  begin
    Exit;
  end;

  if WithColon then
  begin
    if FText[Index] <> ':' then
    begin
      Exit;
    end;
    Inc(Index);
  end;

  if (Index + 1) > FText.Length then
  begin
    Exit;
  end;
  if not (CharInSet(FText[Index], Digits) and CharInSet(FText[Index + 1], Digits)) then
  begin
    Exit;
  end;
  const Minutes = (Ord(FText[Index]) - Ord('0')) * 10 + (Ord(FText[Index + 1]) - Ord('0'));
  if Minutes > 59 then
  begin
    Exit;
  end;

  FFields.HasZone := True;
  FFields.ZoneOffsetMillis := Sign * (Hours * MillisPerHour + Minutes * MillisPerMinute);
  FPosition := Index + 2;
  Result := True;
end;

function TSimpleDateFormatParser.ParseGmtZone: Boolean;
begin
  Inc(FPosition, 3);
  var Sign := 0;
  if FPosition <= FText.Length then
  begin
    if FText[FPosition] = '+' then
    begin
      Sign := 1;
    end
    else if FText[FPosition] = '-' then
    begin
      Sign := -1;
    end;
  end;

  if Sign = 0 then
  begin
    FFields.HasZone := True;
    FFields.ZoneOffsetMillis := 0;
    Exit(True);
  end;
  Result := ParseNumericZone(FPosition + 1, Sign, True);
end;

function TSimpleDateFormatParser.ParseNamedZone: Boolean;
begin
  var Last := FPosition;
  while (Last <= FText.Length) and CharInSet(FText[Last], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(Last);
  end;

  var OffsetMillis: Integer;
  Result := TZoneNames.TryGetOffset(Copy(FText, FPosition, Last - FPosition), OffsetMillis);
  if Result then
  begin
    FFields.HasZone := True;
    FFields.ZoneOffsetMillis := OffsetMillis;
    FPosition := Last;
  end;
end;

function TSimpleDateFormatParser.ParseZone: Boolean;
begin
  const Current = FText[FPosition];
  if Current = '+' then
  begin
    Result := ParseNumericZone(FPosition + 1, 1, False);
  end
  else if Current = '-' then
  begin
    Result := ParseNumericZone(FPosition + 1, -1, False);
  end
  else if ((Current = 'G') or (Current = 'g')) and SameText(Copy(FText, FPosition, 3), 'GMT') then
  begin
    Result := ParseGmtZone;
  end
  else
  begin
    Result := ParseNamedZone;
  end;
end;

function TSimpleDateFormatParser.ParseField(const Letter: Char; const Count: Integer; const ObeyCount: Boolean): Boolean;
begin
  if not SkipBlanks then
  begin
    Exit(False);
  end;

  case Letter of
    'y':
    begin
      Result := ParseYear(Count, ObeyCount);
    end;
    'M':
    begin
      Result := ParseMonth(Count, ObeyCount);
    end;
    'd':
    begin
      FFields.HasDay := True;
      Result := ParsePlainNumber(Count, ObeyCount, FFields.Day);
    end;
    'H':
    begin
      FFields.HasHourOfDay := True;
      Result := ParsePlainNumber(Count, ObeyCount, FFields.HourOfDay);
    end;
    'h':
    begin
      Result := ParseHour12(Count, ObeyCount);
    end;
    'm':
    begin
      Result := ParsePlainNumber(Count, ObeyCount, FFields.Minute);
    end;
    's':
    begin
      Result := ParsePlainNumber(Count, ObeyCount, FFields.Second);
    end;
    'E':
    begin
      Result := ParseDayOfWeek;
    end;
    'a':
    begin
      Result := ParseAmPm;
    end;
    'z':
    begin
      Result := ParseZone;
    end;
  else
    Result := False;
  end;
end;

function TSimpleDateFormatParser.ResolveHour: Integer;
begin
  Result := 0;
  if FFields.HasHourOfDay then
  begin
    Result := FFields.HourOfDay;
  end
  else if FFields.HasHour12 then
  begin
    Result := FFields.Hour12;
    if FFields.HasAmPm then
    begin
      Result := Result + 12 * FFields.AmPm;
    end;
  end
  else if FFields.HasAmPm then
  begin
    Result := 12 * FFields.AmPm;
  end;
end;

// A non lenient calendar rejects a weekday that does not belong to the date
function TSimpleDateFormatParser.WeekdayMatches(const Date: TParsedDate): Boolean;
begin
  // Sunday is 0 here, DayOfWeek gives 1
  Result := ((DayOfWeek(EncodeDate(Date.Year, Date.Month, Date.Day)) - 1) = FFields.DayOfWeek);
end;

procedure TSimpleDateFormatParser.ApplyAmbiguousYear(var Date: TParsedDate);
begin
  if FFields.AmbiguousYear and (EncodeDate(Date.Year, Date.Month, Date.Day) < DateOf(FCenturyStart)) then
  begin
    Inc(Date.Year, 100);
  end;
end;

function TSimpleDateFormatParser.Establish(out Date: TParsedDate): Boolean;
begin
  Date := TParsedDate.Start;
  if FFields.HasYear then
  begin
    Date.Year := FFields.Year;
  end;
  if FFields.HasMonth then
  begin
    Date.Month := FFields.Month;
  end;
  if FFields.HasDay then
  begin
    Date.Day := FFields.Day;
  end;
  Date.Hour := ResolveHour;
  Date.Minute := FFields.Minute;
  Date.Second := FFields.Second;

  Result := Date.IsValid;
  if Result and FFields.HasDayOfWeek then
  begin
    Result := WeekdayMatches(Date);
  end;
  if Result and FFields.AmbiguousYear then
  begin
    ApplyAmbiguousYear(Date);
    Result := Date.IsValid;
  end;
  if Result and FFields.HasZone then
  begin
    Date.OffsetMillis := FFields.ZoneOffsetMillis;
  end;
end;

function TSimpleDateFormatParser.Parse(const Pattern: string; var Position: Integer; out Date: TParsedDate): Boolean;
begin
  FFields := Default(TSimpleFields);
  FPosition := Position + 1;
  const Tokens = Compile(Pattern);
  for var Index := 0 to High(Tokens) do
  begin
    const Token = Tokens[Index];
    if Token.IsField then
    begin
      // A field that is followed by another field takes exactly the number of digits of its pattern letters
      const ObeyCount = ((Index < High(Tokens)) and Tokens[Index + 1].IsField);
      if not ParseField(Token.Letter, Token.Count, ObeyCount) then
      begin
        Exit(False);
      end;
    end
    else if not MatchLiteral(Token.Letter) then
    begin
      Exit(False);
    end;
  end;

  Result := Establish(Date);
  if Result then
  begin
    Position := FPosition - 1;
  end;
end;

{ TDateTextParser }

constructor TDateTextParser.Create(const Text: string);
begin
  inherited Create;
  FText := Text;
end;

class function TDateTextParser.ParseTimeField(const Text: string; var Where: Integer; const MaxLength: Integer; const Remedy: Integer): Integer;
begin
  Result := 0;
  var Index := Where;
  const Limit = Index + Min(MaxLength, Text.Length - Index);
  while (Index < Limit) and CharInSet(Text[Index + 1], Digits) do
  begin
    // 19 digits of a fraction can overflow, and nobody reads that value
    Result := (Result * 10 + (Ord(Text[Index + 1]) - Ord('0'))) mod 1000000000;
    Inc(Index);
  end;

  if Index = Where then
  begin
    Exit(Remedy);
  end;
  Where := Index;
end;

class function TDateTextParser.SkipOptionals(const Text: string; var Where: Integer; const Optionals: string): Char;
begin
  Result := ' ';
  while (Where < Text.Length) and (Optionals.IndexOf(Text[Where + 1]) >= 0) do
  begin
    if Text[Where + 1] <> ' ' then
    begin
      Result := Text[Where + 1];
    end;
    Inc(Where);
  end;
end;

class function TDateTextParser.SkipString(const Text: string; const Victim: string; var Where: Integer): Boolean;
begin
  Result := (Copy(Text, Where + 1, Victim.Length) = Victim);
  if Result then
  begin
    Inc(Where, Victim.Length);
  end;
end;

class function TDateTextParser.RestrainTimeZoneOffset(const ProposedOffset: Int64): Integer;
begin
  // Time zones between -14:00 and 14:00 are valid
  if (ProposedOffset <= 14 * Int64(MillisPerHour)) and (ProposedOffset >= -14 * Int64(MillisPerHour)) then
  begin
    Exit(Integer(ProposedOffset));
  end;

  // Constrain the offset to the range -11:59 through +12:00
  var Offset := ((ProposedOffset + HalfDay) mod FullDay + FullDay) mod FullDay;
  if Offset = 0 then
  begin
    Exit(HalfDay);
  end;
  Offset := (Offset - HalfDay) mod HalfDay;
  Result := Integer(Offset);
end;

// Port of DateConverter.parseTZoffset
function TDateTextParser.TryTimeZoneOffset(var Date: TParsedDate; var InitialWhere: Integer): Boolean;
begin
  var Where := InitialWhere;
  var Sign := SkipOptionals(FText, Where, 'Z+- ');
  const HadGmt = ((Sign = 'Z') or SkipString(FText, 'GMT', Where) or SkipString(FText, 'UTC', Where));
  if HadGmt then
  begin
    Sign := SkipOptionals(FText, Where, '+- ');
  end;

  const Hours = ParseTimeField(FText, Where, 2, NoTimeZoneHours);
  SkipOptionals(FText, Where, ': ' + Quote);
  const Minutes = ParseTimeField(FText, Where, 2, 0);
  SkipOptionals(FText, Where, ' ' + Quote);

  var OffsetMillis := 0;
  if Hours <> NoTimeZoneHours then
  begin
    var HourSign := 1;
    if Sign = '-' then
    begin
      HourSign := -1;
    end;
    OffsetMillis := RestrainTimeZoneOffset(HourSign * (Hours * Int64(MillisPerHour) + Minutes * Int64(MillisPerMinute)));
  end
  else if not HadGmt then
  begin
    const ZoneText = Copy(FText, InitialWhere + 1, FText.Length).Trim;
    if not TZoneNames.TryGetOffset(ZoneText, OffsetMillis) then
    begin
      Exit(False);
    end;
    Where := FText.Length;
  end;

  Date.OffsetMillis := OffsetMillis;
  InitialWhere := Where;
  Result := True;
end;

// Port of DateConverter.parseBigEndianDate
function TDateTextParser.TryBigEndianDate(var Where: Integer; out Date: TParsedDate): Boolean;
begin
  Date := TParsedDate.Start;
  var Position := Where;
  Date.Year := ParseTimeField(FText, Position, 4, 0);
  if Position <> Where + 4 then
  begin
    Exit(False);
  end;

  SkipOptionals(FText, Position, '/- ');
  Date.Month := ParseTimeField(FText, Position, 2, 1);
  SkipOptionals(FText, Position, '/- ');
  Date.Day := ParseTimeField(FText, Position, 2, 1);
  SkipOptionals(FText, Position, ' T');
  Date.Hour := ParseTimeField(FText, Position, 2, 0);
  SkipOptionals(FText, Position, ': ');
  Date.Minute := ParseTimeField(FText, Position, 2, 0);
  SkipOptionals(FText, Position, ': ');
  Date.Second := ParseTimeField(FText, Position, 2, 0);
  if SkipOptionals(FText, Position, '.') = '.' then
  begin
    // Fractions of a second: up to 19 digits are skipped
    ParseTimeField(FText, Position, 19, 0);
  end;

  if not Date.IsValid then
  begin
    Exit(False);
  end;

  Where := Position;
  SkipOptionals(FText, Where, ' ');
  Result := True;
end;

function TDateTextParser.TrySimpleDate(const Patterns: array of string; var Where: Integer; out Date: TParsedDate): Boolean;
begin
  const Parser = TSimpleDateFormatParser.Create(FText);
  try
    for var Pattern in Patterns do
    begin
      var Position := Where;
      if Parser.Parse(Pattern, Position, Date) then
      begin
        Where := Position;
        SkipOptionals(FText, Where, ' ');
        Exit(True);
      end;
    end;
  finally
    Parser.Free;
  end;
  Result := False;
end;

// Port of DateConverter.parseDate
function TDateTextParser.TryParseDate(var InitialWhere: Integer; out Date: TParsedDate): Boolean;
begin
  Result := False;
  if (FText = '') or (FText.Trim = PdfDatePrefix) then
  begin
    Exit;
  end;

  var Where := InitialWhere;
  SkipOptionals(FText, Where, ' ');
  const StartPosition = Where;
  if StartPosition >= FText.Length then
  begin
    Exit;
  end;

  var LongestLength := -1;
  var LongestDate := TParsedDate.Start;
  var Candidate: TParsedDate;
  if TryBigEndianDate(Where, Candidate) and ((Where = FText.Length) or TryTimeZoneOffset(Candidate, Where)) then
  begin
    if Where = FText.Length then
    begin
      InitialWhere := Where;
      Date := Candidate;
      Exit(True);
    end;
    LongestLength := Where;
    LongestDate := Candidate;
  end;

  Where := StartPosition;
  var Found: Boolean;
  if CharInSet(FText[StartPosition + 1], Digits) then
  begin
    Found := TrySimpleDate(DigitStartFormats, Where, Candidate);
  end
  else
  begin
    Found := TrySimpleDate(AlphaStartFormats, Where, Candidate);
  end;

  if Found and ((Where = FText.Length) or TryTimeZoneOffset(Candidate, Where)) then
  begin
    if Where = FText.Length then
    begin
      InitialWhere := Where;
      Date := Candidate;
      Exit(True);
    end;
    if Where > LongestLength then
    begin
      LongestLength := Where;
      LongestDate := Candidate;
    end;
  end;

  if LongestLength >= 0 then
  begin
    InitialWhere := LongestLength;
    Date := LongestDate;
    Result := True;
  end;
end;

{ TDateConverter }

class function TDateConverter.TryParse(const Text: string; out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Value := 0;
  OffsetMinutes := 0;
  if Text.Trim = '' then
  begin
    Exit(False);
  end;

  var Where := 0;
  TDateTextParser.SkipOptionals(Text, Where, ' ');
  TDateTextParser.SkipString(Text, PdfDatePrefix, Where);

  var Date: TParsedDate;
  const Parser = TDateTextParser.Create(Text);
  try
    Result := (Parser.TryParseDate(Where, Date) and (Where = Text.Length));
  finally
    Parser.Free;
  end;

  if Result then
  begin
    Value := EncodeDateTime(Date.Year, Date.Month, Date.Day, Date.Hour, Date.Minute, Date.Second, 0);
    OffsetMinutes := Date.OffsetMillis div MillisPerMinute;
  end;
end;

class function TDateConverter.ToIso8601(const Value: TDateTime; const OffsetMinutes: Integer): string;
begin
  var Sign := '+';
  if OffsetMinutes < 0 then
  begin
    Sign := '-';
  end;

  const AbsoluteMinutes = Abs(OffsetMinutes);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d%s%.2d:%.2d',
                   [YearOf(Value), MonthOf(Value), DayOf(Value), HourOf(Value), MinuteOf(Value), SecondOf(Value),
                    Sign, AbsoluteMinutes div 60, AbsoluteMinutes mod 60]);
end;

end.
