unit Pdf4D.Model.PageTree.Tests;

interface

uses
  System.SysUtils,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TPageTreeTests = class
  private
    FDocuments: TModelTestDocuments;

    procedure AddPages(const Builder: TTestPdfBuilder; const FirstNumber, Count, ParentNumber: Integer);
    function KidsOf(const FirstNumber, Count: Integer): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPageCountWithNestedTree;

    [Test]
    procedure TestPageTreeCycleIsBroken;

    [Test]
    procedure TestCycleThroughRootOfADetachedTreeIsBroken;

    [Test]
    procedure TestWrongCountIsIgnored;

    [Test]
    procedure TestMissingCountGivesZeroAndEnumerationStillWorks;

    [Test]
    procedure TestNodeWithoutTypeButWithKidsIsATreeNode;

    [Test]
    procedure TestLeafWithoutTypeIsSkipped;

    [Test]
    procedure TestKidsThatAreNoDictionariesAreSkippedAndNullsBecomeEmptyPages;

    [Test]
    procedure TestPageDictionaryAsRootIsRepaired;

    [Test]
    procedure TestVeryDeepTreeDoesNotOverflowTheStack;

    [Test]
    procedure TestVeryWideTreeIsLinear;

    [Test]
    procedure TestIndexOfFindsPagesAndRaisesForOthers;

    [Test]
    procedure TestGetOutOfRangeRaises;

    [Test]
    procedure TestPagesAreCachedPerIndex;

    [Test]
    procedure TestEnumerationInTreeOrder;

    [Test]
    procedure TestSharedSubtreeIsCountedOnce;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.Page,
  Pdf4D.Model.PageTree;

{ TPageTreeTests }

procedure TPageTreeTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TPageTreeTests.TearDown;
begin
  FDocuments.Free;
end;

procedure TPageTreeTests.AddPages(const Builder: TTestPdfBuilder; const FirstNumber, Count, ParentNumber: Integer);
begin
  for var Offset := 0 to Count - 1 do
  begin
    Builder.AddObject(FirstNumber + Offset, Format('<< /Type /Page /Parent %d 0 R /Rotate %d >>', [ParentNumber, Offset * 90]));
  end;
end;

function TPageTreeTests.KidsOf(const FirstNumber, Count: Integer): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Offset := 0 to Count - 1 do
    begin
      Builder.Append(FirstNumber + Offset).Append(' 0 R ');
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestPageCountWithNestedTree;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 5 >>');
  try
    Builder.AddObject(3, '<< /Type /Pages /Parent 2 0 R /Kids [5 0 R 6 0 R] /Count 2 >>');
    Builder.AddObject(4, '<< /Type /Pages /Parent 2 0 R /Kids [7 0 R 8 0 R 9 0 R] /Count 3 >>');
    AddPages(Builder, 5, 5, 3);
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(5, Document.Pages.Count);
    Assert.AreEqual(5, Document.Pages.EnumeratedCount);
    // The last page is object 9 and carries /Rotate 360
    Assert.AreEqual(4, Document.Pages.IndexOf(Document.Pages.Get(4).CosObject));
    Assert.AreEqual(0, Document.Pages.Get(4).Rotation);
    Assert.AreEqual(90, Document.Pages.Get(1).Rotation);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestPageTreeCycleIsBroken;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R 2 0 R] /Count 2 >>');
  try
    Builder.AddObject(4, '<< /Type /Pages /Parent 2 0 R /Kids [2 0 R 3 0 R 4 0 R] /Count 1 >>');
    AddPages(Builder, 3, 1, 2);
    const Document = FDocuments.Open(Builder);

    var Count := 0;
    for var Page in Document.Pages do
    begin
      Inc(Count);
      Assert.IsNotNull(Page);
    end;

    // The page that the cyclic nodes point to is counted for each node that lists it, not for each walk around the cycle
    Assert.IsTrue(Count <= 2, Format('%d pages', [Count]));
    Assert.IsTrue(Count >= 1);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestCycleThroughRootOfADetachedTreeIsBroken;
begin
  // A tree built by hand, the file loader would repair this: the root lists a page and then itself
  const Root = TCosDictionary.Create;
  const Page = TCosDictionary.Create;
  const Kids = TCosArray.Create;
  try
    Root.SetItem(TCosNames.Type_, TCosName.Create(TCosNames.Pages));
    Page.SetItem(TCosNames.Type_, TCosName.Create(TCosNames.Page));
    Kids.Add(Page);
    Kids.Add(Root);
    Root.SetItem(TCosNames.Kids, Kids);

    var Messages := '';
    const Log = TPdfLog.Create(
      procedure(const Level: TPdfLogLevel; const Message: string)
      begin
        Messages := Messages + Message + #10;
      end);
    try
      const Tree = TPDPageTree.Create(Root, Log);
      try
        Assert.AreEqual(1, Tree.EnumeratedCount);
        Assert.AreSame(Page, Tree.Get(0).CosObject);
      finally
        Tree.Free;
      end;
    finally
      Log.Free;
    end;
    Assert.IsTrue(Messages.Contains('already been visited'), Messages);
  finally
    // The loop of ownership: Kids owns Page and Root; hand Root back before everything is freed
    Kids.RemoveLast;
    Root.Free;
  end;
end;

procedure TPageTreeTests.TestWrongCountIsIgnored;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 99 >>');
  try
    AddPages(Builder, 3, 3, 2);
    const Document = FDocuments.Open(Builder);

    // PDFBox 3.0.8: the enumeration gives the three real pages, getCount gives the /Count entry
    Assert.AreEqual(99, Document.Pages.Count);
    Assert.AreEqual(3, Document.Pages.EnumeratedCount);
    var Seen := 0;
    for var Page in Document.Pages do
    begin
      Assert.IsNotNull(Page);
      Inc(Seen);
    end;
    Assert.AreEqual(3, Seen);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestMissingCountGivesZeroAndEnumerationStillWorks;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R] >>');
  try
    AddPages(Builder, 3, 2, 2);
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(0, Document.Pages.Count);
    Assert.AreEqual(2, Document.Pages.EnumeratedCount);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestNodeWithoutTypeButWithKidsIsATreeNode;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R] /Count 1 /Parent 2 0 R >>');
    Builder.AddObject(4, '<< /Type /Page /Parent 3 0 R >>');
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(1, Document.Pages.EnumeratedCount);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestLeafWithoutTypeIsSkipped;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');
  try
    Builder.AddObject(3, '<< /Parent 2 0 R /MediaBox [0 0 10 10] >>');
    Builder.AddObject(4, '<< /Type /Page /Parent 2 0 R >>');
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(1, Document.Pages.EnumeratedCount);
    Assert.IsTrue(FDocuments.HasLogLine('Page skipped'), 'no log line');
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestKidsThatAreNoDictionariesAreSkippedAndNullsBecomeEmptyPages;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 42 null] /Count 3 >>');
  try
    AddPages(Builder, 3, 1, 2);
    const Document = FDocuments.Open(Builder);

    // The integer is skipped, the null becomes an empty page
    Assert.AreEqual(2, Document.Pages.EnumeratedCount);
    Assert.AreEqual<Single>(612, Document.Pages.Get(1).MediaBox.Width);
    Assert.IsTrue(FDocuments.HasLogLine('replaced null entry'), 'no log line for the null');
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestPageDictionaryAsRootIsRepaired;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Page /MediaBox [0 0 100 200] >>');
  try
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(1, Document.Pages.Count);
    Assert.AreEqual(1, Document.Pages.EnumeratedCount);
    Assert.AreEqual<Single>(200, Document.Pages.Get(0).MediaBox.Height);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestVeryDeepTreeDoesNotOverflowTheStack;
begin
  const Depth = 3000;
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    for var Level := 1 to Depth - 1 do
    begin
      Builder.AddObject(2 + Level, Format('<< /Type /Pages /Parent %d 0 R /Kids [%d 0 R] /Count 1 >>', [1 + Level, 3 + Level]));
    end;
    Builder.AddObject(2 + Depth, Format('<< /Type /Page /Parent %d 0 R /Rotate 90 >>', [1 + Depth]));
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(1, Document.Pages.EnumeratedCount);
    // The /Rotate of the page itself, and an inherited value that is 3000 parents away is out of reach
    Assert.AreEqual(90, Document.Pages.Get(0).Rotation);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestVeryWideTreeIsLinear;
begin
  const Width = 30000;
  const Builder = TModelTestDocuments.NewBuilder(Format('<< /Type /Pages /Kids [%s] /Count %d >>', [KidsOf(3, Width), Width]));
  try
    AddPages(Builder, 3, Width, 2);
    const Document = FDocuments.Open(Builder);

    const Watch = TStopwatch.StartNew;
    var Seen := 0;
    for var Page in Document.Pages do
    begin
      Inc(Seen, Page.Rotation * 0 + 1);
    end;
    Assert.AreEqual(Width, Seen);
    Assert.AreEqual(Width - 1, Document.Pages.IndexOf(Document.Pages.Get(Width - 1).CosObject));
    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestIndexOfFindsPagesAndRaisesForOthers;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');
  try
    AddPages(Builder, 3, 2, 2);
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(0, Document.Pages.IndexOf(Document.Pages.Get(0).CosObject));
    Assert.AreEqual(1, Document.Pages.IndexOf(Document.Pages.Get(1).CosObject));
    Assert.WillRaise(
      procedure
      begin
        Document.Pages.IndexOf(Document.Pages.CosObject);
      end, EPdfParseException);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestGetOutOfRangeRaises;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    AddPages(Builder, 3, 1, 2);
    const Document = FDocuments.Open(Builder);

    Assert.WillRaise(
      procedure
      begin
        Document.Pages.Get(1);
      end, EArgumentOutOfRangeException);
    Assert.WillRaise(
      procedure
      begin
        Document.Pages.Get(-1);
      end, EArgumentOutOfRangeException);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestPagesAreCachedPerIndex;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');
  try
    AddPages(Builder, 3, 2, 2);
    const Document = FDocuments.Open(Builder);

    Assert.AreSame(Document.Pages.Get(1), Document.Pages.Get(1));
    Assert.AreNotSame(Document.Pages.Get(0), Document.Pages.Get(1));
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestEnumerationInTreeOrder;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 3 >>');
  try
    Builder.AddObject(3, '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 2 >>');
    Builder.AddObject(4, '<< /Type /Page /Parent 3 0 R /Rotate 0 >>');
    Builder.AddObject(5, '<< /Type /Page /Parent 3 0 R /Rotate 90 >>');
    Builder.AddObject(6, '<< /Type /Page /Parent 2 0 R /Rotate 180 >>');
    const Document = FDocuments.Open(Builder);

    var Rotations := '';
    for var Page in Document.Pages do
    begin
      Rotations := Rotations + Page.Rotation.ToString + ' ';
    end;
    Assert.AreEqual('0 90 180 ', Rotations);
  finally
    Builder.Free;
  end;
end;

procedure TPageTreeTests.TestSharedSubtreeIsCountedOnce;
begin
  // PDFBox skips a node with /Kids that it has met before
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 3 0 R] /Count 2 >>');
  try
    Builder.AddObject(3, '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R] /Count 1 >>');
    AddPages(Builder, 4, 1, 3);
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual(1, Document.Pages.EnumeratedCount);
  finally
    Builder.Free;
  end;
end;

end.
