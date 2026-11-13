// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Model.Outline.Tests;

interface

uses
  System.SysUtils,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Model.Document,
  Pdf4D.Model.Outline,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TOutlineTests = class
  private
    FDocuments: TModelTestDocuments;

    function OpenOutline(const Builder: TTestPdfBuilder; out Outline: TPDDocumentOutline): TPDDocument;
    // The outline is object 3 with the item 4 as only child, and the item has the /Dest or /A that Entry gives
    function PageIndexOfEntry(const Entry: string; const CatalogExtra: string; out PageIndex: Integer): Boolean;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOutlineNestedWithNamedDest;

    [Test]
    procedure TestOutlineNextCycleTerminates;

    [Test]
    procedure TestFirstChildCycleGivesTheSameObjectsAgain;

    [Test]
    procedure TestExplicitDestinationsGiveThePage;

    [Test]
    procedure TestMalformedDestinationsGiveNoPage;

    [Test]
    procedure TestNamedDestinationsOfTheCatalogDictionary;

    [Test]
    procedure TestBadValueInALeafSpoilsTheLookupsOfThatLeaf;

    [Test]
    procedure TestDestinationClassResolvesWithADictionary;

    [Test]
    procedure TestOpenCountAndTitle;

    [Test]
    procedure TestVeryWideOutlineIsFast;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Model.Destination,
  Pdf4D.Model.OutlineItem;

{ TOutlineTests }

procedure TOutlineTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TOutlineTests.TearDown;
begin
  FDocuments.Free;
end;

function TOutlineTests.OpenOutline(const Builder: TTestPdfBuilder; out Outline: TPDDocumentOutline): TPDDocument;
begin
  Result := FDocuments.Open(Builder);
  Assert.IsTrue(Result.Catalog.TryGetOutline(Outline));
end;

function TOutlineTests.PageIndexOfEntry(const Entry: string; const CatalogExtra: string; out PageIndex: Integer): Boolean;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, '/Outlines 3 0 R ' + CatalogExtra);
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 4 0 R /Count 1 >>');
    Builder.AddObject(4, Format('<< /Title (Item) /Parent 3 0 R %s >>', [Entry]));
    var Outline: TPDDocumentOutline;
    OpenOutline(Builder, Outline);
    var Item: TPDOutlineItem;
    Assert.IsTrue(Outline.TryGetFirstChild(Item));
    Result := Item.TryGetPageIndex(PageIndex);
  finally
    Builder.Free;
  end;
end;

procedure TOutlineTests.TestOutlineNestedWithNamedDest;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, '/Outlines 3 0 R /Names << /Dests 7 0 R >>');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 5 0 R /Count 3 >>');
    Builder.AddObject(4, '<< /Title (Chapter 1) /Parent 3 0 R /Next 5 0 R /Dest [10 0 R /Fit] /First 6 0 R /Last 6 0 R /Count 1 >>');
    Builder.AddObject(5, '<< /Title (Chapter 2) /Parent 3 0 R /Prev 4 0 R /A << /S /GoTo /D [12 0 R /XYZ 0 0 0] >> >>');
    Builder.AddObject(6, '<< /Title (Section 1.1) /Parent 4 0 R /Dest (chap2) >>');
    Builder.AddObject(7, '<< /Names [(chap2) [11 0 R /Fit]] >>');
    var Outline: TPDDocumentOutline;
    OpenOutline(Builder, Outline);

    Assert.IsTrue(Outline.IsNodeOpen);
    Assert.IsTrue(Outline.HasChildren);
    const TopLevel = Outline.Children;
    Assert.AreEqual<Integer>(2, Length(TopLevel));
    Assert.AreEqual('Chapter 1', TopLevel[0].Title);
    Assert.AreEqual('Chapter 2', TopLevel[1].Title);

    var PageIndex: Integer;
    Assert.IsTrue(TopLevel[0].TryGetPageIndex(PageIndex));
    Assert.AreEqual(0, PageIndex);
    // The destination of the action
    Assert.IsTrue(TopLevel[1].TryGetPageIndex(PageIndex));
    Assert.AreEqual(2, PageIndex);

    Assert.IsTrue(TopLevel[0].HasChildren);
    const Nested = TopLevel[0].Children;
    Assert.AreEqual<Integer>(1, Length(Nested));
    Assert.AreEqual('Section 1.1', Nested[0].Title);
    Assert.IsTrue(Nested[0].TryGetPageIndex(PageIndex));
    Assert.AreEqual(1, PageIndex);
    Assert.IsFalse(Nested[0].HasChildren);
    Assert.IsTrue(TopLevel[1].HasChildren = False);

    var Sibling: TPDOutlineItem;
    Assert.IsTrue(TopLevel[0].TryGetNextSibling(Sibling));
    Assert.AreSame(TopLevel[1], Sibling);
    Assert.IsTrue(TopLevel[1].TryGetPreviousSibling(Sibling));
    Assert.AreSame(TopLevel[0], Sibling);
  finally
    Builder.Free;
  end;
end;

procedure TOutlineTests.TestOutlineNextCycleTerminates;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 5 0 R >>');
    Builder.AddObject(4, '<< /Title (A) /Next 5 0 R >>');
    Builder.AddObject(5, '<< /Title (B) /Next 4 0 R >>');
    var Outline: TPDDocumentOutline;
    OpenOutline(Builder, Outline);
    Assert.AreEqual<Integer>(2, Length(Outline.Children));

    // An item that is its own next sibling
    Builder.AddObject(4, '<< /Title (A) /Next 4 0 R >>');
    OpenOutline(Builder, Outline);
    Assert.AreEqual<Integer>(1, Length(Outline.Children));
  finally
    Builder.Free;
  end;
end;

procedure TOutlineTests.TestFirstChildCycleGivesTheSameObjectsAgain;
begin
  // The item 4 has the outline root as first child and the root has item 4: the walk through the tree is the work of the
  // caller, which can see by the identity of the objects that it has been here
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R >>');
    Builder.AddObject(4, '<< /Title (A) /First 4 0 R >>');
    var Outline: TPDDocumentOutline;
    OpenOutline(Builder, Outline);
    const Top = Outline.Children;
    Assert.AreEqual<Integer>(1, Length(Top));
    const Below = Top[0].Children;
    Assert.AreEqual<Integer>(1, Length(Below));
    Assert.AreSame(Top[0], Below[0]);
  finally
    Builder.Free;
  end;
end;

procedure TOutlineTests.TestExplicitDestinationsGiveThePage;
begin
  var PageIndex: Integer;
  Assert.IsTrue(PageIndexOfEntry('/Dest [11 0 R /Fit]', '', PageIndex));
  Assert.AreEqual(1, PageIndex);
  Assert.IsTrue(PageIndexOfEntry('/Dest [12 0 R /FitH 100]', '', PageIndex));
  Assert.AreEqual(2, PageIndex);
  Assert.IsTrue(PageIndexOfEntry('/Dest [10 0 R /XYZ null null null]', '', PageIndex));
  Assert.AreEqual(0, PageIndex);
  // A page number that counts from 0, which PDFBox accepts for a malformed destination
  Assert.IsTrue(PageIndexOfEntry('/Dest [2 /Fit]', '', PageIndex));
  Assert.AreEqual(2, PageIndex);
  Assert.IsTrue(PageIndexOfEntry('/Dest [1.9 /FitB]', '', PageIndex));
  Assert.AreEqual(1, PageIndex);
  // The action of a go to
  Assert.IsTrue(PageIndexOfEntry('/A << /S /GoTo /D [11 0 R /FitR 0 0 1 1] >>', '', PageIndex));
  Assert.AreEqual(1, PageIndex);
  // A /Dest has precedence over an action
  Assert.IsTrue(PageIndexOfEntry('/Dest [10 0 R /Fit] /A << /S /GoTo /D [12 0 R /Fit] >>', '', PageIndex));
  Assert.AreEqual(0, PageIndex);
end;

procedure TOutlineTests.TestMalformedDestinationsGiveNoPage;
begin
  var PageIndex: Integer;
  // No destination, and an action that is no go to
  Assert.IsFalse(PageIndexOfEntry('', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/A << /S /URI /URI (http://x) >>', '', PageIndex));
  // An unknown destination type, an array that is too short, a dictionary, a number
  Assert.IsFalse(PageIndexOfEntry('/Dest [10 0 R /Foo]', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest [10 0 R]', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest << /D [10 0 R /Fit] >>', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest 5', '', PageIndex));
  // A page that is not in the page tree, a page number that is not there, -1 and an empty array
  Assert.IsFalse(PageIndexOfEntry('/Dest [3 0 R /Fit]', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest [7 /Fit]', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest [-1 /Fit]', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest [null /Fit]', '', PageIndex));
  // A name that is nowhere
  Assert.IsFalse(PageIndexOfEntry('/Dest (nowhere)', '', PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest /nowhere', '/Names << /Dests << /Names [] >> >>', PageIndex));
  // A named destination that is a named destination again is not followed
  Assert.IsFalse(PageIndexOfEntry('/Dest (a)', '/Names << /Dests << /Names [(a) (b) (b) [10 0 R /Fit]] >> >>', PageIndex));
end;

procedure TOutlineTests.TestNamedDestinationsOfTheCatalogDictionary;
begin
  var PageIndex: Integer;
  const Dests = '/Dests << /d1 [10 0 R /Fit] /d2 << /D [11 0 R /Fit] >> /d3 << /X 1 >> /d4 (d1) >>';
  Assert.IsTrue(PageIndexOfEntry('/Dest (d1)', Dests, PageIndex));
  Assert.AreEqual(0, PageIndex);
  Assert.IsTrue(PageIndexOfEntry('/Dest /d2', Dests, PageIndex));
  Assert.AreEqual(1, PageIndex);
  Assert.IsFalse(PageIndexOfEntry('/Dest (d3)', Dests, PageIndex));
  Assert.IsFalse(PageIndexOfEntry('/Dest (d4)', Dests, PageIndex));

  // The name tree wins over the dictionary of the catalog, and it is only used with /Names
  const Both = Dests + ' /Names << /Dests << /Names [(d1) [12 0 R /Fit]] >> >>';
  Assert.IsTrue(PageIndexOfEntry('/Dest (d1)', Both, PageIndex));
  Assert.AreEqual(2, PageIndex);
  // A name that the tree does not have is looked for in the dictionary
  Assert.IsTrue(PageIndexOfEntry('/Dest (d2)', Both, PageIndex));
  Assert.AreEqual(1, PageIndex);
  // /Dests of the names dictionary as a tree with a dictionary value
  Assert.IsTrue(PageIndexOfEntry('/Dest (x)', '/Names << /Dests << /Names [(x) << /D [11 0 R /Fit] >>] >> >>', PageIndex));
  Assert.AreEqual(1, PageIndex);
  // /Dests of the catalog as the tree, when /Names has none
  Assert.IsTrue(PageIndexOfEntry('/Dest (x)', '/Names << >> /Dests << /Names [(x) [11 0 R /Fit]] >>', PageIndex));
  Assert.AreEqual(1, PageIndex);
end;

procedure TOutlineTests.TestBadValueInALeafSpoilsTheLookupsOfThatLeaf;
begin
  var PageIndex: Integer;
  // As in PDFBox the values of the whole leaf are converted, and the unknown type raises, so no fallback is tried either
  const Extra = '/Names << /Dests << /Names [(good) [11 0 R /Fit] (bad) [10 0 R /Nope]] >> >> /Dests << /good [12 0 R /Fit] >>';
  Assert.IsFalse(PageIndexOfEntry('/Dest (good)', Extra, PageIndex));
  // A value that is no destination is not spoiling anything: it is no value
  const Extra2 = '/Names << /Dests << /Names [(good) [11 0 R /Fit] (other) (a name)] >> >>';
  Assert.IsTrue(PageIndexOfEntry('/Dest (good)', Extra2, PageIndex));
  Assert.AreEqual(1, PageIndex);
end;

procedure TOutlineTests.TestDestinationClassResolvesWithADictionary;
begin
  const Extra = '/Names << /Dests << /Names [(n) [12 0 R /Fit]] >> >> /T1 3 0 R /T2 4 0 R /T3 5 0 R /T4 6 0 R /T5 7 0 R /T6 8 0 R';
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, Extra);
  try
    Builder.AddObject(3, '[11 0 R /Fit]');
    Builder.AddObject(4, '<< /D [12 0 R /Fit] >>');
    Builder.AddObject(5, '(n)');
    Builder.AddObject(6, '<< /D (n) >>');
    Builder.AddObject(7, '/n');
    Builder.AddObject(8, '<< /X 1 >>');
    const Document = FDocuments.Open(Builder);

    var PageIndex: Integer;
    var Value: TCosBase;
    Assert.IsTrue(Document.Catalog.CosObject.TryGetDictionaryObject('T1', Value));
    Assert.IsTrue(TPDDestination.TryResolvePageIndex(Document, Value, PageIndex));
    Assert.AreEqual(1, PageIndex);
    Assert.IsTrue(Document.Catalog.CosObject.TryGetDictionaryObject('T2', Value));
    Assert.IsTrue(TPDDestination.TryResolvePageIndex(Document, Value, PageIndex));
    Assert.AreEqual(2, PageIndex);
    Assert.IsTrue(Document.Catalog.CosObject.TryGetDictionaryObject('T3', Value));
    Assert.IsTrue(TPDDestination.TryResolvePageIndex(Document, Value, PageIndex));
    Assert.AreEqual(2, PageIndex);
    Assert.IsTrue(Document.Catalog.CosObject.TryGetDictionaryObject('T4', Value));
    Assert.IsTrue(TPDDestination.TryResolvePageIndex(Document, Value, PageIndex));
    Assert.AreEqual(2, PageIndex);
    Assert.IsTrue(Document.Catalog.CosObject.TryGetDictionaryObject('T5', Value));
    Assert.IsTrue(TPDDestination.TryResolvePageIndex(Document, Value, PageIndex));
    Assert.AreEqual(2, PageIndex);
    Assert.IsTrue(Document.Catalog.CosObject.TryGetDictionaryObject('T6', Value));
    Assert.IsFalse(TPDDestination.TryResolvePageIndex(Document, Value, PageIndex));
    Assert.IsFalse(TPDDestination.TryResolvePageIndex(Document, nil, PageIndex));
  finally
    Builder.Free;
  end;
end;

procedure TOutlineTests.TestOpenCountAndTitle;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 5 0 R /Count 2 >>');
    Builder.AddObject(4, '<< /Title <FEFF00E4> /Count 3 /Next 5 0 R >>');
    Builder.AddObject(5, '<< /Count -2 >>');
    var Outline: TPDDocumentOutline;
    OpenOutline(Builder, Outline);
    const Items = Outline.Children;
    Assert.AreEqual(#$00E4, Items[0].Title);
    Assert.AreEqual(3, Items[0].GetOpenCount);
    Assert.IsTrue(Items[0].IsNodeOpen);
    Assert.AreEqual(-2, Items[1].GetOpenCount);
    Assert.IsFalse(Items[1].IsNodeOpen);
    var Title: string;
    Assert.IsFalse(Items[1].TryGetTitle(Title));
    Assert.AreEqual('', Items[1].Title);
    var Last: TPDOutlineItem;
    Assert.IsTrue(Outline.TryGetLastChild(Last));
    Assert.AreSame(Items[1], Last);
  finally
    Builder.Free;
  end;
end;

procedure TOutlineTests.TestVeryWideOutlineIsFast;
begin
  const Count = 20000;
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '/Outlines 100 0 R /Names << /Dests 101 0 R >>');
  const Names = TStringBuilder.Create;
  try
    Builder.AddObject(100, Format('<< /Type /Outlines /First 102 0 R /Last %d 0 R >>', [102 + Count - 1]));
    Names.Append('<< /Names [');
    for var Index := 0 to Count - 1 do
    begin
      Names.AppendFormat('(d%.6d) [%d 0 R /Fit] ', [Index, 10 + (Index mod 2)]);
      var Next := '';
      if Index + 1 < Count then
      begin
        Next := Format('/Next %d 0 R', [103 + Index]);
      end;
      Builder.AddObject(102 + Index, Format('<< /Title (T%d) /Dest (d%.6d) %s >>', [Index, Index, Next]));
    end;
    Names.Append('] >>');
    Builder.AddObject(101, Names.ToString);

    const Watch = TStopwatch.StartNew;
    var Outline: TPDDocumentOutline;
    OpenOutline(Builder, Outline);
    var Seen := 0;
    var Resolved := 0;
    for var Item in Outline do
    begin
      var PageIndex: Integer;
      if Item.TryGetPageIndex(PageIndex) and (PageIndex = (Seen mod 2)) then
      begin
        Inc(Resolved);
      end;
      Inc(Seen);
    end;
    Assert.AreEqual(Count, Seen);
    Assert.AreEqual(Count, Resolved);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Names.Free;
    Builder.Free;
  end;
end;

end.
