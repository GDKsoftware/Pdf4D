// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TextGolden;

interface

uses
  System.SysUtils;

type
  TTextComparison = record
    // One text per difference, with the section heading and the line number
    Differences: TArray<string>;
    // The number of sections that are equal after the whitespace rules of the text goldens, but not exactly
    LenientSections: Integer;
  end;

  // Compares extracted text with a text golden (docs/golden-format.md, "Text goldens")
  TTextGoldenComparer = record
  strict private
    class function IsHeading(const Line: string): Boolean; static;
    class function Unescaped(const Text: string): string; static;
    class function Collapsed(const Text: string): string; static;
    class function LenientLine(const Line: string): string; static;
    class function LenientLines(const Lines: TArray<string>; out RawNumbers: TArray<Integer>): TArray<string>; static;
    class function SplitSections(const Text: string; out Headings: TArray<string>): TArray<TArray<string>>; static;
    class function IndexOfHeading(const Headings: TArray<string>; const Heading: string): Integer; static;
    class function IsKnown(const Heading, Platform: string; const KnownDifferences: TArray<string>): Boolean; static;
    class function FirstDifference(const Heading: string; const Expected, Actual: TArray<string>): string; static;
    class function AreEqual(const Left, Right: TArray<string>): Boolean; static;
    class procedure CompareSection(const Heading: string; const Expected, Actual: TArray<string>; var Result: TTextComparison); static;
    class procedure CompareHeadings(const Expected, Actual: TArray<string>; var Result: TTextComparison); static;

  public
    // Both texts are lines separated by LF. Lines before the first "text: " heading form one section without a heading.
    // KnownDifferences are the lines of a text-known-differences file ("<heading> [<platform>] # <reason>"). Platform is
    // Win32, Win64 or Linux64.
    class function Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>; const Platform: string): TTextComparison; static;
    // The entries of a known-differences file without comments and empty lines. A missing file gives none.
    class function LoadKnownDifferences(const FileName: string): TArray<string>; static;
    class function CurrentPlatform: string; static;
  end;

implementation

uses
  System.IOUtils;

const
  LineFeed = #10;
  HeadingStart = 'text: ';
  CommentMarker = '#';

{ TTextGoldenComparer }

class function TTextGoldenComparer.IsHeading(const Line: string): Boolean;
begin
  Result := Line.StartsWith(HeadingStart);
end;

class function TTextGoldenComparer.Unescaped(const Text: string): string;
begin
  const Builder = TStringBuilder.Create;
  try
    var Position := 0;
    while Position < Text.Length do
    begin
      const Character = Text.Chars[Position];
      Inc(Position);
      if (Character <> '\') or (Position >= Text.Length) then
      begin
        Builder.Append(Character);
        Continue;
      end;

      const Escaped = Text.Chars[Position];
      Inc(Position);
      case Escaped of
        'n': Builder.Append(#10);
        'r': Builder.Append(#13);
        't': Builder.Append(#9);
        'x':
        begin
          const Code = StrToIntDef('$' + Text.Substring(Position, 2), -1);
          if (Code >= 0) and (Position + 2 <= Text.Length) then
          begin
            Builder.Append(Char(Code));
            Inc(Position, 2);
          end
          else
          begin
            Builder.Append('\x');
          end;
        end;
      else
        Builder.Append(Escaped);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

// Runs of spaces and tabs become one space, then the ends are trimmed. A no-break space is data.
class function TTextGoldenComparer.Collapsed(const Text: string): string;
begin
  const Builder = TStringBuilder.Create;
  try
    var InRun := False;
    for var Character in Text do
    begin
      if (Character = ' ') or (Character = #9) then
      begin
        if not InRun then
        begin
          Builder.Append(' ');
        end;
        InRun := True;
      end
      else
      begin
        Builder.Append(Character);
        InRun := False;
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;

  var First := 0;
  var Last := Result.Length - 1;
  while (First <= Last) and ((Result.Chars[First] = ' ') or (Result.Chars[First] = #9)) do
  begin
    Inc(First);
  end;
  while (Last >= First) and ((Result.Chars[Last] = ' ') or (Result.Chars[Last] = #9)) do
  begin
    Dec(Last);
  end;
  Result := Result.Substring(First, Last - First + 1);
end;

class function TTextGoldenComparer.LenientLine(const Line: string): string;
begin
  var Body := Line;
  if Body.StartsWith('| ') then
  begin
    Body := Body.Substring(2);
  end
  else if Body.StartsWith('|') then
  begin
    Body := Body.Substring(1);
  end;
  Result := Collapsed(Unescaped(Body));
end;

// The lines that stay after the lenient rules; RawNumbers holds for each the one based number it had in the section
class function TTextGoldenComparer.LenientLines(const Lines: TArray<string>; out RawNumbers: TArray<Integer>): TArray<string>;
begin
  Result := nil;
  RawNumbers := nil;
  for var Position := 0 to High(Lines) do
  begin
    const Line = LenientLine(Lines[Position]);
    if Line <> '' then
    begin
      Result := Result + [Line];
      RawNumbers := RawNumbers + [Position + 1];
    end;
  end;
end;

class function TTextGoldenComparer.SplitSections(const Text: string; out Headings: TArray<string>): TArray<TArray<string>>;
begin
  Result := nil;
  Headings := nil;
  if Text = '' then
  begin
    Exit;
  end;

  var Lines := Text.Split([LineFeed]);
  // The empty piece after the last LF is not a line
  if (Length(Lines) > 0) and (Lines[High(Lines)] = '') then
  begin
    SetLength(Lines, Length(Lines) - 1);
  end;

  var Current: TArray<string> := nil;
  var HasCurrent := False;
  for var Line in Lines do
  begin
    if IsHeading(Line) then
    begin
      if HasCurrent then
      begin
        Result := Result + [Current];
      end;
      Headings := Headings + [Line];
      Current := nil;
      HasCurrent := True;
    end
    else
    begin
      if not HasCurrent then
      begin
        // Lines before the first heading (a load-error line) form a section without heading
        Headings := Headings + [''];
        HasCurrent := True;
      end;
      Current := Current + [Line];
    end;
  end;
  if HasCurrent then
  begin
    Result := Result + [Current];
  end;
end;

class function TTextGoldenComparer.IndexOfHeading(const Headings: TArray<string>; const Heading: string): Integer;
begin
  for var Position := 0 to High(Headings) do
  begin
    if Headings[Position] = Heading then
    begin
      Exit(Position);
    end;
  end;
  Result := -1;
end;

// A known entry skips a section when its heading text, before the optional platform and the "#", equals the heading
class function TTextGoldenComparer.IsKnown(const Heading, Platform: string; const KnownDifferences: TArray<string>): Boolean;
begin
  Result := False;
  for var Entry in KnownDifferences do
  begin
    var Head := Entry;
    const Hash = Head.IndexOf(CommentMarker);
    if Hash >= 0 then
    begin
      Head := Head.Substring(0, Hash);
    end;
    Head := Head.TrimRight([' ', #9]);

    var EntryPlatform := '';
    if Head.EndsWith(']') then
    begin
      const Open = Head.LastIndexOf(' [');
      if Open >= 0 then
      begin
        EntryPlatform := Head.Substring(Open + 2, Head.Length - Open - 3);
        Head := Head.Substring(0, Open).TrimRight([' ', #9]);
      end;
    end;

    if (Head = Heading) and ((EntryPlatform = '') or (EntryPlatform = Platform)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TTextGoldenComparer.AreEqual(const Left, Right: TArray<string>): Boolean;
begin
  Result := Length(Left) = Length(Right);
  if not Result then
  begin
    Exit;
  end;
  for var Position := 0 to High(Left) do
  begin
    if Left[Position] <> Right[Position] then
    begin
      Exit(False);
    end;
  end;
end;

class function TTextGoldenComparer.FirstDifference(const Heading: string; const Expected, Actual: TArray<string>): string;
begin
  var ExpectedNumbers: TArray<Integer>;
  var ActualNumbers: TArray<Integer>;
  const ExpectedLines = LenientLines(Expected, ExpectedNumbers);
  const ActualLines = LenientLines(Actual, ActualNumbers);

  var Position := 0;
  while (Position < Length(ExpectedLines)) and (Position < Length(ActualLines)) and (ExpectedLines[Position] = ActualLines[Position]) do
  begin
    Inc(Position);
  end;

  if Position >= Length(ExpectedLines) then
  begin
    Result := Format('%s, line %d: extra line [%s]', [Heading, ActualNumbers[Position], ActualLines[Position]]);
  end
  else if Position >= Length(ActualLines) then
  begin
    Result := Format('%s, line %d: missing line [%s]', [Heading, ExpectedNumbers[Position], ExpectedLines[Position]]);
  end
  else
  begin
    Result := Format('%s, line %d: expected [%s] but found [%s]', [Heading, ExpectedNumbers[Position], ExpectedLines[Position], ActualLines[Position]]);
  end;
end;

class procedure TTextGoldenComparer.CompareSection(const Heading: string; const Expected, Actual: TArray<string>; var Result: TTextComparison);
begin
  if AreEqual(Expected, Actual) then
  begin
    Exit;
  end;

  var Ignored: TArray<Integer>;
  if AreEqual(LenientLines(Expected, Ignored), LenientLines(Actual, Ignored)) then
  begin
    Inc(Result.LenientSections);
    Exit;
  end;

  Result.Differences := Result.Differences + [FirstDifference(Heading, Expected, Actual)];
end;

class procedure TTextGoldenComparer.CompareHeadings(const Expected, Actual: TArray<string>; var Result: TTextComparison);
begin
  var IsSameSet := True;
  for var Heading in Expected do
  begin
    if IndexOfHeading(Actual, Heading) < 0 then
    begin
      IsSameSet := False;
      Result.Differences := Result.Differences + ['missing section: ' + Heading];
    end;
  end;
  for var Heading in Actual do
  begin
    if IndexOfHeading(Expected, Heading) < 0 then
    begin
      IsSameSet := False;
      Result.Differences := Result.Differences + ['extra section: ' + Heading];
    end;
  end;

  if IsSameSet and not AreEqual(Expected, Actual) then
  begin
    Result.Differences := Result.Differences + ['the sections come in another order'];
  end;
end;

class function TTextGoldenComparer.Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>; const Platform: string): TTextComparison;
begin
  Result.Differences := nil;
  Result.LenientSections := 0;

  var ExpectedHeadings: TArray<string>;
  var ActualHeadings: TArray<string>;
  const ExpectedSections = SplitSections(Expected, ExpectedHeadings);
  const ActualSections = SplitSections(Actual, ActualHeadings);

  CompareHeadings(ExpectedHeadings, ActualHeadings, Result);

  for var Position := 0 to High(ExpectedHeadings) do
  begin
    const Heading = ExpectedHeadings[Position];
    const ActualPosition = IndexOfHeading(ActualHeadings, Heading);
    if (ActualPosition < 0) or IsKnown(Heading, Platform, KnownDifferences) then
    begin
      Continue;
    end;
    CompareSection(Heading, ExpectedSections[Position], ActualSections[ActualPosition], Result);
  end;
end;

class function TTextGoldenComparer.LoadKnownDifferences(const FileName: string): TArray<string>;
begin
  Result := nil;
  if not TFile.Exists(FileName) then
  begin
    Exit;
  end;

  for var Line in TFile.ReadAllLines(FileName, TEncoding.UTF8) do
  begin
    const Trimmed = Line.Trim;
    if (Trimmed <> '') and not Trimmed.StartsWith(CommentMarker) then
    begin
      Result := Result + [Trimmed];
    end;
  end;
end;

class function TTextGoldenComparer.CurrentPlatform: string;
begin
  {$IF Defined(LINUX64)}
  Result := 'Linux64';
  {$ELSEIF Defined(WIN64)}
  Result := 'Win64';
  {$ELSEIF Defined(MSWINDOWS)}
  Result := 'Win32';
  {$ELSE}
  Result := 'Other';
  {$ENDIF}
end;

end.
