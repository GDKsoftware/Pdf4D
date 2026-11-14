// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Text.Stripper (lines, words, paragraphs, separators, list item patterns and normalisation). The expected
// texts were confirmed with the PDFBox 3.0.8 oracle.
unit Pdf4D.Text.Stripper.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Model.Document,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Text.Stripper;

type
  [TestFixture]
  TStripperTextTests = class
  private
    FModels: TModelTestDocuments;
    FStripper: TPdfTextStripper;

    function ToUnicodeBuilder(const Content, Mappings: string): TTestPdfBuilder;
    function Extract(const Builder: TTestPdfBuilder): string;
    function ExtractContent(const Content: string): string;
    // The separators that tools/oracle gives PDFBox for its separator section, so that the oracle text can be used as it is
    procedure UseOracleSeparators;
    // A page with a letter at each of Count scattered positions, from a fixed random sequence
    class function ScatteredContent(const Count, Seed, YSpan: Integer): string; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSingleLine;

    [Test]
    procedure TestWordSeparatorInsertedForGap;

    [Test]
    procedure TestNoSeparatorForSmallGap;

    [Test]
    procedure TestNewLineForLowerBaseline;

    [Test]
    procedure TestSortByPosition;

    [Test]
    procedure TestLigatureIsDecomposed;

    [Test]
    procedure TestArabicPresentationFormNormalized;

    [Test]
    procedure TestCustomSeparators;

    [Test]
    procedure TestAddMoreFormatting;

    [Test]
    procedure TestRtlTextStaysInFileOrder;

    [Test]
    procedure TestListItemPatterns;

    [Test]
    procedure TestIgnoreContentStreamSpaceGlyphs;

    [Test]
    procedure TestParagraphSeparatedByLargeGap;

    [Test]
    procedure TestPageWithoutTextWritesOnlyPageEnd;

    [Test]
    procedure TestHangingIndentStaysInOneParagraph;

    [Test]
    procedure TestIndentAfterAHangingLineStartsAParagraph;

    [Test]
    procedure TestLeftOfThePreviousLineStartsAParagraph;

    [Test]
    procedure TestRepeatedListItemFormatStartsAParagraph;

    [Test]
    procedure TestDifferentListItemFormatsStayInOneParagraph;

    [Test]
    procedure TestLigatureAllahAfterAlefGetsLamLamHeh;

    [Test]
    procedure TestLigatureAllahAloneIsDecomposedAndReversed;

    [Test]
    procedure TestHebrewPresentationFormIsReversed;

    [Test]
    procedure TestArabicPresentationFormBIsReversed;

    [Test]
    procedure TestSortedModeMergesLikePdfBox;

    [Test]
    procedure TestInconsistentComparisonFallsBackToMergeSort;

    [Test]
    procedure TestManyScatteredGlyphsFinishInTime;
  end;

implementation

uses
  Pdf4D.Tests.TextDocuments;

const
  Content = 'BT /F1 12 Tf 100 700 Td (Hello) Tj ( World) Tj ET';
  RandomMultiplier = 1103515245;
  RandomIncrement = 12345;
  RandomMask = $7FFFFFFF;
  ScatteredLetterCount = 200;
  HostileGlyphCount = 200000;
  MaxSecondsForHostileInput = 30;
  ScatteredSeed = 94;
  ScatteredYSpan = 20;
  HostileYSpan = 700;
  ShowOneGlyph = 'BT /F1 12 Tf 1 0 0 1 100 700 Tm (A) Tj ET';
  // Lines with one left edge, the second and third shifted to the right by the indent of 30
  FirstLine = '1 0 0 1 100 700 Tm (First) Tj';
  SecondLineIndented = '1 0 0 1 130 686 Tm (second) Tj';
  ThirdLineIndented = '1 0 0 1 130 672 Tm (third) Tj';
  // From the PDFBox 3.0.8 oracle for the text of ScatteredContent: the JDK reports the comparison as inconsistent, so PDFBox
  // sorts the letters again with its own merge sort
  ScatteredSortedText =
  'zg t v'#10 +
  'g wu krykegat o s a w h'#10 +
  'bax slaf swyyzxy hi p nz ex omgj v k x'#10 +
  'an h y f nrs io nr gu h d'#10 +
  'z of'#10 +
  'r p'#10 +
  'n b'#10 +
  'm cg e'#10 +
  'p p y da crj g'#10 +
  'm no v un'#10 +
  't v'#10 +
  'gd n j v e po mr x i z r'#10 +
  'q e q'#10 +
  'j'#10 +
  'bzfa ev k r y c t w'#10 +
  'z f'#10 +
  'z n lgr b fq p l jp h r dk vb wxh dl v oz k'#10 +
  's b s kv on b kf d fntzi'#10 +
  'yp'#10 +
  'ug r'#10 +
  'w f h youzf v p'#10 +
  'z x yv o u g x i q lei u mjpa'#10;

{ TStripperTextTests }

procedure TStripperTextTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FStripper := TPdfTextStripper.Create;
  FStripper.LineSeparator := #10;
  FStripper.PageEnd := #10;
end;

procedure TStripperTextTests.TearDown;
begin
  FStripper.Free;
  FModels.Free;
end;

function TStripperTextTests.Extract(const Builder: TTestPdfBuilder): string;
begin
  try
    Result := FStripper.GetText(FModels.Open(Builder));
  finally
    Builder.Free;
  end;
end;

function TStripperTextTests.ExtractContent(const Content: string): string;
begin
  Result := Extract(TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, Content));
end;

procedure TStripperTextTests.UseOracleSeparators;
begin
  FStripper.LineSeparator := '<EOL>'#10;
  FStripper.WordSeparator := '<W>';
  FStripper.ParagraphStart := '<P>';
  FStripper.ParagraphEnd := '</P>';
  FStripper.PageStart := '<PAGE>';
  FStripper.PageEnd := '</PAGE>'#10;
  FStripper.ArticleStart := '<A>';
  FStripper.ArticleEnd := '</A>';
end;

class function TStripperTextTests.ScatteredContent(const Count, Seed, YSpan: Integer): string;
begin
  var State := Int64(Seed);
  const Builder = TStringBuilder.Create('BT /F1 12 Tf');
  try
    for var Index := 1 to Count do
    begin
      State := (State * RandomMultiplier + RandomIncrement) and RandomMask;
      const Letter = Char(Ord('a') + (State shr 8) mod 26);
      State := (State * RandomMultiplier + RandomIncrement) and RandomMask;
      const X = 30 + (State shr 8) mod 500;
      State := (State * RandomMultiplier + RandomIncrement) and RandomMask;
      const Y = 50 + (State shr 8) mod YSpan;
      Builder.AppendFormat(' 1 0 0 1 %d %d Tm (%s) Tj', [X, Y, Letter]);
    end;
    Builder.Append(' ET');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TStripperTextTests.ToUnicodeBuilder(const Content, Mappings: string): TTestPdfBuilder;
begin
  const CMap = 'begincmap 1 begincodespacerange <00> <FF> endcodespacerange ' +
               Format('%s endcmap', [Mappings]);
  Result := TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 20 0 R >>', Content);
  try
    Result.AddStreamObject(20, '', TEncoding.ASCII.GetBytes(CMap));
  except
    Result.Free;
    raise;
  end;
end;

procedure TStripperTextTests.TestSingleLine;
begin
  Assert.AreEqual('Hello World'#10, ExtractContent(Content));
end;

procedure TStripperTextTests.TestWordSeparatorInsertedForGap;
begin
  Assert.AreEqual('Hello World'#10,
                  ExtractContent('BT /F1 12 Tf 1 0 0 1 100 700 Tm (Hello) Tj 1 0 0 1 137.4 700 Tm (World) Tj ET'));
end;

procedure TStripperTextTests.TestNoSeparatorForSmallGap;
begin
  Assert.AreEqual('HelloWorld'#10,
                  ExtractContent('BT /F1 12 Tf 1 0 0 1 100 700 Tm (Hello) Tj 1 0 0 1 127.8 700 Tm (World) Tj ET'));
end;

procedure TStripperTextTests.TestNewLineForLowerBaseline;
begin
  Assert.AreEqual('A'#10'B'#10, ExtractContent('BT /F1 12 Tf 100 700 Td (A) Tj 0 -20 Td (B) Tj ET'));
end;

procedure TStripperTextTests.TestSortByPosition;
begin
  const Drawing = 'BT /F1 12 Tf 100 700 Td (B) Tj ET BT /F1 12 Tf 100 720 Td (A) Tj ET';
  Assert.AreEqual('B'#10'A'#10, ExtractContent(Drawing));

  FStripper.SortByPosition := True;
  Assert.AreEqual('A'#10'B'#10, ExtractContent(Drawing));
end;

procedure TStripperTextTests.TestLigatureIsDecomposed;
begin
  Assert.AreEqual('fi'#10, Extract(ToUnicodeBuilder('BT /F1 12 Tf 100 700 Td (A) Tj ET', '1 beginbfchar <41> <FB01> endbfchar')));
end;

procedure TStripperTextTests.TestArabicPresentationFormNormalized;
begin
  Assert.AreEqual(#$0644#10, Extract(ToUnicodeBuilder('BT /F1 12 Tf 100 700 Td (A) Tj ET', '1 beginbfchar <41> <FEDF> endbfchar')));
end;

procedure TStripperTextTests.TestCustomSeparators;
begin
  FStripper.LineSeparator := '<EOL>'#10;
  FStripper.WordSeparator := '<W>';
  FStripper.ParagraphStart := '<P>';
  FStripper.ParagraphEnd := '</P>';
  FStripper.PageStart := '<PAGE>';
  FStripper.PageEnd := '</PAGE>'#10;
  FStripper.ArticleStart := '<A>';
  FStripper.ArticleEnd := '</A>';

  // Two words on the first line, then a paragraph that starts after a gap of two lines
  const Drawing = 'BT /F1 12 Tf 1 0 0 1 100 700 Tm (Hello) Tj 1 0 0 1 137.4 700 Tm (World) Tj 1 0 0 1 100 660 Tm (Next) Tj ET';
  Assert.AreEqual('<PAGE><A><P>Hello<W>World<EOL>'#10'</P><P>Next</P></A></PAGE>'#10, ExtractContent(Drawing));
end;

procedure TStripperTextTests.TestAddMoreFormatting;
begin
  FStripper.AddMoreFormatting := True;
  // The page start, article start, paragraph end and article end become the line separator
  Assert.AreEqual(#10#10'Hello World'#10#10#10, ExtractContent(Content));
end;

procedure TStripperTextTests.TestRtlTextStaysInFileOrder;
begin
  // PDFBox runs bidi and gives U+05D1 U+05D0 here. Pdf4D keeps the order of the file.
  Assert.AreEqual(#$05D0#$05D1#10,
                  Extract(ToUnicodeBuilder('BT /F1 12 Tf 100 700 Td (AB) Tj ET', '2 beginbfchar <41> <05D0> <42> <05D1> endbfchar')));
end;

procedure TStripperTextTests.TestListItemPatterns;
begin
  Assert.IsTrue(TListItemPatterns.Matches('1.'));
  Assert.IsTrue(TListItemPatterns.Matches('[12]'));
  Assert.IsTrue(TListItemPatterns.Matches('iv.'));
  Assert.IsTrue(TListItemPatterns.Matches('A)'));
  Assert.IsTrue(TListItemPatterns.Matches('.'));
  Assert.IsTrue(TListItemPatterns.Matches('12)'));
  Assert.IsTrue(TListItemPatterns.Matches('XL.'));

  Assert.IsFalse(TListItemPatterns.Matches('1.2.'));
  Assert.IsFalse(TListItemPatterns.Matches('x'));
  Assert.IsFalse(TListItemPatterns.Matches(''));
  Assert.IsFalse(TListItemPatterns.Matches('[]'));
  Assert.IsFalse(TListItemPatterns.Matches('[1'));
  Assert.IsFalse(TListItemPatterns.Matches('AB.'));
  Assert.IsFalse(TListItemPatterns.Matches('a1)'));
end;

procedure TStripperTextTests.TestIgnoreContentStreamSpaceGlyphs;
begin
  FStripper.IgnoreContentStreamSpaceGlyphs := True;
  // The space of the content stream is dropped, and the gap that is left is wide enough for one of its own
  Assert.AreEqual('Hello World'#10, ExtractContent(Content));
end;

procedure TStripperTextTests.TestParagraphSeparatedByLargeGap;
begin
  FStripper.ParagraphStart := '<P>';
  FStripper.ParagraphEnd := '</P>';
  Assert.AreEqual('<P>A'#10'</P><P>B</P>'#10, ExtractContent('BT /F1 12 Tf 100 700 Td (A) Tj 0 -40 Td (B) Tj ET'));
end;

procedure TStripperTextTests.TestPageWithoutTextWritesOnlyPageEnd;
begin
  Assert.AreEqual(#10, ExtractContent('q Q'));
end;

procedure TStripperTextTests.TestHangingIndentStaysInOneParagraph;
begin
  UseOracleSeparators;
  // The text is the output of the PDFBox 3.0.8 oracle for the same lines
  Assert.AreEqual('<PAGE><A><P>First<EOL>'#10'second<EOL>'#10'third</P></A></PAGE>'#10,
                  ExtractContent('BT /F1 12 Tf ' + FirstLine + ' ' + SecondLineIndented + ' ' + ThirdLineIndented + ' ET'));
end;

procedure TStripperTextTests.TestIndentAfterAHangingLineStartsAParagraph;
begin
  UseOracleSeparators;
  // The third line is indented again, and the second is not the start of a paragraph: a new paragraph
  Assert.AreEqual('<PAGE><A><P>First<EOL>'#10'second<EOL>'#10'</P><P>third</P></A></PAGE>'#10,
                  ExtractContent('BT /F1 12 Tf ' + FirstLine + ' ' + SecondLineIndented + ' 1 0 0 1 160 672 Tm (third) Tj ET'));
end;

procedure TStripperTextTests.TestLeftOfThePreviousLineStartsAParagraph;
begin
  UseOracleSeparators;
  Assert.AreEqual('<PAGE><A><P>First<EOL>'#10'second<EOL>'#10'</P><P>third</P></A></PAGE>'#10,
                  ExtractContent('BT /F1 12 Tf ' + FirstLine + ' ' + SecondLineIndented + ' 1 0 0 1 100 672 Tm (third) Tj ET'));
end;

procedure TStripperTextTests.TestRepeatedListItemFormatStartsAParagraph;
begin
  UseOracleSeparators;
  // The glyph A shows "1.", so both lines start with a list item of the format number and a dot
  const Builder = ToUnicodeBuilder('BT /F1 12 Tf 1 0 0 1 100 700 Tm (A) Tj (x) Tj 1 0 0 1 100 686 Tm (A) Tj (y) Tj ET',
                                   '1 beginbfchar <41> <0031002E> endbfchar');
  Assert.AreEqual('<PAGE><A><P>1.x<EOL>'#10'</P><P>1.y</P></A></PAGE>'#10, Extract(Builder));
end;

procedure TStripperTextTests.TestDifferentListItemFormatsStayInOneParagraph;
begin
  UseOracleSeparators;
  // "1." and "a." are two formats
  const Builder = ToUnicodeBuilder('BT /F1 12 Tf 1 0 0 1 100 700 Tm (A) Tj (x) Tj 1 0 0 1 100 686 Tm (B) Tj (y) Tj ET',
                                   '2 beginbfchar <41> <0031002E> <42> <0061002E> endbfchar');
  Assert.AreEqual('<PAGE><A><P>1.x<EOL>'#10'a.y</P></A></PAGE>'#10, Extract(Builder));
end;

procedure TStripperTextTests.TestLigatureAllahAfterAlefGetsLamLamHeh;
begin
  // The oracle gives U+0647 U+0644 U+0644 U+0627: PDFBox runs bidi over the word and reverses it, Pdf4D keeps the file order
  Assert.AreEqual(#$0627#$0644#$0644#$0647#10,
                  Extract(ToUnicodeBuilder('BT /F1 12 Tf 1 0 0 1 100 700 Tm (AB) Tj ET', '2 beginbfchar <41> <0627> <42> <FDF2> endbfchar')));
end;

procedure TStripperTextTests.TestLigatureAllahAloneIsDecomposedAndReversed;
begin
  // The oracle gives U+0627 U+0644 U+0644 U+0647. Pdf4D reverses the decomposed form as PDFBox does before its bidi pass,
  // and has no bidi pass.
  Assert.AreEqual(#$0647#$0644#$0644#$0627#10,
                  Extract(ToUnicodeBuilder('BT /F1 12 Tf 1 0 0 1 100 700 Tm (B) Tj ET', '1 beginbfchar <42> <FDF2> endbfchar')));
end;

procedure TStripperTextTests.TestHebrewPresentationFormIsReversed;
begin
  // U+FB2A is U+05E9 U+05C1 in NFKC, and the oracle gives that order after its bidi pass
  Assert.AreEqual(#$05C1#$05E9#10, Extract(ToUnicodeBuilder(ShowOneGlyph, '1 beginbfchar <41> <FB2A> endbfchar')));
end;

procedure TStripperTextTests.TestArabicPresentationFormBIsReversed;
begin
  // U+FEF5 is U+0644 U+0622 in NFKC, and the oracle gives that order after its bidi pass
  Assert.AreEqual(#$0622#$0644#10, Extract(ToUnicodeBuilder(ShowOneGlyph, '1 beginbfchar <41> <FEF5> endbfchar')));
end;

procedure TStripperTextTests.TestSortedModeMergesLikePdfBox;
begin
  FStripper.SortByPosition := True;
  // More than 32 glyphs, so the sort merges runs. The text is the sorted section of the oracle.
  const Drawing = 'BT /F1 12 Tf 1 0 0 1 100 660 Tm (Third line of the text) Tj 1 0 0 1 100 700 Tm (First line of the text) Tj ' +
                  '1 0 0 1 100 680 Tm (Second line of the text) Tj 1 0 0 1 250 700 Tm (and more) Tj ET';
  Assert.AreEqual('First line of the text and more'#10'Second line of the text'#10'Third line of the text'#10, ExtractContent(Drawing));
end;

procedure TStripperTextTests.TestInconsistentComparisonFallsBackToMergeSort;
begin
  FStripper.SortByPosition := True;
  // The JDK reports that the comparison of these 200 letters is inconsistent, and PDFBox sorts them again with its merge sort
  Assert.AreEqual(ScatteredSortedText, ExtractContent(ScatteredContent(ScatteredLetterCount, ScatteredSeed, ScatteredYSpan)));
end;

procedure TStripperTextTests.TestManyScatteredGlyphsFinishInTime;
begin
  // The letters are shown at 200,000 places of one page, so the map of the shown characters fills up with entries
  const Content = ScatteredContent(HostileGlyphCount, ScatteredSeed, HostileYSpan);
  const Watch = TStopwatch.StartNew;

  const Text = ExtractContent(Content);

  Assert.IsTrue(Text.Length > HostileGlyphCount div 2, 'The text of the page is written');
  Assert.IsTrue(Watch.Elapsed.TotalSeconds < MaxSecondsForHostileInput, Format('Took %.1f seconds', [Watch.Elapsed.TotalSeconds]));
end;

end.
