unit Pdf4D.Model.NameTree.Tests;

interface

uses
  System.SysUtils,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.NameTree,
  Pdf4D.Model.NumberTree,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TNameTreeTests = class
  private
    FDocuments: TModelTestDocuments;

    // The tree is object 3, in /Names /Dests
    function OpenTree(const Builder: TTestPdfBuilder): TCosDictionary;
    // The caller owns the tree
    function NewTree(const Builder: TTestPdfBuilder): TPDNameTreeNode;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNameTreeLookupThroughKids;

    [Test]
    procedure TestNameTreeCycleTerminates;

    [Test]
    procedure TestGetAllKeepsTheOrderOfTheTree;

    [Test]
    procedure TestNodeWithKidsAndNamesIsFoundByNamesAndListedByKids;

    [Test]
    procedure TestDuplicateKeyKeepsItsPlaceAndTakesTheLastValue;

    [Test]
    procedure TestKeyThatIsNoStringRaises;

    [Test]
    procedure TestKeysAreComparedAsText;

    [Test]
    procedure TestBadKidIsSkippedByGetAll;

    [Test]
    procedure TestVeryDeepTreeDoesNotOverflowTheStack;

    [Test]
    procedure TestManyLookupsInAWideLeafAreFast;
  end;

  [TestFixture]
  TNumberTreeTests = class
  private
    FDocuments: TModelTestDocuments;

    // The tree is object 3, as /PageLabels
    function OpenTree(const Builder: TTestPdfBuilder): TCosDictionary;
    // The caller owns the tree
    function NewTree(const Builder: TTestPdfBuilder): TPDNumberTreeNode;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNumberTreeLookupThroughKids;

    [Test]
    procedure TestNumberTreeCycleTerminates;

    [Test]
    procedure TestGetAllKeepsTheOrderOfTheTree;

    [Test]
    procedure TestLeafWithKeyThatIsNoIntegerIsLeftOut;

    [Test]
    procedure TestKidWithoutLimitsRaisesInLookup;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names;

{ TNameTreeTests }

procedure TNameTreeTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TNameTreeTests.TearDown;
begin
  FDocuments.Free;
end;

function TNameTreeTests.OpenTree(const Builder: TTestPdfBuilder): TCosDictionary;
begin
  var Names: TCosDictionary;
  Assert.IsTrue(FDocuments.Open(Builder).Catalog.TryGetNames(Names));
  Assert.IsTrue(Names.TryGetCosDictionary(TCosNames.Dests, Result));
end;

function TNameTreeTests.NewTree(const Builder: TTestPdfBuilder): TPDNameTreeNode;
begin
  // The root is found first: the document that gives the log is opened by it
  const Root = OpenTree(Builder);
  Result := TPDNameTreeNode.Create(Root, nil, FDocuments.Document.CosDocument.Log);
end;

procedure TNameTreeTests.TestNameTreeLookupThroughKids;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(4, '<< /Limits [(a) (m)] /Names [(a) 10 (k) 11] >>');
    Builder.AddObject(5, '<< /Limits [(n) (z)] /Names [(p) 12 (z) 13] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.IsTrue(Tree.TryGetValue('k', Value));
      Assert.AreEqual(Int64(11), TCosInteger(Value).Value);
      Assert.IsTrue(Tree.TryGetValue('z', Value));
      Assert.AreEqual(Int64(13), TCosInteger(Value).Value);
      Assert.IsTrue(Tree.TryGetValue('a', Value));
      Assert.AreEqual(Int64(10), TCosInteger(Value).Value);
      // Inside the limits of a leaf, but not in it, and outside all limits
      Assert.IsFalse(Tree.TryGetValue('b', Value));
      Assert.IsFalse(Tree.TryGetValue('~', Value));
      Assert.IsFalse(Tree.TryGetValue('', Value));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestNameTreeCycleTerminates;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Kids [3 0 R 4 0 R] >>');
    Builder.AddObject(4, '<< /Kids [3 0 R 5 0 R] >>');
    Builder.AddObject(5, '<< /Kids [4 0 R] /Names [(a) 1] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.IsFalse(Tree.TryGetValue('a', Value));
      Assert.AreEqual<Integer>(0, Length(Tree.GetAll));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestGetAllKeepsTheOrderOfTheTree;
begin
  // Not sorted: the second kid has names that are smaller than those of the first
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(4, '<< /Names [(m) 1 (z) 2] >>');
    Builder.AddObject(5, '<< /Names [(b) 3 (a) 4] >>');
    const Tree = NewTree(Builder);
    try
      const All = Tree.GetAll;
      Assert.AreEqual<Integer>(4, Length(All));
      Assert.AreEqual('m', All[0].Key);
      Assert.AreEqual('z', All[1].Key);
      Assert.AreEqual('b', All[2].Key);
      Assert.AreEqual('a', All[3].Key);
      Assert.AreEqual(Int64(4), TCosInteger(All[3].Value).Value);
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestNodeWithKidsAndNamesIsFoundByNamesAndListedByKids;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Names [(own) 1] /Kids [4 0 R] >>');
    Builder.AddObject(4, '<< /Names [(kid) 2] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      // PDFBox.getValue looks at the /Names of a node first, the walk of the oracle at the /Kids
      Assert.IsTrue(Tree.TryGetValue('own', Value));
      Assert.IsFalse(Tree.TryGetValue('kid', Value));
      const All = Tree.GetAll;
      Assert.AreEqual<Integer>(1, Length(All));
      Assert.AreEqual('kid', All[0].Key);
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestDuplicateKeyKeepsItsPlaceAndTakesTheLastValue;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Names [(a) 1 (b) 2 (a) 3] >>');
    const Tree = NewTree(Builder);
    try
      const All = Tree.GetAll;
      Assert.AreEqual<Integer>(2, Length(All));
      Assert.AreEqual('a', All[0].Key);
      Assert.AreEqual(Int64(3), TCosInteger(All[0].Value).Value);
      var Value: TCosBase;
      Assert.IsTrue(Tree.TryGetValue('a', Value));
      Assert.AreEqual(Int64(3), TCosInteger(Value).Value);
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestKeyThatIsNoStringRaises;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Names [(a) 1 7 2] >>');
    const Tree = NewTree(Builder);
    try
      Assert.WillRaiseDescendant(
        procedure
        begin
          Tree.GetAll;
        end, EPdfParseException);

      var Value: TCosBase;
      Assert.WillRaiseDescendant(
        procedure
        begin
          Tree.TryGetValue('a', Value);
        end, EPdfParseException);
      // The failure is remembered, and is the same the next time
      Assert.WillRaiseDescendant(
        procedure
        begin
          Tree.TryGetValue('a', Value);
        end, EPdfParseException);
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestKeysAreComparedAsText;
begin
  // The key is a UTF-16BE string with a byte order mark, and is the same text as the name that is asked for
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R] >>');
    Builder.AddObject(4, '<< /Limits [<FEFF00E4> <FEFF00E4>] /Names [<FEFF00E4> 5] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.IsTrue(Tree.TryGetValue(#$00E4, Value));
      Assert.AreEqual(Int64(5), TCosInteger(Value).Value);
      Assert.IsFalse(Tree.TryGetValue('a', Value));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestBadKidIsSkippedByGetAll;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Kids [7 4 0 R] >>');
    Builder.AddObject(4, '<< /Names [(a) 1] >>');
    const Tree = NewTree(Builder);
    try
      Assert.AreEqual<Integer>(1, Length(Tree.GetAll));
      // The first kid has no limits, so it is the one that is followed, and it is no node
      var Value: TCosBase;
      Assert.IsFalse(Tree.TryGetValue('a', Value));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestVeryDeepTreeDoesNotOverflowTheStack;
begin
  const Depth = 3000;
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 100 0 R >>');
  try
    for var Number := 0 to Depth - 1 do
    begin
      Builder.AddObject(100 + Number, Format('<< /Kids [%d 0 R] >>', [101 + Number]));
    end;
    Builder.AddObject(100 + Depth, '<< /Names [(deep) 1] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.IsFalse(Tree.TryGetValue('deep', Value));
      Assert.AreEqual<Integer>(0, Length(Tree.GetAll));
      Assert.IsTrue(FDocuments.HasLogLine('too deep'));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNameTreeTests.TestManyLookupsInAWideLeafAreFast;
begin
  const Count = 20000;
  const Names = TStringBuilder.Create;
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /Dests 3 0 R >>');
  try
    Names.Append('<< /Names [');
    for var Index := 0 to Count - 1 do
    begin
      Names.AppendFormat('(n%.6d) %d ', [Index, Index]);
    end;
    Names.Append('] >>');
    Builder.AddObject(3, Names.ToString);
    const Tree = NewTree(Builder);
    try
      const Watch = TStopwatch.StartNew;
      var Value: TCosBase;
      for var Index := 0 to Count - 1 do
      begin
        Assert.IsTrue(Tree.TryGetValue(Format('n%.6d', [Index]), Value));
      end;
      Assert.IsTrue(Watch.ElapsedMilliseconds < 3000, Format('%d ms', [Watch.ElapsedMilliseconds]));
      Assert.AreEqual<Integer>(Count, Length(Tree.GetAll));
    finally
      Tree.Free;
    end;
  finally
    Names.Free;
    Builder.Free;
  end;
end;

{ TNumberTreeTests }

procedure TNumberTreeTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TNumberTreeTests.TearDown;
begin
  FDocuments.Free;
end;

function TNumberTreeTests.OpenTree(const Builder: TTestPdfBuilder): TCosDictionary;
begin
  Assert.IsTrue(FDocuments.Open(Builder).Catalog.TryGetPageLabels(Result));
end;

function TNumberTreeTests.NewTree(const Builder: TTestPdfBuilder): TPDNumberTreeNode;
begin
  const Root = OpenTree(Builder);
  Result := TPDNumberTreeNode.Create(Root, nil, FDocuments.Document.CosDocument.Log);
end;

procedure TNumberTreeTests.TestNumberTreeLookupThroughKids;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/PageLabels 3 0 R');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(4, '<< /Limits [0 9] /Nums [0 100 5 101] >>');
    Builder.AddObject(5, '<< /Limits [10 99] /Nums [10 102 50 103] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.IsTrue(Tree.TryGetValue(5, Value));
      Assert.AreEqual(Int64(101), TCosInteger(Value).Value);
      Assert.IsTrue(Tree.TryGetValue(50, Value));
      Assert.AreEqual(Int64(103), TCosInteger(Value).Value);
      Assert.IsFalse(Tree.TryGetValue(7, Value));
      Assert.IsFalse(Tree.TryGetValue(500, Value));
      Assert.IsFalse(Tree.TryGetValue(-1, Value));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNumberTreeTests.TestNumberTreeCycleTerminates;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/PageLabels 3 0 R');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 4 0 R] >>');
    Builder.AddObject(4, '<< /Limits [0 9] /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(5, '<< /Limits [0 9] /Kids [4 0 R 3 0 R] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.IsFalse(Tree.TryGetValue(1, Value));
      Assert.AreEqual<Integer>(0, Length(Tree.GetAll));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNumberTreeTests.TestGetAllKeepsTheOrderOfTheTree;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/PageLabels 3 0 R');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(4, '<< /Nums [8 1 2 2] >>');
    Builder.AddObject(5, '<< /Nums [0 3 2 4] >>');
    const Tree = NewTree(Builder);
    try
      const All = Tree.GetAll;
      Assert.AreEqual<Integer>(4, Length(All));
      Assert.AreEqual(8, All[0].Key);
      Assert.AreEqual(2, All[1].Key);
      Assert.AreEqual(0, All[2].Key);
      Assert.AreEqual(2, All[3].Key);
      Assert.AreEqual(Int64(4), TCosInteger(All[3].Value).Value);
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNumberTreeTests.TestLeafWithKeyThatIsNoIntegerIsLeftOut;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/PageLabels 3 0 R');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(4, '<< /Nums [0 1 2.5 2] >>');
    Builder.AddObject(5, '<< /Nums [3 3] >>');
    const Tree = NewTree(Builder);
    try
      const All = Tree.GetAll;
      Assert.AreEqual<Integer>(1, Length(All));
      Assert.AreEqual(3, All[0].Key);
      Assert.IsTrue(FDocuments.HasLogLine('page labels ignored'));
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TNumberTreeTests.TestKidWithoutLimitsRaisesInLookup;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/PageLabels 3 0 R');
  try
    Builder.AddObject(3, '<< /Kids [4 0 R] >>');
    Builder.AddObject(4, '<< /Nums [0 1] >>');
    const Tree = NewTree(Builder);
    try
      var Value: TCosBase;
      Assert.WillRaiseDescendant(
        procedure
        begin
          Tree.TryGetValue(0, Value);
        end, EPdfParseException);
    finally
      Tree.Free;
    end;
  finally
    Builder.Free;
  end;
end;

end.
