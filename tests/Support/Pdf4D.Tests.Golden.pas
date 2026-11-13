unit Pdf4D.Tests.Golden;

interface

uses
  System.SysUtils;

type
  // Compares a dump with a golden dump line by line
  TGoldenComparer = record
  strict private
    class function Normalize(const Line: string): string; static;
    class function IgnoredKeys(const Line: string; const KnownDifferences: TArray<string>): TArray<string>; static;
    class function WithoutKeys(const Line: string; const Keys: TArray<string>): string; static;
    class function IsKnown(const Line: string; const KnownDifferences: TArray<string>): Boolean; static;
    class function AreNumbersEqual(const Expected, Actual: string): Boolean; static;
    class procedure SplitNumbers(const Line: string; out Skeleton: string; out Numbers: TArray<Double>); static;

  public
    // Both texts are lines separated by LF. Whitespace is normalized (runs become one space, trailing spaces go). Lines are
    // matched by what identifies them: "object <n> <g>:", "page <i>:" and "info <key>:" by that start, the lines of the
    // other sections by their kind and their position in it. Numbers with a decimal point may differ by 0.001. Lines that
    // start with one of the KnownDifferences (for example "object 12 0:") are skipped, when it is the expected or the found
    // line. An entry "<prefix> ignore-key /Key" does not skip the line: for the lines that start with the prefix, the entry
    // "/Key <value>" (an integer or a reference) is removed from both lines before they are compared. The result holds one text per remaining difference.
    class function Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>): TArray<string>; static;

    // The prefixes of a known-differences file: per line the prefix, then " # " and the reason. A missing file gives none.
    class function LoadKnownDifferences(const FileName: string): TArray<string>; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections;

const
  FloatTolerance = 0.001;
  ReasonSeparator = ' # ';
  IgnoreKeyMarker = ' ignore-key ';
  NumberMarker = #1;
  KeyedByStart: array[0..2] of string = ('object ', 'page ', 'info ');

{ TGoldenComparer }

class function TGoldenComparer.Normalize(const Line: string): string;
begin
  const Builder = TStringBuilder.Create;
  try
    var PendingSpace := False;
    for var Character in Line do
    begin
      if (Character = ' ') or (Character = #9) or (Character = #13) then
      begin
        PendingSpace := True;
      end
      else
      begin
        if PendingSpace and (Builder.Length > 0) then
        begin
          Builder.Append(' ');
        end;
        PendingSpace := False;
        Builder.Append(Character);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TGoldenComparer.IsKnown(const Line: string; const KnownDifferences: TArray<string>): Boolean;
begin
  Result := False;
  for var Prefix in KnownDifferences do
  begin
    if not Prefix.Contains(IgnoreKeyMarker) and Line.StartsWith(Prefix) then
    begin
      Exit(True);
    end;
  end;
end;

class function TGoldenComparer.IgnoredKeys(const Line: string; const KnownDifferences: TArray<string>): TArray<string>;
begin
  Result := nil;
  for var Entry in KnownDifferences do
  begin
    const Stop = Entry.IndexOf(IgnoreKeyMarker);
    if (Stop > 0) and Line.StartsWith(Entry.Substring(0, Stop)) then
    begin
      Result := Result + [Entry.Substring(Stop + IgnoreKeyMarker.Length) + ' '];
    end;
  end;
end;

// Removes "/Key <integer>" and "/Key <n> <g> R" when the key stands as a whole name
class function TGoldenComparer.WithoutKeys(const Line: string; const Keys: TArray<string>): string;
begin
  Result := Line;
  for var Key in Keys do
  begin
    var Start := Result.IndexOf(Key);
    while Start >= 0 do
    begin
      var Stop := Start + Key.Length;
      const ValueStart = Stop;
      while (Stop < Result.Length) and CharInSet(Result[Stop + 1], ['0'..'9', '-']) do
      begin
        Inc(Stop);
      end;
      if Stop > ValueStart then
      begin
        const Reference = Result.Substring(Stop).StartsWith(' ');
        var AfterGeneration := Stop + 1;
        while Reference and (AfterGeneration < Result.Length) and CharInSet(Result[AfterGeneration + 1], ['0'..'9']) do
        begin
          Inc(AfterGeneration);
        end;
        if Reference and (AfterGeneration > Stop + 1) and Result.Substring(AfterGeneration).StartsWith(' R') then
        begin
          Stop := AfterGeneration + 2;
        end;
        Result := Normalize(Result.Remove(Start, Stop - Start));
        Start := Result.IndexOf(Key);
      end
      else
      begin
        Start := Result.IndexOf(Key, Start + 1);
      end;
    end;
  end;
end;

// Replaces every number with a decimal point by a marker and collects the values
class procedure TGoldenComparer.SplitNumbers(const Line: string; out Skeleton: string; out Numbers: TArray<Double>);
begin
  Numbers := nil;
  const Builder = TStringBuilder.Create;
  try
    var Position := 1;
    while Position <= Line.Length do
    begin
      const Character = Line[Position];
      const StartsNumber = CharInSet(Character, ['0'..'9', '-']) and
                           ((Position = 1) or not CharInSet(Line[Position - 1], ['0'..'9', 'a'..'z', 'A'..'Z', '.', '#', '-']));
      var IsFloat := False;
      var Stop := Position;
      if StartsNumber then
      begin
        if Line[Stop] = '-' then
        begin
          Inc(Stop);
        end;
        const DigitsStart = Stop;
        while (Stop <= Line.Length) and CharInSet(Line[Stop], ['0'..'9']) do
        begin
          Inc(Stop);
        end;
        if (Stop > DigitsStart) and (Stop <= Line.Length) and (Line[Stop] = '.') then
        begin
          const FractionStart = Stop + 1;
          var FractionStop := FractionStart;
          while (FractionStop <= Line.Length) and CharInSet(Line[FractionStop], ['0'..'9']) do
          begin
            Inc(FractionStop);
          end;
          const EndsCleanly = (FractionStop > Line.Length) or not CharInSet(Line[FractionStop], ['a'..'z', 'A'..'Z', '.', '#']);
          if (FractionStop > FractionStart) and EndsCleanly then
          begin
            IsFloat := True;
            Stop := FractionStop;
          end;
        end;
      end;

      var Value: Double;
      if IsFloat and TryStrToFloat(Line.Substring(Position - 1, Stop - Position), Value, TFormatSettings.Invariant) then
      begin
        Numbers := Numbers + [Value];
        Builder.Append(NumberMarker);
        Position := Stop;
      end
      else
      begin
        Builder.Append(Character);
        Inc(Position);
      end;
    end;
    Skeleton := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TGoldenComparer.AreNumbersEqual(const Expected, Actual: string): Boolean;
begin
  var ExpectedSkeleton: string;
  var ActualSkeleton: string;
  var ExpectedNumbers: TArray<Double>;
  var ActualNumbers: TArray<Double>;
  SplitNumbers(Expected, ExpectedSkeleton, ExpectedNumbers);
  SplitNumbers(Actual, ActualSkeleton, ActualNumbers);

  Result := (ExpectedSkeleton = ActualSkeleton) and (Length(ExpectedNumbers) = Length(ActualNumbers));
  if Result then
  begin
    for var Index := 0 to High(ExpectedNumbers) do
    begin
      if Abs(ExpectedNumbers[Index] - ActualNumbers[Index]) > FloatTolerance then
      begin
        Exit(False);
      end;
    end;
  end;
end;

class function TGoldenComparer.Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>): TArray<string>;

  procedure Collect(const Text: string; const Keys: TList<string>; const Lines: TDictionary<string, string>);
  begin
    const Counts = TDictionary<string, Integer>.Create;
    try
      for var Raw in Text.Split([#10]) do
      begin
        var Line := Normalize(Raw);
        if Line = '' then
        begin
          Continue;
        end;
        Line := WithoutKeys(Line, IgnoredKeys(Line, KnownDifferences));

        var IsKeyedByStart := False;
        for var Prefix in KeyedByStart do
        begin
          IsKeyedByStart := IsKeyedByStart or Line.StartsWith(Prefix);
        end;

        var Key := Line;
        const Stop = Line.IndexOf(':');
        if Stop > 0 then
        begin
          const Kind = Line.Substring(0, Stop);
          if IsKeyedByStart then
          begin
            Key := Kind + ':';
          end
          else
          begin
            var Count := 0;
            Counts.TryGetValue(Kind, Count);
            Counts.AddOrSetValue(Kind, Count + 1);
            Key := Kind + '#' + IntToStr(Count);
          end;
        end;

        if not Lines.ContainsKey(Key) then
        begin
          Keys.Add(Key);
        end;
        Lines.AddOrSetValue(Key, Line);
      end;
    finally
      Counts.Free;
    end;
  end;

begin
  Result := nil;
  const ExpectedKeys = TList<string>.Create;
  const ActualKeys = TList<string>.Create;
  const ExpectedLines = TDictionary<string, string>.Create;
  const ActualLines = TDictionary<string, string>.Create;
  try
    Collect(Expected, ExpectedKeys, ExpectedLines);
    Collect(Actual, ActualKeys, ActualLines);

    for var Key in ExpectedKeys do
    begin
      const ExpectedLine = ExpectedLines[Key];
      var ActualLine: string;
      if not ActualLines.TryGetValue(Key, ActualLine) then
      begin
        if not IsKnown(ExpectedLine, KnownDifferences) then
        begin
          Result := Result + ['missing: ' + ExpectedLine];
        end;
      end
      else if (ExpectedLine <> ActualLine) and not AreNumbersEqual(ExpectedLine, ActualLine) and
              not IsKnown(ExpectedLine, KnownDifferences) and not IsKnown(ActualLine, KnownDifferences) then
      begin
        Result := Result + ['expected: ' + ExpectedLine + sLineBreak + '   found: ' + ActualLine];
      end;
    end;

    for var Key in ActualKeys do
    begin
      if not ExpectedLines.ContainsKey(Key) and not IsKnown(ActualLines[Key], KnownDifferences) then
      begin
        Result := Result + ['unexpected: ' + ActualLines[Key]];
      end;
    end;
  finally
    ActualLines.Free;
    ExpectedLines.Free;
    ActualKeys.Free;
    ExpectedKeys.Free;
  end;
end;

class function TGoldenComparer.LoadKnownDifferences(const FileName: string): TArray<string>;
begin
  Result := nil;
  if not TFile.Exists(FileName) then
  begin
    Exit;
  end;

  for var Row in TFile.ReadAllLines(FileName, TEncoding.UTF8) do
  begin
    if (Row = '') or Row.StartsWith('#') then
    begin
      Continue;
    end;

    const Stop = Row.IndexOf(ReasonSeparator);
    if Stop > 0 then
    begin
      Result := Result + [Row.Substring(0, Stop)];
    end
    else
    begin
      Result := Result + [Row];
    end;
  end;
end;

end.
