// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.PositionedText;

{$EXCESSPRECISION OFF}

interface

uses
  System.Generics.Collections,
  Pdf4D.Common.Quad;

type
  // The place of one glyph in the extracted text
  TPdfGlyphBox = record
    // 0-based
    PageIndex: Integer;
    // Global over the whole text: it increases at every line separator and at the start of every page
    LineIndex: Integer;
    // Global: one per word that the stripper wrote
    WordIndex: Integer;
    Quad: TPdfQuad;
    // TTextPosition.WidthOfSpace in user space units
    WidthOfSpace: Single;
    // The number of the ActualText sequence that replaced the text of this glyph (the glyphs of one sequence share it), 0 when there is none
    ActualTextSpan: Integer;
  end;

  // The part of a located range that lies on one page
  TPdfLocatedRun = record
    PageIndex: Integer;
    Text: string;
    // One per line touched
    Quads: TArray<TPdfQuad>;
  end;

  // The text of a document with the glyph of every character. The positions are 1-based UTF-16 code units in Text.
  TPdfPositionedText = class
  private
    FText: string;
    FGlyphs: TArray<TPdfGlyphBox>;
    FCharToGlyph: TArray<Integer>;

    procedure GuardRange(const Start, Length: Integer);
    function GlyphsOfRange(const Start, Length: Integer): TArray<Integer>;
    procedure AddActualTextGlyphs(const Found: TList<Integer>);
    function RunOfPage(const Start, Length: Integer; const PageGlyphs: TArray<Integer>): TPdfLocatedRun;
    function QuadsOfLines(const PageGlyphs: TArray<Integer>): TArray<TPdfQuad>;

  public
    // CharToGlyph[I] is the glyph of character I (0-based), or -1 for a separator or a character without a quad
    constructor Create(const Text: string; const Glyphs: TArray<TPdfGlyphBox>; const CharToGlyph: TArray<Integer>);

    // The glyph of character Index (0-based), or -1
    function GlyphOfChar(const Index: Integer): Integer;
    // Start is 1-based. A range that touches the text of an ActualText sequence includes all the glyphs of that sequence. Raises EArgumentOutOfRangeException when Start < 1, Length < 0 or Start + Length - 1 > Length(Text).
    function Locate(const Start, Length: Integer): TArray<TPdfLocatedRun>;

    property Text: string read FText;
    property Glyphs: TArray<TPdfGlyphBox> read FGlyphs;
  end;

implementation

uses
  System.SysUtils;

{ TPdfPositionedText }

constructor TPdfPositionedText.Create(const Text: string; const Glyphs: TArray<TPdfGlyphBox>; const CharToGlyph: TArray<Integer>);
begin
  inherited Create;
  FText := Text;
  FGlyphs := Glyphs;
  FCharToGlyph := CharToGlyph;
end;

function TPdfPositionedText.GlyphOfChar(const Index: Integer): Integer;
begin
  const IsInRange = ((Index >= 0) and (Index < System.Length(FCharToGlyph)));
  if not IsInRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The character index %d is outside the text of %d characters', [Index, System.Length(FCharToGlyph)]);
  end;

  Result := FCharToGlyph[Index];
end;

procedure TPdfPositionedText.GuardRange(const Start, Length: Integer);
begin
  const IsValid = ((Start >= 1) and (Length >= 0) and (Length <= System.Length(FText) - Start + 1));
  if not IsValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The range of %d characters from %d lies outside the text of %d characters',
                                                 [Length, Start, System.Length(FText)]);
  end;
end;

function TPdfPositionedText.GlyphsOfRange(const Start, Length: Integer): TArray<Integer>;
begin
  const Found = TList<Integer>.Create;
  try
    var Previous := -1;
    for var Index := Start - 1 to Start + Length - 2 do
    begin
      const Glyph = FCharToGlyph[Index];
      const IsNewGlyph = ((Glyph >= 0) and (Glyph <> Previous));
      if IsNewGlyph then
      begin
        Found.Add(Glyph);
        Previous := Glyph;
      end;
    end;

    AddActualTextGlyphs(Found);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

// The text of an ActualText sequence sits on its first glyph, so a range that touches the sequence takes all its glyphs
procedure TPdfPositionedText.AddActualTextGlyphs(const Found: TList<Integer>);
begin
  const Spans = TList<Integer>.Create;
  try
    for var Glyph in Found do
    begin
      const Span = FGlyphs[Glyph].ActualTextSpan;
      if (Span <> 0) and not Spans.Contains(Span) then
      begin
        Spans.Add(Span);
      end;
    end;

    if Spans.Count = 0 then
    begin
      Exit;
    end;

    const InSpans = TList<Integer>.Create;
    try
      for var Index := 0 to High(FGlyphs) do
      begin
        if Spans.Contains(FGlyphs[Index].ActualTextSpan) and not Found.Contains(Index) then
        begin
          InSpans.Add(Index);
        end;
      end;
      Found.AddRange(InSpans);
    finally
      InSpans.Free;
    end;
    Found.Sort;
  finally
    Spans.Free;
  end;
end;

function TPdfPositionedText.QuadsOfLines(const PageGlyphs: TArray<Integer>): TArray<TPdfQuad>;
begin
  const Quads = TList<TPdfQuad>.Create;
  try
    var Line := -1;
    var LineQuad: TPdfQuad;
    for var Glyph in PageGlyphs do
    begin
      const Box = FGlyphs[Glyph];
      const IsSameLine = (Quads.Count > 0) and (Box.LineIndex = Line);
      if IsSameLine then
      begin
        LineQuad := LineQuad.Extend(Box.Quad);
        Quads[Quads.Count - 1] := LineQuad;
      end
      else
      begin
        Line := Box.LineIndex;
        LineQuad := Box.Quad;
        Quads.Add(LineQuad);
      end;
    end;

    Result := Quads.ToArray;
  finally
    Quads.Free;
  end;
end;

function TPdfPositionedText.RunOfPage(const Start, Length: Integer; const PageGlyphs: TArray<Integer>): TPdfLocatedRun;
begin
  Result.PageIndex := FGlyphs[PageGlyphs[0]].PageIndex;
  Result.Quads := QuadsOfLines(PageGlyphs);

  var First := -1;
  var Last := -1;
  for var Index := Start - 1 to Start + Length - 2 do
  begin
    const Glyph = FCharToGlyph[Index];
    const IsOnPage = ((Glyph >= 0) and (FGlyphs[Glyph].PageIndex = Result.PageIndex));
    if IsOnPage then
    begin
      if First < 0 then
      begin
        First := Index;
      end;
      Last := Index;
    end;
  end;

  Result.Text := Copy(FText, First + 1, Last - First + 1);
end;

function TPdfPositionedText.Locate(const Start, Length: Integer): TArray<TPdfLocatedRun>;
begin
  GuardRange(Start, Length);

  const Runs = TList<TPdfLocatedRun>.Create;
  const PageGlyphs = TList<Integer>.Create;
  try
    for var Glyph in GlyphsOfRange(Start, Length) do
    begin
      const IsOtherPage = (PageGlyphs.Count > 0) and (FGlyphs[Glyph].PageIndex <> FGlyphs[PageGlyphs[0]].PageIndex);
      if IsOtherPage then
      begin
        Runs.Add(RunOfPage(Start, Length, PageGlyphs.ToArray));
        PageGlyphs.Clear;
      end;
      PageGlyphs.Add(Glyph);
    end;

    if PageGlyphs.Count > 0 then
    begin
      Runs.Add(RunOfPage(Start, Length, PageGlyphs.ToArray));
    end;
    Result := Runs.ToArray;
  finally
    PageGlyphs.Free;
    Runs.Free;
  end;
end;

end.
