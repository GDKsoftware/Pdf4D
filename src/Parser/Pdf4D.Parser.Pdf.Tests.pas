unit Pdf4D.Parser.Pdf.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TPdfParserTests = class
  private
    FDocument: TCosDocument;
    FLogLines: TList<string>;

    function Ascii(const Text: string): TBytes;
    function MinimalBuilder: TTestPdfBuilder;
    function MinimalFile: TBytes;
    function Load(const Data: TBytes): TCosDocument; overload;
    function Load(const Data: TBytes; const MaxDecodedStreamSize: Int64): TCosDocument; overload;
    function WithLeadingGarbage(const Data: TBytes): TBytes;
    procedure AssertShiftedFileLoads(const Style: TXrefStyle);
    procedure OpenFile(const Data: TBytes);
    function Fetch(const Number: Integer): TCosBase;
    function StreamText(const Number: Integer): string;
    function HasLogLine(const Fragment: string): Boolean;
    procedure AssertLoadRaises(const Data: TBytes);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLoadsMinimalDocument;

    [Test]
    procedure TestVersionFromHeader;

    [Test]
    procedure TestHeaderWithGarbageInsideTheHeaderLine;

    [Test]
    procedure TestHeaderWithLeadingGarbage;

    [Test]
    procedure TestHeaderWithLeadingGarbageAndXrefStream;

    [Test]
    procedure TestMissingCatalogTypeIsAdded;

    [Test]
    procedure TestObjectsAreLazy;

    [Test]
    procedure TestStreamLengthIndirect;

    [Test]
    procedure TestStreamLengthSelfReference;

    [Test]
    procedure TestStreamLengthBeyondEof;

    [Test]
    procedure TestStreamWithoutLengthUsesEndstream;

    [Test]
    procedure TestStreamWithoutLengthDropsFinalLineBreakOfDataThatStartsWithHighByte;

    [Test]
    procedure TestObjectFromObjectStream;

    [Test]
    procedure TestReferenceToMissingObjectIsNull;

    [Test]
    procedure TestChainOfLengthObjectsDoesNotOverflowTheStack;

    [Test]
    procedure TestMutualStreamLengthCycle;

    [Test]
    procedure TestObjectStreamIsParsedOnceForManyMissingKeys;

    [Test]
    procedure TestLimitExceededOnLazyLoadPropagates;

    [Test]
    procedure TestLimitExceededRaisesForEveryKeyOfTheObjectStream;

    [Test]
    procedure TestPositionOfTheSourceIsKeptWhileLoading;

    [Test]
    procedure TestIncrementalUpdateIsLoaded;

    [Test]
    procedure TestXrefValuesAreSetOnTheDocument;

    [Test]
    procedure TestMissingStartxrefRaises;

    [Test]
    procedure TestMissingRootRaises;

    [Test]
    procedure TestFileWithoutHeaderRaises;

    [Test]
    procedure TestEmptyFileRaises;

    [Test]
    procedure TestOwnedSourceIsFreedOnFailure;

    [Test]
    procedure TestHostileBytesRaiseOnlyPdfExceptions;
  end;

implementation

uses
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Parser.Pdf;

type
  TFreedFlagStream = class(TBytesStream)
  private
    FFreed: PBoolean;

  public
    constructor Create(const Data: TBytes; const Freed: PBoolean);
    destructor Destroy; override;
  end;

{ TFreedFlagStream }

constructor TFreedFlagStream.Create(const Data: TBytes; const Freed: PBoolean);
begin
  inherited Create(Data);
  FFreed := Freed;
end;

destructor TFreedFlagStream.Destroy;
begin
  FFreed^ := True;
  inherited;
end;

{ TPdfParserTests }

procedure TPdfParserTests.Setup;
begin
  FLogLines := TList<string>.Create;
end;

procedure TPdfParserTests.TearDown;
begin
  FreeAndNil(FDocument);
  FLogLines.Free;
end;

function TPdfParserTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function TPdfParserTests.MinimalBuilder: TTestPdfBuilder;
begin
  Result := TTestPdfBuilder.Create;
  try
    Result.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    Result.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    Result.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    Result.SetRoot(1);
  except
    Result.Free;
    raise;
  end;
end;

function TPdfParserTests.MinimalFile: TBytes;
begin
  const Builder = MinimalBuilder;
  try
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

function TPdfParserTests.Load(const Data: TBytes): TCosDocument;
begin
  Result := Load(Data, TPdfLoadOptions.Default.MaxDecodedStreamSize);
end;

function TPdfParserTests.Load(const Data: TBytes; const MaxDecodedStreamSize: Int64): TCosDocument;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxDecodedStreamSize := MaxDecodedStreamSize;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;
  Result := TPdfParser.Parse(TBytesStream.Create(Data), True, Options);
end;

procedure TPdfParserTests.OpenFile(const Data: TBytes);
begin
  FreeAndNil(FDocument);
  FDocument := Load(Data);
end;

function TPdfParserTests.Fetch(const Number: Integer): TCosBase;
begin
  Result := FDocument.GetObjectFromPool(TCosObjectKey.Make(Number, 0)).GetObject;
end;

function TPdfParserTests.StreamText(const Number: Integer): string;
begin
  const Stream = Fetch(Number) as TCosStream;
  const Raw = Stream.CreateRawStream;
  try
    var Data: TBytes;
    SetLength(Data, Raw.Size);
    if Length(Data) > 0 then
    begin
      Raw.Position := 0;
      Raw.ReadBuffer(Data[0], Length(Data));
    end;
    Result := TEncoding.ASCII.GetString(Data);
  finally
    Raw.Free;
  end;
end;

function TPdfParserTests.HasLogLine(const Fragment: string): Boolean;
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

procedure TPdfParserTests.AssertLoadRaises(const Data: TBytes);
begin
  Assert.WillRaise(
    procedure
    begin
      Load(Data).Free;
    end,
    EPdfParseException);
end;

procedure TPdfParserTests.TestLoadsMinimalDocument;
begin
  OpenFile(MinimalFile);

  var Root: TCosDictionary;
  Assert.IsTrue(FDocument.Trailer.TryGetCosDictionary(TCosNames.Root, Root));
  Assert.AreEqual(TCosNames.Catalog, Root.GetNameAsString(TCosNames.Type_, ''));
end;

procedure TPdfParserTests.TestVersionFromHeader;
begin
  var Data := MinimalFile;
  Assert.AreEqual('%PDF-1.', TEncoding.ASCII.GetString(Data, 0, 7));
  Data[7] := Ord('4');

  OpenFile(Data);

  Assert.AreEqual<Single>(1.4, FDocument.Version);
end;

function TPdfParserTests.WithLeadingGarbage(const Data: TBytes): TBytes;
begin
  // One line of 100 bytes that does not start with a digit and has no header marker: every offset in the file is 100 too low
  const Garbage = Ascii(StringOfChar('G', 99) + #10);
  Assert.AreEqual<Integer>(100, Length(Garbage));
  Result := Garbage + Data;
end;

// The offsets of the xref and the startxref are wrong by 100 bytes: the nearest xref is searched, and the offsets of the
// objects are checked and corrected
procedure TPdfParserTests.AssertShiftedFileLoads(const Style: TXrefStyle);
begin
  const Builder = MinimalBuilder;
  try
    OpenFile(WithLeadingGarbage(Builder.Build(Style)));
  finally
    Builder.Free;
  end;

  Assert.IsTrue(FDocument.Trailer.ContainsKey(TCosNames.Root));
  Assert.AreEqual<Single>(1.7, FDocument.Version);
  Assert.IsTrue(Fetch(3) is TCosDictionary, 'an object can be dereferenced');
  Assert.AreEqual(TCosNames.Page, TCosDictionary(Fetch(3)).GetNameAsString(TCosNames.Type_, ''));
end;

procedure TPdfParserTests.TestHeaderWithLeadingGarbage;
begin
  AssertShiftedFileLoads(TXrefStyle.Table);
end;

procedure TPdfParserTests.TestHeaderWithLeadingGarbageAndXrefStream;
begin
  AssertShiftedFileLoads(TXrefStyle.Stream);
end;

procedure TPdfParserTests.TestHeaderWithGarbageInsideTheHeaderLine;
begin
  // Garbage in front of the header, in the 15 bytes of the header of the builder so that the offsets stay right
  var Data := MinimalFile;
  const Header = Ascii('GAR%PDF-1.7'#10'%%'#10);
  Assert.AreEqual<Integer>(15, Length(Header));
  Move(Header[0], Data[0], Length(Header));

  OpenFile(Data);

  Assert.IsTrue(FDocument.Trailer.ContainsKey(TCosNames.Root));
  Assert.AreEqual<Single>(1.7, FDocument.Version);
end;

procedure TPdfParserTests.TestMissingCatalogTypeIsAdded;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, '<< /Pages 2 0 R >>');
    Builder.AddObject(2, '<< /Type /Pages /Kids [] /Count 0 >>');
    Builder.SetRoot(1);
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  var Root: TCosDictionary;
  Assert.IsTrue(FDocument.Trailer.TryGetCosDictionary(TCosNames.Root, Root));
  Assert.AreEqual(TCosNames.Catalog, Root.GetNameAsString(TCosNames.Type_, ''));
end;

procedure TPdfParserTests.TestObjectsAreLazy;
begin
  OpenFile(MinimalFile);

  const Page = FDocument.GetObjectFromPool(TCosObjectKey.Make(3, 0));
  Assert.IsFalse(Page.IsLoaded);
  Assert.IsTrue(Page.GetObject is TCosDictionary);
  Assert.IsTrue(Page.IsLoaded);
end;

procedure TPdfParserTests.TestStreamLengthIndirect;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /Length 9 0 R >>'#10'stream'#10'ABCDE'#10'endstream');
    Builder.AddObject(9, '5');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  Assert.AreEqual('ABCDE', StreamText(4));
end;

procedure TPdfParserTests.TestStreamLengthSelfReference;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /Length 4 0 R >>'#10'stream'#10'ABCDE'#10'endstream');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  Assert.AreEqual('ABCDE', StreamText(4));
  Assert.IsTrue(HasLogLine('not found'));
end;

procedure TPdfParserTests.TestStreamLengthBeyondEof;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /Length 999999 >>'#10'stream'#10'ABCDE'#10'endstream');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  Assert.AreEqual('ABCDE', StreamText(4));
  Assert.IsTrue(HasLogLine('out of range'));
end;

procedure TPdfParserTests.TestStreamWithoutLengthUsesEndstream;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< >>'#10'stream'#10'ABCDE'#10'endstream');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  Assert.AreEqual('ABCDE', StreamText(4));
  Assert.AreEqual<Integer>(5, (Fetch(4) as TCosStream).GetInt(TCosNames.Length, -1));
end;

// Java reads the bytes as signed, so a byte of 0x80 or more is binary data and the line break before endstream is not part of it
procedure TPdfParserTests.TestStreamWithoutLengthDropsFinalLineBreakOfDataThatStartsWithHighByte;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< >>'#10'stream'#10'x' + Char($9C) + 'ABCDEFGHIJKL'#13#10'endstream');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(14, (Fetch(4) as TCosStream).GetInt(TCosNames.Length, -1));
end;

procedure TPdfParserTests.TestObjectFromObjectStream;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddCompressedObject(5, '<< /Kind /Packed >>', 6);
    Builder.AddCompressedObject(7, '42', 6);
    OpenFile(Builder.Build(TXrefStyle.Stream));
  finally
    Builder.Free;
  end;

  const Entry = Fetch(5);
  Assert.IsTrue(Entry is TCosDictionary);
  Assert.AreEqual('Packed', TCosDictionary(Entry).GetNameAsString('Kind', ''));
  Assert.AreEqual<Integer>(42, (Fetch(7) as TCosInteger).IntValue);
end;

procedure TPdfParserTests.TestReferenceToMissingObjectIsNull;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /A 99 0 R >>');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  var Value: TCosBase;
  Assert.IsFalse((Fetch(4) as TCosDictionary).TryGetDictionaryObject('A', Value));
end;

procedure TPdfParserTests.TestChainOfLengthObjectsDoesNotOverflowTheStack;
begin
  const Builder = MinimalBuilder;
  try
    // The length of object N is object N + 1, a thousand times
    for var Number := 10 to 1010 do
    begin
      Builder.AddObject(Number, Format('<< /Length %d 0 R >>'#10'stream'#10'AB'#10'endstream', [Number + 1]));
    end;
    Builder.AddObject(1011, '2');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  // The objects of the chain are streams, which are no valid length: what matters is that the chain ends
  Assert.IsTrue(Fetch(10) is TCosNull, 'a stream is no length: the object is not loaded');
  Assert.IsTrue(HasLogLine('Wrong type of length object'));
  Assert.IsTrue(HasLogLine('too many objects'));
end;

procedure TPdfParserTests.TestMutualStreamLengthCycle;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /Length 5 0 R >>'#10'stream'#10'ABCDE'#10'endstream');
    Builder.AddObject(5, '<< /Length 4 0 R >>'#10'stream'#10'FGHIJ'#10'endstream');
    OpenFile(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  // Each is the length of the other, and a stream is no length: the first is not loaded, and the second is read to its
  // endstream
  Assert.IsTrue(Fetch(4) is TCosNull);
  Assert.IsTrue(Fetch(5) is TCosStream);
  Assert.AreEqual('FGHIJ', StreamText(5));
  Assert.IsTrue(HasLogLine('Wrong type of length object'));
end;

// The xref maps many numbers to an object stream that cannot be read: it is tried once, not once for each number
procedure TPdfParserTests.TestObjectStreamIsParsedOnceForManyMissingKeys;
begin
  const FirstNumber = 1000;
  const KeyCount = 200;
  var Data: TBytes;
  const Builder = MinimalBuilder;
  try
    for var Number := FirstNumber to FirstNumber + KeyCount - 1 do
    begin
      Builder.AddCompressedObject(Number, '1', 6);
    end;
    Data := Builder.Build(TXrefStyle.Stream);
  finally
    Builder.Free;
  end;

  // Break /N of the object stream: the stream cannot be parsed
  const Pattern = Ascii('/Type /ObjStm /N ');
  var Position := -1;
  for var Start := 0 to Length(Data) - Length(Pattern) do
  begin
    if CompareMem(@Data[Start], @Pattern[0], Length(Pattern)) then
    begin
      Position := Start;
      Break;
    end;
  end;
  Assert.IsTrue(Position > 0, 'the object stream is in the file');
  Data[Position + Length('/Type /ObjStm /')] := Ord('M');
  OpenFile(Data);

  for var Number := FirstNumber to FirstNumber + KeyCount - 1 do
  begin
    Assert.IsTrue(FDocument.GetObjectFromPool(TCosObjectKey.Make(Number, 0)).GetObject is TCosNull, Format('object %d is not null', [Number]));
  end;

  var Failures := 0;
  for var Line in FLogLines do
  begin
    if Line.Contains('object stream 6 could not be parsed') then
    begin
      Inc(Failures);
    end;
  end;
  Assert.AreEqual<Integer>(1, Failures);
end;

// PDFBox has no limit on the decoded size. The limit is an addition of this library, so its exception is not an IOException
// to be logged and turned into null: it reaches the caller who dereferences the object.
procedure TPdfParserTests.TestLimitExceededOnLazyLoadPropagates;
begin
  var Data: TBytes;
  const Builder = MinimalBuilder;
  try
    Builder.ObjectStreamFilter := TStreamFilter.Flate;
    Builder.AddCompressedObject(5, '<< /Pad (' + StringOfChar('x', 500) + ') >>', 6);
    Data := Builder.Build(TXrefStyle.Stream);
  finally
    Builder.Free;
  end;

  FDocument := Load(Data, 200);

  Assert.WillRaise(
    procedure
    begin
      Fetch(5);
    end,
    EPdfLimitExceededException);
end;

procedure TPdfParserTests.TestLimitExceededRaisesForEveryKeyOfTheObjectStream;
begin
  var Data: TBytes;
  const Builder = MinimalBuilder;
  try
    Builder.ObjectStreamFilter := TStreamFilter.Flate;
    Builder.AddCompressedObject(5, '<< /Pad (' + StringOfChar('x', 500) + ') >>', 6);
    Builder.AddCompressedObject(7, '42', 6);
    Data := Builder.Build(TXrefStyle.Stream);
  finally
    Builder.Free;
  end;

  FDocument := Load(Data, 200);

  for var Number in [5, 7, 5] do
  begin
    Assert.WillRaise(
      procedure
      begin
        Fetch(Number);
      end,
      EPdfLimitExceededException,
      Format('Object %d of the object stream', [Number]));
  end;
end;

procedure TPdfParserTests.TestPositionOfTheSourceIsKeptWhileLoading;
begin
  OpenFile(MinimalFile);
  FDocument.Source.Seek(5);

  Fetch(3);

  Assert.AreEqual<Int64>(5, FDocument.Source.GetPosition);
end;

procedure TPdfParserTests.TestIncrementalUpdateIsLoaded;
begin
  const Original = MinimalFile;
  const Update = TTestPdfBuilder.Create;
  try
    Update.AddObject(3, '<< /Type /Page /Parent 2 0 R /Updated true >>');
    Update.SetRoot(1);
    Update.MinimumSize := 4;
    OpenFile(Update.AppendIncrementalUpdate(Original, TXrefStyle.Table));
  finally
    Update.Free;
  end;

  Assert.IsTrue((Fetch(3) as TCosDictionary).GetBoolean('Updated', False));
end;

procedure TPdfParserTests.TestXrefValuesAreSetOnTheDocument;
begin
  OpenFile(MinimalFile);

  Assert.IsTrue(FDocument.StartXref > 0);
  Assert.IsFalse(FDocument.IsXRefStream);
  Assert.AreEqual<Int64>(3, FDocument.HighestXRefObjectNumber);
end;

procedure TPdfParserTests.TestMissingStartxrefRaises;
begin
  AssertLoadRaises(Ascii('%PDF-1.4'#10'1 0 obj'#10'<< /Type /Catalog >>'#10'endobj'#10));
end;

procedure TPdfParserTests.TestMissingRootRaises;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, '<< /A 1 >>');
    AssertLoadRaises(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;
end;

procedure TPdfParserTests.TestFileWithoutHeaderRaises;
begin
  AssertLoadRaises(Ascii('no header here'#10'and no data'#10));
end;

procedure TPdfParserTests.TestEmptyFileRaises;
begin
  AssertLoadRaises(nil);
end;

procedure TPdfParserTests.TestOwnedSourceIsFreedOnFailure;
begin
  var Freed := False;
  const FlagPointer = @Freed;
  Assert.WillRaise(
    procedure
    begin
      TPdfParser.Parse(TFreedFlagStream.Create(Ascii('garbage'), FlagPointer), True, TPdfLoadOptions.Default).Free;
    end,
    EPdfParseException);
  Assert.IsTrue(Freed);
end;

procedure TPdfParserTests.TestHostileBytesRaiseOnlyPdfExceptions;
begin
  const Valid = MinimalFile;
  var Seed: Cardinal := 12345;
  for var Round := 1 to 300 do
  begin
    var Data := Copy(Valid);
    for var Change := 1 to 4 do
    begin
      Seed := Cardinal((UInt64(Seed) * 1103515245 + 12345) and $FFFFFFFF);
      Data[(Seed shr 8) mod Cardinal(Length(Data))] := Byte(Seed shr 16);
    end;

    try
      OpenFile(Data);
      for var Key in FDocument.ObjectKeys do
      begin
        FDocument.GetObjectFromPool(Key).GetObject;
      end;
    except
      on EPdfException do
      begin
        // The file is damaged: an error of the library is the answer
      end;
    end;
  end;
end;

end.
