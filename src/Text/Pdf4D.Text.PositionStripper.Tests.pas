// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.PositionStripper.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Text.PositionedText,
  Pdf4D.Text.PositionStripper;

type
  // Adds a character to every word of more than two characters, so that the text no longer matches the positions however it is measured
  TTrailingMarkStripper = class(TPdfPositionStripper)
  protected
    function HandleDirection(const Text: string): string; override;
  end;

  // Makes the protected spreading of characters reachable
  TProportionalCountsStripper = class(TPdfPositionStripper)
  public
    class function CountsOf(const CharCount, PositionCount: Integer): TArray<Integer>;
  end;

  [TestFixture]
  TPdfPositionStripperTests = class
  private
    const OneLine = 'BT /F1 12 Tf 100 700 Td (Factuur) Tj 44.016 0 Td (2024-0815) Tj ET';
    const TwoParagraphs = 'BT /F1 12 Tf 100 700 Td (Para one) Tj 0 -60 Td (Para two) Tj ET';
    const TwoLines = 'BT /F1 12 Tf 100 700 Td (Line one) Tj 0 -14 Td (Line two) Tj ET';

  private
    FModels: TModelTestDocuments;
    FPositioned: TPdfPositionedText;

    function NewBuilder(const Content: string): TTestPdfBuilder;
    function NewTwoPageBuilder(const FirstContent, SecondContent: string; const Kids: string = '3 0 R 5 0 R'): TTestPdfBuilder;
    function NewLigatureBuilder(const Content, Mappings: string): TTestPdfBuilder;
    // The text of the text stripper and of the position stripper with the same options. The builder is freed.
    procedure ExtractBoth(const Builder: TTestPdfBuilder; const SortByPosition: Boolean; out Expected, Actual: string);
    // Extracts with the position stripper. The builder is freed.
    procedure Extract(const Builder: TTestPdfBuilder; const SortByPosition: Boolean = False);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTextEqualsExtractText;

    [Test]
    procedure TestSeparatorsHaveNoGlyph;

    [Test]
    procedure TestLigatureMapsTwoCharsToOneGlyph;

    [Test]
    procedure TestSortedOutputMapsToRightGlyph;

    [Test]
    procedure TestAllahLigatureTakesTheCharactersOfItsGlyph;

    [Test]
    procedure TestWordThatDoesNotAddUpIsSpreadOverItsGlyphsAndLogged;

    [Test]
    procedure TestGlyphWithoutQuadGivesMinusOneAndKeepsText;

    [Test]
    procedure TestLocateActualTextHighlightsAllGlyphsOfTheSequence;

    [Test]
    procedure TestLocateSingleWord;

    [Test]
    procedure TestLocateAcrossLinesGivesQuadPerLine;

    [Test]
    procedure TestLocateAcrossPagesGivesFragmentPerPage;

    [Test]
    procedure TestLocateOnlySeparatorsIsEmpty;

    [Test]
    procedure TestLocateOutOfRangeRaises;

    [Test]
    procedure TestPageReferencedTwiceGivesPageIndexOfEachOccurrence;

    [Test]
    procedure TestSpreadingVeryLongWordDoesNotOverflow;
  end;

implementation

uses
  Pdf4D.Tests.TextDocuments,
  Pdf4D.Text.Stripper;

const
  Tolerance = 0.001;

{ TTrailingMarkStripper }

function TTrailingMarkStripper.HandleDirection(const Text: string): string;
begin
  Result := Text;
  if Length(Text) > 2 then
  begin
    Result := Text + '!';
  end;
end;

{ TProportionalCountsStripper }

class function TProportionalCountsStripper.CountsOf(const CharCount, PositionCount: Integer): TArray<Integer>;
begin
  Result := ProportionalCounts(CharCount, PositionCount);
end;

{ TPdfPositionStripperTests }

procedure TPdfPositionStripperTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
end;

procedure TPdfPositionStripperTests.TearDown;
begin
  FreeAndNil(FPositioned);
  FModels.Free;
end;

function TPdfPositionStripperTests.NewBuilder(const Content: string): TTestPdfBuilder;
begin
  Result := TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, Content);
end;

function TPdfPositionStripperTests.NewTwoPageBuilder(const FirstContent, SecondContent: string; const Kids: string): TTestPdfBuilder;
begin
  const Resources = '/Resources << /Font << /F1 10 0 R >> >>';
  Result := TModelTestDocuments.NewBuilder(Format('<< /Type /Pages /Kids [%s] /Count 2 >>', [Kids]));
  try
    Result.AddObject(3, Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R %s >>', [Resources]));
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(FirstContent));
    Result.AddObject(5, Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R %s >>', [Resources]));
    Result.AddStreamObject(6, '', TEncoding.ASCII.GetBytes(SecondContent));
    Result.AddObject(10, TTextTestDocuments.HelveticaF1);
  except
    Result.Free;
    raise;
  end;
end;

function TPdfPositionStripperTests.NewLigatureBuilder(const Content, Mappings: string): TTestPdfBuilder;
begin
  const CMap = 'begincmap 1 begincodespacerange <00> <FF> endcodespacerange ' + Format('%s endcmap', [Mappings]);
  Result := TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 20 0 R >>', Content);
  try
    Result.AddStreamObject(20, '', TEncoding.ASCII.GetBytes(CMap));
  except
    Result.Free;
    raise;
  end;
end;

procedure TPdfPositionStripperTests.ExtractBoth(const Builder: TTestPdfBuilder; const SortByPosition: Boolean; out Expected, Actual: string);
begin
  try
    const Document = FModels.Open(Builder);

    const TextStripper = TPdfTextStripper.Create;
    try
      TextStripper.SortByPosition := SortByPosition;
      Expected := TextStripper.GetText(Document);
    finally
      TextStripper.Free;
    end;

    const PositionStripper = TPdfPositionStripper.Create;
    try
      PositionStripper.SortByPosition := SortByPosition;
      const Positioned = PositionStripper.Extract(Document);
      try
        Actual := Positioned.Text;
      finally
        Positioned.Free;
      end;
    finally
      PositionStripper.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TPdfPositionStripperTests.Extract(const Builder: TTestPdfBuilder; const SortByPosition: Boolean);
begin
  FreeAndNil(FPositioned);
  try
    const Stripper = TPdfPositionStripper.Create;
    try
      Stripper.SortByPosition := SortByPosition;
      FPositioned := Stripper.Extract(FModels.Open(Builder));
    finally
      Stripper.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TPdfPositionStripperTests.TestTextEqualsExtractText;
begin
  var Expected: string;
  var Actual: string;

  ExtractBoth(NewBuilder(OneLine), False, Expected, Actual);
  Assert.AreEqual(Expected, Actual, 'one line');

  ExtractBoth(NewTwoPageBuilder(TwoParagraphs, TwoParagraphs), False, Expected, Actual);
  Assert.AreEqual(Expected, Actual, 'two pages with two paragraphs');

  ExtractBoth(NewBuilder('BT /F1 12 Tf 300 700 Td (Zeta) Tj ET BT /F1 12 Tf 100 700 Td (Alpha) Tj 0 -30 Td (Beta) Tj ET'), True, Expected, Actual);
  Assert.AreEqual(Expected, Actual, 'sorted');
end;

procedure TPdfPositionStripperTests.TestSeparatorsHaveNoGlyph;
begin
  Extract(NewBuilder(OneLine));

  const SpaceIndex = FPositioned.Text.IndexOf(' ');

  Assert.AreEqual<Integer>(7, SpaceIndex);
  Assert.AreEqual<Integer>(-1, FPositioned.GlyphOfChar(SpaceIndex));
  for var Index := 0 to SpaceIndex - 1 do
  begin
    Assert.IsTrue(FPositioned.GlyphOfChar(Index) >= 0, Format('character %d has a glyph', [Index]));
  end;
  for var Index := SpaceIndex + 1 to SpaceIndex + 9 do
  begin
    Assert.IsTrue(FPositioned.GlyphOfChar(Index) >= 0, Format('character %d has a glyph', [Index]));
  end;
end;

procedure TPdfPositionStripperTests.TestLigatureMapsTwoCharsToOneGlyph;
begin
  Extract(NewLigatureBuilder('BT /F1 12 Tf 100 700 Td (AB) Tj ET', '2 beginbfchar <41> <FB01> <42> <0042> endbfchar'));

  Assert.IsTrue(FPositioned.Text.StartsWith('fiB'), 'the text starts with fiB');
  Assert.IsTrue(FPositioned.GlyphOfChar(0) >= 0);
  Assert.AreEqual<Integer>(FPositioned.GlyphOfChar(0), FPositioned.GlyphOfChar(1));
  Assert.AreNotEqual<Integer>(FPositioned.GlyphOfChar(1), FPositioned.GlyphOfChar(2));
end;

procedure TPdfPositionStripperTests.TestSortedOutputMapsToRightGlyph;
begin
  Extract(NewBuilder('BT /F1 12 Tf 300 700 Td (Zeta) Tj ET BT /F1 12 Tf 100 700 Td (Alpha) Tj ET'), True);

  Assert.IsTrue(FPositioned.Text.StartsWith('Alpha'), 'the sorted text starts with Alpha');
  const FirstGlyph = FPositioned.Glyphs[FPositioned.GlyphOfChar(0)];
  Assert.AreEqual(Double(100), Double(FirstGlyph.Quad.P1.X), Tolerance);
  for var Glyph in FPositioned.Glyphs do
  begin
    Assert.IsTrue(Glyph.Quad.P1.X >= FirstGlyph.Quad.P1.X - Tolerance, 'no glyph lies left of the first one');
  end;
end;

procedure TPdfPositionStripperTests.TestAllahLigatureTakesTheCharactersOfItsGlyph;
begin
  Extract(NewLigatureBuilder('BT /F1 12 Tf 100 700 Td (AB) Tj ET', '2 beginbfchar <41> <0627> <42> <FDF2> endbfchar'));

  Assert.IsTrue(FPositioned.Text.StartsWith(#$0627#$0644#$0644#$0647), 'the Allah ligature is written as lam lam heh after the alef');
  const AlefGlyph = FPositioned.GlyphOfChar(0);
  const LigatureGlyph = FPositioned.GlyphOfChar(1);
  Assert.IsTrue(AlefGlyph >= 0);
  Assert.AreNotEqual<Integer>(AlefGlyph, LigatureGlyph);
  Assert.AreEqual<Integer>(LigatureGlyph, FPositioned.GlyphOfChar(2));
  Assert.AreEqual<Integer>(LigatureGlyph, FPositioned.GlyphOfChar(3));
  Assert.IsFalse(FModels.HasLogLine('spread evenly'), 'the characters were attributed exactly');
end;

procedure TPdfPositionStripperTests.TestWordThatDoesNotAddUpIsSpreadOverItsGlyphsAndLogged;
begin
  const Builder = NewBuilder('BT /F1 12 Tf 100 700 Td (A) Tj (B) Tj (C) Tj ET');
  try
    const Stripper = TTrailingMarkStripper.Create;
    try
      FPositioned := Stripper.Extract(FModels.Open(Builder));
    finally
      Stripper.Free;
    end;
  finally
    Builder.Free;
  end;

  Assert.IsTrue(FPositioned.Text.StartsWith('ABC!'));
  const FirstGlyph = FPositioned.GlyphOfChar(0);
  const SecondGlyph = FPositioned.GlyphOfChar(2);
  const ThirdGlyph = FPositioned.GlyphOfChar(3);
  Assert.IsTrue(FirstGlyph >= 0);
  Assert.AreNotEqual<Integer>(FirstGlyph, SecondGlyph);
  Assert.AreNotEqual<Integer>(SecondGlyph, ThirdGlyph);
  Assert.AreEqual<Integer>(FirstGlyph, FPositioned.GlyphOfChar(1));
  Assert.IsTrue(FModels.HasLogLine('spread evenly'), 'the debug line is logged');
end;

procedure TPdfPositionStripperTests.TestGlyphWithoutQuadGivesMinusOneAndKeepsText;
begin
  const Content = 'BT /F1 12 Tf 100 700 Td (A) Tj 0 0 0 0 150 700 Tm (B) Tj ET';
  var Expected: string;
  var Actual: string;
  ExtractBoth(NewBuilder(Content), False, Expected, Actual);
  Assert.AreEqual(Expected, Actual, 'the text does not change');

  Extract(NewBuilder(Content));

  const BIndex = FPositioned.Text.IndexOf('B');
  Assert.IsTrue(BIndex > 0, 'the text has the B');
  Assert.IsTrue(FPositioned.GlyphOfChar(0) >= 0);
  Assert.AreEqual<Integer>(-1, FPositioned.GlyphOfChar(BIndex));
end;

procedure TPdfPositionStripperTests.TestLocateActualTextHighlightsAllGlyphsOfTheSequence;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td /Span <</ActualText (XY)>> BDC (AB) Tj EMC ET'));

  Assert.IsTrue(FPositioned.Text.StartsWith('XY'), 'the text is the actual text');
  const Runs = FPositioned.Locate(2, 1);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual('Y', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Length(Runs[0].Quads));
  Assert.AreEqual(Double(100), Double(Runs[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(116.008), Double(Runs[0].Quads[0].P2.X), Tolerance);
end;

procedure TPdfPositionStripperTests.TestLocateSingleWord;
begin
  Extract(NewBuilder(OneLine));

  const Runs = FPositioned.Locate(Pos('2024-0815', FPositioned.Text), 9);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual<Integer>(0, Runs[0].PageIndex);
  Assert.AreEqual('2024-0815', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Length(Runs[0].Quads));
  Assert.AreEqual(Double(144.016), Double(Runs[0].Quads[0].P1.X), Tolerance);
end;

procedure TPdfPositionStripperTests.TestLocateAcrossLinesGivesQuadPerLine;
begin
  Extract(NewBuilder(TwoLines));

  const Start = Pos('one', FPositioned.Text);
  const Finish = Pos('Line two', FPositioned.Text) + Length('Line two');

  const Runs = FPositioned.Locate(Start, Finish - Start);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual<Integer>(2, Length(Runs[0].Quads));
  Assert.IsTrue(Runs[0].Quads[1].P1.Y < Runs[0].Quads[0].P1.Y, 'the second line lies below the first');
end;

procedure TPdfPositionStripperTests.TestLocateAcrossPagesGivesFragmentPerPage;
begin
  Extract(NewTwoPageBuilder('BT /F1 12 Tf 100 700 Td (First page) Tj ET', 'BT /F1 12 Tf 100 700 Td (Second page) Tj ET'));

  const Start = Pos('page', FPositioned.Text);
  const Finish = Pos('Second', FPositioned.Text) + Length('Second');

  const Runs = FPositioned.Locate(Start, Finish - Start);

  Assert.AreEqual<Integer>(2, Length(Runs));
  Assert.AreEqual<Integer>(0, Runs[0].PageIndex);
  Assert.AreEqual('page', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Runs[1].PageIndex);
  Assert.AreEqual('Second', Runs[1].Text);
end;

procedure TPdfPositionStripperTests.TestLocateOnlySeparatorsIsEmpty;
begin
  Extract(NewBuilder(TwoLines));

  const Start = Pos('one', FPositioned.Text) + Length('one');

  const Runs = FPositioned.Locate(Start, 1);

  Assert.AreEqual<Integer>(0, Length(Runs));
end;

procedure TPdfPositionStripperTests.TestLocateOutOfRangeRaises;
begin
  Extract(NewBuilder(OneLine));

  Assert.WillRaise(
    procedure
    begin
      FPositioned.Locate(0, 1);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FPositioned.Locate(1, -1);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FPositioned.Locate(Length(FPositioned.Text), 2);
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfPositionStripperTests.TestPageReferencedTwiceGivesPageIndexOfEachOccurrence;
begin
  Extract(NewTwoPageBuilder('BT /F1 12 Tf 100 700 Td (Same page) Tj ET', 'BT /F1 12 Tf 100 700 Td (Unused) Tj ET', '3 0 R 3 0 R'));

  Assert.AreEqual<Integer>(2, Length(FPositioned.Text.Split(['Same page'], TStringSplitOptions.None)) - 1, 'the page is read twice');
  Assert.AreEqual<Integer>(0, FPositioned.Glyphs[0].PageIndex);
  Assert.AreEqual<Integer>(1, FPositioned.Glyphs[High(FPositioned.Glyphs)].PageIndex);
end;

procedure TPdfPositionStripperTests.TestSpreadingVeryLongWordDoesNotOverflow;
begin
  const Count = 70000;

  const Counts = TProportionalCountsStripper.CountsOf(Count, Count);

  Assert.AreEqual<Integer>(Count, Length(Counts));
  for var Index := 0 to High(Counts) do
  begin
    if Counts[Index] <> 1 then
    begin
      Assert.Fail(Format('position %d got %d characters', [Index, Counts[Index]]));
    end;
  end;
end;

end.
