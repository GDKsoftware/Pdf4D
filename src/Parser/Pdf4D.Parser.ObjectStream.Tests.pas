// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Parser.ObjectStream.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Parser.ObjectStream,
  Pdf4D.Parser.Xref,
  Pdf4D.Parser.XrefTrailerResolver,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TObjectStreamParserTests = class
  private
    FDocument: TCosDocument;
    FResolver: TXrefTrailerResolver;
    FXrefParser: TXrefParser;
    FStream: TCosStream;
    FLogLines: TList<string>;

    function Ascii(const Text: string): TBytes;
    procedure OpenDocument(const Data: TBytes);
    function NewObjectStream(const Count, First: Integer; const Content: string): TCosStream;
    function ReadStreamObjectAt(const Offset: Int64): TCosStream;
    procedure ParseXrefOf(const Data: TBytes);
    procedure AssertParseAllRaises(const Parser: TObjectStreamParser);
    procedure AssertReadStreamRaises(const Offset: Int64);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestObjectStreamReturnsAllObjects;

    [Test]
    procedure TestParseObjectGivesTheObjectOfThatNumber;

    [Test]
    procedure TestParseObjectOfUnknownNumberGivesFalse;

    [Test]
    procedure TestParserCanBeUsedMoreThanOnce;

    [Test]
    procedure TestReadObjectNumbersGivesTheHeader;

    [Test]
    procedure TestMissingCountRaises;

    [Test]
    procedure TestNegativeCountRaises;

    [Test]
    procedure TestMissingFirstRaises;

    [Test]
    procedure TestNegativeFirstRaises;

    [Test]
    procedure TestHugeCountStopsAtTheEndOfTheHeader;

    [Test]
    procedure TestHugeFirstGivesNoObject;

    [Test]
    procedure TestCountLargerThanTheHeaderRaisesAtTheEnd;

    [Test]
    procedure TestOffsetOutsideTheStreamGivesNoObject;

    [Test]
    procedure TestNegativeOffsetRaisesForOneObject;

    [Test]
    procedure TestNegativeOffsetInAllObjectsParsesAtTheStart;

    [Test]
    procedure TestDuplicateObjectNumbersUseTheIndexOfTheXrefTable;

    [Test]
    procedure TestArrayWithReferenceIsANormalObject;

    [Test]
    procedure TestHeaderWithoutNumbersRaises;

    [Test]
    [TestCase('Plain', '0')]
    [TestCase('Flate', '1')]
    procedure TestObjectStreamOfAFileBuiltWithXrefStream(const FilterOrdinal: Integer);

    [Test]
    procedure TestStreamWithoutLengthIsReadUntilEndstream;

    [Test]
    procedure TestStreamWithTooLargeLengthIsReadUntilEndstream;

    [Test]
    procedure TestStreamEndingWithEndobjIsAccepted;

    [Test]
    procedure TestStreamWithGarbageInsteadOfEndstreamRaises;

    [Test]
    procedure TestBinaryStreamKeepsItsLengthWithoutTheFinalLineBreak;

    [Test]
    procedure TestTextStreamKeepsItsFinalLineBreak;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfString,
  Pdf4D.Parser.Base,
  Pdf4D.Parser.StreamObject;

const
  Members = '11 0 12 3 (a) <</X 1>>';
  MembersFirst = 10;

{ TObjectStreamParserTests }

procedure TObjectStreamParserTests.Setup;
begin
  FLogLines := TList<string>.Create;
  OpenDocument(nil);
end;

procedure TObjectStreamParserTests.TearDown;
begin
  FreeAndNil(FStream);
  FreeAndNil(FXrefParser);
  FreeAndNil(FResolver);
  FreeAndNil(FDocument);
  FLogLines.Free;
end;

function TObjectStreamParserTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

procedure TObjectStreamParserTests.OpenDocument(const Data: TBytes);
begin
  FreeAndNil(FDocument);
  var Options := TPdfLoadOptions.Default;
  Options.OnLog := procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;
  FDocument := TCosDocument.Create(TRandomAccessRead.FromBytes(Data), Options);
end;

function TObjectStreamParserTests.NewObjectStream(const Count, First: Integer; const Content: string): TCosStream;
begin
  FreeAndNil(FStream);
  FStream := TCosStream.Create;
  FStream.SetItem(TCosNames.N, TCosInteger.Create(Count));
  FStream.SetItem(TCosNames.First, TCosInteger.Create(First));
  FStream.SetRawData(Ascii(Content));
  FStream.Document := FDocument;
  Result := FStream;
end;

procedure TObjectStreamParserTests.ParseXrefOf(const Data: TBytes);
begin
  OpenDocument(Data);
  FResolver := TXrefTrailerResolver.Create(FDocument.Log);
  FXrefParser := TXrefParser.Create(FResolver);
  FXrefParser.ParseXref(FDocument, TXrefParser.FindStartXrefOffset(FDocument.Source));
end;

function TObjectStreamParserTests.ReadStreamObjectAt(const Offset: Int64): TCosStream;
begin
  FDocument.Source.Seek(Offset);
  const Parser = TBaseParser.Create(FDocument.Source, FDocument);
  try
    Parser.ReadObjectNumber;
    Parser.ReadGenerationNumber;
    Parser.ReadExpectedString('obj');
    const Dictionary = Parser.ParseCosDictionary(False);
    try
      const Reader = TStreamObjectReader.Create(Parser, FDocument);
      try
        Result := Reader.ParseCosStream(Dictionary);
      finally
        Reader.Free;
      end;
    finally
      Dictionary.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.AssertParseAllRaises(const Parser: TObjectStreamParser);
begin
  Assert.WillRaise(
    procedure
    begin
      Parser.ParseAllObjects.Free;
    end,
    EPdfParseException);
end;

procedure TObjectStreamParserTests.AssertReadStreamRaises(const Offset: Int64);
begin
  Assert.WillRaise(
    procedure
    begin
      FStream := ReadStreamObjectAt(Offset);
    end,
    EPdfParseException);
end;

procedure TObjectStreamParserTests.TestObjectStreamReturnsAllObjects;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, MembersFirst, Members), FDocument);
  try
    const Objects = Parser.ParseAllObjects;
    try
      Assert.AreEqual(2, Integer(Objects.Count));

      var First: TCosBase;
      Assert.IsTrue(Objects.TryGetValue(TCosObjectKey.Make(11, 0), First));
      Assert.IsTrue(First is TCosString);
      Assert.AreEqual('a', TCosString(First).GetString);
      Assert.IsFalse(First.Direct, 'objects of an object stream are indirect');

      var Second: TCosBase;
      Assert.IsTrue(Objects.TryGetValue(TCosObjectKey.Make(12, 0), Second));
      Assert.IsTrue(Second is TCosDictionary);
      Assert.AreEqual(1, TCosDictionary(Second).GetInt('X', 0));
    finally
      Objects.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestParseObjectGivesTheObjectOfThatNumber;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, MembersFirst, Members), FDocument);
  try
    var Found: TCosBase;
    Assert.IsTrue(Parser.TryParseObject(12, Found));
    try
      Assert.IsTrue(Found is TCosDictionary);
      Assert.AreEqual(1, TCosDictionary(Found).GetInt('X', 0));
    finally
      Found.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestParseObjectOfUnknownNumberGivesFalse;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, MembersFirst, Members), FDocument);
  try
    var Found: TCosBase;
    Assert.IsFalse(Parser.TryParseObject(99, Found));
    Assert.IsNull(Found);
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestParserCanBeUsedMoreThanOnce;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, MembersFirst, Members), FDocument);
  try
    var First: TCosBase;
    var Second: TCosBase;
    Assert.IsTrue(Parser.TryParseObject(11, First));
    Assert.IsTrue(Parser.TryParseObject(12, Second));
    First.Free;
    Second.Free;
    const Objects = Parser.ParseAllObjects;
    Objects.Free;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestReadObjectNumbersGivesTheHeader;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, MembersFirst, Members), FDocument);
  try
    const Numbers = Parser.ReadObjectNumbers;
    try
      Assert.AreEqual(2, Integer(Numbers.Count));
      Assert.AreEqual(0, Numbers[11]);
      Assert.AreEqual(3, Numbers[12]);
    finally
      Numbers.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestMissingCountRaises;
begin
  FStream := TCosStream.Create;
  FStream.SetItem(TCosNames.First, TCosInteger.Create(0));
  Assert.WillRaise(
    procedure
    begin
      TObjectStreamParser.Create(FStream, FDocument).Free;
    end,
    EPdfParseException);
end;

procedure TObjectStreamParserTests.TestNegativeCountRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TObjectStreamParser.Create(NewObjectStream(-1, 0, ''), FDocument).Free;
    end,
    EPdfParseException);
end;

procedure TObjectStreamParserTests.TestMissingFirstRaises;
begin
  FStream := TCosStream.Create;
  FStream.SetItem(TCosNames.N, TCosInteger.Create(1));
  Assert.WillRaise(
    procedure
    begin
      TObjectStreamParser.Create(FStream, FDocument).Free;
    end,
    EPdfParseException);
end;

procedure TObjectStreamParserTests.TestNegativeFirstRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TObjectStreamParser.Create(NewObjectStream(1, -5, ''), FDocument).Free;
    end,
    EPdfParseException);
end;

procedure TObjectStreamParserTests.TestHugeCountStopsAtTheEndOfTheHeader;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(High(Integer), MembersFirst, Members), FDocument);
  try
    const Objects = Parser.ParseAllObjects;
    try
      Assert.AreEqual(2, Integer(Objects.Count));
    finally
      Objects.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestHugeFirstGivesNoObject;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, High(Integer), Members), FDocument);
  try
    // The header is read in full as long as there is data, and the objects are far outside
    var Found: TCosBase;
    Assert.WillNotRaise(
      procedure
      begin
        Parser.TryParseObject(11, Found);
      end);
    Found.Free;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestCountLargerThanTheHeaderRaisesAtTheEnd;
begin
  // /First points beyond the data, so the loop reads on until the data ends and no number is left
  var Parser := TObjectStreamParser.Create(NewObjectStream(1000, 5000, '1 0 2 3 4 5'), FDocument);
  try
    AssertParseAllRaises(Parser);
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestOffsetOutsideTheStreamGivesNoObject;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(1, 8, '11 9999 (x)'), FDocument);
  try
    var Found: TCosBase;
    Assert.IsFalse(Parser.TryParseObject(11, Found));
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestNegativeOffsetRaisesForOneObject;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(1, 14, '11 2147483648 (x)'), FDocument);
  try
    var Found: TCosBase;
    Assert.WillRaise(
      procedure
      begin
        Parser.TryParseObject(11, Found);
      end,
      EPdfParseException);
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestNegativeOffsetInAllObjectsParsesAtTheStart;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(1, 14, '11 2147483648 (x)'), FDocument);
  try
    const Objects = Parser.ParseAllObjects;
    try
      Assert.AreEqual(1, Integer(Objects.Count));
    finally
      Objects.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestDuplicateObjectNumbersUseTheIndexOfTheXrefTable;
begin
  // Object 11 is twice in the stream; the xref table says the one with index 1 is the right one
  FDocument.XrefTable.Add(TCosObjectKey.MakeInObjectStream(11, 1), -7);
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, 10, '11 0 11 4 (a) (b) '), FDocument);
  try
    const Objects = Parser.ParseAllObjects;
    try
      Assert.AreEqual(1, Integer(Objects.Count));
      Assert.AreEqual('b', TCosString(Objects[TCosObjectKey.Make(11, 0)]).GetString);
    finally
      Objects.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestArrayWithReferenceIsANormalObject;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(1, 5, '11 0 [1 2 R]'), FDocument);
  try
    const Objects = Parser.ParseAllObjects;
    try
      Assert.AreEqual(1, Integer(Objects.Count), 'an array that holds a reference is a normal object');
    finally
      Objects.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestHeaderWithoutNumbersRaises;
begin
  var Parser := TObjectStreamParser.Create(NewObjectStream(2, 4, 'abc def'), FDocument);
  try
    AssertParseAllRaises(Parser);
  finally
    Parser.Free;
  end;
end;

procedure TObjectStreamParserTests.TestObjectStreamOfAFileBuiltWithXrefStream(const FilterOrdinal: Integer);
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, '<< /Type /Catalog >>');
    Builder.SetRoot(1);
    Builder.AddCompressedObject(10, '(first)', 12);
    Builder.AddCompressedObject(11, '<< /Second true >>', 12);
    Builder.ObjectStreamFilter := TStreamFilter(FilterOrdinal);
    ParseXrefOf(Builder.Build(TXrefStyle.Stream));

    FStream := ReadStreamObjectAt(Builder.OffsetOf(12));
    var Parser := TObjectStreamParser.Create(FStream, FDocument);
    try
      const Objects = Parser.ParseAllObjects;
      try
        Assert.AreEqual(2, Integer(Objects.Count));
        Assert.AreEqual('first', TCosString(Objects[TCosObjectKey.Make(10, 0)]).GetString);
        Assert.IsTrue(TCosDictionary(Objects[TCosObjectKey.Make(11, 0)]).GetBoolean('Second', False));
      finally
        Objects.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TObjectStreamParserTests.TestStreamWithoutLengthIsReadUntilEndstream;
begin
  const Data = '%PDF-1.4'#10'1 0 obj'#10'<< /A 1 >>'#10'stream'#10'BINARY'#1#2#10'endstream'#10'endobj'#10;
  OpenDocument(Ascii(Data));

  FStream := ReadStreamObjectAt(9);

  Assert.AreEqual(8, FStream.GetInt(TCosNames.Length, -1), 'the length is set');
  Assert.IsTrue(FLogLines.Count > 0);
end;

procedure TObjectStreamParserTests.TestStreamWithTooLargeLengthIsReadUntilEndstream;
begin
  const Data = '%PDF-1.4'#10'1 0 obj'#10'<< /Length 99999 >>'#10'stream'#10'ABC'#1#10'endstream'#10'endobj'#10;
  OpenDocument(Ascii(Data));

  FStream := ReadStreamObjectAt(9);

  Assert.AreEqual(4, FStream.GetInt(TCosNames.Length, -1));
end;

procedure TObjectStreamParserTests.TestStreamEndingWithEndobjIsAccepted;
begin
  const Data = '%PDF-1.4'#10'1 0 obj'#10'<< /A 1 >>'#10'stream'#10'ABC'#1#10'endobj'#10;
  OpenDocument(Ascii(Data));

  FStream := ReadStreamObjectAt(9);

  Assert.AreEqual(4, FStream.GetInt(TCosNames.Length, -1));
end;

procedure TObjectStreamParserTests.TestStreamWithGarbageInsteadOfEndstreamRaises;
begin
  const Data = '%PDF-1.4'#10'1 0 obj'#10'<< /Length 3 >>'#10'stream'#10'ABC'#10'endstrXX'#10;
  OpenDocument(Ascii(Data));

  AssertReadStreamRaises(9);
end;

procedure TObjectStreamParserTests.TestBinaryStreamKeepsItsLengthWithoutTheFinalLineBreak;
begin
  const Data = '%PDF-1.4'#10'1 0 obj'#10'<< /A 1 >>'#10'stream'#10#1#2#3#4#5#6#7#8#9#11#12#1#13#10'endstream'#10;
  OpenDocument(Ascii(Data));

  FStream := ReadStreamObjectAt(9);

  Assert.AreEqual(12, FStream.GetInt(TCosNames.Length, -1), 'CR LF before endstream is not data');
end;

procedure TObjectStreamParserTests.TestTextStreamKeepsItsFinalLineBreak;
begin
  const Data = '%PDF-1.4'#10'1 0 obj'#10'<< /A 1 >>'#10'stream'#10'0 0 m 10 10 l S'#10'endstream'#10;
  OpenDocument(Ascii(Data));

  FStream := ReadStreamObjectAt(9);

  Assert.AreEqual(Length('0 0 m 10 10 l S') + 1, FStream.GetInt(TCosNames.Length, -1), 'ASCII data keeps its final line break');
end;

end.
