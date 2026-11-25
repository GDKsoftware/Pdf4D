// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.Layout.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Text.PositionedText,
  Pdf4D.Text.Layout;

type
  [TestFixture]
  TPdfTextLayoutTests = class
  private
    const BedragWidth = 38.688;
    const SpaceWidth = 3.336;

  private
    FModels: TModelTestDocuments;
    FPositioned: TPdfPositionedText;

    function NewBuilder(const Content: string): TTestPdfBuilder;
    function NewTwoPageBuilder(const FirstContent, SecondContent: string): TTestPdfBuilder;
    // Extracts with the position stripper. The builder is freed.
    procedure Extract(const Builder: TTestPdfBuilder);
    function LayoutOfPage(const PageIndex: Integer; const Options: TPdfLayoutOptions): TPdfPageLayout; overload;
    function LayoutOfPage(const PageIndex: Integer): TPdfPageLayout; overload;
    // A line with Bedrag, then Totaal after a gap of GapInSpaces times the width of a space
    function ContentWithGap(const GapInSpaces: Double): string;
    procedure AssertItemsPointIntoText(const Items: TArray<TPdfLayoutItem>; const Kind: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDateIsOneSegment;

    [Test]
    procedure TestColonEndsSegment;

    [Test]
    procedure TestColonRuleCanBeTurnedOff;

    [Test]
    procedure TestLargeGapEndsSegment;

    [Test]
    procedure TestGapJustBelowFactorStaysOneSegment;

    [Test]
    procedure TestGapJustAboveFactorEndsSegment;

    [Test]
    procedure TestLinesFollowLineSeparators;

    [Test]
    procedure TestStartAndLengthPointIntoText;

    [Test]
    procedure TestOtherPageIsNotIncluded;

    [Test]
    procedure TestPageWithoutTextIsEmpty;
  end;

implementation

uses
  Pdf4D.Tests.TextDocuments,
  Pdf4D.Text.PositionStripper;

const
  Tolerance = 0.001;

{ TPdfTextLayoutTests }

procedure TPdfTextLayoutTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
end;

procedure TPdfTextLayoutTests.TearDown;
begin
  FreeAndNil(FPositioned);
  FModels.Free;
end;

function TPdfTextLayoutTests.NewBuilder(const Content: string): TTestPdfBuilder;
begin
  Result := TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, Content);
end;

function TPdfTextLayoutTests.NewTwoPageBuilder(const FirstContent, SecondContent: string): TTestPdfBuilder;
begin
  const Resources = '/Resources << /Font << /F1 10 0 R >> >>';
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>');
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

procedure TPdfTextLayoutTests.Extract(const Builder: TTestPdfBuilder);
begin
  FreeAndNil(FPositioned);
  try
    const Stripper = TPdfPositionStripper.Create;
    try
      FPositioned := Stripper.Extract(FModels.Open(Builder));
    finally
      Stripper.Free;
    end;
  finally
    Builder.Free;
  end;
end;

function TPdfTextLayoutTests.LayoutOfPage(const PageIndex: Integer; const Options: TPdfLayoutOptions): TPdfPageLayout;
begin
  Result := TPdfTextLayoutBuilder.Build(FPositioned, PageIndex, Options);
end;

function TPdfTextLayoutTests.LayoutOfPage(const PageIndex: Integer): TPdfPageLayout;
begin
  Result := LayoutOfPage(PageIndex, TPdfLayoutOptions.Default);
end;

function TPdfTextLayoutTests.ContentWithGap(const GapInSpaces: Double): string;
begin
  const Offset = BedragWidth + GapInSpaces * SpaceWidth;

  Result := Format('BT /F1 12 Tf 100 700 Td (Bedrag) Tj %.4f 0 Td (Totaal) Tj ET', [Offset], TFormatSettings.Invariant);
end;

procedure TPdfTextLayoutTests.AssertItemsPointIntoText(const Items: TArray<TPdfLayoutItem>; const Kind: string);
begin
  Assert.IsTrue(Length(Items) > 0, Format('%s: there are items', [Kind]));
  for var Item in Items do
  begin
    Assert.AreEqual(Item.Text, Copy(FPositioned.Text, Item.Start, Item.Length), Format('%s: %s', [Kind, Item.Text]));
    Assert.AreEqual<Integer>(1, Length(Item.Quads), Format('%s: one quad', [Kind]));
  end;
end;

procedure TPdfTextLayoutTests.TestDateIsOneSegment;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (12 maart 2026) Tj ET'));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(3, Length(Layout.Words));
  Assert.AreEqual<Integer>(1, Length(Layout.Segments));
  Assert.AreEqual('12 maart 2026', Layout.Segments[0].Text);
  Assert.AreEqual('maart', Layout.Words[1].Text);
end;

procedure TPdfTextLayoutTests.TestColonEndsSegment;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (Nummer: 2024-0815) Tj ET'));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(2, Length(Layout.Segments));
  Assert.AreEqual('Nummer:', Layout.Segments[0].Text);
  Assert.AreEqual('2024-0815', Layout.Segments[1].Text);
  Assert.AreEqual<Integer>(1, Length(Layout.Lines));
end;

procedure TPdfTextLayoutTests.TestColonRuleCanBeTurnedOff;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (Nummer: 2024-0815) Tj ET'));
  var Options := TPdfLayoutOptions.Default;
  Options.BreakAfterColon := False;

  const Layout = LayoutOfPage(0, Options);

  Assert.AreEqual<Integer>(1, Length(Layout.Segments));
  Assert.AreEqual('Nummer: 2024-0815', Layout.Segments[0].Text);
end;

procedure TPdfTextLayoutTests.TestLargeGapEndsSegment;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (Bedrag) Tj 78.688 0 Td (EUR 1.234,56) Tj ET'));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(2, Length(Layout.Segments));
  Assert.AreEqual('Bedrag', Layout.Segments[0].Text);
  Assert.AreEqual<Integer>(1, Length(Layout.Lines));
end;

procedure TPdfTextLayoutTests.TestGapJustBelowFactorStaysOneSegment;
begin
  Extract(NewBuilder(ContentWithGap(1.9)));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(2, Length(Layout.Words));
  Assert.AreEqual<Integer>(1, Length(Layout.Segments));
end;

procedure TPdfTextLayoutTests.TestGapJustAboveFactorEndsSegment;
begin
  Extract(NewBuilder(ContentWithGap(2.1)));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(2, Length(Layout.Words));
  Assert.AreEqual<Integer>(2, Length(Layout.Segments));
end;

procedure TPdfTextLayoutTests.TestLinesFollowLineSeparators;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (Line one) Tj 0 -14 Td (Line two) Tj 0 -14 Td (Line three) Tj ET'));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(3, Length(Layout.Lines));
  Assert.AreEqual('Line one', Layout.Lines[0].Text);
  Assert.AreEqual('Line three', Layout.Lines[2].Text);
  for var Line in Layout.Lines do
  begin
    Assert.AreEqual<Integer>(1, Length(Line.Quads));
  end;

  const FirstQuad = Layout.Lines[0].Quads[0];
  Assert.AreEqual(Double(100), Double(FirstQuad.P1.X), Tolerance);
  Assert.AreEqual(Double(146.032), Double(FirstQuad.P2.X), Tolerance);
  Assert.IsTrue(Layout.Lines[1].Quads[0].P1.Y < FirstQuad.P1.Y, 'the second line lies below the first');
end;

procedure TPdfTextLayoutTests.TestStartAndLengthPointIntoText;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (Nummer: 2024-0815) Tj 0 -14 Td (12 maart 2026) Tj 0 -14 Td (Bedrag) Tj 90 0 Td (Totaal) Tj ET'));

  const Layout = LayoutOfPage(0);

  AssertItemsPointIntoText(Layout.Words, 'words');
  AssertItemsPointIntoText(Layout.Segments, 'segments');
  AssertItemsPointIntoText(Layout.Lines, 'lines');
end;

procedure TPdfTextLayoutTests.TestOtherPageIsNotIncluded;
begin
  Extract(NewTwoPageBuilder('BT /F1 12 Tf 100 700 Td (First page) Tj ET', 'BT /F1 12 Tf 100 700 Td (Second sheet here) Tj ET'));

  const Layout = LayoutOfPage(0);

  Assert.AreEqual<Integer>(0, Layout.PageIndex);
  Assert.AreEqual<Integer>(2, Length(Layout.Words));
  Assert.AreEqual('First', Layout.Words[0].Text);
  Assert.AreEqual('page', Layout.Words[1].Text);
  Assert.AreEqual<Integer>(1, Length(Layout.Lines));
  Assert.AreEqual<Integer>(3, Length(LayoutOfPage(1).Words));
end;

procedure TPdfTextLayoutTests.TestPageWithoutTextIsEmpty;
begin
  Extract(NewBuilder('BT /F1 12 Tf 100 700 Td (Only) Tj ET'));

  const Layout = LayoutOfPage(5);

  Assert.AreEqual<Integer>(0, Length(Layout.Words));
  Assert.AreEqual<Integer>(0, Length(Layout.Segments));
  Assert.AreEqual<Integer>(0, Length(Layout.Lines));
end;

end.
