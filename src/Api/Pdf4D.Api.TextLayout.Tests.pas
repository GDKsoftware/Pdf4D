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
    procedure TestBrokenContentRaisesPdfException(const Content: string);

  end;

implementation

uses
  System.RegularExpressions,
  Pdf4D.Api.Document,
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

procedure TApiTextLayoutTests.TestBrokenContentRaisesPdfException(const Content: string);
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

end.
