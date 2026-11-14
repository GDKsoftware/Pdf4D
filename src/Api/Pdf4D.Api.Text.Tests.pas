// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Text.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.TextOptions;

type
  // Loads documents on its own thread, after the start gate opens, and keeps the text of each, or the message of the exception
  TExtractionThread = class(TThread)
  private
    FFileNames: TArray<string>;
    FOptions: TPdfTextOptions;
    FStartGate: TEvent;
    FTexts: TArray<string>;
    FFailure: string;

    function ExtractTextOf(const FileName: string): string;

  protected
    procedure Execute; override;

  public
    // The gate is not owned
    constructor Create(const FileNames: TArray<string>; const Options: TPdfTextOptions; const StartGate: TEvent);

    property Texts: TArray<string> read FTexts;
    property Failure: string read FFailure;
  end;

  // Fails on every write, like a destination that is full
  TFailingWriter = class(TStringWriter)
  public
    procedure Write(const Value: string); override;
  end;

  // An outline item that does not come from this library
  TForeignBookmark = class(TInterfacedObject, IPdfOutlineItem)
  public
    function Title: string;
    function TryGetPageIndex(out Index: Integer): Boolean;
    function Children: TArray<IPdfOutlineItem>;
  end;

  [TestFixture]
  TApiTextTests = class
  private
    FStreams: TObjectList<TStream>;

    class function CorpusFileNamesWithText(const Count: Integer): TArray<string>; static;
    class function HasTextInFirstSection(const RelativePath: string): Boolean; static;
    // A document of one page that shows Content
    function LoadContent(const Content: string): IPdfDocument;
    // Three pages that show A, B and C, with a bookmark for each of the first two pages
    function LoadThreePagesWithBookmarks: IPdfDocument;
    function LoadBytes(const Data: TBytes): IPdfDocument;
    class function PageEndSlash: TPdfTextOptions; static;
    procedure CheckConcurrentExtraction(const SortByPosition: Boolean);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestUsageExample;

    [Test]
    procedure TestPageRangeOption;

    [Test]
    procedure TestPageExtractTextKeepsDocumentAlive;

    [Test]
    procedure TestPageExtractTextGivesOnlyThatPage;

    [Test]
    procedure TestWriterOverload;

    [Test]
    procedure TestDefaultOptionsEqualPdfBoxDefaults;

    [Test]
    procedure TestSeparatorOptionsAreApplied;

    [Test]
    procedure TestWordSeparatorOptionIsApplied;

    [Test]
    procedure TestLineSeparatorOptionIsApplied;

    [Test]
    procedure TestIgnoreContentStreamSpaceGlyphsOptionIsApplied;

    [Test]
    procedure TestSortByPositionOptionIsApplied;

    [Test]
    procedure TestStartBookmarkSelectsTheFirstPage;

    [Test]
    procedure TestEndBookmarkSelectsTheLastPage;

    [Test]
    procedure TestStartAndEndBookmarkOfOnePage;

    [Test]
    procedure TestForeignBookmarkIsAnArgumentError;

    [Test]
    procedure TestBookmarkOfAnotherDocumentIsAnArgumentError;

    [Test]
    procedure TestWriterExceptionIsRaisedAsItWas;

    [Test]
    procedure TestNilWriterIsAnArgumentError;

    [Test]
    procedure TestGuardedWriterForwardsCharAndLines;

    [Test]
    procedure TestConcurrentExtractionMatchesSequential;

    [Test]
    procedure TestConcurrentSortedExtractionMatchesSequential;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.GuardedWriter,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.TextDocuments;

const
  FirstSectionHeading = 'text: default page 1';
  HelloFile = 'pdfbox/input/hello3.pdf';
  EuropeanFile = 'pdfbox/input/eu-001.pdf';
  ThreadCount = 4;
  FilesPerThread = 5;
  // The three pages have the objects 10 to 12 and show the letters A, B and C. Object 30 is their font.
  PageBodyFormat = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 30 0 R >> >> >>';
  OutlineRoot = '<< /Type /Outlines /First 4 0 R /Last 5 0 R /Count 2 >>';
  FirstBookmarkBody = '<< /Title (First) /Parent 3 0 R /Next 5 0 R /Dest [10 0 R /Fit] >>';
  SecondBookmarkBody = '<< /Title (Second) /Parent 3 0 R /Prev 4 0 R /Dest [11 0 R /Fit] >>';
  ForeignBookmarkMessage = 'does not come from this library';
  OtherDocumentMessage = 'belongs to another document';
  DiskFullMessage = 'The destination is full';
  BChar: Char = 'B';
  ForwardedText = 'ABC' + sLineBreak + sLineBreak;

{ TExtractionThread }

constructor TExtractionThread.Create(const FileNames: TArray<string>; const Options: TPdfTextOptions; const StartGate: TEvent);
begin
  inherited Create(True);
  FFileNames := FileNames;
  FOptions := Options;
  FStartGate := StartGate;
  SetLength(FTexts, Length(FileNames));
end;

procedure TExtractionThread.Execute;
begin
  try
    FStartGate.WaitFor;
    for var Position := 0 to High(FFileNames) do
    begin
      FTexts[Position] := ExtractTextOf(FFileNames[Position]);
    end;
  except
    on Problem: Exception do
    begin
      FFailure := Format('%s: %s', [Problem.ClassName, Problem.Message]);
    end;
  end;
end;

function TExtractionThread.ExtractTextOf(const FileName: string): string;
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(FileName);

  const Document = TPdfDocument.Load(TCorpus.PdfPath(FileName), Options);
  Result := Document.ExtractText(FOptions);
end;

{ TFailingWriter }

procedure TFailingWriter.Write(const Value: string);
begin
  raise EWriteError.Create(DiskFullMessage);
end;

{ TForeignBookmark }

function TForeignBookmark.Title: string;
begin
  Result := 'Foreign';
end;

function TForeignBookmark.TryGetPageIndex(out Index: Integer): Boolean;
begin
  Index := 1;
  Result := True;
end;

function TForeignBookmark.Children: TArray<IPdfOutlineItem>;
begin
  Result := nil;
end;

{ TApiTextTests }

class function TApiTextTests.HasTextInFirstSection(const RelativePath: string): Boolean;
begin
  Result := False;

  const GoldenPath = TPath.Combine(TCorpus.GoldenFolder, TCorpus.GoldenName(RelativePath) + '.text.txt');
  if not TFile.Exists(GoldenPath) then
  begin
    Exit;
  end;

  var IsInFirstSection := False;
  for var Line in TFile.ReadAllLines(GoldenPath, TEncoding.UTF8) do
  begin
    const IsHeading = Line.StartsWith('text: ');
    if IsHeading then
    begin
      if IsInFirstSection then
      begin
        Exit;
      end;
      IsInFirstSection := (Line = FirstSectionHeading);
    end
    else if IsInFirstSection and Line.StartsWith('|') then
    begin
      Exit(True);
    end;
  end;
end;

class function TApiTextTests.CorpusFileNamesWithText(const Count: Integer): TArray<string>;
begin
  Result := nil;
  for var RelativePath in TCorpus.Files do
  begin
    if HasTextInFirstSection(RelativePath) then
    begin
      Result := Result + [RelativePath];
      if Length(Result) = Count then
      begin
        Exit;
      end;
    end;
  end;
end;

procedure TApiTextTests.Setup;
begin
  FStreams := TObjectList<TStream>.Create(True);
end;

procedure TApiTextTests.TearDown;
begin
  FStreams.Free;
end;

class function TApiTextTests.PageEndSlash: TPdfTextOptions;
begin
  Result := TPdfTextOptions.Default;
  Result.PageEnd := '/';
end;

function TApiTextTests.LoadBytes(const Data: TBytes): IPdfDocument;
begin
  const Stream = TBytesStream.Create(Data);
  FStreams.Add(Stream);
  Result := TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
end;

function TApiTextTests.LoadContent(const Content: string): IPdfDocument;
begin
  const Builder = TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, Content);
  try
    Result := LoadBytes(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;
end;

function TApiTextTests.LoadThreePagesWithBookmarks: IPdfDocument;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, '/Outlines 3 0 R');
  try
    const Letters = 'ABC';
    for var Index := 0 to 2 do
    begin
      Builder.AddObject(10 + Index, Format(PageBodyFormat, [20 + Index]));
      Builder.AddStreamObject(20 + Index, '', TEncoding.ASCII.GetBytes(Format('BT /F1 12 Tf 100 700 Td (%s) Tj ET', [Letters[Index + 1]])));
    end;
    Builder.AddObject(30, TTextTestDocuments.HelveticaF1);
    Builder.AddObject(3, OutlineRoot);
    Builder.AddObject(4, FirstBookmarkBody);
    Builder.AddObject(5, SecondBookmarkBody);
    Result := LoadBytes(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;
end;

procedure TApiTextTests.TestUsageExample;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(HelloFile));

  const Text = Document.ExtractText;

  Assert.IsTrue(Text.Contains('Hello'), Text);
end;

procedure TApiTextTests.TestPageRangeOption;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(EuropeanFile));
  var Options := TPdfTextOptions.Default;
  Options.StartPage := 2;
  Options.EndPage := 2;

  const Text = Document.ExtractText(Options).Trim;

  Assert.IsTrue(Text.StartsWith('Pesticides'), Text);
  Assert.IsTrue(Text.EndsWith('1 000 10 10'), Text);
  Assert.AreEqual(1378, Text.Replace(#13, '').Length);
end;

procedure TApiTextTests.TestPageExtractTextKeepsDocumentAlive;
begin
  var Document := TPdfDocument.Load(TCorpus.PdfPath(HelloFile));
  const Page = Document.Page(0);
  Document := nil;

  const Text = Page.ExtractText;

  Assert.IsTrue(Text.Contains('Hello'), Text);
end;

procedure TApiTextTests.TestPageExtractTextGivesOnlyThatPage;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(EuropeanFile));
  var Options := TPdfTextOptions.Default;
  Options.StartPage := 2;
  Options.EndPage := 2;

  const Expected = Document.ExtractText(Options);
  const Actual = Document.Page(1).ExtractText;

  Assert.AreEqual(Expected, Actual);
end;

procedure TApiTextTests.TestWriterOverload;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(EuropeanFile));
  const Writer = TStringWriter.Create;
  try
    Document.WriteText(Writer, TPdfTextOptions.Default);

    Assert.AreEqual(Document.ExtractText, Writer.ToString);
  finally
    Writer.Free;
  end;
end;

procedure TApiTextTests.TestDefaultOptionsEqualPdfBoxDefaults;
begin
  const Options = TPdfTextOptions.Default;

  Assert.IsFalse(Options.SortByPosition);
  Assert.AreEqual(1, Options.StartPage);
  Assert.AreEqual(MaxInt, Options.EndPage);
  Assert.IsTrue(Options.SuppressDuplicateOverlappingText);
  Assert.IsTrue(Options.ShouldSeparateByBeads);
  Assert.IsFalse(Options.AddMoreFormatting);
  Assert.IsFalse(Options.IgnoreContentStreamSpaceGlyphs);
  Assert.AreEqual(sLineBreak, Options.LineSeparator);
  Assert.AreEqual(' ', Options.WordSeparator);
  Assert.AreEqual(sLineBreak, Options.PageEnd);
  Assert.AreEqual('', Options.PageStart);
  Assert.AreEqual('', Options.ParagraphStart);
  Assert.AreEqual('', Options.ParagraphEnd);
  Assert.AreEqual('', Options.ArticleStart);
  Assert.AreEqual('', Options.ArticleEnd);
  Assert.AreEqual<Single>(0.5, Options.SpacingTolerance);
  Assert.AreEqual<Single>(0.3, Options.AverageCharTolerance);
  Assert.AreEqual<Single>(2.0, Options.IndentThreshold);
  Assert.AreEqual<Single>(2.5, Options.DropThreshold);
  Assert.IsFalse(Assigned(Options.StartBookmark));
  Assert.IsFalse(Assigned(Options.EndBookmark));
end;

procedure TApiTextTests.TestSeparatorOptionsAreApplied;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(HelloFile));
  var Options := TPdfTextOptions.Default;
  Options.PageStart := '<PAGE>';
  Options.PageEnd := '</PAGE>';

  const Text = Document.ExtractText(Options);

  Assert.IsTrue(Text.StartsWith('<PAGE>'), Text);
  Assert.IsTrue(Text.EndsWith('</PAGE>'), Text);
end;

procedure TApiTextTests.TestWordSeparatorOptionIsApplied;
begin
  const Document = LoadContent('BT /F1 12 Tf 1 0 0 1 100 700 Tm (Hello) Tj 1 0 0 1 137.4 700 Tm (World) Tj ET');
  var Options := PageEndSlash;
  Assert.AreEqual('Hello World/', Document.ExtractText(Options));

  Options.WordSeparator := '<W>';

  Assert.AreEqual('Hello<W>World/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestLineSeparatorOptionIsApplied;
begin
  const Document = LoadContent('BT /F1 12 Tf 1 0 0 1 100 700 Tm (A) Tj 1 0 0 1 100 686 Tm (B) Tj ET');
  var Options := PageEndSlash;
  Options.LineSeparator := '|';
  Assert.AreEqual('A|B/', Document.ExtractText(Options));

  Options.LineSeparator := '<L>';

  Assert.AreEqual('A<L>B/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestIgnoreContentStreamSpaceGlyphsOptionIsApplied;
begin
  // The texts are those of PDFBox 3.0.8 for the same page and setting
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (A  B) Tj ET');
  var Options := PageEndSlash;
  Assert.AreEqual('A  B/', Document.ExtractText(Options));

  Options.IgnoreContentStreamSpaceGlyphs := True;

  Assert.AreEqual('A B/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestSortByPositionOptionIsApplied;
begin
  const Document = LoadContent('BT /F1 12 Tf 100 700 Td (B) Tj ET BT /F1 12 Tf 100 720 Td (A) Tj ET');
  var Options := PageEndSlash;
  Options.LineSeparator := '|';
  Assert.AreEqual('B|A/', Document.ExtractText(Options));

  Options.SortByPosition := True;

  Assert.AreEqual('A|B/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestStartBookmarkSelectsTheFirstPage;
begin
  const Document = LoadThreePagesWithBookmarks;
  var Options := PageEndSlash;
  Options.StartBookmark := Document.Outline[1];

  Assert.AreEqual('B/C/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestEndBookmarkSelectsTheLastPage;
begin
  const Document = LoadThreePagesWithBookmarks;
  var Options := PageEndSlash;
  Options.EndBookmark := Document.Outline[1];

  Assert.AreEqual('A/B/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestStartAndEndBookmarkOfOnePage;
begin
  const Document = LoadThreePagesWithBookmarks;
  const Bookmarks = Document.Outline;
  var Options := PageEndSlash;
  Options.StartBookmark := Bookmarks[1];
  Options.EndBookmark := Bookmarks[1];

  Assert.AreEqual('B/', Document.ExtractText(Options));
end;

procedure TApiTextTests.TestForeignBookmarkIsAnArgumentError;
begin
  const Document = LoadThreePagesWithBookmarks;
  var Options := PageEndSlash;
  Options.StartBookmark := TForeignBookmark.Create;

  Assert.WillRaiseWithMessageRegex(
    procedure
    begin
      Document.ExtractText(Options);
    end, EArgumentException, ForeignBookmarkMessage);
end;

procedure TApiTextTests.TestBookmarkOfAnotherDocumentIsAnArgumentError;
begin
  const Document = LoadThreePagesWithBookmarks;
  const Other = LoadThreePagesWithBookmarks;
  var Options := PageEndSlash;
  Options.EndBookmark := Other.Outline[0];

  Assert.WillRaiseWithMessageRegex(
    procedure
    begin
      Document.ExtractText(Options);
    end, EArgumentException, OtherDocumentMessage);
end;

procedure TApiTextTests.TestNilWriterIsAnArgumentError;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(HelloFile));

  Assert.WillRaise(
    procedure
    begin
      Document.WriteText(nil, TPdfTextOptions.Default);
    end, EArgumentNilException);
end;

procedure TApiTextTests.TestGuardedWriterForwardsCharAndLines;
begin
  const Destination = TStringWriter.Create;
  try
    const Guarded = TPdfGuardedWriter.Create(Destination);
    try
      Guarded.Write('A');
      Guarded.Write(BChar);
      Guarded.WriteLine('C');
      Guarded.WriteLine;
    finally
      Guarded.Free;
    end;

    Assert.AreEqual(ForwardedText, Destination.ToString);
  finally
    Destination.Free;
  end;
end;

procedure TApiTextTests.TestWriterExceptionIsRaisedAsItWas;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath(HelloFile));
  const Writer = TFailingWriter.Create;
  try
    var Caught: Boolean := False;
    try
      Document.WriteText(Writer, TPdfTextOptions.Default);
    except
      on Failure: Exception do
      begin
        Caught := True;
        Assert.AreEqual(EWriteError.ClassName, Failure.ClassName);
        Assert.AreEqual(DiskFullMessage, Failure.Message);
      end;
    end;
    Assert.IsTrue(Caught, 'The writer exception must reach the caller');

    // The document is still usable
    Assert.IsTrue(Document.ExtractText.Contains('Hello'));
  finally
    Writer.Free;
  end;
end;

procedure TApiTextTests.CheckConcurrentExtraction(const SortByPosition: Boolean);
begin
  const Expected: Integer = ThreadCount * FilesPerThread;
  const FileNames = CorpusFileNamesWithText(Expected);
  const Actual: Integer = Length(FileNames);
  Assert.AreEqual(Expected, Actual);

  var Options := TPdfTextOptions.Default;
  Options.SortByPosition := SortByPosition;

  const StartGate = TEvent.Create(nil, True, False, '');
  const Workers = TObjectList<TExtractionThread>.Create(True);
  try
    for var Worker := 0 to ThreadCount - 1 do
    begin
      Workers.Add(TExtractionThread.Create(Copy(FileNames, Worker * FilesPerThread, FilesPerThread), Options, StartGate));
    end;
    for var Worker in Workers do
    begin
      Worker.Start;
    end;
    // All threads wait at the gate and start together
    StartGate.SetEvent;
    for var Worker in Workers do
    begin
      Worker.WaitFor;
      Assert.AreEqual('', Worker.Failure);
    end;

    for var Worker := 0 to ThreadCount - 1 do
    begin
      const Sequential = TExtractionThread.Create(Copy(FileNames, Worker * FilesPerThread, FilesPerThread), Options, StartGate);
      try
        Sequential.Start;
        Sequential.WaitFor;
        Assert.AreEqual('', Sequential.Failure);
        for var Position := 0 to FilesPerThread - 1 do
        begin
          const FileName = FileNames[(Worker * FilesPerThread) + Position];
          const Text = Workers[Worker].Texts[Position];
          Assert.IsTrue(Text <> '', FileName);
          const IsSame = (Sequential.Texts[Position] = Text);
          Assert.IsTrue(IsSame, FileName);
        end;
      finally
        Sequential.Free;
      end;
    end;
  finally
    Workers.Free;
    StartGate.Free;
  end;
end;

procedure TApiTextTests.TestConcurrentExtractionMatchesSequential;
begin
  CheckConcurrentExtraction(False);
end;

procedure TApiTextTests.TestConcurrentSortedExtractionMatchesSequential;
begin
  CheckConcurrentExtraction(True);
end;

end.
