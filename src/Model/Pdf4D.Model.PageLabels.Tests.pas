// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.PageLabels.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Document,
  Pdf4D.Model.PageLabels,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TPageLabelsTests = class
  private
    FDocuments: TModelTestDocuments;

    // A document with PageCount pages and the number tree Nums in /PageLabels
    function OpenWithLabels(const PageCount: Integer; const Nums: string): TPDDocument;
    function LabelsOf(const Document: TPDDocument): TArray<string>;
    function FirstLabelOfStart(const Style: string; const Start: Integer): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPageLabelsRomanAndPrefix;

    [Test]
    procedure TestOnlyTheDocumentGivesDecimalLabelsAndIgnoresTheTree;

    [Test]
    procedure TestNoDictionaryGivesDecimalLabels;

    [Test]
    procedure TestRomanNumbersOfAnySize;

    [Test]
    procedure TestLettersRepeatBeyondTwentySix;

    [Test]
    procedure TestPrefixIsCutAtANullByte;

    [Test]
    procedure TestUnknownStyleFallsBackToDecimalAndNoStyleGivesOnlyThePrefix;

    [Test]
    procedure TestLabelsFollowTheCountOfThePageTree;

    [Test]
    procedure TestHugeCountWithFewPagesAllocatesForTheRealPages;

    [Test]
    procedure TestRangeBeyondTheLastPageAndNegativeKeysChangeNothing;

    [Test]
    procedure TestStartValueWrapsAroundLikeAnInt;

    [Test]
    procedure TestValueThatIsNoDictionaryRaises;

    [Test]
    procedure TestNullRangeRaisesWhenItHasPages;

    [Test]
    procedure TestHugeLabelsAreLimited;

    [Test]
    procedure TestNegativeCountRaises;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary;

{ TPageLabelsTests }

procedure TPageLabelsTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TPageLabelsTests.TearDown;
begin
  FDocuments.Free;
end;

function TPageLabelsTests.OpenWithLabels(const PageCount: Integer; const Nums: string): TPDDocument;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(PageCount, Format('/PageLabels << /Nums [%s] >>', [Nums]));
  try
    Result := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
end;

function TPageLabelsTests.LabelsOf(const Document: TPDDocument): TArray<string>;
begin
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Document.Catalog.TryGetPageLabels(Dictionary));
  const Labels = TPDPageLabels.Create(Document, Dictionary);
  try
    Result := Labels.GetLabelsByPageIndices;
  finally
    Labels.Free;
  end;
end;

function TPageLabelsTests.FirstLabelOfStart(const Style: string; const Start: Integer): string;
begin
  const Document = OpenWithLabels(1, Format('0 << /S /%s /St %d >>', [Style, Start]));
  Result := LabelsOf(Document)[0];
end;

procedure TPageLabelsTests.TestPageLabelsRomanAndPrefix;
begin
  const Labels = LabelsOf(OpenWithLabels(5, '0 << /S /r >> 3 << /S /D /P (A-) /St 5 >>'));
  Assert.AreEqual<Integer>(5, Length(Labels));
  Assert.AreEqual('i', Labels[0]);
  Assert.AreEqual('ii', Labels[1]);
  Assert.AreEqual('iii', Labels[2]);
  Assert.AreEqual('A-5', Labels[3]);
  Assert.AreEqual('A-6', Labels[4]);
end;

procedure TPageLabelsTests.TestOnlyTheDocumentGivesDecimalLabelsAndIgnoresTheTree;
begin
  // PDPageLabels(PDDocument) of PDFBox 3.0.8 does not read /PageLabels, and the golden files were made with it
  const Document = OpenWithLabels(3, '0 << /S /r >>');
  const Labels = TPDPageLabels.Create(Document);
  try
    const Found = Labels.GetLabelsByPageIndices;
    Assert.AreEqual<Integer>(3, Length(Found));
    Assert.AreEqual('1', Found[0]);
    Assert.AreEqual('2', Found[1]);
    Assert.AreEqual('3', Found[2]);
    Assert.AreEqual(1, Labels.PageRangeCount);
  finally
    Labels.Free;
  end;
end;

procedure TPageLabelsTests.TestNoDictionaryGivesDecimalLabels;
begin
  const Document = OpenWithLabels(2, '');
  const Labels = TPDPageLabels.Create(Document, nil);
  try
    Assert.AreEqual('1,2', string.Join(',', Labels.GetLabelsByPageIndices));
  finally
    Labels.Free;
  end;
end;

procedure TPageLabelsTests.TestRomanNumbersOfAnySize;
begin
  Assert.AreEqual('IV', FirstLabelOfStart('R', 4));
  Assert.AreEqual('ix', FirstLabelOfStart('r', 9));
  Assert.AreEqual('XL', FirstLabelOfStart('R', 40));
  Assert.AreEqual('XCIX', FirstLabelOfStart('R', 99));
  Assert.AreEqual('CD', FirstLabelOfStart('R', 400));
  Assert.AreEqual('MCMXCIV', FirstLabelOfStart('R', 1994));
  Assert.AreEqual('MMMCMXCIX', FirstLabelOfStart('R', 3999));
  // Beyond 3999 there are as many m as there are thousands, as Acrobat has it
  Assert.AreEqual('MMMM', FirstLabelOfStart('R', 4000));
  Assert.AreEqual('mmmmmmmmmmmmcccxlv', FirstLabelOfStart('r', 12345));
  // Zero and a negative number give nothing
  Assert.AreEqual('', FirstLabelOfStart('R', 0));
  Assert.AreEqual('', FirstLabelOfStart('r', -5));
  Assert.AreEqual(100002, FirstLabelOfStart('r', 100002000).Length);
end;

procedure TPageLabelsTests.TestLettersRepeatBeyondTwentySix;
begin
  Assert.AreEqual('A', FirstLabelOfStart('A', 1));
  Assert.AreEqual('Z', FirstLabelOfStart('A', 26));
  Assert.AreEqual('AA', FirstLabelOfStart('A', 27));
  Assert.AreEqual('BB', FirstLabelOfStart('A', 28));
  Assert.AreEqual('zz', FirstLabelOfStart('a', 52));
  Assert.AreEqual('aaa', FirstLabelOfStart('a', 53));
  Assert.AreEqual('', FirstLabelOfStart('a', 0));
  Assert.AreEqual('', FirstLabelOfStart('a', -3));
end;

procedure TPageLabelsTests.TestPrefixIsCutAtANullByte;
begin
  const Labels = LabelsOf(OpenWithLabels(1, '0 << /S /D /P <41420043> >>'));
  Assert.AreEqual('AB1', Labels[0]);
end;

procedure TPageLabelsTests.TestUnknownStyleFallsBackToDecimalAndNoStyleGivesOnlyThePrefix;
begin
  const Labels = LabelsOf(OpenWithLabels(3, '0 << /S /X /St 7 >> 1 << /P (only) >> 2 << >>'));
  Assert.AreEqual('7', Labels[0]);
  Assert.AreEqual('only', Labels[1]);
  Assert.AreEqual('', Labels[2]);
end;

procedure TPageLabelsTests.TestLabelsFollowTheCountOfThePageTree;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [10 0 R] /Count 3 >>');
  try
    Builder.AddObject(10, '<< /Type /Page /Parent 2 0 R >>');
    // The count says 3 and there is one page: the labels are made for the page that exists
    const Labels = TPDPageLabels.Create(FDocuments.Open(Builder));
    try
      Assert.AreEqual(1, FDocuments.Document.Pages.EnumeratedCount);
      Assert.AreEqual<Integer>(1, Length(Labels.GetLabelsByPageIndices));
    finally
      Labels.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TPageLabelsTests.TestHugeCountWithFewPagesAllocatesForTheRealPages;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [10 0 R 11 0 R] /Count 9999999 >>');
  try
    Builder.AddObject(10, '<< /Type /Page /Parent 2 0 R >>');
    Builder.AddObject(11, '<< /Type /Page /Parent 2 0 R >>');
    const Labels = TPDPageLabels.Create(FDocuments.Open(Builder));
    try
      Assert.AreEqual<Integer>(2, Length(Labels.GetLabelsByPageIndices));
    finally
      Labels.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TPageLabelsTests.TestRangeBeyondTheLastPageAndNegativeKeysChangeNothing;
begin
  const Labels = LabelsOf(OpenWithLabels(3, '-5 << /S /R >> 0 << /S /D /P (p) >> 100 << /S /r >>'));
  Assert.AreEqual('p1,p2,p3', string.Join(',', Labels));
end;

procedure TPageLabelsTests.TestStartValueWrapsAroundLikeAnInt;
begin
  const Labels = LabelsOf(OpenWithLabels(2, '0 << /S /D /St 2147483647 >>'));
  Assert.AreEqual('2147483647', Labels[0]);
  Assert.AreEqual('-2147483648', Labels[1]);
end;

procedure TPageLabelsTests.TestValueThatIsNoDictionaryRaises;
begin
  const Document = OpenWithLabels(1, '0 5');
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Document.Catalog.TryGetPageLabels(Dictionary));
  Assert.WillRaiseDescendant(
    procedure
    begin
      TPDPageLabels.Create(Document, Dictionary).Free;
    end, EPdfParseException);
end;

procedure TPageLabelsTests.TestNullRangeRaisesWhenItHasPages;
begin
  const Document = OpenWithLabels(2, '0 null');
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Document.Catalog.TryGetPageLabels(Dictionary));
  const Labels = TPDPageLabels.Create(Document, Dictionary);
  try
    Assert.WillRaiseDescendant(
      procedure
      begin
        Labels.GetLabelsByPageIndices;
      end, EPdfParseException);
  finally
    Labels.Free;
  end;
end;

procedure TPageLabelsTests.TestHugeLabelsAreLimited;
begin
  // Every label is about two million m, and PDFBox would build all of them
  const Document = OpenWithLabels(30, '0 << /S /r /St 2147483000 >>');
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Document.Catalog.TryGetPageLabels(Dictionary));
  const Labels = TPDPageLabels.Create(Document, Dictionary);
  try
    Assert.WillRaiseDescendant(
      procedure
      begin
        Labels.GetLabelsByPageIndices;
      end, EPdfLimitExceededException);
  finally
    Labels.Free;
  end;
end;

procedure TPageLabelsTests.TestNegativeCountRaises;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count -4 >>');
  try
    const Labels = TPDPageLabels.Create(FDocuments.Open(Builder));
    try
      Assert.WillRaiseDescendant(
        procedure
        begin
          Labels.GetLabelsByPageIndices;
        end, EPdfParseException);
    finally
      Labels.Free;
    end;
  finally
    Builder.Free;
  end;
end;

end.
