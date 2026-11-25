// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.TextLayout.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TApiTextLayoutTests = class
  private
    const OneLine = 'BT /F1 12 Tf 100 700 Td (Factuur) Tj 44.016 0 Td (2024-0815) Tj ET';

  private
    FStreams: TObjectList<TStream>;

    class function FailureClassOf(const Work: TProc): TClass; static;
    function NewBuilder(const PageEntries, Content: string): TTestPdfBuilder;
    function NewTwoPageBuilder(const FirstContent, SecondContent: string): TTestPdfBuilder;
    function LoadBuilder(const Builder: TTestPdfBuilder): IPdfDocument;
    function LoadContent(const Content: string; const PageEntries: string = ''): IPdfDocument;
    function InvoiceQuadsOf(const Document: IPdfDocument): TArray<TPdfQuad>;
    procedure AssertSameQuads(const Expected, Actual: TArray<TPdfQuad>);
    procedure AssertSamePoint(const Expected, Actual: TPointF);
    procedure AssertTextFailsWith(const Document: IPdfDocument; const FailureClass: ExceptClass);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDocumentTextEqualsExtractText;

    [Test]
    procedure TestDocumentTextEqualsExtractTextWithOptions;

    [Test]
    procedure TestPageLocateFindsInvoiceNumber;

    [Test]
    procedure TestPageTextEqualsExtractTextOfThePage;

    [Test]
    procedure TestPageLocateOnSecondPage;

    [Test]
    procedure TestFindSegmentAtPointOnRotatedPage;

    [Test]
    procedure TestChangingReturnedLayoutArraysLeavesTheLayoutAlone;

    [Test]
    procedure TestRotatedPageGivesSameQuads;

    [Test]
    procedure TestCropBoxOffsetIsAdded;

    [Test]
    procedure TestTextLayoutUsesSortByPosition;

    [Test]
    procedure TestTextLayoutOptionsChangeSegments;

    [Test]
    procedure TestFindSegmentAtPoint;

    [Test]
    procedure TestFindWordAtPoint;

    [Test]
    procedure TestResultOutlivesDocumentVariable;

    [Test]
    procedure TestLayoutOutlivesDocumentVariable;

    [Test]
    procedure TestLocateOutOfRangeRaises;

    [Test]
    [TestCase('NestedInlineImage', 'BT /F1 12 Tf 100 700 Td (Hi) Tj ET BI /W 1 BI /H 2 ID x EI')]
    [TestCase('UnterminatedString', 'BT /F1 12 Tf 100 700 Td (Hi Tj ET')]
    [TestCase('HugeNumbers', 'BT /F1 12 Tf 1e300 0 0 1e300 1e300 1e300 Tm (Hi) Tj ET')]
    procedure TestBrokenContentFailsLikeExtractText(const Content: string);

    [Test]
    procedure TestInputFailureOfTheStripperBecomesParseException;

    [Test]
    procedure TestPdfExceptionOfTheStripperIsRaisedAsItWas;

    [Test]
    procedure TestOtherFailureOfTheStripperIsRaisedAsItWas;

    [Test]
    procedure TestLayoutTextHoldsTheRangesOfTheItems;

    [Test]
    procedure TestNegativeSegmentGapFactorRaises;

    [Test]
    procedure TestNotANumberSegmentGapFactorRaises;

    [Test]
    procedure TestQuadContainsPointInsideAndNotOutside;

    [Test]
    procedure TestObliqueQuadContainsPointInsideAndNotOutside;

    [Test]
    procedure TestQuadWithCornersTheOtherWayRoundContainsPoint;

    [Test]
    procedure TestQuadWithoutAreaContainsNoPoint;

    [Test]
    procedure TestQuadWithNotANumberCornerContainsNoPoint;
  end;

implementation

uses
  System.Math,
  System.RegularExpressions,
  Pdf4D.Api.Document,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Api.TextLayout,
  Pdf4D.Common.Quad,
  Pdf4D.Api.TextOptions,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.TextDocuments;

const
  Tolerance = 0.001;
  InvoicePattern = '\d{4}-\d{4}';
  PageEntriesFormat = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 10 0 R >> >> %s >>';

{ TApiTextLayoutTests }

procedure TApiTextLayoutTests.Setup;
begin
  FStreams := TObjectList<TStream>.Create(True);
end;

procedure TApiTextLayoutTests.TearDown;
begin
  TPdfDocumentHandle.StripperHook := nil;
  FStreams.Free;
end;

function TApiTextLayoutTests.NewBuilder(const PageEntries, Content: string): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Result.AddObject(3, Format(PageEntriesFormat, [4, PageEntries]));
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));
    Result.AddObject(10, TTextTestDocuments.HelveticaF1);
  except
    Result.Free;
    raise;
  end;
end;

function TApiTextLayoutTests.NewTwoPageBuilder(const FirstContent, SecondContent: string): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>');
  try
    Result.AddObject(3, Format(PageEntriesFormat, [4, '']));
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(FirstContent));
    Result.AddObject(5, Format(PageEntriesFormat, [6, '']));
    Result.AddStreamObject(6, '', TEncoding.ASCII.GetBytes(SecondContent));
    Result.AddObject(10, TTextTestDocuments.HelveticaF1);
  except
    Result.Free;
    raise;
  end;
end;

function TApiTextLayoutTests.LoadBuilder(const Builder: TTestPdfBuilder): IPdfDocument;
begin
  try
    const Stream = TBytesStream.Create(Builder.Build(TXrefStyle.Table));
    FStreams.Add(Stream);
    Result := TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;
end;

function TApiTextLayoutTests.LoadContent(const Content: string; const PageEntries: string): IPdfDocument;
begin
  Result := LoadBuilder(NewBuilder(PageEntries, Content));
end;

function TApiTextLayoutTests.InvoiceQuadsOf(const Document: IPdfDocument): TArray<TPdfQuad>;
begin
  const Positioned = Document.Page(0).ExtractTextWithPositions;
  const Match = TRegEx.Match(Positioned.Text, InvoicePattern);

  Result := Positioned.Locate(Match.Index, Match.Length)[0].Quads;
end;

procedure TApiTextLayoutTests.AssertSamePoint(const Expected, Actual: TPointF);
begin
  Assert.AreEqual(Double(Expected.X), Double(Actual.X), Tolerance);
  Assert.AreEqual(Double(Expected.Y), Double(Actual.Y), Tolerance);
end;

procedure TApiTextLayoutTests.AssertSameQuads(const Expected, Actual: TArray<TPdfQuad>);
begin
  Assert.AreEqual<Integer>(Length(Expected), Length(Actual));
  for var Index := 0 to High(Expected) do
  begin
    AssertSamePoint(Expected[Index].P1, Actual[Index].P1);
    AssertSamePoint(Expected[Index].P2, Actual[Index].P2);
    AssertSamePoint(Expected[Index].P3, Actual[Index].P3);
    AssertSamePoint(Expected[Index].P4, Actual[Index].P4);
  end;
end;

procedure TApiTextLayoutTests.TestDocumentTextEqualsExtractText;
begin
  const Document = LoadContent(OneLine);

  Assert.AreEqual(Document.ExtractText, Document.ExtractTextWithPositions.Text);
end;

procedure TApiTextLayoutTests.TestDocumentTextEqualsExtractTextWithOptions;
begin
  const Document = LoadBuilder(NewTwoPageBuilder('BT /F1 12 Tf 100 700 Td (First) Tj ET', 'BT /F1 12 Tf 100 700 Td (Second) Tj ET'));
  var Options := TPdfTextOptions.Default;
  Options.StartPage := 2;
  Options.EndPage := 2;

  const Positioned = Document.ExtractTextWithPositions(Options);

  Assert.AreEqual(Document.ExtractText(Options), Positioned.Text);
  Assert.IsTrue(Positioned.Text.Contains('Second'));
  Assert.IsFalse(Positioned.Text.Contains('First'));
end;

procedure TApiTextLayoutTests.TestPageLocateFindsInvoiceNumber;
begin
  const Document = LoadContent(OneLine);
  const Positioned = Document.Page(0).ExtractTextWithPositions;
  const Match = TRegEx.Match(Positioned.Text, InvoicePattern);

  const Fragments = Positioned.Locate(Match.Index, Match.Length);

  Assert.AreEqual<Integer>(1, Length(Fragments));
  Assert.AreEqual('2024-0815', Fragments[0].Text);
  Assert.AreEqual<Integer>(0, Fragments[0].PageIndex);
  Assert.AreEqual<Integer>(0, Fragments[0].Start);
  Assert.AreEqual<Integer>(0, Fragments[0].Length);
  Assert.AreEqual(Double(144.016), Double(Fragments[0].Quads[0].P1.X), Tolerance);
end;

procedure TApiTextLayoutTests.TestPageTextEqualsExtractTextOfThePage;
begin
  const Document = LoadBuilder(NewTwoPageBuilder('BT /F1 12 Tf 100 700 Td (First page) Tj 0 -14 Td (more) Tj ET', 'BT /F1 12 Tf 100 700 Td (Second page) Tj ET'));

  Assert.AreEqual(Document.Page(0).ExtractText, Document.Page(0).ExtractTextWithPositions.Text);
  Assert.AreEqual(Document.Page(1).ExtractText, Document.Page(1).ExtractTextWithPositions.Text);
  Assert.IsTrue(Document.Page(1).ExtractTextWithPositions.Text.Contains('Second'));
end;

procedure TApiTextLayoutTests.TestPageLocateOnSecondPage;
begin
  const Document = LoadBuilder(NewTwoPageBuilder('BT /F1 12 Tf 100 700 Td (First page) Tj ET', 'BT /F1 12 Tf 150 600 Td (Second page) Tj ET'));
  const Positioned = Document.Page(1).ExtractTextWithPositions;
  const Start = Positioned.Text.IndexOf('Second') + 1;

  const Fragments = Positioned.Locate(Start, Length('Second'));

  Assert.AreEqual<Integer>(1, Length(Fragments));
  Assert.AreEqual<Integer>(1, Fragments[0].PageIndex);
  Assert.AreEqual('Second', Fragments[0].Text);
  Assert.AreEqual(Double(150), Double(Fragments[0].Quads[0].P1.X), Tolerance);
  Assert.IsTrue(Fragments[0].Quads[0].P1.Y < 620, 'the quad lies on the second page text line');
end;

procedure TApiTextLayoutTests.TestFindSegmentAtPointOnRotatedPage;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (12 maart 2026) Tj ET', '/Rotate 90');
  const Layout = Document.Page(0).TextLayout;
  var Fragment: TPdfTextFragment;

  const IsFoundInside = Layout.TryFindSegmentAt(TPointF.Create(110, 704), Fragment);
  const FoundText = Fragment.Text;
  const IsFoundRotatedPoint = Layout.TryFindSegmentAt(TPointF.Create(704, 110), Fragment);

  Assert.IsTrue(IsFoundInside, 'the point is given in PDF user space');
  Assert.AreEqual('12 maart 2026', FoundText);
  Assert.IsFalse(IsFoundRotatedPoint);
end;

procedure TApiTextLayoutTests.TestChangingReturnedLayoutArraysLeavesTheLayoutAlone;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (12 maart 2026) Tj ET');
  const Layout = Document.Page(0).TextLayout;
  var Words := Layout.Words;
  const OriginalText = Words[0].Text;
  const OriginalLeft = Words[0].Quads[0].P1.X;

  Words[0].Text := 'changed';
  Words[0].Quads[0].P1 := TPointF.Create(-1, -1);
  var Lines := Layout.Lines;
  Lines[0].Quads[0].P1 := TPointF.Create(-1, -1);
  var Segments := Layout.Segments;
  Segments[0].Quads[0].P1 := TPointF.Create(-1, -1);
  var Found: TPdfTextFragment;
  Assert.IsTrue(Layout.TryFindWordAt(TPointF.Create(105, 704), Found));
  Found.Quads[0].P1 := TPointF.Create(-1, -1);

  Assert.AreEqual(OriginalText, Layout.Words[0].Text);
  Assert.AreEqual(Double(OriginalLeft), Double(Layout.Words[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(OriginalLeft), Double(Layout.Lines[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(OriginalLeft), Double(Layout.Segments[0].Quads[0].P1.X), Tolerance);
  Assert.IsTrue(Layout.TryFindWordAt(TPointF.Create(105, 704), Found));
end;

procedure TApiTextLayoutTests.TestRotatedPageGivesSameQuads;
begin
  const Plain = InvoiceQuadsOf(LoadContent(OneLine));

  const Rotated = InvoiceQuadsOf(LoadContent(OneLine, '/Rotate 90'));

  AssertSameQuads(Plain, Rotated);
end;

procedure TApiTextLayoutTests.TestCropBoxOffsetIsAdded;
begin
  const Plain = InvoiceQuadsOf(LoadContent(OneLine));

  const Cropped = InvoiceQuadsOf(LoadContent(OneLine, '/CropBox [50 50 562 742]'));

  AssertSameQuads(Plain, Cropped);
end;

procedure TApiTextLayoutTests.TestTextLayoutUsesSortByPosition;
begin
  const Document = LoadContent('BT /F1 12 Tf 200 700 Td (Right) Tj ET BT /F1 12 Tf 100 700 Td (Left) Tj ET');

  const Layout = Document.Page(0).TextLayout;

  Assert.AreEqual<Integer>(2, Length(Layout.Words));
  Assert.AreEqual('Left', Layout.Words[0].Text);
  Assert.AreEqual('Right', Layout.Words[1].Text);
  Assert.AreEqual<Integer>(0, Layout.PageIndex);
end;

procedure TApiTextLayoutTests.TestTextLayoutOptionsChangeSegments;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (Nummer: 2024-0815) Tj ET');
  var Options := TPdfTextLayoutOptions.Default;
  Options.BreakAfterColon := False;

  const Default = Document.Page(0).TextLayout;
  const NoBreak = Document.Page(0).TextLayout(Options);

  Assert.AreEqual<Integer>(2, Length(Default.Segments));
  Assert.AreEqual<Integer>(1, Length(NoBreak.Segments));
end;

procedure TApiTextLayoutTests.TestFindSegmentAtPoint;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (12 maart 2026) Tj ET');
  const Layout = Document.Page(0).TextLayout;
  var Fragment: TPdfTextFragment;

  const IsFoundInside = Layout.TryFindSegmentAt(TPointF.Create(110, 704), Fragment);
  const FoundText = Fragment.Text;
  const IsFoundBeside = Layout.TryFindSegmentAt(TPointF.Create(50, 704), Fragment);

  Assert.IsTrue(IsFoundInside);
  Assert.AreEqual('12 maart 2026', FoundText);
  Assert.IsFalse(IsFoundBeside);
end;

procedure TApiTextLayoutTests.TestFindWordAtPoint;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (12 maart 2026) Tj ET');
  const Layout = Document.Page(0).TextLayout;
  var Fragment: TPdfTextFragment;

  const IsFound = Layout.TryFindWordAt(TPointF.Create(135, 704), Fragment);

  Assert.IsTrue(IsFound);
  Assert.AreEqual('maart', Fragment.Text);
end;

procedure TApiTextLayoutTests.TestResultOutlivesDocumentVariable;
begin
  var Document := LoadContent(OneLine);
  const Positioned = Document.ExtractTextWithPositions;
  Document := nil;
  const Match = TRegEx.Match(Positioned.Text, InvoicePattern);

  const Fragments = Positioned.Locate(Match.Index, Match.Length);

  Assert.AreEqual<Integer>(1, Length(Fragments));
  Assert.AreEqual(Double(144.016), Double(Fragments[0].Quads[0].P1.X), Tolerance);
end;

procedure TApiTextLayoutTests.TestLayoutOutlivesDocumentVariable;
begin
  var Document := LoadContent(OneLine);
  const Layout = Document.Page(0).TextLayout;
  Document := nil;

  Assert.AreEqual<Integer>(2, Length(Layout.Words));
  Assert.AreEqual('Factuur', Layout.Words[0].Text);
end;

procedure TApiTextLayoutTests.TestLocateOutOfRangeRaises;
begin
  const Positioned = LoadContent(OneLine).ExtractTextWithPositions;

  Assert.WillRaise(
    procedure
    begin
      Positioned.Locate(0, 1);
    end, EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      Positioned.Locate(1, Length(Positioned.Text) + 1);
    end, EArgumentOutOfRangeException);
end;

class function TApiTextLayoutTests.FailureClassOf(const Work: TProc): TClass;
begin
  Result := nil;
  try
    Work;
  except
    on Failure: Exception do
    begin
      Result := Failure.ClassType;
    end;
  end;
end;

procedure TApiTextLayoutTests.TestBrokenContentFailsLikeExtractText(const Content: string);
begin
  const Document = LoadContent(Content);

  const ExpectedClass = FailureClassOf(
    procedure
    begin
      Document.ExtractText;
    end);
  const PositionedClass = FailureClassOf(
    procedure
    begin
      Document.ExtractTextWithPositions;
    end);
  const LayoutClass = FailureClassOf(
    procedure
    begin
      Document.Page(0).TextLayout;
    end);

  Assert.IsTrue(ExpectedClass = PositionedClass, 'ExtractTextWithPositions must fail like ExtractText');
  Assert.IsTrue(ExpectedClass = LayoutClass, 'TextLayout must fail like ExtractText');
  Assert.IsTrue((not Assigned(ExpectedClass)) or ExpectedClass.InheritsFrom(EPdfException), 'A broken file gives an EPdfException');
end;

procedure TApiTextLayoutTests.AssertTextFailsWith(const Document: IPdfDocument; const FailureClass: ExceptClass);
begin
  Assert.WillRaise(
    procedure
    begin
      Document.ExtractTextWithPositions;
    end, FailureClass);
  Assert.WillRaise(
    procedure
    begin
      Document.Page(0).ExtractTextWithPositions;
    end, FailureClass);
  Assert.WillRaise(
    procedure
    begin
      Document.Page(0).TextLayout;
    end, FailureClass);
  Assert.WillRaise(
    procedure
    begin
      Document.ExtractText;
    end, FailureClass);
end;

procedure TApiTextLayoutTests.TestInputFailureOfTheStripperBecomesParseException;
begin
  const Document = LoadContent(OneLine);
  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise ERangeError.Create('Injected failure');
    end;

  AssertTextFailsWith(Document, EPdfParseException);
end;

procedure TApiTextLayoutTests.TestPdfExceptionOfTheStripperIsRaisedAsItWas;
begin
  const Document = LoadContent(OneLine);
  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise EPdfLimitExceededException.Create('Injected failure');
    end;

  AssertTextFailsWith(Document, EPdfLimitExceededException);
end;

procedure TApiTextLayoutTests.TestOtherFailureOfTheStripperIsRaisedAsItWas;
begin
  const Document = LoadContent(OneLine);
  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise EInvalidOperation.Create('Injected failure');
    end;

  AssertTextFailsWith(Document, EInvalidOperation);
end;

procedure TApiTextLayoutTests.TestLayoutTextHoldsTheRangesOfTheItems;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (Nummer: 2024-0815) Tj 0 -14 Td (12 maart 2026) Tj ET');
  const Layout = Document.Page(0).TextLayout;

  Assert.IsTrue(Length(Layout.Words) > 0);
  Assert.IsTrue(Length(Layout.Segments) > 0);
  Assert.IsTrue(Length(Layout.Lines) > 0);
  for var Fragment in Layout.Words + Layout.Segments + Layout.Lines do
  begin
    Assert.AreEqual(Fragment.Text, Copy(Layout.Text, Fragment.Start, Fragment.Length));
  end;
end;

procedure TApiTextLayoutTests.TestNegativeSegmentGapFactorRaises;
begin
  const Document = LoadContent(OneLine);
  var Options := TPdfTextLayoutOptions.Default;
  Options.SegmentGapFactor := -1;

  Assert.WillRaise(
    procedure
    begin
      Document.Page(0).TextLayout(Options);
    end, EArgumentOutOfRangeException);
end;

procedure TApiTextLayoutTests.TestNotANumberSegmentGapFactorRaises;
begin
  const Document = LoadContent(OneLine);
  var Options := TPdfTextLayoutOptions.Default;
  Options.SegmentGapFactor := NaN;

  Assert.WillRaise(
    procedure
    begin
      Document.Page(0).TextLayout(Options);
    end, EArgumentOutOfRangeException);
end;

procedure TApiTextLayoutTests.TestQuadContainsPointInsideAndNotOutside;
begin
  const Quad = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(10, 0), TPointF.Create(10, 10), TPointF.Create(0, 10));

  Assert.IsTrue(TPdfTextLayout.IsInsideQuad(TPointF.Create(5, 5), Quad));
  Assert.IsTrue(TPdfTextLayout.IsInsideQuad(TPointF.Create(10, 5), Quad), 'the edge belongs to the quad');
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(15, 5), Quad));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(5, -1), Quad));
end;

procedure TApiTextLayoutTests.TestObliqueQuadContainsPointInsideAndNotOutside;
begin
  const Quad = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(10, 10), TPointF.Create(5, 15), TPointF.Create(-5, 5));

  Assert.IsTrue(TPdfTextLayout.IsInsideQuad(TPointF.Create(2.5, 7.5), Quad));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(10, 0), Quad));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(0, 12), Quad));
end;

procedure TApiTextLayoutTests.TestQuadWithCornersTheOtherWayRoundContainsPoint;
begin
  const Quad = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(0, 10), TPointF.Create(10, 10), TPointF.Create(10, 0));

  Assert.IsTrue(TPdfTextLayout.IsInsideQuad(TPointF.Create(5, 5), Quad));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(15, 5), Quad));
end;

procedure TApiTextLayoutTests.TestQuadWithoutAreaContainsNoPoint;
begin
  const Corner = TPointF.Create(5, 5);
  const Dot = TPdfQuad.Create(Corner, Corner, Corner, Corner);
  const Line = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(10, 0), TPointF.Create(10, 0), TPointF.Create(0, 0));

  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(Corner, Dot));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(1, 1), Dot));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(5, 0), Line));
  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(5, 3), Line));
end;

procedure TApiTextLayoutTests.TestQuadWithNotANumberCornerContainsNoPoint;
begin
  const Quad = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(10, 0), TPointF.Create(NaN, 10), TPointF.Create(0, 10));

  Assert.IsFalse(TPdfTextLayout.IsInsideQuad(TPointF.Create(5, 5), Quad));
end;

end.
