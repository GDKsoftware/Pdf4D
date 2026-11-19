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
    type
      // The first and last character (0-based) of a range that lie on one page
      TCharSpan = record
        First: Integer;
        Last: Integer;
      end;

  private
    FText: string;
    FGlyphs: TArray<TPdfGlyphBox>;
    FCharToGlyph: TArray<Integer>;
    // The glyph indices of every ActualText sequence, ascending
    FSpanGlyphs: TObjectDictionary<Integer, TList<Integer>>;

    procedure IndexSpans;
    procedure GuardRange(const Start, Length: Integer);
    function GlyphsOfRange(const Start, Length: Integer): TArray<Integer>;
    procedure AddActualTextGlyphs(const Found: TList<Integer>);
    function CharSpansPerPage(const Start, Length: Integer): TDictionary<Integer, TCharSpan>;
    function RunOfPage(const PageGlyphs: TArray<Integer>; const CharSpans: TDictionary<Integer, TCharSpan>): TPdfLocatedRun;
    function QuadsOfLines(const PageGlyphs: TArray<Integer>): TArray<TPdfQuad>;

  public
    // CharToGlyph[I] is the glyph of character I (0-based), or -1 for a separator or a character without a quad
    constructor Create(const Text: string; const Glyphs: TArray<TPdfGlyphBox>; const CharToGlyph: TArray<Integer>);
    destructor Destroy; override;

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
  FSpanGlyphs := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  IndexSpans;
end;

destructor TPdfPositionedText.Destroy;
begin
  FSpanGlyphs.Free;
  inherited;
end;

// Made once here, not when needed, so that Locate changes no state and may run on several threads
procedure TPdfPositionedText.IndexSpans;
begin
  for var Index := 0 to High(FGlyphs) do
  begin
    const Span = FGlyphs[Index].ActualTextSpan;
    if Span = 0 then
    begin
      Continue;
    end;

    var Members: TList<Integer>;
    if not FSpanGlyphs.TryGetValue(Span, Members) then
    begin
      Members := TList<Integer>.Create;
      FSpanGlyphs.Add(Span, Members);
    end;
    Members.Add(Index);
  end;
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
  const Spans = TDictionary<Integer, Boolean>.Create;
  const Known = TDictionary<Integer, Boolean>.Create;
  try
    for var Glyph in Found do
    begin
      const Span = FGlyphs[Glyph].ActualTextSpan;
      if Span <> 0 then
      begin
        Spans.AddOrSetValue(Span, True);
      end;
    end;

    if Spans.Count = 0 then
    begin
      Exit;
    end;

    for var Glyph in Found do
    begin
      Known.AddOrSetValue(Glyph, True);
    end;

    const CountBefore = Found.Count;
    for var Span in Spans.Keys do
    begin
      for var Glyph in FSpanGlyphs[Span] do
      begin
        if not Known.ContainsKey(Glyph) then
        begin
          Found.Add(Glyph);
        end;
      end;
    end;

    if Found.Count > CountBefore then
    begin
      Found.Sort;
    end;
  finally
    Known.Free;
    Spans.Free;
  end;
end;

// A glyph that lies wholly before the quad so far, further than half its own width, starts a quad of its own: it belongs to another
// run of the line, such as a text piece that was drawn later but lies to the left. Glyphs that touch the quad extend it, which keeps
// right-to-left text in logical order together.
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
      const IsBackAwayFromLine = (IsSameLine and (LineQuad.GapBefore(Box.Quad) > Box.Quad.BaselineLength / 2));
      if IsSameLine and not IsBackAwayFromLine then
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

// One pass over the range, so that a long range costs no more per page than a short one
function TPdfPositionedText.CharSpansPerPage(const Start, Length: Integer): TDictionary<Integer, TCharSpan>;
begin
  Result := TDictionary<Integer, TCharSpan>.Create;
  try
    for var Index := Start - 1 to Start + Length - 2 do
    begin
      const Glyph = FCharToGlyph[Index];
      if Glyph < 0 then
      begin
        Continue;
      end;

      const PageIndex = FGlyphs[Glyph].PageIndex;
      var CharSpan: TCharSpan;
      if not Result.TryGetValue(PageIndex, CharSpan) then
      begin
        CharSpan.First := Index;
      end;
      CharSpan.Last := Index;
      Result.AddOrSetValue(PageIndex, CharSpan);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPdfPositionedText.RunOfPage(const PageGlyphs: TArray<Integer>; const CharSpans: TDictionary<Integer, TCharSpan>): TPdfLocatedRun;
begin
  Result.PageIndex := FGlyphs[PageGlyphs[0]].PageIndex;
  Result.Quads := QuadsOfLines(PageGlyphs);
  Result.Text := '';

  // A page can hold glyphs of the range without holding one of its characters, when an ActualText sequence runs over a page end
  var CharSpan: TCharSpan;
  if CharSpans.TryGetValue(Result.PageIndex, CharSpan) then
  begin
    Result.Text := Copy(FText, CharSpan.First + 1, CharSpan.Last - CharSpan.First + 1);
  end;
end;

function TPdfPositionedText.Locate(const Start, Length: Integer): TArray<TPdfLocatedRun>;
begin
  GuardRange(Start, Length);

  const Runs = TList<TPdfLocatedRun>.Create;
  const PageGlyphs = TList<Integer>.Create;
  const CharSpans = CharSpansPerPage(Start, Length);
  try
    for var Glyph in GlyphsOfRange(Start, Length) do
    begin
      const IsOtherPage = (PageGlyphs.Count > 0) and (FGlyphs[Glyph].PageIndex <> FGlyphs[PageGlyphs[0]].PageIndex);
      if IsOtherPage then
      begin
        Runs.Add(RunOfPage(PageGlyphs.ToArray, CharSpans));
        PageGlyphs.Clear;
      end;
      PageGlyphs.Add(Glyph);
    end;

    if PageGlyphs.Count > 0 then
    begin
      Runs.Add(RunOfPage(PageGlyphs.ToArray, CharSpans));
    end;
    Result := Runs.ToArray;
  finally
    CharSpans.Free;
    PageGlyphs.Free;
    Runs.Free;
  end;
end;

end.
