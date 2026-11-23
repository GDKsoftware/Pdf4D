// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PageText.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText;

type
  [TestFixture]
  TPdfPageTextTests = class
  private
    FStreams: TObjectList<TStream>;

    function LoadDocument(const Data: TBytes): IPdfDocument;
    function InvoiceText: IPdfPageText;
    // The index of the Occurrence-th (from 0) word with this text
    function IndexOfWord(const PageText: IPdfPageText; const Text: string; const Occurrence: Integer = 0): Integer;
    function WordTextAt(const PageText: IPdfPageText; const X, Y: Single): string;
    function SegmentTextAt(const PageText: IPdfPageText; const X, Y: Single): string;
    procedure AssertEmptyFindsNothing(const PageText: IPdfPageText);
    procedure AssertWorksAfterDocumentIsGone(const PageText: IPdfPageText);
    function MakeTextAfterDocumentIsReleased: IPdfPageText;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFindSegmentOnSameLine;
    [Test]
    procedure TestColonSplitsSegments;
    [Test]
    procedure TestPointBesideTextFindsNothing;
    [Test]
    procedure TestNearestWordOutsideText;
    [Test]
    procedure TestSelectAcrossWordsOnOneLine;
    [Test]
    procedure TestSelectAcrossLines;
    [Test]
    procedure TestSelectIsOrderIndependent;
    [Test]
    procedure TestSelectOutOfRangeRaises;
    [Test]
    procedure TestLinkAtPoint;
    [Test]
    procedure TestEmptyPageTextFindsNothing;
    [Test]
    procedure TestScannedPageIsEmpty;
    [Test]
    procedure TestSnapshotOutlivesDocument;
    [Test]
    procedure TestHitTestIsFastOnDensePage;
    [Test]
    procedure TestBuildIsFastWithManyWordsOnOneLine;
    [Test]
    procedure TestCollapsedWordHoldsNoPoint;
    [Test]
    procedure TestLastOverlappingLinkWins;
    [Test]
    procedure TestSelectionQuadsAreIndependentOfOrder;
  end;

implementation

uses
  System.Diagnostics,
  System.Math,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Quad,
  Pdf4D.Tests.ViewerDocuments;

const
  DenseLines = 100;
  DenseWordsPerLine = 50;
  DenseWordWidth = 10;
  DensePitch = 12;
  DenseWordLength = 5;
  DenseQueryCount = 1000;
  DenseSeed = 4242;
  DenseBudgetMilliseconds = 200;
  LongLineWords = 100000;
  LongLineBudgetMilliseconds = 1000;
  NoWord: Integer = -1;
  NoLayoutAsked = 'The page text must not ask the layout';

type
  TFakeTextLayout = class(TInterfacedObject, IPdfTextLayout)
  private
    FWords: TArray<TPdfTextFragment>;
    FLines: TArray<TPdfTextFragment>;

    class function BuildFragment(const Left, Bottom, Right, Top: Single; const Start, Length: Integer): TPdfTextFragment; static;

  public
    constructor CreateDense;
    // One line of WordCount words, each 1 wide at a pitch of 2
    constructor CreateLongLine(const WordCount: Integer);
    // One line of three words: a word that has collapsed to a point at x 5, then real words at 10..20 and 30..40
    constructor CreateCollapsedWord;

    function PageIndex: Integer;
    function Text: string;
    function Words: TArray<TPdfTextFragment>;
    function Segments: TArray<TPdfTextFragment>;
    function Lines: TArray<TPdfTextFragment>;
    function TryFindSegmentAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
    function TryFindWordAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
  end;

{ TFakeTextLayout }

class function TFakeTextLayout.BuildFragment(const Left, Bottom, Right, Top: Single; const Start, Length: Integer): TPdfTextFragment;
begin
  Result.PageIndex := 0;
  Result.Text := Format('w%d', [Start]);
  Result.Quads := [TPdfQuad.Create(TPointF.Create(Left, Bottom), TPointF.Create(Right, Bottom),
                                   TPointF.Create(Right, Top), TPointF.Create(Left, Top))];
  Result.Start := Start;
  Result.Length := Length;
end;

constructor TFakeTextLayout.CreateDense;
begin
  inherited Create;

  const WordSpan = DenseWordLength + 1;
  const LineSpan = DenseWordsPerLine * WordSpan;
  for var LineIndex := 0 to DenseLines - 1 do
  begin
    const Bottom = LineIndex * DensePitch;
    const LineStart = 1 + (LineIndex * LineSpan);
    FLines := FLines + [BuildFragment(0, Bottom, DenseWordsPerLine * DensePitch, Bottom + DenseWordWidth, LineStart, LineSpan - 1)];

    for var Column := 0 to DenseWordsPerLine - 1 do
    begin
      const Left = Column * DensePitch;
      const WordStart = LineStart + (Column * WordSpan);
      FWords := FWords + [BuildFragment(Left, Bottom, Left + DenseWordWidth, Bottom + DenseWordWidth, WordStart, DenseWordLength)];
    end;
  end;
end;

constructor TFakeTextLayout.CreateLongLine(const WordCount: Integer);
begin
  inherited Create;

  SetLength(FWords, WordCount);
  for var Index := 0 to WordCount - 1 do
  begin
    const Left = Index * 2;
    FWords[Index] := BuildFragment(Left, 0, Left + 1, 1, Index * 2, 1);
  end;
  FLines := [BuildFragment(0, 0, WordCount * 2, 1, 0, WordCount * 2)];
end;

constructor TFakeTextLayout.CreateCollapsedWord;
begin
  inherited Create;

  FWords := [BuildFragment(5, 5, 5, 5, 0, 1), BuildFragment(10, 0, 20, 10, 2, 1), BuildFragment(30, 0, 40, 10, 4, 1)];
  FLines := [BuildFragment(0, 0, 40, 10, 0, 6)];
end;

function TFakeTextLayout.PageIndex: Integer;
begin
  Result := 0;
end;

function TFakeTextLayout.Text: string;
begin
  Result := '';
end;

function TFakeTextLayout.Words: TArray<TPdfTextFragment>;
begin
  Result := FWords;
end;

function TFakeTextLayout.Segments: TArray<TPdfTextFragment>;
begin
  Result := FWords;
end;

function TFakeTextLayout.Lines: TArray<TPdfTextFragment>;
begin
  Result := FLines;
end;

function TFakeTextLayout.TryFindSegmentAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
begin
  raise ENotImplemented.Create(NoLayoutAsked);
end;

function TFakeTextLayout.TryFindWordAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
begin
  raise ENotImplemented.Create(NoLayoutAsked);
end;

{ TPdfPageTextTests }

procedure TPdfPageTextTests.Setup;
begin
  FStreams := TObjectList<TStream>.Create(True);
end;

procedure TPdfPageTextTests.TearDown;
begin
  FStreams.Free;
end;

function TPdfPageTextTests.LoadDocument(const Data: TBytes): IPdfDocument;
begin
  const Stream = TBytesStream.Create(Data);
  FStreams.Add(Stream);

  Result := TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
end;

function TPdfPageTextTests.InvoiceText: IPdfPageText;
begin
  const Page = LoadDocument(TViewerDocuments.Invoice).Page(0);

  Result := TPdfPageText.Create(Page.TextLayout, Page.Links);
end;

function TPdfPageTextTests.IndexOfWord(const PageText: IPdfPageText; const Text: string; const Occurrence: Integer): Integer;
begin
  var Seen := 0;
  const Words = PageText.Words;
  for var Index := 0 to High(Words) do
  begin
    const IsMatch = (Words[Index].Text = Text);
    if IsMatch and (Seen = Occurrence) then
    begin
      Exit(Index);
    end;
    if IsMatch then
    begin
      Inc(Seen);
    end;
  end;
  raise EArgumentException.CreateFmt('The page has no word %d of "%s"', [Occurrence, Text]);
end;

function TPdfPageTextTests.WordTextAt(const PageText: IPdfPageText; const X, Y: Single): string;
begin
  var WordIndex: Integer;
  const IsFound = PageText.TryFindWordAt(TPointF.Create(X, Y), WordIndex);
  Assert.IsTrue(IsFound, Format('No word at (%g,%g)', [X, Y]));

  Result := PageText.Words[WordIndex].Text;
end;

function TPdfPageTextTests.SegmentTextAt(const PageText: IPdfPageText; const X, Y: Single): string;
begin
  var Segment: TPdfTextFragment;
  const IsFound = PageText.TryFindSegmentAt(TPointF.Create(X, Y), Segment);
  Assert.IsTrue(IsFound, Format('No segment at (%g,%g)', [X, Y]));

  Result := Segment.Text;
end;

procedure TPdfPageTextTests.TestFindSegmentOnSameLine;
begin
  const Text = SegmentTextAt(InvoiceText, 150, 703);

  Assert.AreEqual('Factuur 2024-0815', Text);
end;

procedure TPdfPageTextTests.TestColonSplitsSegments;
begin
  const PageText = InvoiceText;

  Assert.AreEqual('2024-0815', SegmentTextAt(PageText, 160, 683));
  Assert.AreEqual('Nummer:', SegmentTextAt(PageText, 110, 683));
end;

procedure TPdfPageTextTests.TestPointBesideTextFindsNothing;
begin
  const PageText = InvoiceText;
  var WordIndex: Integer;
  var Segment: TPdfTextFragment;

  Assert.IsFalse(PageText.TryFindWordAt(TPointF.Create(400, 400), WordIndex));
  Assert.IsFalse(PageText.TryFindSegmentAt(TPointF.Create(400, 400), Segment));
end;

procedure TPdfPageTextTests.TestNearestWordOutsideText;
begin
  const PageText = InvoiceText;
  var WordIndex: Integer;

  const IsFound = PageText.TryFindNearestWord(TPointF.Create(95, 703), WordIndex);

  Assert.IsTrue(IsFound);
  Assert.AreEqual('Factuur', PageText.Words[WordIndex].Text);
end;

procedure TPdfPageTextTests.TestSelectAcrossWordsOnOneLine;
begin
  const PageText = InvoiceText;
  const Anchor = IndexOfWord(PageText, 'Nummer:');
  const Focus = IndexOfWord(PageText, '2024-0815', 1);

  const Selection = PageText.Select(Anchor, Focus, TPdfSelectionKind.Drag);

  Assert.AreEqual('Nummer: 2024-0815', Selection.Text);
  Assert.AreEqual(1, Integer(Length(Selection.Quads)));
  Assert.AreEqual<TPdfSelectionKind>(TPdfSelectionKind.Drag, Selection.Kind);
  Assert.AreEqual(0, Selection.PageIndex);
end;

procedure TPdfPageTextTests.TestSelectAcrossLines;
begin
  const PageText = InvoiceText;
  const Anchor = IndexOfWord(PageText, '2024-0815', 0);
  const Focus = IndexOfWord(PageText, 'Nummer:');

  const Selection = PageText.Select(Anchor, Focus, TPdfSelectionKind.Drag);

  Assert.AreEqual('2024-0815' + sLineBreak + 'Nummer:', Selection.Text);
  Assert.AreEqual(2, Integer(Length(Selection.Quads)));
end;

procedure TPdfPageTextTests.TestSelectIsOrderIndependent;
begin
  const PageText = InvoiceText;
  const Last = High(PageText.Words);

  const Forward = PageText.Select(1, Last, TPdfSelectionKind.Drag);
  const Backward = PageText.Select(Last, 1, TPdfSelectionKind.Drag);

  Assert.AreEqual(Forward.Text, Backward.Text);
  Assert.AreEqual(Integer(Length(Forward.Quads)), Integer(Length(Backward.Quads)));
end;

procedure TPdfPageTextTests.TestSelectOutOfRangeRaises;
begin
  const PageText = InvoiceText;
  const WordCount = Length(PageText.Words);

  Assert.WillRaise(
    procedure
    begin
      PageText.Select(0, WordCount, TPdfSelectionKind.Drag);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      PageText.Select(-1, 0, TPdfSelectionKind.Click);
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfPageTextTests.TestLinkAtPoint;
begin
  const PageText = InvoiceText;
  var Link: TPdfLink;

  const IsLinkFound = PageText.TryFindLinkAt(TPointF.Create(150, 610), Link);

  Assert.IsTrue(IsLinkFound);
  Assert.AreEqual<TPdfLinkKind>(TPdfLinkKind.GoTo, Link.Kind);
  Assert.AreEqual(1, Link.TargetPageIndex);
  Assert.AreEqual(2, Integer(Length(PageText.Links)));

  var Other: TPdfLink;
  const IsOutsideFound = PageText.TryFindLinkAt(TPointF.Create(150, 640), Other);

  Assert.IsFalse(IsOutsideFound);
end;

procedure TPdfPageTextTests.AssertEmptyFindsNothing(const PageText: IPdfPageText);
begin
  var WordIndex: Integer;
  var Segment: TPdfTextFragment;
  var Link: TPdfLink;
  const Point = TPointF.Create(100, 100);

  Assert.IsTrue(PageText.IsEmpty);
  Assert.IsFalse(PageText.TryFindSegmentAt(Point, Segment));
  Assert.IsFalse(PageText.TryFindWordAt(Point, WordIndex));
  Assert.IsFalse(PageText.TryFindNearestWord(Point, WordIndex));
  Assert.IsFalse(PageText.TryFindLinkAt(Point, Link));
  Assert.AreEqual('', PageText.SelectAll.Text);
  Assert.AreEqual(0, Integer(Length(PageText.SelectAll.Quads)));
end;

procedure TPdfPageTextTests.TestEmptyPageTextFindsNothing;
begin
  const PageText = TPdfPageText.Empty(3);

  AssertEmptyFindsNothing(PageText);

  Assert.AreEqual(3, PageText.PageIndex);
end;

procedure TPdfPageTextTests.TestScannedPageIsEmpty;
begin
  const Page = LoadDocument(TViewerDocuments.Scanned).Page(0);

  const PageText: IPdfPageText = TPdfPageText.Create(Page.TextLayout, Page.Links);

  AssertEmptyFindsNothing(PageText);
end;

function TPdfPageTextTests.MakeTextAfterDocumentIsReleased: IPdfPageText;
begin
  var Document := LoadDocument(TViewerDocuments.Invoice);
  var Page := Document.Page(0);
  var Layout := Page.TextLayout;
  Result := TPdfPageText.Create(Layout, Page.Links);

  Layout := nil;
  Page := nil;
  Document := nil;
end;

procedure TPdfPageTextTests.AssertWorksAfterDocumentIsGone(const PageText: IPdfPageText);
begin
  Assert.AreEqual('Factuur 2024-0815', SegmentTextAt(PageText, 150, 703));
  Assert.AreEqual('Nummer:', WordTextAt(PageText, 110, 683));
  Assert.AreEqual(2, Integer(Length(PageText.Links)));
  Assert.AreEqual('Factuur', PageText.Select(0, 0, TPdfSelectionKind.Click).Text);
  Assert.IsFalse(PageText.SelectAll.Text.IsEmpty);
end;

procedure TPdfPageTextTests.TestSnapshotOutlivesDocument;
begin
  const PageText = MakeTextAfterDocumentIsReleased;

  AssertWorksAfterDocumentIsGone(PageText);
end;

procedure TPdfPageTextTests.TestHitTestIsFastOnDensePage;
begin
  const Layout: IPdfTextLayout = TFakeTextLayout.CreateDense;
  const PageText: IPdfPageText = TPdfPageText.Create(Layout, nil);
  RandSeed := DenseSeed;
  const PageWidth = DenseWordsPerLine * DensePitch;
  const PageHeight = DenseLines * DensePitch;
  var Points: TArray<TPointF>;
  SetLength(Points, DenseQueryCount);
  for var Index := 0 to High(Points) do
  begin
    Points[Index] := TPointF.Create(Random * PageWidth, Random * PageHeight);
  end;
  var Found: TArray<Integer>;
  SetLength(Found, DenseQueryCount);

  const Watch = TStopwatch.StartNew;
  for var Index := 0 to High(Points) do
  begin
    var WordIndex: Integer;
    const IsFound = PageText.TryFindWordAt(Points[Index], WordIndex);
    Found[Index] := IfThen(IsFound, WordIndex, NoWord);
  end;
  Watch.Stop;

  for var Index := 0 to High(Points) do
  begin
    const Column = Trunc(Points[Index].X / DensePitch);
    const Row = Trunc(Points[Index].Y / DensePitch);
    const InsideWord = ((Points[Index].X - (Column * DensePitch)) <= DenseWordWidth) and
                       ((Points[Index].Y - (Row * DensePitch)) <= DenseWordWidth);
    const Expected: Integer = IfThen(InsideWord, (Row * DenseWordsPerLine) + Column, NoWord);
    Assert.AreEqual(Expected, Found[Index], Format('Point %d (%g,%g)', [Index, Points[Index].X, Points[Index].Y]));
  end;
  Assert.AreEqual(DenseLines * DenseWordsPerLine, Integer(Length(PageText.Words)));
  {$IFNDEF DEBUG}
  Assert.IsTrue(Watch.ElapsedMilliseconds < DenseBudgetMilliseconds, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  {$ENDIF}
end;

procedure TPdfPageTextTests.TestBuildIsFastWithManyWordsOnOneLine;
begin
  const Layout: IPdfTextLayout = TFakeTextLayout.CreateLongLine(LongLineWords);

  const Watch = TStopwatch.StartNew;
  const PageText: IPdfPageText = TPdfPageText.Create(Layout, nil);
  Watch.Stop;

  Assert.AreEqual(LongLineWords, Integer(Length(PageText.Words)));
  var WordIndex: Integer;
  Assert.IsTrue(PageText.TryFindWordAt(TPointF.Create((LongLineWords - 1) * 2 + 0.5, 0.5), WordIndex));
  Assert.AreEqual(LongLineWords - 1, WordIndex);
  {$IFNDEF DEBUG}
  Assert.IsTrue(Watch.ElapsedMilliseconds < LongLineBudgetMilliseconds, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  {$ENDIF}
end;

procedure TPdfPageTextTests.TestCollapsedWordHoldsNoPoint;
begin
  const Layout: IPdfTextLayout = TFakeTextLayout.CreateCollapsedWord;
  const PageText: IPdfPageText = TPdfPageText.Create(Layout, nil);
  var WordIndex: Integer;
  var Segment: TPdfTextFragment;

  Assert.IsTrue(PageText.TryFindWordAt(TPointF.Create(15, 5), WordIndex));
  Assert.AreEqual(1, WordIndex);
  Assert.IsTrue(PageText.TryFindWordAt(TPointF.Create(35, 5), WordIndex));
  Assert.AreEqual(2, WordIndex);
  Assert.IsTrue(PageText.TryFindSegmentAt(TPointF.Create(15, 5), Segment));
  Assert.AreEqual(2, Segment.Start);
  Assert.IsFalse(PageText.TryFindWordAt(TPointF.Create(25, 5), WordIndex), 'Between the words');
end;

procedure TPdfPageTextTests.TestLastOverlappingLinkWins;
begin
  const Layout: IPdfTextLayout = TFakeTextLayout.CreateCollapsedWord;
  const Square = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(10, 0), TPointF.Create(10, 10), TPointF.Create(0, 10));
  var First := Default(TPdfLink);
  First.Uri := 'first';
  First.Quads := [Square];
  var Second := First;
  Second.Uri := 'second';
  const WithLinks: IPdfPageText = TPdfPageText.Create(Layout, [First, Second]);
  var Link: TPdfLink;

  Assert.IsTrue(WithLinks.TryFindLinkAt(TPointF.Create(5, 5), Link));

  Assert.AreEqual('second', Link.Uri);
end;

procedure TPdfPageTextTests.TestSelectionQuadsAreIndependentOfOrder;
begin
  const PageText = InvoiceText;
  const Last = High(PageText.Words);

  const Forward = PageText.Select(1, Last, TPdfSelectionKind.Drag);
  const Backward = PageText.Select(Last, 1, TPdfSelectionKind.Drag);

  for var Index := 0 to High(Forward.Quads) do
  begin
    Assert.AreEqual(Double(Forward.Quads[Index].Bounds.Left), Double(Backward.Quads[Index].Bounds.Left), 0.001);
    Assert.AreEqual(Double(Forward.Quads[Index].Bounds.Right), Double(Backward.Quads[Index].Bounds.Right), 0.001);
    Assert.AreEqual(Double(Forward.Quads[Index].Bounds.Top), Double(Backward.Quads[Index].Bounds.Top), 0.001);
    Assert.AreEqual(Double(Forward.Quads[Index].Bounds.Bottom), Double(Backward.Quads[Index].Bounds.Bottom), 0.001);
  end;
end;

end.
