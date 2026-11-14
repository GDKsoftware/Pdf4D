// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Text.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework;

type
  // Loads documents on its own thread and keeps the text of each, or the message of the exception
  TExtractionThread = class(TThread)
  private
    FFileNames: TArray<string>;
    FTexts: TArray<string>;
    FFailure: string;

    function ExtractTextOf(const FileName: string): string;

  protected
    procedure Execute; override;

  public
    constructor Create(const FileNames: TArray<string>);

    property Texts: TArray<string> read FTexts;
    property Failure: string read FFailure;
  end;

  [TestFixture]
  TApiTextTests = class
  private
    class function CorpusFileNamesWithText(const Count: Integer): TArray<string>; static;
    class function HasTextInFirstSection(const RelativePath: string): Boolean; static;

  public
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
    procedure TestConcurrentExtractionMatchesSequential;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.TextOptions,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.Corpus;

const
  FirstSectionHeading = 'text: default page 1';
  ThreadCount = 4;
  FilesPerThread = 5;

{ TExtractionThread }

constructor TExtractionThread.Create(const FileNames: TArray<string>);
begin
  inherited Create(True);
  FFileNames := FileNames;
  SetLength(FTexts, Length(FileNames));
end;

procedure TExtractionThread.Execute;
begin
  try
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
  Result := Document.ExtractText;
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

procedure TApiTextTests.TestUsageExample;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath('pdfbox/input/hello3.pdf'));

  const Text = Document.ExtractText;

  Assert.IsTrue(Text.Contains('Hello'), Text);
end;

procedure TApiTextTests.TestPageRangeOption;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath('pdfbox/input/eu-001.pdf'));
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
  var Document := TPdfDocument.Load(TCorpus.PdfPath('pdfbox/input/hello3.pdf'));
  const Page = Document.Page(0);
  Document := nil;

  const Text = Page.ExtractText;

  Assert.IsTrue(Text.Contains('Hello'), Text);
end;

procedure TApiTextTests.TestPageExtractTextGivesOnlyThatPage;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath('pdfbox/input/eu-001.pdf'));
  var Options := TPdfTextOptions.Default;
  Options.StartPage := 2;
  Options.EndPage := 2;

  const Expected = Document.ExtractText(Options);
  const Actual = Document.Page(1).ExtractText;

  Assert.AreEqual(Expected, Actual);
end;

procedure TApiTextTests.TestWriterOverload;
begin
  const Document = TPdfDocument.Load(TCorpus.PdfPath('pdfbox/input/eu-001.pdf'));
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
  const Document = TPdfDocument.Load(TCorpus.PdfPath('pdfbox/input/hello3.pdf'));
  var Options := TPdfTextOptions.Default;
  Options.PageStart := '<PAGE>';
  Options.PageEnd := '</PAGE>';

  const Text = Document.ExtractText(Options);

  Assert.IsTrue(Text.StartsWith('<PAGE>'), Text);
  Assert.IsTrue(Text.EndsWith('</PAGE>'), Text);
end;

procedure TApiTextTests.TestConcurrentExtractionMatchesSequential;
begin
  const Expected: Integer = ThreadCount * FilesPerThread;
  const FileNames = CorpusFileNamesWithText(Expected);
  const Actual: Integer = Length(FileNames);
  Assert.AreEqual(Expected, Actual);

  const Workers = TObjectList<TExtractionThread>.Create(True);
  try
    for var Worker := 0 to ThreadCount - 1 do
    begin
      Workers.Add(TExtractionThread.Create(Copy(FileNames, Worker * FilesPerThread, FilesPerThread)));
    end;
    for var Worker in Workers do
    begin
      Worker.Start;
    end;
    for var Worker in Workers do
    begin
      Worker.WaitFor;
      Assert.AreEqual('', Worker.Failure);
    end;

    for var Worker := 0 to ThreadCount - 1 do
    begin
      const Sequential = TExtractionThread.Create(Copy(FileNames, Worker * FilesPerThread, FilesPerThread));
      try
        Sequential.Start;
        Sequential.WaitFor;
        Assert.AreEqual('', Sequential.Failure);
        for var Position := 0 to FilesPerThread - 1 do
        begin
          const IsSame = (Sequential.Texts[Position] = Workers[Worker].Texts[Position]);
          Assert.IsTrue(IsSame, FileNames[(Worker * FilesPerThread) + Position]);
        end;
      finally
        Sequential.Free;
      end;
    end;
  finally
    Workers.Free;
  end;
end;

end.
