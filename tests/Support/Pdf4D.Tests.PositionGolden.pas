// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.PositionGolden;

interface

uses
  System.SysUtils;

type
  // Compares a position dump with a position golden (docs/golden-format.md, "Position goldens")
  TPositionGoldenComparer = record
  strict private
    type
      TGoldenLine = record
        // The page the line belongs to, 0 before the first page line
        Page: Integer;
        // The one based number of the line in the file
        Number: Integer;
        Text: string;
      end;

    const
      // Both sides are rounded to two decimals, so equal values can be 0.01 apart in the files; the rest is the margin of the rule
      MaxDifference = 0.02;
      Epsilon = 0.000001;
      LineMarker = 'line: ';
      PageMarker = 'page ';

    class function ParseLines(const Text: string): TArray<TGoldenLine>; static;
    class function IsKnownPage(const Page: Integer; const Platform: string; const KnownDifferences: TArray<string>): Boolean; static;
    class function WithoutKnownPages(const Lines: TArray<TGoldenLine>; const KnownDifferences: TArray<string>; const Platform: string): TArray<TGoldenLine>; static;
    class function AreNumbersEqual(const Expected, Actual: string): Boolean; static;
    class function AreLineValuesEqual(const Expected, Actual: string): Boolean; static;
    class function AreLinesEqual(const Expected, Actual: string): Boolean; static;
    class function DescribeDifference(const Expected, Actual: TGoldenLine): string; static;

  public
    // Both texts are lines separated by LF. KnownDifferences are the lines of a known-differences file ("<page> [<platform>] # <reason>").
    // Platform is Win32, Win64 or Linux64. The result has one text per difference.
    class function Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>; const Platform: string): TArray<string>; static;
  end;

implementation

uses
  System.Math;

const
  LineFeed = #10;
  CommentMarker = '#';

{ TPositionGoldenComparer }

class function TPositionGoldenComparer.ParseLines(const Text: string): TArray<TGoldenLine>;
begin
  Result := nil;
  if Text = '' then
  begin
    Exit;
  end;

  var Pieces := Text.Split([LineFeed]);
  if Pieces[High(Pieces)] = '' then
  begin
    SetLength(Pieces, Length(Pieces) - 1);
  end;

  var Page := 0;
  for var Index := 0 to High(Pieces) do
  begin
    const Piece = Pieces[Index];
    if Piece.StartsWith(PageMarker) then
    begin
      Page := StrToIntDef(Piece.Substring(PageMarker.Length), 0);
    end;

    var Parsed: TGoldenLine;
    Parsed.Page := Page;
    Parsed.Number := Index + 1;
    Parsed.Text := Piece;
    Result := Result + [Parsed];
  end;
end;

// A known entry skips a page when its text before the optional platform and the "#" (trailing spaces removed) is the page number
class function TPositionGoldenComparer.IsKnownPage(const Page: Integer; const Platform: string; const KnownDifferences: TArray<string>): Boolean;
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
    Head := Head.Trim;

    var EntryPlatform := '';
    if Head.EndsWith(']') then
    begin
      const Open = Head.LastIndexOf(' [');
      if Open >= 0 then
      begin
        EntryPlatform := Head.Substring(Open + 2, Head.Length - Open - 3);
        Head := Head.Substring(0, Open).Trim;
      end;
    end;

    const IsSamePage = (StrToIntDef(Head, 0) = Page);
    const IsSamePlatform = ((EntryPlatform = '') or (EntryPlatform = Platform));
    if IsSamePage and (Page > 0) and IsSamePlatform then
    begin
      Exit(True);
    end;
  end;
end;

class function TPositionGoldenComparer.WithoutKnownPages(const Lines: TArray<TGoldenLine>; const KnownDifferences: TArray<string>;
                                                         const Platform: string): TArray<TGoldenLine>;
begin
  Result := nil;
  for var Line in Lines do
  begin
    if not IsKnownPage(Line.Page, Platform, KnownDifferences) then
    begin
      Result := Result + [Line];
    end;
  end;
end;

// Numbers within the tolerance, or the same text for what is no number (NaN, Infinity)
class function TPositionGoldenComparer.AreNumbersEqual(const Expected, Actual: string): Boolean;
begin
  var ExpectedValue: Double;
  var ActualValue: Double;
  const AreBothNumbers = (TryStrToFloat(Expected, ExpectedValue, TFormatSettings.Invariant) and
                          TryStrToFloat(Actual, ActualValue, TFormatSettings.Invariant));
  if not AreBothNumbers then
  begin
    Exit(Expected = Actual);
  end;

  Result := (Abs(ExpectedValue - ActualValue) <= MaxDifference + Epsilon);
end;

class function TPositionGoldenComparer.AreLineValuesEqual(const Expected, Actual: string): Boolean;
begin
  const ExpectedTokens = Expected.Substring(LineMarker.Length).Split([' '], TStringSplitOptions.ExcludeEmpty);
  const ActualTokens = Actual.Substring(LineMarker.Length).Split([' '], TStringSplitOptions.ExcludeEmpty);
  Result := (Length(ExpectedTokens) = Length(ActualTokens));
  if not Result then
  begin
    Exit;
  end;

  // The number of glyphs is the last token and must be exact
  for var Index := 0 to High(ExpectedTokens) do
  begin
    const IsGlyphCount = (Index = High(ExpectedTokens));
    if IsGlyphCount then
    begin
      Result := (ExpectedTokens[Index] = ActualTokens[Index]);
    end
    else
    begin
      Result := AreNumbersEqual(ExpectedTokens[Index], ActualTokens[Index]);
    end;
    if not Result then
    begin
      Exit;
    end;
  end;
end;

class function TPositionGoldenComparer.AreLinesEqual(const Expected, Actual: string): Boolean;
begin
  const AreBothLines = (Expected.StartsWith(LineMarker) and Actual.StartsWith(LineMarker));
  if AreBothLines then
  begin
    Exit(AreLineValuesEqual(Expected, Actual));
  end;

  Result := (Expected = Actual);
end;

class function TPositionGoldenComparer.DescribeDifference(const Expected, Actual: TGoldenLine): string;
begin
  Result := Format('page %d, line %d: expected [%s] but found [%s]', [Expected.Page, Expected.Number, Expected.Text, Actual.Text]);
end;

class function TPositionGoldenComparer.Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>; const Platform: string): TArray<string>;
begin
  Result := nil;
  const ExpectedLines = WithoutKnownPages(ParseLines(Expected), KnownDifferences, Platform);
  const ActualLines = WithoutKnownPages(ParseLines(Actual), KnownDifferences, Platform);

  const Shared = Min(Length(ExpectedLines), Length(ActualLines));
  for var Index := 0 to Shared - 1 do
  begin
    if not AreLinesEqual(ExpectedLines[Index].Text, ActualLines[Index].Text) then
    begin
      Result := Result + [DescribeDifference(ExpectedLines[Index], ActualLines[Index])];
    end;
  end;

  if Length(ExpectedLines) > Shared then
  begin
    Result := Result + [Format('missing line %d: [%s]', [ExpectedLines[Shared].Number, ExpectedLines[Shared].Text])];
  end;
  if Length(ActualLines) > Shared then
  begin
    Result := Result + [Format('extra line %d: [%s]', [ActualLines[Shared].Number, ActualLines[Shared].Text])];
  end;
end;

end.
