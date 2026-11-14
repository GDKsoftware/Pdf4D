// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Replaces java.text.Normalizer (NFKC) as used by pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/SaslPrep.java (3.0.8)
// The algorithm is the one of Unicode Standard Annex 15: full compatibility decomposition, canonical ordering, canonical composition.
unit Pdf4D.Encryption.UnicodeNormalization;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TCodePoints = TArray<Integer>;

  TPdfUnicodeNormalizer = class
  private
    FDecompositions: TDictionary<Integer, TCodePoints>;
    FCombiningClasses: TDictionary<Integer, Integer>;
    FCompositions: TDictionary<Int64, Integer>;

    class function ParseHex(const Text: string): Integer; static;
    class function ToCodePoints(const Text: string): TCodePoints; static;
    class function FromCodePoints(const CodePoints: TCodePoints): string; static;
    class function CompositionKey(const First, Second: Integer): Int64; static;

    procedure LoadDecompositions;
    procedure LoadCombiningClasses;
    procedure LoadCompositions;
    procedure AddDecomposition(const Entry: string);
    procedure AddCombiningClass(const Entry: string);
    procedure AddComposition(const Entry: string);
    function CombiningClassOf(const CodePoint: Integer): Integer;
    function Decompose(const CodePoints: TCodePoints): TCodePoints;
    procedure AppendDecomposed(const CodePoint: Integer; const Target: TList<Integer>);
    procedure AppendHangulDecomposition(const CodePoint: Integer; const Target: TList<Integer>);
    procedure OrderCanonically(const CodePoints: TCodePoints);
    function Compose(const CodePoints: TCodePoints): TCodePoints;
    function TryCompose(const First, Second: Integer; out Composite: Integer): Boolean;
    function TryComposeHangul(const First, Second: Integer; out Composite: Integer): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    // NFKC. A lone surrogate stays as it is.
    function NormalizeNfkc(const Text: string): string;
  end;

implementation

uses
  Pdf4D.Encryption.UnicodeData;

const
  EntrySeparator = ';';
  ValueSeparator = '=';
  CodePointSeparator = ' ';
  RangeSeparator = '-';
  HighSurrogateFirst = $D800;
  HighSurrogateLast = $DBFF;
  LowSurrogateFirst = $DC00;
  LowSurrogateLast = $DFFF;
  SupplementaryBase = $10000;
  SurrogateShift = 10;
  SurrogateMask = $3FF;
  UnlimitedClass = 256;
  HangulSyllableBase = $AC00;
  HangulLeadBase = $1100;
  HangulVowelBase = $1161;
  HangulTrailBase = $11A7;
  HangulLeadCount = 19;
  HangulVowelCount = 21;
  HangulTrailCount = 28;
  HangulVowelTrailCount = HangulVowelCount * HangulTrailCount;
  HangulSyllableCount = HangulLeadCount * HangulVowelTrailCount;
  KeyShift = 32;

{ TPdfUnicodeNormalizer }

constructor TPdfUnicodeNormalizer.Create;
begin
  inherited Create;
  FDecompositions := TDictionary<Integer, TCodePoints>.Create;
  FCombiningClasses := TDictionary<Integer, Integer>.Create;
  FCompositions := TDictionary<Int64, Integer>.Create;
  LoadDecompositions;
  LoadCombiningClasses;
  LoadCompositions;
end;

destructor TPdfUnicodeNormalizer.Destroy;
begin
  FDecompositions.Free;
  FCombiningClasses.Free;
  FCompositions.Free;
  inherited;
end;

class function TPdfUnicodeNormalizer.ParseHex(const Text: string): Integer;
begin
  Result := StrToInt('$' + Text);
end;

class function TPdfUnicodeNormalizer.CompositionKey(const First, Second: Integer): Int64;
begin
  Result := (Int64(First) shl KeyShift) or Int64(Second);
end;

class function TPdfUnicodeNormalizer.ToCodePoints(const Text: string): TCodePoints;
begin
  SetLength(Result, Length(Text));
  var Count := 0;
  var Position := 1;
  while Position <= Length(Text) do
  begin
    var CodePoint := Ord(Text[Position]);
    const IsHigh = ((CodePoint >= HighSurrogateFirst) and (CodePoint <= HighSurrogateLast));
    if IsHigh and (Position < Length(Text)) then
    begin
      const Low = Ord(Text[Position + 1]);
      if (Low >= LowSurrogateFirst) and (Low <= LowSurrogateLast) then
      begin
        CodePoint := SupplementaryBase + ((CodePoint - HighSurrogateFirst) shl SurrogateShift) + (Low - LowSurrogateFirst);
        Inc(Position);
      end;
    end;
    Result[Count] := CodePoint;
    Inc(Count);
    Inc(Position);
  end;
  SetLength(Result, Count);
end;

class function TPdfUnicodeNormalizer.FromCodePoints(const CodePoints: TCodePoints): string;
begin
  Result := '';
  for var CodePoint in CodePoints do
  begin
    if CodePoint >= SupplementaryBase then
    begin
      const Offset = CodePoint - SupplementaryBase;
      Result := Result + Char(HighSurrogateFirst + (Offset shr SurrogateShift)) + Char(LowSurrogateFirst + (Offset and SurrogateMask));
    end
    else
    begin
      Result := Result + Char(CodePoint);
    end;
  end;
end;

{ loading the data }

procedure TPdfUnicodeNormalizer.AddDecomposition(const Entry: string);
begin
  const Parts = Entry.Split([ValueSeparator]);
  const Values = Parts[1].Split([CodePointSeparator]);
  var Decomposition: TCodePoints;
  SetLength(Decomposition, Length(Values));
  for var Position := 0 to High(Values) do
  begin
    Decomposition[Position] := ParseHex(Values[Position]);
  end;
  const CodePoint = ParseHex(Parts[0]);
  FDecompositions.Add(CodePoint, Decomposition);
end;

procedure TPdfUnicodeNormalizer.AddCombiningClass(const Entry: string);
begin
  const Parts = Entry.Split([ValueSeparator]);
  const CombiningClass = StrToInt(Parts[1]);
  const Bounds = Parts[0].Split([RangeSeparator]);
  const First = ParseHex(Bounds[0]);
  var Last := First;
  if Length(Bounds) > 1 then
  begin
    Last := ParseHex(Bounds[1]);
  end;

  for var CodePoint := First to Last do
  begin
    FCombiningClasses.Add(CodePoint, CombiningClass);
  end;
end;

procedure TPdfUnicodeNormalizer.AddComposition(const Entry: string);
begin
  const Parts = Entry.Split([ValueSeparator]);
  const Pair = Parts[0].Split([CodePointSeparator]);
  const Key = CompositionKey(ParseHex(Pair[0]), ParseHex(Pair[1]));
  FCompositions.Add(Key, ParseHex(Parts[1]));
end;

procedure TPdfUnicodeNormalizer.LoadDecompositions;
begin
  for var Entry in CompatibilityDecompositions.Split([EntrySeparator], TStringSplitOptions.ExcludeEmpty) do
  begin
    AddDecomposition(Entry);
  end;
end;

procedure TPdfUnicodeNormalizer.LoadCombiningClasses;
begin
  for var Entry in CombiningClasses.Split([EntrySeparator], TStringSplitOptions.ExcludeEmpty) do
  begin
    AddCombiningClass(Entry);
  end;
end;

procedure TPdfUnicodeNormalizer.LoadCompositions;
begin
  for var Entry in CanonicalCompositions.Split([EntrySeparator], TStringSplitOptions.ExcludeEmpty) do
  begin
    AddComposition(Entry);
  end;
end;

{ the algorithm }

function TPdfUnicodeNormalizer.CombiningClassOf(const CodePoint: Integer): Integer;
begin
  if not FCombiningClasses.TryGetValue(CodePoint, Result) then
  begin
    Result := 0;
  end;
end;

procedure TPdfUnicodeNormalizer.AppendHangulDecomposition(const CodePoint: Integer; const Target: TList<Integer>);
begin
  const SyllableIndex = CodePoint - HangulSyllableBase;
  Target.Add(HangulLeadBase + (SyllableIndex div HangulVowelTrailCount));
  Target.Add(HangulVowelBase + ((SyllableIndex mod HangulVowelTrailCount) div HangulTrailCount));
  const TrailIndex = SyllableIndex mod HangulTrailCount;
  if TrailIndex <> 0 then
  begin
    Target.Add(HangulTrailBase + TrailIndex);
  end;
end;

procedure TPdfUnicodeNormalizer.AppendDecomposed(const CodePoint: Integer; const Target: TList<Integer>);
begin
  const IsHangulSyllable = ((CodePoint >= HangulSyllableBase) and (CodePoint < HangulSyllableBase + HangulSyllableCount));
  var Decomposition: TCodePoints;
  if IsHangulSyllable then
  begin
    AppendHangulDecomposition(CodePoint, Target);
  end
  else if FDecompositions.TryGetValue(CodePoint, Decomposition) then
  begin
    Target.AddRange(Decomposition);
  end
  else
  begin
    Target.Add(CodePoint);
  end;
end;

function TPdfUnicodeNormalizer.Decompose(const CodePoints: TCodePoints): TCodePoints;
begin
  const Decomposed = TList<Integer>.Create;
  try
    for var CodePoint in CodePoints do
    begin
      AppendDecomposed(CodePoint, Decomposed);
    end;
    Result := Decomposed.ToArray;
  finally
    Decomposed.Free;
  end;
end;

// Runs of characters with a combining class above zero are sorted by that class. Insertion sort keeps equal classes in order.
procedure TPdfUnicodeNormalizer.OrderCanonically(const CodePoints: TCodePoints);
begin
  for var Position := 1 to High(CodePoints) do
  begin
    const Moving = CodePoints[Position];
    const MovingClass = CombiningClassOf(Moving);
    var Target := Position;
    while (MovingClass <> 0) and (Target > 0) and (CombiningClassOf(CodePoints[Target - 1]) > MovingClass) do
    begin
      CodePoints[Target] := CodePoints[Target - 1];
      Dec(Target);
    end;
    CodePoints[Target] := Moving;
  end;
end;

function TPdfUnicodeNormalizer.TryComposeHangul(const First, Second: Integer; out Composite: Integer): Boolean;
begin
  Composite := 0;
  const IsLeadAndVowel = ((First >= HangulLeadBase) and (First < HangulLeadBase + HangulLeadCount) and
                          (Second >= HangulVowelBase) and (Second < HangulVowelBase + HangulVowelCount));
  if IsLeadAndVowel then
  begin
    const LeadIndex = First - HangulLeadBase;
    const VowelIndex = Second - HangulVowelBase;
    Composite := HangulSyllableBase + (((LeadIndex * HangulVowelCount) + VowelIndex) * HangulTrailCount);
    Exit(True);
  end;

  const IsSyllableAndTrail = ((First >= HangulSyllableBase) and (First < HangulSyllableBase + HangulSyllableCount) and
                              (((First - HangulSyllableBase) mod HangulTrailCount) = 0) and
                              (Second > HangulTrailBase) and (Second < HangulTrailBase + HangulTrailCount));
  if IsSyllableAndTrail then
  begin
    Composite := First + (Second - HangulTrailBase);
  end;
  Result := IsSyllableAndTrail;
end;

function TPdfUnicodeNormalizer.TryCompose(const First, Second: Integer; out Composite: Integer): Boolean;
begin
  const Key = CompositionKey(First, Second);
  Result := (FCompositions.TryGetValue(Key, Composite) or TryComposeHangul(First, Second, Composite));
end;

function TPdfUnicodeNormalizer.Compose(const CodePoints: TCodePoints): TCodePoints;
begin
  if Length(CodePoints) = 0 then
  begin
    Exit(CodePoints);
  end;

  const Composed = TList<Integer>.Create;
  try
    Composed.Add(CodePoints[0]);
    var StarterPosition := 0;
    var LastClass := CombiningClassOf(CodePoints[0]);
    if LastClass <> 0 then
    begin
      LastClass := UnlimitedClass;
    end;

    for var Position := 1 to High(CodePoints) do
    begin
      const Current = CodePoints[Position];
      const CurrentClass = CombiningClassOf(Current);
      var Composite: Integer;
      const IsComposable = ((LastClass < CurrentClass) or (LastClass = 0)) and TryCompose(Composed[StarterPosition], Current, Composite);
      if IsComposable then
      begin
        Composed[StarterPosition] := Composite;
      end
      else
      begin
        if CurrentClass = 0 then
        begin
          StarterPosition := Composed.Count;
        end;
        LastClass := CurrentClass;
        Composed.Add(Current);
      end;
    end;
    Result := Composed.ToArray;
  finally
    Composed.Free;
  end;
end;

function TPdfUnicodeNormalizer.NormalizeNfkc(const Text: string): string;
begin
  const CodePoints = ToCodePoints(Text);
  const Decomposed = Decompose(CodePoints);
  OrderCanonically(Decomposed);
  const Composed = Compose(Decomposed);
  Result := FromCodePoints(Composed);
end;

end.
