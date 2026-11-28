// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ImageLocations;

interface

uses
  System.SysUtils,
  Pdf4D.Api.Document.Interfaces;

type
  // Writes and compares the image location dump of docs/golden-format.md ("Image location goldens"), the lines that the PDFBox
  // oracle writes: <page> <index> <pixel width> <pixel height> <a> <b> <c> <d> <e> <f>, an "error <page>" line for a page that fails
  TImageLocations = record
  strict private
    type
      TGoldenLine = record
        // The page the line belongs to
        Page: Integer;
        // The one based number of the line in the file
        Number: Integer;
        Text: string;
      end;

    const
      MaxPages = 50;
      // Both sides are rounded to two decimals, so equal values can be 0.01 apart in the files; the rest is the margin of the rule
      MaxDifference = 0.02;
      ErrorMarker = 'error ';
      LoadErrorMarker = 'load-error:';
      LineFeed = #10;
      CommentMarker = '#';

    class function ParseLines(const Text: string): TArray<TGoldenLine>; static;
    class function PageOfLine(const Line: string): Integer; static;
    class function IsKnownPage(const Page: Integer; const Platform: string; const KnownDifferences: TArray<string>): Boolean; static;
    class function PageLines(const Lines: TArray<TGoldenLine>; const Page: Integer): TArray<string>; static;
    class function PagesOf(const Lines: TArray<TGoldenLine>): TArray<Integer>; static;
    class function AreNumbersEqual(const Expected, Actual: string): Boolean; static;
    class function AreImageLinesEqual(const Expected, Actual: string): Boolean; static;
    class procedure ComparePage(const Page: Integer; const Expected, Actual: TArray<string>; var Differences: TArray<string>); static;

  public
    // Lenient: every exception of a page becomes an "error" line. Strict: only a PDF exception does.
    class function Dump(const Document: IPdfDocument; const IsStrict: Boolean = False): string; static;
    // Both texts are lines separated by LF. KnownDifferences are the lines of a known-differences file ("<page> [<platform>] # <reason>").
    // Platform is Win32, Win64 or Linux64. The result has one text per difference.
    class function Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>; const Platform: string): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Extract.Images,
  Pdf4D.Extract.Images.Interfaces,
  Pdf4D.Tests.PositionDump;

{ TImageLocations }

class function TImageLocations.Dump(const Document: IPdfDocument; const IsStrict: Boolean): string;
begin
  const Lines = TStringBuilder.Create;
  try
    const PageCount = Min(Document.PageCount, MaxPages);
    for var PageIndex := 0 to PageCount - 1 do
    begin
      const Start = Lines.Length;
      try
        const Images = TPdfImages.OfPage(Document.Page(PageIndex)).Images;
        for var Info in Images do
        begin
          Lines.Append(PageIndex + 1).Append(' ').Append(Info.Index).Append(' ').Append(Info.PixelWidth).Append(' ').Append(Info.PixelHeight);
          for var Part := 0 to 5 do
          begin
            Lines.Append(' ').Append(TPositionDump.Number(Info.Matrix.GetValue(Part div 2, Part mod 2)));
          end;
          Lines.Append(LineFeed);
        end;
      except
        on Failure: Exception do
        begin
          const IsExpected = (Failure is EPdfException);
          if IsStrict and (not IsExpected) then
          begin
            raise;
          end;
          // What the page gave before it failed is dropped, as the oracle does
          Lines.Length := Start;
          Lines.Append(ErrorMarker).Append(PageIndex + 1).Append(LineFeed);
        end;
      end;
    end;
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

class function TImageLocations.PageOfLine(const Line: string): Integer;
begin
  if Line.StartsWith(ErrorMarker) then
  begin
    Exit(StrToIntDef(Line.Substring(ErrorMarker.Length), 0));
  end;

  const Space = Line.IndexOf(' ');
  if Space < 0 then
  begin
    Exit(0);
  end;
  Result := StrToIntDef(Line.Substring(0, Space), 0);
end;

class function TImageLocations.ParseLines(const Text: string): TArray<TGoldenLine>;
begin
  Result := nil;
  if Text = '' then
  begin
    Exit;
  end;

  // A checkout with CRLF line ends holds the same lines
  var Pieces := Text.Replace(#13, '').Split([LineFeed]);
  if Pieces[High(Pieces)] = '' then
  begin
    SetLength(Pieces, Length(Pieces) - 1);
  end;

  SetLength(Result, Length(Pieces));
  for var Index := 0 to High(Pieces) do
  begin
    Result[Index].Page := PageOfLine(Pieces[Index]);
    Result[Index].Number := Index + 1;
    Result[Index].Text := Pieces[Index];
  end;
end;

class function TImageLocations.IsKnownPage(const Page: Integer; const Platform: string; const KnownDifferences: TArray<string>): Boolean;
begin
  Result := False;
  for var Entry in KnownDifferences do
  begin
    // "<page> [<platform>] # <reason>"
    const Head = Entry.Split([CommentMarker])[0].Trim.Split([' '], TStringSplitOptions.ExcludeEmpty);
    if (Length(Head) = 0) or (StrToIntDef(Head[0], -1) <> Page) then
    begin
      Continue;
    end;
    Result := (Length(Head) = 1) or (Head[1] = Platform);
    if Result then
    begin
      Exit;
    end;
  end;
end;

class function TImageLocations.PageLines(const Lines: TArray<TGoldenLine>; const Page: Integer): TArray<string>;
begin
  Result := nil;
  for var Line in Lines do
  begin
    if Line.Page = Page then
    begin
      Result := Result + [Line.Text];
    end;
  end;
end;

class function TImageLocations.PagesOf(const Lines: TArray<TGoldenLine>): TArray<Integer>;
begin
  Result := nil;
  for var Line in Lines do
  begin
    if not TArray.Contains<Integer>(Result, Line.Page) then
    begin
      Result := Result + [Line.Page];
    end;
  end;
end;

class function TImageLocations.AreNumbersEqual(const Expected, Actual: string): Boolean;
begin
  if SameText(Expected, Actual) then
  begin
    Exit(True);
  end;

  var ExpectedValue, ActualValue: Double;
  const Settings = TFormatSettings.Invariant;
  const IsParsed = (TryStrToFloat(Expected, ExpectedValue, Settings) and TryStrToFloat(Actual, ActualValue, Settings));
  Result := (IsParsed and (Abs(ExpectedValue - ActualValue) <= MaxDifference));
end;

// <page> <index> <width> <height> <a> <b> <c> <d> <e> <f>: the first four are whole numbers that must be equal
class function TImageLocations.AreImageLinesEqual(const Expected, Actual: string): Boolean;
begin
  const ExpectedParts = Expected.Split([' ']);
  const ActualParts = Actual.Split([' ']);
  if (Length(ExpectedParts) <> Length(ActualParts)) then
  begin
    Exit(False);
  end;

  Result := True;
  for var Index := 0 to High(ExpectedParts) do
  begin
    const IsWhole = (Index < 4);
    if IsWhole then
    begin
      Result := (Result and (ExpectedParts[Index] = ActualParts[Index]));
    end
    else
    begin
      Result := (Result and AreNumbersEqual(ExpectedParts[Index], ActualParts[Index]));
    end;
  end;
end;

class procedure TImageLocations.ComparePage(const Page: Integer; const Expected, Actual: TArray<string>; var Differences: TArray<string>);
begin
  if Length(Expected) <> Length(Actual) then
  begin
    Differences := Differences + [Format('page %d: PDFBox has %d lines, Pdf4D has %d', [Page, Length(Expected), Length(Actual)])];
    Exit;
  end;

  for var Index := 0 to High(Expected) do
  begin
    const IsError = (Expected[Index].StartsWith(ErrorMarker) or Actual[Index].StartsWith(ErrorMarker));
    var IsEqual: Boolean;
    if IsError then
    begin
      IsEqual := (Expected[Index] = Actual[Index]);
    end
    else
    begin
      IsEqual := AreImageLinesEqual(Expected[Index], Actual[Index]);
    end;
    if not IsEqual then
    begin
      Differences := Differences + [Format('page %d line %d: PDFBox "%s", Pdf4D "%s"', [Page, Index + 1, Expected[Index], Actual[Index]])];
    end;
  end;
end;

class function TImageLocations.Compare(const Expected, Actual: string; const KnownDifferences: TArray<string>; const Platform: string): TArray<string>;
begin
  Result := nil;
  const ExpectedLines = ParseLines(Expected);
  const ActualLines = ParseLines(Actual);

  const IsLoadError = ((Length(ExpectedLines) > 0) and ExpectedLines[0].Text.StartsWith(LoadErrorMarker)) or
                      ((Length(ActualLines) > 0) and ActualLines[0].Text.StartsWith(LoadErrorMarker));
  if IsLoadError then
  begin
    if Expected <> Actual then
    begin
      Result := [Format('PDFBox "%s", Pdf4D "%s"', [Expected.Trim, Actual.Trim])];
    end;
    Exit;
  end;

  var Pages := PagesOf(ExpectedLines);
  for var Page in PagesOf(ActualLines) do
  begin
    if not TArray.Contains<Integer>(Pages, Page) then
    begin
      Pages := Pages + [Page];
    end;
  end;

  for var Page in Pages do
  begin
    if not IsKnownPage(Page, Platform, KnownDifferences) then
    begin
      ComparePage(Page, PageLines(ExpectedLines, Page), PageLines(ActualLines, Page), Result);
    end;
  end;
end;

end.
