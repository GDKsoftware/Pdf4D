// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.PositionStripper;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Model.Document,
  Pdf4D.Model.Page,
  Pdf4D.Text.PositionedText,
  Pdf4D.Text.Stripper,
  Pdf4D.Text.TextPosition;

type
  // Extracts the same text as TPdfTextStripper with the same options, and keeps the glyph of every character
  TPdfPositionStripper = class(TPdfTextStripper)
  private
    FPageIndex: Integer;
    FLineIndex: Integer;
    FWordIndex: Integer;
    FCropLowerLeft: TPointF;
    FLog: TPdfLog;
    FBuilder: TStringBuilder;
    FGlyphs: TList<TPdfGlyphBox>;
    FCharToGlyph: TList<Integer>;

    procedure PadCharsTo(const Count: Integer);
    function AddGlyph(const Position: TTextPosition): Integer;
    procedure MapWord(const Text: string; const Positions: TArray<TTextPosition>);
    function CharCounts(const Text: string; const Positions: TArray<TTextPosition>): TArray<Integer>;
    function RawCounts(const Positions: TArray<TTextPosition>): TArray<Integer>;
    function NormalizedCounts(const Positions: TArray<TTextPosition>): TArray<Integer>;
    function NormalizedLengthAfter(const Previous: Char; const HasPrevious: Boolean; const Piece: string): Integer;
    class function ProportionalCounts(const CharCount, PositionCount: Integer): TArray<Integer>; static;
    class function Sum(const Counts: TArray<Integer>): Integer; static;

  protected
    procedure BeginPage(const Page: TPDPage); override;
    procedure WriteLineSeparator; override;
    procedure WriteString(const Text: string; const TextPositions: TArray<TTextPosition>); override;

  public
    constructor Create;
    destructor Destroy; override;

    // The caller owns the result
    function Extract(const Document: TPDDocument): TPdfPositionedText;
  end;

implementation

uses
  Pdf4D.Common.Quad,
  Pdf4D.Text.GlyphQuad;

{ TPdfPositionStripper }

constructor TPdfPositionStripper.Create;
begin
  inherited Create;
  FGlyphs := TList<TPdfGlyphBox>.Create;
  FCharToGlyph := TList<Integer>.Create;
end;

destructor TPdfPositionStripper.Destroy;
begin
  FCharToGlyph.Free;
  FGlyphs.Free;
  inherited;
end;

function TPdfPositionStripper.Extract(const Document: TPDDocument): TPdfPositionedText;
begin
  FGlyphs.Clear;
  FCharToGlyph.Clear;
  FPageIndex := -1;
  FLineIndex := -1;
  FWordIndex := -1;

  const Builder = TStringBuilder.Create;
  const Writer = TStringWriter.Create(Builder);
  try
    FBuilder := Builder;
    WriteText(Document, Writer);

    const Text = Builder.ToString;
    PadCharsTo(Length(Text));
    Result := TPdfPositionedText.Create(Text, FGlyphs.ToArray, FCharToGlyph.ToArray);
  finally
    FBuilder := nil;
    FLog := nil;
    Writer.Free;
    Builder.Free;
  end;
end;

procedure TPdfPositionStripper.BeginPage(const Page: TPDPage);
begin
  inherited;
  FPageIndex := Document.Pages.IndexOf(Page.CosObject);
  FCropLowerLeft := TPointF.Create(Page.CropBox.LowerLeftX, Page.CropBox.LowerLeftY);
  FLog := Page.Context.Log;
  Inc(FLineIndex);
end;

procedure TPdfPositionStripper.WriteLineSeparator;
begin
  inherited;
  Inc(FLineIndex);
end;

procedure TPdfPositionStripper.WriteString(const Text: string; const TextPositions: TArray<TTextPosition>);
begin
  // What was written outside the words (separators, paragraph and page marks) has no glyph
  PadCharsTo(FBuilder.Length);
  Inc(FWordIndex);

  inherited;

  MapWord(Text, TextPositions);
  PadCharsTo(FBuilder.Length);
end;

procedure TPdfPositionStripper.PadCharsTo(const Count: Integer);
begin
  while FCharToGlyph.Count < Count do
  begin
    FCharToGlyph.Add(-1);
  end;
end;

function TPdfPositionStripper.AddGlyph(const Position: TTextPosition): Integer;
begin
  Result := -1;
  var Quad: TPdfQuad;
  if not TGlyphQuad.TryCreate(Position, FCropLowerLeft, Quad) then
  begin
    Exit;
  end;

  var Box: TPdfGlyphBox;
  Box.PageIndex := FPageIndex;
  Box.LineIndex := FLineIndex;
  Box.WordIndex := FWordIndex;
  Box.Quad := Quad;
  Box.WidthOfSpace := Position.WidthOfSpace;
  Box.ActualTextSpan := Position.ActualTextSpan;
  Result := FGlyphs.Add(Box);
end;

procedure TPdfPositionStripper.MapWord(const Text: string; const Positions: TArray<TTextPosition>);
begin
  const Counts = CharCounts(Text, Positions);
  for var Index := 0 to High(Positions) do
  begin
    const Glyph = AddGlyph(Positions[Index]);
    for var Character := 1 to Counts[Index] do
    begin
      FCharToGlyph.Add(Glyph);
    end;
  end;
end;

// How many characters of Text come from each position. Where the normalisation of the word changes the length, the positions
// are measured one by one; when even that does not add up, the characters are spread evenly.
function TPdfPositionStripper.CharCounts(const Text: string; const Positions: TArray<TTextPosition>): TArray<Integer>;
begin
  const Raw = RawCounts(Positions);
  if Sum(Raw) = Length(Text) then
  begin
    Exit(Raw);
  end;

  const Normalized = NormalizedCounts(Positions);
  if Sum(Normalized) = Length(Text) then
  begin
    Exit(Normalized);
  end;

  if Assigned(FLog) then
  begin
    FLog.Debug('The characters of a word do not add up to its positions, they are spread evenly (%d characters, %d positions)',
               [Length(Text), Length(Positions)]);
  end;
  Result := ProportionalCounts(Length(Text), Length(Positions));
end;

function TPdfPositionStripper.RawCounts(const Positions: TArray<TTextPosition>): TArray<Integer>;
begin
  SetLength(Result, Length(Positions));
  for var Index := 0 to High(Positions) do
  begin
    Result[Index] := Length(Positions[Index].VisuallyOrderedUnicode);
  end;
end;

function TPdfPositionStripper.NormalizedCounts(const Positions: TArray<TTextPosition>): TArray<Integer>;
begin
  SetLength(Result, Length(Positions));
  var Previous := #0;
  var HasPrevious := False;
  for var Index := 0 to High(Positions) do
  begin
    const Piece = Positions[Index].VisuallyOrderedUnicode;
    Result[Index] := NormalizedLengthAfter(Previous, HasPrevious, Piece);
    if Piece <> '' then
    begin
      Previous := Piece[Length(Piece)];
      HasPrevious := True;
    end;
  end;
end;

// The normalisation of a character can depend on the character before it, so that one is normalised along and left out
function TPdfPositionStripper.NormalizedLengthAfter(const Previous: Char; const HasPrevious: Boolean; const Piece: string): Integer;
begin
  if not HasPrevious then
  begin
    Exit(Length(NormalizeWord(Piece)));
  end;

  const WithPrevious = Length(NormalizeWord(Previous + Piece));
  const PreviousOnly = Length(NormalizeWord(Previous));
  Result := WithPrevious - PreviousOnly;
end;

class function TPdfPositionStripper.ProportionalCounts(const CharCount, PositionCount: Integer): TArray<Integer>;
begin
  Result := nil;
  SetLength(Result, PositionCount);
  if PositionCount = 0 then
  begin
    Exit;
  end;

  for var Character := 0 to CharCount - 1 do
  begin
    const Owner = Character * PositionCount div CharCount;
    Inc(Result[Owner]);
  end;
end;

class function TPdfPositionStripper.Sum(const Counts: TArray<Integer>): Integer;
begin
  Result := 0;
  for var Count in Counts do
  begin
    Inc(Result, Count);
  end;
end;

end.
