unit Pdf4D.Parser.Xref.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Parser.Xref,
  Pdf4D.Parser.XrefTrailerResolver,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TXrefParserTests = class
  private
    FDocument: TCosDocument;
    FResolver: TXrefTrailerResolver;
    FParser: TXrefParser;
    FLogLines: TList<string>;

    function Ascii(const Text: string): TBytes;
    function TextOf(const Data: TBytes): string;
    function ThreeObjectBuilder: TTestPdfBuilder;
    procedure OpenFile(const Data: TBytes);
    function ParseOpened: TCosDictionary;
    function ParseFile(const Data: TBytes): TCosDictionary;
    function XrefCount: Integer;
    function OffsetInTable(const Number: Int64; const Generation: Integer = 0): Int64;
    function HasLogLine(const Fragment: string): Boolean;
    function RawXrefStreamFile(const Dictionary: string; const Data: TBytes): TBytes;
    function SingleObjectHead: string;
    function SingleObjectTable: string;
    procedure AssertParseRaises(const Data: TBytes);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestParsesClassicXrefTable;

    [Test]
    procedure TestTrailerIsCopiedToTheDocument;

    [Test]
    [TestCase('Plain', '0')]
    [TestCase('Flate', '1')]
    [TestCase('FlateWithPredictor', '2')]
    procedure TestParsesXrefStreamWithIndex(const FilterOrdinal: Integer);

    [Test]
    procedure TestParsesXrefStreamWithDefaultIndex;

    [Test]
    procedure TestXrefStreamMarksObjectStreamEntries;

    [Test]
    [TestCase('Table', '0')]
    [TestCase('Stream', '1')]
    procedure TestIncrementalUpdateOverridesOlderEntry(const StyleOrdinal: Integer);

    [Test]
    procedure TestIncrementalUpdateKeepsTrailerEntriesOfTheOlderSection;

    [Test]
    procedure TestHybridFileUsesXrefStm;

    [Test]
    procedure TestPrevCycleTerminates;

    [Test]
    procedure TestPrevChainOfTwoSectionsLoopTerminates;

    [Test]
    procedure TestXrefTableWithWrongEntryLength;

    [Test]
    procedure TestXrefTableWithCarriageReturnEntries;

    [Test]
    procedure TestXrefTableEntriesWithOffsetZeroAreSkipped;

    [Test]
    procedure TestStartXrefFinderUsesTheLastMarker;

    [Test]
    procedure TestStartXrefFinderRaisesWithoutMarker;

    [Test]
    procedure TestWrongStartXrefOffsetUsesSearchHook;

    [Test]
    procedure TestWrongStartXrefOffsetWithoutSearchGivesEmptyTable;

    [Test]
    procedure TestWrongPrevOffsetIsFixedAndWritten;

    [Test]
    procedure TestXrefStreamWithoutWRaises;

    [Test]
    procedure TestXrefStreamWithWrongNumberOfWidthsRaises;

    [Test]
    procedure TestXrefStreamWithHugeWidthsRaises;

    [Test]
    procedure TestXrefStreamWithNegativeWidthRaises;

    [Test]
    procedure TestXrefStreamWithOddIndexRaises;

    [Test]
    procedure TestXrefStreamWithNonIntegerIndexRaises;

    [Test]
    procedure TestXrefStreamWithHugeSizeReadsOnlyTheData;

    [Test]
    procedure TestXrefStreamWithoutFieldWidthsReadsNothing;

    [Test]
    procedure TestXrefStreamIndexThatOverflowsDoesNotWrap;

    [Test]
    procedure TestXrefStreamWithTruncatedLastEntryIgnoresIt;

    [Test]
    procedure TestXrefStreamWithNegativeCountInIndex;

    [Test]
    procedure TestXrefStreamWithWrongLengthIsRead;

    [Test]
    procedure TestHybridWithDamagedXRefStmIsOnlyLogged;

    [Test]
    procedure TestHybridWithWrongXRefStmIsOnlyLogged;

    [Test]
    procedure TestTableWithUnparsableSubsectionHeaderRaises;

    [Test]
    procedure TestPrevFarBeyondTheFileEndsTheChain;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray;

const
  CatalogBody = '<< /Type /Catalog /Pages 2 0 R >>';
  PagesBody = '<< /Type /Pages /Count 0 /Kids [] >>';
  TableMarker = 'xref'#10'0 4';

{ TXrefParserTests }

procedure TXrefParserTests.Setup;
begin
  FLogLines := TList<string>.Create;
end;

procedure TXrefParserTests.TearDown;
begin
  FreeAndNil(FParser);
  FreeAndNil(FResolver);
  FreeAndNil(FDocument);
  FLogLines.Free;
end;

function TXrefParserTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function TXrefParserTests.TextOf(const Data: TBytes): string;
begin
  Result := '';
  for var Value in Data do
  begin
    Result := Result + Char(Value);
  end;
end;

function TXrefParserTests.ThreeObjectBuilder: TTestPdfBuilder;
begin
  Result := TTestPdfBuilder.Create;
  Result.AddObject(1, CatalogBody);
  Result.AddObject(2, PagesBody);
  Result.AddObject(3, '<< /Kind /Third >>');
  Result.SetRoot(1);
end;

procedure TXrefParserTests.OpenFile(const Data: TBytes);
begin
  var Options := TPdfLoadOptions.Default;
  Options.OnLog := procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;

  FDocument := TCosDocument.Create(TRandomAccessRead.FromBytes(Data), Options);
  FResolver := TXrefTrailerResolver.Create(FDocument.Log);
  FParser := TXrefParser.Create(FResolver);
end;

function TXrefParserTests.ParseOpened: TCosDictionary;
begin
  const StartXrefOffset = TXrefParser.FindStartXrefOffset(FDocument.Source);
  Result := FParser.ParseXref(FDocument, StartXrefOffset);
end;

function TXrefParserTests.ParseFile(const Data: TBytes): TCosDictionary;
begin
  OpenFile(Data);
  Result := ParseOpened;
end;

function TXrefParserTests.XrefCount: Integer;
begin
  Result := Integer(FDocument.XrefTable.Count);
end;

function TXrefParserTests.OffsetInTable(const Number: Int64; const Generation: Integer): Int64;
begin
  if not FDocument.XrefTable.TryGetValue(TCosObjectKey.Make(Number, Generation), Result) then
  begin
    Assert.Fail(Format('Object %d %d is not in the xref table', [Number, Generation]));
  end;
end;

function TXrefParserTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLogLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Exit(True);
    end;
  end;
end;

// A file of one xref stream object at offset 9, with the entries in Data and Dictionary as its dictionary
function TXrefParserTests.RawXrefStreamFile(const Dictionary: string; const Data: TBytes): TBytes;
begin
  const Head = Ascii(Format('%%PDF-1.7'#10'1 0 obj'#10'<< /Type /XRef %s /Length %d >>'#10'stream'#10, [Dictionary, Length(Data)]));
  const Tail = Ascii(#10'endstream'#10'endobj'#10'startxref'#10'9'#10'%%EOF'#10);
  Result := Head + Data + Tail;
end;

function TXrefParserTests.SingleObjectHead: string;
begin
  Result := '%PDF-1.4'#10'1 0 obj'#10'<< /Type /Catalog >>'#10'endobj'#10;
end;

// The table for the head of SingleObjectHead: a free entry and object 1 at offset 9
function TXrefParserTests.SingleObjectTable: string;
begin
  Result := 'xref'#10'0 2'#10'0000000000 65535 f '#10'0000000009 00000 n '#10;
end;

procedure TXrefParserTests.AssertParseRaises(const Data: TBytes);
begin
  Assert.WillRaise(
    procedure
    begin
      ParseFile(Data);
    end,
    EPdfParseException);
end;

procedure TXrefParserTests.TestParsesClassicXrefTable;
begin
  const Builder = ThreeObjectBuilder;
  try
    ParseFile(Builder.Build(TXrefStyle.Table));

    for var Number := 1 to 3 do
    begin
      Assert.AreEqual(Builder.OffsetOf(Number), OffsetInTable(Number), Format('offset of object %d', [Number]));
    end;
    Assert.AreEqual(3, XrefCount, 'free entries are not in the table');
    Assert.IsFalse(FParser.IsXRefStream);
    Assert.AreEqual<Int64>(3, FParser.HighestXRefObjectNumber);
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestTrailerIsCopiedToTheDocument;
begin
  const Builder = ThreeObjectBuilder;
  try
    Builder.TrailerExtra := '/Info 3 0 R /ID [<AA> <BB>] /Nested << /A [1 2.5 (x)] >>';

    const Trailer = ParseFile(Builder.Build(TXrefStyle.Table));

    Assert.AreSame(FDocument.Trailer, Trailer);
    Assert.AreEqual(4, Trailer.GetInt(TCosNames.Size, 0));
    Assert.IsTrue(Trailer.ContainsKey(TCosNames.Root));
    Assert.IsTrue(Trailer.ContainsKey('Info'));
    var IdArray: TCosArray;
    Assert.IsTrue(Trailer.TryGetCosArray('ID', IdArray));
    Assert.AreEqual(2, IdArray.Count);
    var Nested: TCosDictionary;
    Assert.IsTrue(Trailer.TryGetCosDictionary('Nested', Nested));
    var Inner: TCosArray;
    Assert.IsTrue(Nested.TryGetCosArray('A', Inner));
    Assert.AreEqual(3, Inner.Count);
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestParsesXrefStreamWithIndex(const FilterOrdinal: Integer);
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(5, CatalogBody);
    Builder.AddObject(6, PagesBody);
    Builder.SetRoot(5);
    Builder.Widths := [1, 2, 1];
    Builder.Index := [0, 1, 5, 2];
    Builder.XrefStreamNumber := 7;
    Builder.XrefStreamFilter := TStreamFilter(FilterOrdinal);

    ParseFile(Builder.Build(TXrefStyle.Stream));

    Assert.AreEqual(Builder.OffsetOf(5), OffsetInTable(5));
    Assert.AreEqual(Builder.OffsetOf(6), OffsetInTable(6));
    Assert.AreEqual(2, XrefCount, 'only the objects of /Index, without the free entry');
    Assert.IsTrue(FParser.IsXRefStream);
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestParsesXrefStreamWithDefaultIndex;
begin
  const Builder = ThreeObjectBuilder;
  try
    ParseFile(Builder.Build(TXrefStyle.Stream));

    for var Number := 1 to 3 do
    begin
      Assert.AreEqual(Builder.OffsetOf(Number), OffsetInTable(Number));
    end;
    Assert.AreEqual(Builder.OffsetOf(4), OffsetInTable(4), 'the xref stream lists itself');
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestXrefStreamMarksObjectStreamEntries;
begin
  const Builder = ThreeObjectBuilder;
  try
    Builder.AddCompressedObject(10, '<< /A 1 >>', 12);
    Builder.AddCompressedObject(11, '<< /B 2 >>', 12);

    ParseFile(Builder.Build(TXrefStyle.Stream));

    Assert.AreEqual<Int64>(-12, OffsetInTable(10));
    Assert.AreEqual<Int64>(-12, OffsetInTable(11));
    Assert.AreEqual(Builder.OffsetOf(12), OffsetInTable(12));

    var StreamIndexOf11 := -1;
    for var Entry in FDocument.XrefTable do
    begin
      if Entry.Key.Number = 11 then
      begin
        StreamIndexOf11 := Entry.Key.StreamIndex;
      end;
    end;
    Assert.AreEqual(1, StreamIndexOf11, 'the index in the object stream is kept in the key');
    Assert.AreEqual<Integer>(2, Integer(Length(FResolver.GetContainedObjectNumbers(12))));
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestIncrementalUpdateOverridesOlderEntry(const StyleOrdinal: Integer);
begin
  const Style = TXrefStyle(StyleOrdinal);
  const Base = ThreeObjectBuilder;
  const Update = TTestPdfBuilder.Create;
  try
    const BaseData = Base.Build(Style);
    Update.AddObject(2, '<< /Type /Pages /Count 1 /Kids [] >>');
    Update.SetRoot(1);
    Update.MinimumSize := 6;
    // The base has the xref stream as object 4: the update must not use a number that exists
    Update.XrefStreamNumber := 5;

    ParseFile(Update.AppendIncrementalUpdate(BaseData, Style));

    Assert.AreEqual(Update.OffsetOf(2), OffsetInTable(2), 'the update wins');
    Assert.IsTrue(Update.OffsetOf(2) > Base.OffsetOf(2));
    Assert.AreEqual(Base.OffsetOf(1), OffsetInTable(1), 'untouched objects stay');
    Assert.AreEqual(Base.OffsetOf(3), OffsetInTable(3));
  finally
    Update.Free;
    Base.Free;
  end;
end;

procedure TXrefParserTests.TestIncrementalUpdateKeepsTrailerEntriesOfTheOlderSection;
begin
  const Base = ThreeObjectBuilder;
  const Update = TTestPdfBuilder.Create;
  try
    Base.TrailerExtra := '/Info 3 0 R';
    const BaseData = Base.Build(TXrefStyle.Table);
    Update.AddObject(2, PagesBody);
    Update.MinimumSize := 4;

    const Trailer = ParseFile(Update.AppendIncrementalUpdate(BaseData, TXrefStyle.Table));

    Assert.IsTrue(Trailer.ContainsKey('Info'), 'the Info of the older trailer');
    Assert.IsTrue(Trailer.ContainsKey(TCosNames.Root), 'the Root of the older trailer');
  finally
    Update.Free;
    Base.Free;
  end;
end;

procedure TXrefParserTests.TestHybridFileUsesXrefStm;
begin
  const Builder = ThreeObjectBuilder;
  try
    Builder.AddCompressedObject(10, '<< /A 1 >>', 12);

    ParseFile(Builder.Build(TXrefStyle.Hybrid));

    Assert.AreEqual(Builder.OffsetOf(1), OffsetInTable(1));
    Assert.AreEqual<Int64>(-12, OffsetInTable(10), 'the compressed object comes from the xref stream');
    Assert.IsTrue(FParser.HasHybridXRef);
    Assert.IsFalse(FParser.IsXRefStream, 'the table is the main section');
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestPrevCycleTerminates;
begin
  const Builder = ThreeObjectBuilder;
  try
    const TableOffset = TextOf(Builder.Build(TXrefStyle.Table)).IndexOf(TableMarker);
    Assert.IsTrue(TableOffset > 0);
    Builder.TrailerExtra := Format('/Prev %d', [TableOffset]);

    AssertParseRaises(Builder.Build(TXrefStyle.Table));
    Assert.IsTrue(HasLogLine('/Prev loop'), 'a warning is logged');
  finally
    Builder.Free;
  end;
end;

// Two sections that point to each other, with offsets of fixed width so that the text does not move
procedure TXrefParserTests.TestPrevChainOfTwoSectionsLoopTerminates;
begin
  const SectionFormat = 'xref'#10'0 2'#10'0000000000 65535 f '#10'0000000009 00000 n '#10'trailer'#10'<< /Size 2 /Root 1 0 R /Prev %.10d >>'#10;
  const Head = SingleObjectHead;
  const FirstOffset = Length(Head);
  const SecondOffset = FirstOffset + Length(Format(SectionFormat, [0]));
  const Sections = Format(SectionFormat, [SecondOffset]) + Format(SectionFormat, [FirstOffset]);

  AssertParseRaises(Ascii(Head + Sections + Format('startxref'#10'%d'#10'%%EOF', [SecondOffset])));

  Assert.IsTrue(HasLogLine('/Prev loop'));
end;

procedure TXrefParserTests.TestXrefTableWithWrongEntryLength;
begin
  const Head = '%PDF-1.4'#10;
  const Object1 = '1 0 obj'#10'<< /Type /Catalog >>'#10'endobj'#10;
  const Object2 = '2 0 obj'#10'<< /A 1 >>'#10'endobj'#10;
  const Offset1 = Length(Head);
  const Offset2 = Offset1 + Length(Object1);
  const XrefOffset = Offset2 + Length(Object2);
  // 19 bytes per entry: no space before the line feed
  const Table = Format('xref'#10'0 3'#10'0000000000 65535 f'#10'%.10d 00000 n'#10'%.10d 00000 n'#10, [Offset1, Offset2]);
  const Trailer = Format('trailer'#10'<< /Size 3 /Root 1 0 R >>'#10'startxref'#10'%d'#10'%%EOF', [XrefOffset]);

  ParseFile(Ascii(Head + Object1 + Object2 + Table + Trailer));

  Assert.AreEqual<Int64>(Offset1, OffsetInTable(1));
  Assert.AreEqual<Int64>(Offset2, OffsetInTable(2));
end;

procedure TXrefParserTests.TestXrefTableWithCarriageReturnEntries;
begin
  const Head = SingleObjectHead;
  const Table = 'xref'#13'0 2'#13'0000000000 65535 f'#13#10'0000000009 00000 n'#13#10;
  const Trailer = Format('trailer'#13'<< /Size 2 /Root 1 0 R >>'#13'startxref'#13'%d'#13'%%EOF', [Length(Head)]);

  ParseFile(Ascii(Head + Table + Trailer));

  Assert.AreEqual<Int64>(9, OffsetInTable(1));
end;

procedure TXrefParserTests.TestXrefTableEntriesWithOffsetZeroAreSkipped;
begin
  const Head = SingleObjectHead;
  const Table = 'xref'#10'0 3'#10'0000000000 65535 f '#10'0000000000 00000 n '#10'0000000009 00000 n '#10;
  const Trailer = Format('trailer'#10'<< /Size 3 /Root 1 0 R >>'#10'startxref'#10'%d'#10'%%EOF', [Length(Head)]);

  ParseFile(Ascii(Head + Table + Trailer));

  Assert.AreEqual(1, XrefCount);
  Assert.AreEqual<Int64>(9, OffsetInTable(2));
end;

procedure TXrefParserTests.TestStartXrefFinderUsesTheLastMarker;
begin
  const Text = 'startxref'#10'1'#10'%%EOF'#10'junk startxref'#10'22'#10'%%EOF'#10'trailing';
  const Source = TRandomAccessRead.FromBytes(Ascii(Text));
  try
    const Offset = TXrefParser.FindStartXrefOffset(Source);

    Assert.AreEqual<Int64>(Text.LastIndexOf('startxref'), Offset);
    Assert.AreEqual<Int64>(0, Source.GetPosition, 'the source is rewound');
  finally
    Source.Free;
  end;
end;

procedure TXrefParserTests.TestStartXrefFinderRaisesWithoutMarker;
begin
  const Source = TRandomAccessRead.FromBytes(Ascii('%PDF-1.4 no marker here'));
  try
    var Raised := False;
    try
      TXrefParser.FindStartXrefOffset(Source);
    except
      on EPdfParseException do
      begin
        Raised := True;
      end;
    end;
    Assert.IsTrue(Raised);
  finally
    Source.Free;
  end;
end;

procedure TXrefParserTests.TestWrongStartXrefOffsetUsesSearchHook;
begin
  const Builder = ThreeObjectBuilder;
  try
    const Text = TextOf(Builder.Build(TXrefStyle.Table));
    const TableOffset = Text.IndexOf(TableMarker);
    Assert.IsTrue(TableOffset > 0);
    // The startxref value is 3 bytes too small, and the hook knows where the table is
    const Broken = Ascii(Text.Replace(Format('startxref'#10'%d', [TableOffset]), Format('startxref'#10'%d', [TableOffset - 3])));

    var SearchedFor: Int64 := -1;
    OpenFile(Broken);
    FParser.OnSearchXRef :=
      function(const ExpectedOffset: Int64): Int64
      begin
        SearchedFor := ExpectedOffset;
        Result := TableOffset;
      end;

    ParseOpened;

    Assert.AreEqual<Int64>(TableOffset - 3, SearchedFor);
    Assert.AreEqual<Int64>(TableOffset, FParser.StartXref);
    Assert.AreEqual(Builder.OffsetOf(1), OffsetInTable(1));
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestWrongStartXrefOffsetWithoutSearchGivesEmptyTable;
begin
  const Builder = ThreeObjectBuilder;
  try
    const Text = TextOf(Builder.Build(TXrefStyle.Table));
    const TableOffset = Text.IndexOf(TableMarker);
    const Broken = Ascii(Text.Replace(Format('startxref'#10'%d', [TableOffset]), Format('startxref'#10'%d', [TableOffset + 2])));

    ParseFile(Broken);

    Assert.AreEqual(0, XrefCount, 'like PDFBox, the offset 0 is used: the caller recovers');
    Assert.IsTrue(HasLogLine('Can''t find the object xref table/stream'));
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestWrongPrevOffsetIsFixedAndWritten;
begin
  const Base = ThreeObjectBuilder;
  const Update = TTestPdfBuilder.Create;
  try
    const BaseData = Base.Build(TXrefStyle.Table);
    Update.AddObject(2, PagesBody);
    Update.MinimumSize := 4;
    var Text := TextOf(Update.AppendIncrementalUpdate(BaseData, TXrefStyle.Table));
    const BaseTable = Text.IndexOf(TableMarker);
    Text := Text.Replace(Format('/Prev %d', [BaseTable]), Format('/Prev %d', [BaseTable + 1]));

    OpenFile(Ascii(Text));
    FParser.OnSearchXRef :=
      function(const ExpectedOffset: Int64): Int64
      begin
        Result := BaseTable;
      end;

    const Trailer = ParseOpened;

    Assert.AreEqual<Int64>(BaseTable, Trailer.GetLong(TCosNames.Prev, -1));
    Assert.AreEqual(Base.OffsetOf(1), OffsetInTable(1), 'the older section was found through the fixed offset');
  finally
    Update.Free;
    Base.Free;
  end;
end;

procedure TXrefParserTests.TestXrefStreamWithoutWRaises;
begin
  AssertParseRaises(RawXrefStreamFile('/Size 1', nil));
end;

procedure TXrefParserTests.TestXrefStreamWithWrongNumberOfWidthsRaises;
begin
  AssertParseRaises(RawXrefStreamFile('/Size 1 /W [1 2]', nil));
end;

procedure TXrefParserTests.TestXrefStreamWithHugeWidthsRaises;
begin
  AssertParseRaises(RawXrefStreamFile('/Size 1 /W [2147483647 2147483647 2147483647]', nil));
end;

procedure TXrefParserTests.TestXrefStreamWithNegativeWidthRaises;
begin
  AssertParseRaises(RawXrefStreamFile('/Size 1 /W [1 -1 2]', nil));
end;

procedure TXrefParserTests.TestXrefStreamWithOddIndexRaises;
begin
  AssertParseRaises(RawXrefStreamFile('/Size 1 /W [1 1 1] /Index [0 1 5]', nil));
end;

procedure TXrefParserTests.TestXrefStreamWithNonIntegerIndexRaises;
begin
  AssertParseRaises(RawXrefStreamFile('/Size 1 /W [1 1 1] /Index [0 (a)]', nil));
end;

procedure TXrefParserTests.TestXrefStreamWithHugeSizeReadsOnlyTheData;
begin
  // Two entries of three bytes: type 1, offset 9, generation 0 for object 0 and 1
  const Entries: TBytes = [1, 9, 0, 1, 9, 0];

  ParseFile(RawXrefStreamFile('/Size 2147483647 /W [1 1 1]', Entries));

  Assert.AreEqual(2, XrefCount);
end;

procedure TXrefParserTests.TestXrefStreamWithoutFieldWidthsReadsNothing;
begin
  const Entries: TBytes = [1, 2, 3, 4];

  ParseFile(RawXrefStreamFile('/Size 2147483647 /W [0 0 0]', Entries));

  Assert.AreEqual(0, XrefCount);
  Assert.IsTrue(HasLogLine('no width'));
end;

procedure TXrefParserTests.TestXrefStreamIndexThatOverflowsDoesNotWrap;
begin
  const Entries: TBytes = [1, 9, 0, 1, 9, 0, 1, 9, 0];

  ParseFile(RawXrefStreamFile('/Size 1 /W [1 1 1] /Index [9223372036854775800 100]', Entries));

  Assert.AreEqual(3, XrefCount);
  Assert.AreEqual<Int64>(9, OffsetInTable(9223372036854775800));
end;

procedure TXrefParserTests.TestXrefStreamWithTruncatedLastEntryIgnoresIt;
begin
  // The second entry has two of its three bytes
  const Entries: TBytes = [1, 9, 0, 1, 9];

  ParseFile(RawXrefStreamFile('/Size 2 /W [1 1 1]', Entries));

  Assert.AreEqual(1, XrefCount);
end;

procedure TXrefParserTests.TestXrefStreamWithNegativeCountInIndex;
begin
  const Entries: TBytes = [1, 9, 0, 1, 9, 0];

  ParseFile(RawXrefStreamFile('/Size 1 /W [1 1 1] /Index [5 -3 7 2]', Entries));

  // Like PDFBox, a second range is entered without a look at its size: the first range gives nothing, the second two numbers
  Assert.AreEqual(2, XrefCount);
  Assert.AreEqual<Int64>(9, OffsetInTable(7));
  Assert.AreEqual<Int64>(9, OffsetInTable(8));
end;

procedure TXrefParserTests.TestXrefStreamWithWrongLengthIsRead;
begin
  // The byte after the first one is not white space: with 9 or 0 there, /Length 1 would look right to PDFBox
  const Entries: TBytes = [1, 65, 0];
  const Head = Ascii('%PDF-1.7'#10'1 0 obj'#10'<< /Type /XRef /Size 1 /W [1 1 1] /Length 1 >>'#10'stream'#10);
  const Tail = Ascii(#10'endstream'#10'endobj'#10'startxref'#10'9'#10'%%EOF'#10);

  ParseFile(Head + Entries + Tail);

  Assert.AreEqual(1, XrefCount, 'the length was found by looking for endstream');
  Assert.AreEqual<Int64>(65, OffsetInTable(0));
  Assert.IsTrue(HasLogLine('end of the stream doesn''t point'));
end;

procedure TXrefParserTests.TestHybridWithDamagedXRefStmIsOnlyLogged;
begin
  const Builder = ThreeObjectBuilder;
  try
    Builder.AddCompressedObject(10, '<< /A 1 >>', 12);
    // Same length, so no offset moves: the object at /XRefStm is no xref stream any more
    const Damaged = TextOf(Builder.Build(TXrefStyle.Hybrid)).Replace('/Type /XRef', '/Type /Xref');

    ParseFile(Ascii(Damaged));

    Assert.AreEqual(Builder.OffsetOf(1), OffsetInTable(1), 'the table is still read');
    Assert.IsFalse(FParser.HasHybridXRef);
    Assert.IsTrue(HasLogLine('Skipped XRef stream') or HasLogLine('Failed to parse /XRefStm'));
  finally
    Builder.Free;
  end;
end;

procedure TXrefParserTests.TestHybridWithWrongXRefStmIsOnlyLogged;
begin
  const Head = SingleObjectHead;
  const Trailer = Format('trailer'#10'<< /Size 2 /Root 1 0 R /XRefStm 1 >>'#10'startxref'#10'%d'#10'%%EOF', [Length(Head)]);

  ParseFile(Ascii(Head + SingleObjectTable + Trailer));

  Assert.AreEqual<Int64>(9, OffsetInTable(1));
  Assert.IsFalse(FParser.HasHybridXRef);
end;

procedure TXrefParserTests.TestTableWithUnparsableSubsectionHeaderRaises;
begin
  const Head = SingleObjectHead;
  const Trailer = Format('trailer'#10'<< /Size 2 >>'#10'startxref'#10'%d'#10'%%EOF', [Length(Head)]);

  AssertParseRaises(Ascii(Head + 'xref'#10'zero three'#10 + Trailer));
end;

procedure TXrefParserTests.TestPrevFarBeyondTheFileEndsTheChain;
begin
  const Head = SingleObjectHead;
  const Trailer = Format('trailer'#10'<< /Size 2 /Root 1 0 R /Prev 999999999999 >>'#10'startxref'#10'%d'#10'%%EOF', [Length(Head)]);

  ParseFile(Ascii(Head + SingleObjectTable + Trailer));

  Assert.AreEqual<Int64>(9, OffsetInTable(1));
  Assert.AreEqual<Int64>(0, FDocument.Trailer.GetLong(TCosNames.Prev, -1), 'the unusable /Prev is replaced by 0, like PDFBox');
end;

end.
