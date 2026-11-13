// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Parser.BruteForce.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TBruteForceParserTests = class
  private
    FDocument: TCosDocument;
    FLogLines: TList<string>;

    function Ascii(const Text: string): TBytes;
    function MinimalBuilder: TTestPdfBuilder;
    function Load(const Data: TBytes): TCosDocument;
    function CutAfterLastEndObj(const Data: TBytes): TBytes;
    function IndexOf(const Data: TBytes; const Text: string): Integer;
    function RootOf(const Document: TCosDocument): TCosDictionary;
    function HasLogLine(const Fragment: string): Boolean;
    function CorruptedFile(const Delta: Int64): TBytes;
    function TruncationSubject(const Style: TXrefStyle): TBytes;
    procedure AssertTruncationsRecoverOrRaise(const Data: TBytes);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestWrongXrefOffsetsAreRepaired;

    [Test]
    procedure TestXrefOffsetsBeyondTheEndAreReplacedBySearch;

    [Test]
    procedure TestMissingXrefAndTrailer;

    [Test]
    procedure TestInfoDictionaryIsFound;

    [Test]
    procedure TestLastCatalogIsTheRoot;

    [Test]
    procedure TestRootInObjectStreamIsFound;

    [Test]
    procedure TestWrongStartxrefIsFixedToNearestXrefTable;

    [Test]
    procedure TestTruncatedFileRecoversOrRaises;

    [Test]
    procedure TestTruncatedFileWithXrefStreamRecoversOrRaises;

    [Test]
    procedure TestNoCatalogAnywhereRaises;

    [Test]
    procedure TestManyObjectsWithoutXref;

    [Test]
    procedure TestManyObjectStreamMarkersAreScannedOnce;

    [Test]
    procedure TestPageTreeWithManyMissingKidsIsCheckedInOnePass;

    [Test]
    procedure TestObjectLimitIsTheLimitOfXrefStreams;
  end;

implementation

uses
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Parser.BruteForce,
  Pdf4D.Parser.Pdf;

const
  TruncationStep = 7;

{ TBruteForceParserTests }

procedure TBruteForceParserTests.Setup;
begin
  FLogLines := TList<string>.Create;
end;

procedure TBruteForceParserTests.TearDown;
begin
  FreeAndNil(FDocument);
  FLogLines.Free;
end;

function TBruteForceParserTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function TBruteForceParserTests.MinimalBuilder: TTestPdfBuilder;
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

function TBruteForceParserTests.Load(const Data: TBytes): TCosDocument;
begin
  var Options := TPdfLoadOptions.Default;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;
  Result := TPdfParser.Parse(TBytesStream.Create(Data), True, Options);
end;

// The offset of the last place where Text is
function TBruteForceParserTests.IndexOf(const Data: TBytes; const Text: string): Integer;
begin
  const Pattern = Ascii(Text);
  Result := -1;
  for var Start := 0 to Length(Data) - Length(Pattern) do
  begin
    if CompareMem(@Data[Start], @Pattern[0], Length(Pattern)) then
    begin
      Result := Start;
    end;
  end;
end;

function TBruteForceParserTests.CutAfterLastEndObj(const Data: TBytes): TBytes;
begin
  const Position = IndexOf(Data, 'endobj');
  Assert.IsTrue(Position > 0, 'the file has an endobj');
  Result := Copy(Data, 0, Position + Length('endobj') + 1);
end;

function TBruteForceParserTests.RootOf(const Document: TCosDocument): TCosDictionary;
begin
  Assert.IsTrue(Document.Trailer.TryGetCosDictionary(TCosNames.Root, Result), 'the trailer has a /Root');
end;

function TBruteForceParserTests.HasLogLine(const Fragment: string): Boolean;
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

function TBruteForceParserTests.CorruptedFile(const Delta: Int64): TBytes;
begin
  const Builder = MinimalBuilder;
  try
    for var Number := 1 to 3 do
    begin
      Builder.CorruptOffset(Number, Delta);
    end;
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

procedure TBruteForceParserTests.TestWrongXrefOffsetsAreRepaired;
begin
  FDocument := Load(CorruptedFile(3));

  const Root = RootOf(FDocument);
  Assert.AreEqual(TCosNames.Catalog, Root.GetNameAsString(TCosNames.Type_, ''));
  var Pages: TCosDictionary;
  Assert.IsTrue(Root.TryGetCosDictionary(TCosNames.Pages, Pages));
  Assert.AreEqual<Integer>(1, Pages.GetInt(TCosNames.Count, 0));
  // PDFBox logs this repair at debug level only, so the log has no warning to look for
end;

procedure TBruteForceParserTests.TestXrefOffsetsBeyondTheEndAreReplacedBySearch;
begin
  FDocument := Load(CorruptedFile(100000));

  const Root = RootOf(FDocument);
  Assert.AreEqual(TCosNames.Catalog, Root.GetNameAsString(TCosNames.Type_, ''));
  var Pages: TCosDictionary;
  Assert.IsTrue(Root.TryGetCosDictionary(TCosNames.Pages, Pages));
  Assert.IsTrue(HasLogLine('Replaced read xref table with the results of a brute force search'));
end;

procedure TBruteForceParserTests.TestMissingXrefAndTrailer;
begin
  const Builder = MinimalBuilder;
  try
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Table)));
  finally
    Builder.Free;
  end;

  const Root = RootOf(FDocument);
  Assert.AreEqual(TCosNames.Catalog, Root.GetNameAsString(TCosNames.Type_, ''));
  Assert.AreEqual<Int64>(3, FDocument.HighestXRefObjectNumber);
  Assert.IsTrue(FDocument.XrefTable.ContainsKey(TCosObjectKey.Make(2, 0)));
end;

procedure TBruteForceParserTests.TestInfoDictionaryIsFound;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /Producer (Pdf4D) /Title (Test) >>');
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Table)));
  finally
    Builder.Free;
  end;

  var Info: TCosDictionary;
  Assert.IsTrue(FDocument.Trailer.TryGetCosDictionary(TCosNames.Info, Info), 'the trailer has an /Info');
  Assert.IsTrue(Info.ContainsKey(TCosNames.Producer));
end;

procedure TBruteForceParserTests.TestLastCatalogIsTheRoot;
begin
  const Builder = MinimalBuilder;
  try
    Builder.AddObject(4, '<< /Type /Catalog /Pages 2 0 R /Lang (nl) >>');
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Table)));
  finally
    Builder.Free;
  end;

  Assert.IsTrue(RootOf(FDocument).ContainsKey(TCosNames.Lang), 'the catalog with the bigger offset wins');
end;

procedure TBruteForceParserTests.TestRootInObjectStreamIsFound;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    Builder.AddCompressedObject(1, '<< /Type /Catalog /Pages 2 0 R >>', 4);
    Builder.AddCompressedObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>', 4);
    Builder.SetRoot(1);
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Stream)));
  finally
    Builder.Free;
  end;

  const Root = RootOf(FDocument);
  Assert.AreEqual(TCosNames.Catalog, Root.GetNameAsString(TCosNames.Type_, ''));
  var Pages: TCosDictionary;
  Assert.IsTrue(Root.TryGetCosDictionary(TCosNames.Pages, Pages));
end;

procedure TBruteForceParserTests.TestWrongStartxrefIsFixedToNearestXrefTable;
begin
  const Builder = MinimalBuilder;
  var Data: TBytes;
  try
    Data := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;

  const XrefOffset = IndexOf(Data, #10'xref'#10) + 1;
  const StartxrefValue = IndexOf(Data, 'startxref'#10) + Length('startxref'#10);
  const Correct = IntToStr(XrefOffset);
  Assert.AreEqual(Correct, TEncoding.ASCII.GetString(Data, StartxrefValue, Length(Correct)));
  const Wrong = Ascii(IntToStr(XrefOffset - 4).PadLeft(Length(Correct), '0'));
  Move(Wrong[0], Data[StartxrefValue], Length(Wrong));

  FDocument := Load(Data);

  Assert.AreEqual<Int64>(XrefOffset, FDocument.StartXref);
  Assert.IsFalse(FDocument.XrefTable.Count = 0);
end;

function TBruteForceParserTests.TruncationSubject(const Style: TXrefStyle): TBytes;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>');
    Builder.AddStreamObject(4, '', Ascii('0 0 m 10 10 l S'));
    Builder.AddObject(5, '<< /Producer (Pdf4D) >>');
    if Style <> TXrefStyle.Table then
    begin
      Builder.AddCompressedObject(6, '<< /Kind /Packed >>', 7);
      Builder.AddCompressedObject(8, '42', 7);
    end;
    Builder.TrailerExtra := '/Info 5 0 R';
    Builder.SetRoot(1);
    Result := Builder.Build(Style);
  finally
    Builder.Free;
  end;
end;

procedure TBruteForceParserTests.AssertTruncationsRecoverOrRaise(const Data: TBytes);
begin
  var Loaded := 0;
  var Cut := 0;
  while Cut <= Length(Data) do
  begin
    try
      const Document = Load(Copy(Data, 0, Cut));
      try
        Inc(Loaded);
        for var Key in Document.ObjectKeys do
        begin
          Document.GetObjectFromPool(Key).GetObject;
        end;
      finally
        Document.Free;
      end;
    except
      on EPdfParseException do
      begin
        // The file is cut off: an error of the parser is the answer
      end;
      on Failure: Exception do
      begin
        Assert.Fail(Format('Cut at %d of %d bytes raised %s: %s', [Cut, Length(Data), Failure.ClassName, Failure.Message]));
      end;
    end;
    Inc(Cut, TruncationStep);
  end;
  Assert.IsTrue(Loaded > 0, 'some of the cut files load');
  Assert.IsTrue(Loaded < (Length(Data) div TruncationStep), 'the shortest cut files do not load');
end;

procedure TBruteForceParserTests.TestTruncatedFileRecoversOrRaises;
begin
  AssertTruncationsRecoverOrRaise(TruncationSubject(TXrefStyle.Table));
end;

procedure TBruteForceParserTests.TestTruncatedFileWithXrefStreamRecoversOrRaises;
begin
  AssertTruncationsRecoverOrRaise(TruncationSubject(TXrefStyle.Stream));
end;

procedure TBruteForceParserTests.TestNoCatalogAnywhereRaises;
begin
  const Builder = TTestPdfBuilder.Create;
  var Data: TBytes;
  try
    Builder.AddObject(1, '<< /Type /Pages /Kids [] /Count 0 >>');
    Builder.AddObject(2, '<< /A 1 >>');
    Data := CutAfterLastEndObj(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;

  Assert.WillRaiseWithMessageRegex(
    procedure
    begin
      Load(Data).Free;
    end,
    EPdfParseException,
    'Missing root object specification in trailer');
end;

procedure TBruteForceParserTests.TestManyObjectsWithoutXref;
begin
  const ObjectCount = 5000;
  const Builder = MinimalBuilder;
  try
    for var Number := 4 to ObjectCount do
    begin
      Builder.AddObject(Number, Format('<< /Index %d >>', [Number]));
    end;
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Table)));
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(ObjectCount, FDocument.XrefTable.Count);
  Assert.AreEqual<Int64>(ObjectCount, FDocument.HighestXRefObjectNumber);
end;

procedure TBruteForceParserTests.TestManyObjectStreamMarkersAreScannedOnce;
begin
  const Marker = Ascii('/ObjStm /XRef ');
  var Data: TBytes;
  SetLength(Data, Length(Marker) * 40000);
  for var Position := 0 to 39999 do
  begin
    Move(Marker[0], Data[Position * Length(Marker)], Length(Marker));
  end;

  const Builder = MinimalBuilder;
  try
    Builder.AddStreamObject(4, '', Data);
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Table)));
  finally
    Builder.Free;
  end;

  Assert.IsTrue(FDocument.Trailer.ContainsKey(TCosNames.Root));
end;

// After a rebuilt trailer the kids that cannot be loaded are removed from the page tree: with many of them, one by one
// would be quadratic
procedure TBruteForceParserTests.TestPageTreeWithManyMissingKidsIsCheckedInOnePass;
begin
  const MissingCount = 30000;
  const Kids = TStringBuilder.Create;
  const Builder = TTestPdfBuilder.Create;
  try
    Kids.Append('3 0 R');
    for var Number := 100 to 100 + MissingCount - 1 do
    begin
      Kids.Append(Format(' %d 0 R', [Number]));
    end;
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    Builder.AddObject(2, Format('<< /Type /Pages /Kids [%s] /Count 1 >>', [Kids.ToString]));
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    Builder.SetRoot(1);
    FDocument := Load(CutAfterLastEndObj(Builder.Build(TXrefStyle.Table)));
  finally
    Builder.Free;
    Kids.Free;
  end;

  var Pages: TCosDictionary;
  Assert.IsTrue(RootOf(FDocument).TryGetCosDictionary(TCosNames.Pages, Pages));
  var KidsArray: TCosArray;
  Assert.IsTrue(Pages.TryGetCosArray(TCosNames.Kids, KidsArray));
  Assert.AreEqual<Integer>(1, KidsArray.Count);
  Assert.AreEqual<Integer>(1, Pages.GetInt(TCosNames.Count, 0));
end;

procedure TBruteForceParserTests.TestObjectLimitIsTheLimitOfXrefStreams;
begin
  Assert.AreEqual<Integer>(8388607, TBruteForceParser.MaxFoundObjects);
end;

end.
