// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Text.Stripper (pages, articles, actual text and the text positions), Pdf4D.Model.MarkedContent and
// TPDPage.ThreadBeads
unit Pdf4D.Text.Stripper.Collect.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Model.Document,
  Pdf4D.Model.Page,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Text.Stripper,
  Pdf4D.Text.TextPosition;

type
  // Keeps, for each page that was finished, the text of every article: the Unicode of its positions, joined with a bar
  TCollectingStripper = class(TPdfTextStripper)
  private
    FPages: TList<TArray<string>>;
    FStartedPages: Integer;

  protected
    procedure BeginPage(const Page: TPDPage); override;
    procedure FinishPage(const Page: TPDPage); override;

  public
    constructor Create;
    destructor Destroy; override;

    function ArticleText(const PageIndex, ArticleIndex: Integer): string;

    property Pages: TList<TArray<string>> read FPages;
    property StartedPages: Integer read FStartedPages;
  end;

  [TestFixture]
  TStripperCollectTests = class
  private
    FModels: TModelTestDocuments;
    FStripper: TCollectingStripper;

    function PageBody(const Number: Integer; const Extra: string = ''): string;
    // Three pages (objects 10 to 12) that show the letters A, B and C, a font F1 (object 30) and the catalog extra
    function NewThreePageBuilder(const CatalogExtra: string; const Extra: string = ''): TTestPdfBuilder;
    function OpenSinglePage(const Content: string; const Extra: string = ''): TPDDocument;
    function OpenBuilder(const Builder: TTestPdfBuilder): TPDDocument;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOverlappingDuplicateTextIsSuppressed;

    [Test]
    procedure TestPageRange;

    [Test]
    procedure TestBookmarkRange;

    [Test]
    procedure TestBookmarkPointingNowhereTwiceGivesNoText;

    [Test]
    procedure TestEndBookmarkToPageOutsideTheTreeGivesNoText;

    [Test]
    procedure TestBeadsSplitArticles;

    [Test]
    procedure TestNoBeadsSeparationPutsEverythingInArticleZero;

    [Test]
    procedure TestNullBeadEntryKeepsItsPlace;

    [Test]
    procedure TestActualTextReplacesGlyphs;

    [Test]
    procedure TestSoftHyphenRemovedFromActualText;

    [Test]
    procedure TestActualTextEndsAtEndOfSequence;

    [Test]
    procedure TestNestedSequenceWithoutActualTextEndsTheOuterOne;

    [Test]
    procedure TestDefaults;

    [Test]
    procedure TestAddMoreFormattingSetsTheSeparators;

    [Test]
    procedure TestFloatMaskIsRestored;

    [Test]
    procedure TestStripperCanRunAgain;
  end;

implementation

uses
  Pdf4D.Model.Outline,
  Pdf4D.Model.OutlineItem,
  Pdf4D.Tests.TextDocuments;

const
  ShowA = 'BT /F1 12 Tf 100 700 Td (A) Tj ET';
  ShowFont = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';

{ TCollectingStripper }

constructor TCollectingStripper.Create;
begin
  inherited Create;
  FPages := TList<TArray<string>>.Create;
end;

destructor TCollectingStripper.Destroy;
begin
  FPages.Free;
  inherited;
end;

procedure TCollectingStripper.BeginPage(const Page: TPDPage);
begin
  Inc(FStartedPages);
end;

procedure TCollectingStripper.FinishPage(const Page: TPDPage);
begin
  var Articles: TArray<string>;
  SetLength(Articles, CharactersByArticle.Count);
  for var Index := 0 to CharactersByArticle.Count - 1 do
  begin
    var Joined := '';
    for var Position in CharactersByArticle[Index] do
    begin
      if Joined <> '' then
      begin
        Joined := Joined + '|';
      end;
      Joined := Joined + Position.Unicode;
    end;
    Articles[Index] := Joined;
  end;
  FPages.Add(Articles);
end;

function TCollectingStripper.ArticleText(const PageIndex, ArticleIndex: Integer): string;
begin
  Result := FPages[PageIndex][ArticleIndex];
end;

{ TStripperCollectTests }

procedure TStripperCollectTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FStripper := TCollectingStripper.Create;
end;

procedure TStripperCollectTests.TearDown;
begin
  FStripper.Free;
  FModels.Free;
end;

function TStripperCollectTests.PageBody(const Number: Integer; const Extra: string): string;
begin
  Result := Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R ' +
                   '/Resources << /Font << /F1 30 0 R >> >> %s >>', [Number, Extra]);
end;

function TStripperCollectTests.NewThreePageBuilder(const CatalogExtra: string; const Extra: string): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilderWithPages(3, CatalogExtra);
  try
    const Letters = 'ABC';
    for var Index := 0 to 2 do
    begin
      Result.AddObject(10 + Index, PageBody(20 + Index, Extra));
      Result.AddStreamObject(20 + Index, '', TEncoding.ASCII.GetBytes(Format('BT /F1 12 Tf 100 700 Td (%s) Tj ET', [Letters[Index + 1]])));
    end;
    Result.AddObject(30, ShowFont);
  except
    Result.Free;
    raise;
  end;
end;

function TStripperCollectTests.OpenBuilder(const Builder: TTestPdfBuilder): TPDDocument;
begin
  try
    Result := FModels.Open(Builder);
  finally
    Builder.Free;
  end;
end;

function TStripperCollectTests.OpenSinglePage(const Content: string; const Extra: string): TPDDocument;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '');
  try
    Builder.AddObject(10, PageBody(20, Extra));
    Builder.AddStreamObject(20, '', TEncoding.ASCII.GetBytes(Content));
    Builder.AddObject(30, ShowFont);
    Result := FModels.Open(Builder);
  finally
    Builder.Free;
  end;
end;

procedure TStripperCollectTests.TestOverlappingDuplicateTextIsSuppressed;
begin
  const Content = ShowA + ' ' + ShowA;
  FStripper.GetText(OpenSinglePage(Content));
  Assert.AreEqual('A', FStripper.ArticleText(0, 0));

  FStripper.SuppressDuplicateOverlappingText := False;
  FStripper.GetText(FModels.Document);
  Assert.AreEqual('A|A', FStripper.ArticleText(1, 0));
end;

procedure TStripperCollectTests.TestPageRange;
begin
  FStripper.StartPage := 2;
  FStripper.EndPage := 2;
  FStripper.GetText(OpenBuilder(NewThreePageBuilder('')));

  Assert.AreEqual<Integer>(1, FStripper.StartedPages);
  Assert.AreEqual<Integer>(1, FStripper.Pages.Count);
  Assert.AreEqual('B', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestBookmarkRange;
begin
  const Builder = NewThreePageBuilder('/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 4 0 R /Count 1 >>');
    Builder.AddObject(4, '<< /Title (Second) /Parent 3 0 R /Dest [11 0 R /Fit] >>');
    const Document = FModels.Open(Builder);
    var Outline: TPDDocumentOutline;
    var Item: TPDOutlineItem;
    Assert.IsTrue(Document.Catalog.TryGetOutline(Outline));
    Assert.IsTrue(Outline.TryGetFirstChild(Item));

    FStripper.StartBookmark := Item;
    FStripper.GetText(Document);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(2, FStripper.Pages.Count);
  Assert.AreEqual('B', FStripper.ArticleText(0, 0));
  Assert.AreEqual('C', FStripper.ArticleText(1, 0));
end;

procedure TStripperCollectTests.TestBookmarkPointingNowhereTwiceGivesNoText;
begin
  const Builder = NewThreePageBuilder('/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 4 0 R /Count 1 >>');
    Builder.AddObject(4, '<< /Title (Nowhere) /Parent 3 0 R >>');
    const Document = FModels.Open(Builder);
    var Outline: TPDDocumentOutline;
    var Item: TPDOutlineItem;
    Assert.IsTrue(Document.Catalog.TryGetOutline(Outline));
    Assert.IsTrue(Outline.TryGetFirstChild(Item));

    FStripper.StartBookmark := Item;
    FStripper.EndBookmark := Item;
    FStripper.GetText(Document);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(0, FStripper.Pages.Count);
end;

procedure TStripperCollectTests.TestEndBookmarkToPageOutsideTheTreeGivesNoText;
begin
  // PDPageTree.indexOf gives -1 for a page that is not in the tree, so the end page number is 0 and no page is selected
  const Builder = NewThreePageBuilder('/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 4 0 R /Count 1 >>');
    Builder.AddObject(4, '<< /Title (Elsewhere) /Parent 3 0 R /Dest [5 0 R /Fit] >>');
    Builder.AddObject(5, '<< /Type /Page >>');
    const Document = FModels.Open(Builder);
    var Outline: TPDDocumentOutline;
    var Item: TPDOutlineItem;
    Assert.IsTrue(Document.Catalog.TryGetOutline(Outline));
    Assert.IsTrue(Outline.TryGetFirstChild(Item));

    FStripper.EndBookmark := Item;
    FStripper.GetText(Document);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(0, FStripper.Pages.Count);
end;

procedure TStripperCollectTests.TestBeadsSplitArticles;
begin
  const Content = 'BT /F1 12 Tf 100 700 Td (T) Tj ET BT /F1 12 Tf 100 100 Td (U) Tj ET';
  FStripper.GetText(OpenSinglePage(Content, '/B [<< /R [0 400 612 792] >>]'));

  // One bead gives three articles: before the bead, in the bead and after it. The text at y = 700 lies in the bead
  // (the y of a position counts from the top of the page), the text at y = 100 below it, which is the last article.
  Assert.AreEqual<Integer>(3, Length(FStripper.Pages[0]));
  Assert.AreEqual('', FStripper.ArticleText(0, 0));
  Assert.AreEqual('T', FStripper.ArticleText(0, 1));
  Assert.AreEqual('U', FStripper.ArticleText(0, 2));
end;

procedure TStripperCollectTests.TestNoBeadsSeparationPutsEverythingInArticleZero;
begin
  const Content = 'BT /F1 12 Tf 100 700 Td (T) Tj ET BT /F1 12 Tf 100 100 Td (U) Tj ET';
  FStripper.ShouldSeparateByBeads := False;
  FStripper.GetText(OpenSinglePage(Content, '/B [<< /R [0 400 612 792] >>]'));

  Assert.AreEqual<Integer>(1, Length(FStripper.Pages[0]));
  Assert.AreEqual('T|U', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestNullBeadEntryKeepsItsPlace;
begin
  const Content = 'BT /F1 12 Tf 100 700 Td (T) Tj ET';
  const Document = OpenSinglePage(Content, '/B [null << /R [0 400 612 792] >>]');
  const Beads = Document.Pages.Get(0).ThreadBeads;
  Assert.AreEqual<Integer>(2, Length(Beads));
  Assert.IsFalse(Beads[0].HasRectangle);
  Assert.IsTrue(Beads[1].HasRectangle);
  Assert.AreEqual<Single>(400, Beads[1].Rectangle.LowerLeftY);

  // The entry without rectangle sends every character to article 0
  FStripper.GetText(Document);
  Assert.AreEqual<Integer>(5, Length(FStripper.Pages[0]));
  Assert.AreEqual('T', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestActualTextReplacesGlyphs;
begin
  FStripper.GetText(OpenSinglePage('/Span << /ActualText (fi) >> BDC BT /F1 12 Tf (XY) Tj ET EMC'));

  // The first glyph takes the text, the others are emptied
  Assert.AreEqual('fi|', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestSoftHyphenRemovedFromActualText;
begin
  FStripper.GetText(OpenSinglePage('/Span << /ActualText <FEFF0063006F00AD006F0070> >> BDC BT /F1 12 Tf (XY) Tj ET EMC'));

  // The string is UTF-16 with a soft hyphen (U+00AD) in the middle
  Assert.AreEqual('coop|', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestActualTextEndsAtEndOfSequence;
begin
  FStripper.GetText(OpenSinglePage('/Span << /ActualText (fi) >> BDC BT /F1 12 Tf (X) Tj ET EMC BT /F1 12 Tf 100 600 Td (Z) Tj ET'));

  Assert.AreEqual('fi|Z', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestNestedSequenceWithoutActualTextEndsTheOuterOne;
begin
  // PDFBox keeps one actual text, so the inner sequence ends the actual text of the outer one
  FStripper.GetText(OpenSinglePage('/Span << /ActualText (fi) >> BDC /Span << /MCID 1 >> BDC BT /F1 12 Tf (X) Tj ET EMC EMC'));

  Assert.AreEqual('X', FStripper.ArticleText(0, 0));
end;

procedure TStripperCollectTests.TestDefaults;
begin
  Assert.AreEqual<Integer>(1, FStripper.StartPage);
  Assert.AreEqual<Integer>(MaxInt, FStripper.EndPage);
  Assert.IsFalse(FStripper.SortByPosition);
  Assert.IsTrue(FStripper.ShouldSeparateByBeads);
  Assert.IsTrue(FStripper.SuppressDuplicateOverlappingText);
  Assert.IsFalse(FStripper.AddMoreFormatting);
  Assert.IsFalse(FStripper.IgnoreContentStreamSpaceGlyphs);
  Assert.AreEqual(sLineBreak, FStripper.LineSeparator);
  Assert.AreEqual(' ', FStripper.WordSeparator);
  Assert.AreEqual('', FStripper.ParagraphStart);
  Assert.AreEqual('', FStripper.ParagraphEnd);
  Assert.AreEqual('', FStripper.PageStart);
  Assert.AreEqual(sLineBreak, FStripper.PageEnd);
  Assert.AreEqual('', FStripper.ArticleStart);
  Assert.AreEqual('', FStripper.ArticleEnd);
  Assert.AreEqual<Single>(0.5, FStripper.SpacingTolerance);
  Assert.AreEqual<Single>(0.3, FStripper.AverageCharTolerance);
  Assert.AreEqual<Single>(2.0, FStripper.IndentThreshold);
  Assert.AreEqual<Single>(2.5, FStripper.DropThreshold);
end;

procedure TStripperCollectTests.TestAddMoreFormattingSetsTheSeparators;
begin
  FStripper.AddMoreFormatting := True;
  FStripper.LineSeparator := '#';
  FStripper.GetText(OpenSinglePage(ShowA));

  Assert.AreEqual('#', FStripper.ParagraphEnd);
  Assert.AreEqual('#', FStripper.PageStart);
  Assert.AreEqual('#', FStripper.ArticleStart);
  Assert.AreEqual('#', FStripper.ArticleEnd);
end;

procedure TStripperCollectTests.TestFloatMaskIsRestored;
begin
  const Before = GetExceptionMask;
  FStripper.GetText(OpenBuilder(NewThreePageBuilder('')));
  Assert.IsTrue(Before = GetExceptionMask);
end;

procedure TStripperCollectTests.TestStripperCanRunAgain;
begin
  const Document = OpenBuilder(NewThreePageBuilder(''));
  FStripper.GetText(Document);
  FStripper.GetText(Document);

  Assert.AreEqual<Integer>(6, FStripper.Pages.Count);
  Assert.AreEqual('A', FStripper.ArticleText(3, 0));
  Assert.AreEqual('C', FStripper.ArticleText(5, 0));
end;

end.
