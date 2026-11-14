// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Text.Stripper (lines, words, paragraphs, separators, list item patterns and normalisation). The expected
// texts were confirmed with the PDFBox 3.0.8 oracle.
unit Pdf4D.Text.Stripper.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
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
  end;

implementation

uses
  Pdf4D.Tests.TextDocuments;

const
  Content = 'BT /F1 12 Tf 100 700 Td (Hello) Tj ( World) Tj ET';

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


end.
