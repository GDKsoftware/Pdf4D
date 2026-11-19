// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.Layout;

{$EXCESSPRECISION OFF}

interface

uses
  System.Generics.Collections,
  Pdf4D.Common.Quad,
  Pdf4D.Text.PositionedText;

type
  TPdfLayoutOptions = record
    // A gap along the baseline of more than this many times the width of a space ends a segment
    SegmentGapFactor: Single;
    // A word that ends on a colon ends the segment
    BreakAfterColon: Boolean;

    class function Default: TPdfLayoutOptions; static;
  end;

  // A word, segment or line of a page
  TPdfLayoutItem = record
    Text: string;
    // One quad: the union of the glyphs of the item
    Quads: TArray<TPdfQuad>;
    // The range in TPdfPositionedText.Text, 1-based
    Start, Length: Integer;
  end;

  TPdfPageLayout = record
    PageIndex: Integer;
    Words, Segments, Lines: TArray<TPdfLayoutItem>;
  end;

  TPdfTextLayoutBuilder = class
  private
    type
      TWordSpan = record
        LineIndex: Integer;
        // The range of characters of the word, 0-based
        First, Last: Integer;
        Quad: TPdfQuad;
        WidthOfSpace: Single;
      end;

  private
    FPositioned: TPdfPositionedText;
    FPageIndex: Integer;
    FOptions: TPdfLayoutOptions;
    FWords: TList<TWordSpan>;

    constructor Create(const Positioned: TPdfPositionedText; const PageIndex: Integer; const Options: TPdfLayoutOptions);

    procedure CollectWords;
    procedure AddWord(const First, Last: Integer);
    function BuildWords: TArray<TPdfLayoutItem>;
    function BuildSegments: TArray<TPdfLayoutItem>;
    function BuildLines: TArray<TPdfLayoutItem>;
    function ItemOfWords(const FirstWord, LastWord: Integer): TPdfLayoutItem;
    function EndsSegmentBefore(const WordPosition: Integer): Boolean;
    function EndsWithColon(const Word: TWordSpan): Boolean;
    function GapAlongBaseline(const Previous, Next: TWordSpan): Double;

  public
    class function Build(const Text: TPdfPositionedText; const PageIndex: Integer; const Options: TPdfLayoutOptions): TPdfPageLayout; static;

    destructor Destroy; override;
  end;

implementation

uses
  System.Character;

{ TPdfLayoutOptions }

class function TPdfLayoutOptions.Default: TPdfLayoutOptions;
begin
  Result.SegmentGapFactor := 2.0;
  Result.BreakAfterColon := True;
end;

{ TPdfTextLayoutBuilder }

class function TPdfTextLayoutBuilder.Build(const Text: TPdfPositionedText; const PageIndex: Integer; const Options: TPdfLayoutOptions): TPdfPageLayout;
begin
  const Builder = TPdfTextLayoutBuilder.Create(Text, PageIndex, Options);
  try
    Builder.CollectWords;

    Result.PageIndex := PageIndex;
    Result.Words := Builder.BuildWords;
    Result.Segments := Builder.BuildSegments;
    Result.Lines := Builder.BuildLines;
  finally
    Builder.Free;
  end;
end;

constructor TPdfTextLayoutBuilder.Create(const Positioned: TPdfPositionedText; const PageIndex: Integer; const Options: TPdfLayoutOptions);
begin
  inherited Create;
  FPositioned := Positioned;
  FPageIndex := PageIndex;
  FOptions := Options;
  FWords := TList<TWordSpan>.Create;
end;

destructor TPdfTextLayoutBuilder.Destroy;
begin
  FWords.Free;
  inherited Destroy;
end;

// A word is a run of characters of one WordIndex that holds no white space: the stripper writes the spaces of the content
// itself inside a word
procedure TPdfTextLayoutBuilder.CollectWords;
begin
  var First := -1;
  var WordIndex := -1;
  for var Index := 0 to Length(FPositioned.Text) - 1 do
  begin
    const Glyph = FPositioned.GlyphOfChar(Index);
    var IsWordChar := False;
    var CharWordIndex := -1;
    if Glyph >= 0 then
    begin
      const Box = FPositioned.Glyphs[Glyph];
      IsWordChar := ((Box.PageIndex = FPageIndex) and not FPositioned.Text[Index + 1].IsWhiteSpace);
      CharWordIndex := Box.WordIndex;
    end;

    const ContinuesWord = (IsWordChar and (First >= 0) and (CharWordIndex = WordIndex));
    if not ContinuesWord then
    begin
      if First >= 0 then
      begin
        AddWord(First, Index - 1);
      end;

      First := -1;
      if IsWordChar then
      begin
        First := Index;
        WordIndex := CharWordIndex;
      end;
    end;
  end;

  if First >= 0 then
  begin
    AddWord(First, Length(FPositioned.Text) - 1);
  end;
end;

procedure TPdfTextLayoutBuilder.AddWord(const First, Last: Integer);
begin
  const Runs = FPositioned.Locate(First + 1, Last - First + 1);
  for var Run in Runs do
  begin
    if (Run.PageIndex = FPageIndex) and (Length(Run.Quads) > 0) then
    begin
      var Span: TWordSpan;
      Span.First := First;
      Span.Last := Last;
      Span.LineIndex := FPositioned.Glyphs[FPositioned.GlyphOfChar(First)].LineIndex;
      Span.WidthOfSpace := FPositioned.Glyphs[FPositioned.GlyphOfChar(Last)].WidthOfSpace;
      Span.Quad := Run.Quads[0];
      for var Index := 1 to High(Run.Quads) do
      begin
        Span.Quad := Span.Quad.Extend(Run.Quads[Index]);
      end;
      FWords.Add(Span);
    end;
  end;
end;

function TPdfTextLayoutBuilder.ItemOfWords(const FirstWord, LastWord: Integer): TPdfLayoutItem;
begin
  var Quad := FWords[FirstWord].Quad;
  for var Index := FirstWord + 1 to LastWord do
  begin
    Quad := Quad.Extend(FWords[Index].Quad);
  end;

  const FirstChar = FWords[FirstWord].First;
  const LastChar = FWords[LastWord].Last;
  Result.Start := FirstChar + 1;
  Result.Length := LastChar - FirstChar + 1;
  Result.Text := Copy(FPositioned.Text, Result.Start, Result.Length);
  Result.Quads := [Quad];
end;

function TPdfTextLayoutBuilder.BuildWords: TArray<TPdfLayoutItem>;
begin
  SetLength(Result, FWords.Count);
  for var Index := 0 to FWords.Count - 1 do
  begin
    Result[Index] := ItemOfWords(Index, Index);
  end;
end;

function TPdfTextLayoutBuilder.BuildSegments: TArray<TPdfLayoutItem>;
begin
  const Items = TList<TPdfLayoutItem>.Create;
  try
    var FirstWord := 0;
    for var Index := 1 to FWords.Count do
    begin
      const IsEnd = ((Index = FWords.Count) or EndsSegmentBefore(Index));
      if IsEnd then
      begin
        Items.Add(ItemOfWords(FirstWord, Index - 1));
        FirstWord := Index;
      end;
    end;

    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function TPdfTextLayoutBuilder.BuildLines: TArray<TPdfLayoutItem>;
begin
  const Items = TList<TPdfLayoutItem>.Create;
  try
    var FirstWord := 0;
    for var Index := 1 to FWords.Count do
    begin
      const IsEnd = ((Index = FWords.Count) or (FWords[Index].LineIndex <> FWords[Index - 1].LineIndex));
      if IsEnd then
      begin
        Items.Add(ItemOfWords(FirstWord, Index - 1));
        FirstWord := Index;
      end;
    end;

    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function TPdfTextLayoutBuilder.EndsSegmentBefore(const WordPosition: Integer): Boolean;
begin
  const Previous = FWords[WordPosition - 1];
  const Next = FWords[WordPosition];

  const IsOtherLine = (Previous.LineIndex <> Next.LineIndex);
  if IsOtherLine then
  begin
    Exit(True);
  end;

  const IsBrokenByColon = (FOptions.BreakAfterColon and EndsWithColon(Previous));
  if IsBrokenByColon then
  begin
    Exit(True);
  end;

  const MaximumGap = Double(FOptions.SegmentGapFactor) * Double(Previous.WidthOfSpace);
  Result := (GapAlongBaseline(Previous, Next) > MaximumGap);
end;

function TPdfTextLayoutBuilder.EndsWithColon(const Word: TWordSpan): Boolean;
begin
  Result := (FPositioned.Text[Word.Last + 1] = ':');
end;

// The distance from the end of Previous to the start of Next, measured along the baseline of Previous. A baseline without
// length gives no gap. Double, so that large coordinates do not overflow.
function TPdfTextLayoutBuilder.GapAlongBaseline(const Previous, Next: TWordSpan): Double;
begin
  const BaselineX = Double(Previous.Quad.P2.X) - Double(Previous.Quad.P1.X);
  const BaselineY = Double(Previous.Quad.P2.Y) - Double(Previous.Quad.P1.Y);
  const BaselineLength = Sqrt(BaselineX * BaselineX + BaselineY * BaselineY);
  if not (BaselineLength > 0) then
  begin
    Exit(0);
  end;

  const GapX = Double(Next.Quad.P1.X) - Double(Previous.Quad.P2.X);
  const GapY = Double(Next.Quad.P1.Y) - Double(Previous.Quad.P2.Y);
  Result := (GapX * BaselineX + GapY * BaselineY) / BaselineLength;
end;

end.
