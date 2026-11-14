// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/test/java/org/apache/pdfbox/text/TestTextStripper.java (3.0.8)
unit Pdf4D.Tests.PdfBoxText.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Rtti,
  DUnitX.Types,
  DUnitX.InternalDataProvider,
  DUnitX.TestDataProvider,
  DUnitX.TestFramework,
  Pdf4D.Font.Base,
  Pdf4D.Model.Document,
  Pdf4D.Text.Stripper;

type
  // The lines of a text, handed out one at a time with the blank lines skipped
  TNonBlankLineReader = record
  strict private
    FLines: TArray<string>;
    FPosition: Integer;

  public
    constructor Create(const Lines: TArray<string>);

    // False when no line is left
    function TryReadNonBlank(out Line: string): Boolean;
    // The number of lines read so far, the blank ones included
    property Position: Integer read FPosition;
  end;

  // The comparison of TestTextStripper.compareResult and stringsEqual: blank lines are skipped, a line is trimmed, and a space
  // or a character above 256 in the one text may stand for a run of them in the other
  TPdfBoxTextComparer = record
  strict private
    class function SplitLines(const Text: string): TArray<string>; static;
    class function IsBlank(const Line: string): Boolean; static;
    class function SkipWhitespace(const Chars: TCharArray; const Index: Integer): Integer; static;
    class function NullableEqual(const HasExpected: Boolean; const Expected: string; const HasActual: Boolean; const Actual: string): Boolean; static;

  public
    // Both lines are not null
    class function StringsEqual(const Expected, Actual: string): Boolean; static;
    // One text per line that differs, with the line numbers and both lines. Empty when the texts are equal.
    class function Compare(const Expected, Actual: string): TArray<string>; static;
  end;

  // One test case per expected text file of the PDFBox test suite in tests/reference/pdfbox-text
  TPdfBoxTextCaseProvider = class(TTestDataProvider)
  strict private
    FFiles: TArray<string>;

  public
    constructor Create; override;

    function GetCaseCount(const MethodName: string): Integer; override;
    function GetCaseName(const MethodName: string; const CaseNumber: Integer): string; override;
    function GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray; override;
  end;

  // Subclass of TestTextStripper.PDFTabulaTextStripper: the font height as PDFBox calculated it for Tabula
  TTabulaTextStripper = class(TPdfTextStripper)
  protected
    function ComputeFontHeight(const Font: TPDFont): Single; override;
  end;

  // The text of the PDF files that PDFBox ships with its tests must equal the expected text files of that test suite, by the
  // rules of TestTextStripper (docs/golden-format.md has the other reference, the oracle goldens)
  [TestFixture]
  TPdfBoxTextTests = class
  strict private
    class function ReferenceFolder: string; static;
    class function ReferenceName(const File_: string): string; static;
    class function IsSorted(const File_: string): Boolean; static;
    class function CorpusPathOf(const File_: string): string; static;
    class function KnownDifference(const File_: string; out Reason: string): Boolean; static;
    class function LoadDocument(const PdfPath: string): TPDDocument; static;
    class function WithoutBom(const Text: string): string; static;
    class function WithoutCarriageReturns(const Text: string): string; static;
    class procedure SaveActual(const File_, Actual: string); static;
    class function OutlineItemPageIndex(const Item: TObject): Integer; static;

  public
    class constructor Create;

    [Test]
    [TestCaseProvider(TPdfBoxTextCaseProvider)]
    procedure TestMatchesPdfBoxReference(const File_: string);

    [Test]
    procedure TestStripByOutlineItems;

    [Test]
    procedure TestStartEndPage;

    [Test]
    procedure TestIgnoreContentStreamSpaceGlyphs;

    [Test]
    procedure TestTabula;

    [Test]
    [TestCase('Equal', 'abc,abc,True')]
    [TestCase('Different', 'abc,abd,False')]
    [TestCase('OuterSpacesAreTrimmed', ' abc ,abc,True')]
    [TestCase('ExpectedLonger', 'abcd,abc,False')]
    [TestCase('ActualLonger', 'abc,abcd,False')]
    [TestCase('SpaceRunIsNotEqualToOneSpace', 'a  b,a b,False')]
    [TestCase('SameSpaceRun', 'a  b,a  b,True')]
    procedure TestStringsEqual(const Expected, Actual: string; const IsEqual: Boolean);

    [Test]
    procedure TestCompareSkipsBlankLines;

    [Test]
    procedure TestCompareReportsMissingLines;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Type3,
  Pdf4D.Model.Outline,
  Pdf4D.Model.OutlineItem,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Text.TextPosition,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.TextDocuments;

const
  ProviderName = 'Pdf4DPdfBoxText';
  OutputEnvironmentVariable = 'PDF4D_GOLDEN_OUTPUT';
  KnownDifferencesName = 'known-differences.txt';
  SortedSuffix = '-sorted.txt';
  TabulaSuffix = '-tabula.txt';
  TextSuffix = '.txt';
  SavedFileFormat = 'reference__%s';
  KnownDifferenceFormat = 'Known difference: %s';
  ReferenceTextPath = 'reference' + PathDelim + 'pdfbox-text';
  BidiSamplePrefix = 'BidiSample.pdf';
  InputFolder = 'pdfbox/input/';
  BidiSampleFolder = 'pdfbox/org/apache/pdfbox/text/';
  WithOutlinePath = 'pdfbox/org/apache/pdfbox/pdmodel/with_outline.pdf';
  TabulaPdf = 'pdfbox/input/eu-001.pdf';
  TabulaReference = 'eu-001.pdf-tabula.txt';
  ReasonSeparator = ' # ';
  MaxReportedDifferences = 20;
  ShortMinValue = -32768;
  ShortRange = 65536;
  Thousand: Single = 1000;
  TimesRomanFont = '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>';

{ TNonBlankLineReader }

constructor TNonBlankLineReader.Create(const Lines: TArray<string>);
begin
  FLines := Lines;
  FPosition := 0;
end;

function TNonBlankLineReader.TryReadNonBlank(out Line: string): Boolean;
begin
  Line := '';
  while (FPosition < Length(FLines)) and (FLines[FPosition].Trim = '') do
  begin
    Inc(FPosition);
  end;

  Result := FPosition < Length(FLines);
  if Result then
  begin
    Line := FLines[FPosition];
    Inc(FPosition);
  end;
end;

{ TPdfBoxTextComparer }

class function TPdfBoxTextComparer.SplitLines(const Text: string): TArray<string>;
begin
  // As BufferedReader.readLine: a line ends at LF, CR or CRLF, and the end of the text ends the last line
  var Lines := TList<string>.Create;
  try
    var Start := 1;
    var Index := 1;
    while Index <= Text.Length do
    begin
      if (Text[Index] = #10) or (Text[Index] = #13) then
      begin
        Lines.Add(Copy(Text, Start, Index - Start));
        if (Text[Index] = #13) and (Index < Text.Length) and (Text[Index + 1] = #10) then
        begin
          Inc(Index);
        end;
        Start := Index + 1;
      end;
      Inc(Index);
    end;
    if Start <= Text.Length then
    begin
      Lines.Add(Copy(Text, Start, Text.Length - Start + 1));
    end;
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

class function TPdfBoxTextComparer.IsBlank(const Line: string): Boolean;
begin
  // String.trim removes the characters up to the space, as Trim does
  Result := Line.Trim = '';
end;

class function TPdfBoxTextComparer.SkipWhitespace(const Chars: TCharArray; const Index: Integer): Integer;
begin
  Result := Index;
  // At a space, or a character above 256, all of them are skipped; the position goes back one because the caller goes forward
  if (Chars[Result] = ' ') or (Ord(Chars[Result]) > 256) then
  begin
    while (Result < Length(Chars)) and ((Chars[Result] = ' ') or (Ord(Chars[Result]) > 256)) do
    begin
      Inc(Result);
    end;
    Dec(Result);
  end;
end;

class function TPdfBoxTextComparer.StringsEqual(const Expected, Actual: string): Boolean;
begin
  const ExpectedChars = Expected.Trim.ToCharArray;
  const ActualChars = Actual.Trim.ToCharArray;
  var ExpectedIndex := 0;
  var ActualIndex := 0;
  Result := True;
  while (ExpectedIndex < Length(ExpectedChars)) and (ActualIndex < Length(ActualChars)) do
  begin
    if ExpectedChars[ExpectedIndex] <> ActualChars[ActualIndex] then
    begin
      Result := False;
      Break;
    end;
    ExpectedIndex := SkipWhitespace(ExpectedChars, ExpectedIndex) + 1;
    ActualIndex := SkipWhitespace(ActualChars, ActualIndex) + 1;
  end;

  if Result then
  begin
    Result := ((ExpectedIndex = Length(ExpectedChars)) and (ActualIndex = Length(ActualChars)) and
               (Length(ExpectedChars) = Length(ActualChars)));
  end;
end;

class function TPdfBoxTextComparer.NullableEqual(const HasExpected: Boolean; const Expected: string; const HasActual: Boolean; const Actual: string): Boolean;
begin
  if (not HasExpected) and (not HasActual) then
  begin
    Exit(True);
  end;
  if HasExpected and HasActual then
  begin
    Exit(StringsEqual(Expected, Actual));
  end;
  // One of them is null: equal only when the other is blank
  Result := ((not HasExpected) and IsBlank(Actual)) or ((not HasActual) and IsBlank(Expected));
end;

class function TPdfBoxTextComparer.Compare(const Expected, Actual: string): TArray<string>;
begin
  var ExpectedReader := TNonBlankLineReader.Create(SplitLines(Expected));
  var ActualReader := TNonBlankLineReader.Create(SplitLines(Actual));
  var Differences := TList<string>.Create;
  try
    while True do
    begin
      var ExpectedLine: string;
      var ActualLine: string;
      const HasExpected = ExpectedReader.TryReadNonBlank(ExpectedLine);
      const HasActual = ActualReader.TryReadNonBlank(ActualLine);
      if not NullableEqual(HasExpected, ExpectedLine, HasActual, ActualLine) then
      begin
        Differences.Add(Format('expected line %d, actual line %d:%s  expected: "%s"%s  actual:   "%s"',
                               [ExpectedReader.Position, ActualReader.Position, sLineBreak, ExpectedLine, sLineBreak, ActualLine]));
      end;
      if (not HasExpected) or (not HasActual) then
      begin
        Break;
      end;
    end;
    Result := Differences.ToArray;
  finally
    Differences.Free;
  end;
end;

{ TPdfBoxTextCaseProvider }

constructor TPdfBoxTextCaseProvider.Create;
begin
  // TTestDataProvider.Create is abstract: no inherited call
  const Folder = TCorpus.Folder;
  if Folder = '' then
  begin
    Exit;
  end;

  const ReferenceFolder = TPath.Combine(TPath.GetDirectoryName(Folder), ReferenceTextPath);
  if not TDirectory.Exists(ReferenceFolder) then
  begin
    Exit;
  end;

  for var Path in TDirectory.GetFiles(ReferenceFolder, '*' + TextSuffix) do
  begin
    const Name = TPath.GetFileName(Path);
    // The tabula text has its own test
    if (Name <> KnownDifferencesName) and (not Name.EndsWith(TabulaSuffix)) then
    begin
      FFiles := FFiles + [Name];
    end;
  end;
  TArray.Sort<string>(FFiles);
end;

function TPdfBoxTextCaseProvider.GetCaseCount(const MethodName: string): Integer;
begin
  // Without the reference texts there is one case that reports it
  Result := Length(FFiles);
  if Result = 0 then
  begin
    Result := 1;
  end;
end;

function TPdfBoxTextCaseProvider.GetCaseName(const MethodName: string; const CaseNumber: Integer): string;
begin
  if Length(FFiles) = 0 then
  begin
    Result := 'NoReferenceTexts';
  end
  else
  begin
    Result := FFiles[CaseNumber];
  end;
end;

function TPdfBoxTextCaseProvider.GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray;
begin
  SetLength(Result, 1);
  if Length(FFiles) = 0 then
  begin
    Result[0] := '';
  end
  else
  begin
    Result[0] := FFiles[CaseNumber];
  end;
end;

{ TTabulaTextStripper }

function TTabulaTextStripper.ComputeFontHeight(const Font: TPDFont): Single;
begin
  var BoundingBox := Font.GetBoundingBox;
  if BoundingBox.LowerLeftY < ShortMinValue then
  begin
    // PDFBOX-2158 and PDFBOX-3130
    BoundingBox.LowerLeftY := -(BoundingBox.LowerLeftY + ShortRange);
  end;
  var GlyphHeight := BoundingBox.Height / 2;

  var Descriptor: TPDFontDescriptor;
  if Font.TryGetFontDescriptor(Descriptor) then
  begin
    // Sometimes the bounding box has very high values, but the cap height is fine
    const CapHeight = Descriptor.CapHeight;
    if (not TJavaFloat.IsSame(CapHeight, 0)) and ((CapHeight < GlyphHeight) or TJavaFloat.IsSame(GlyphHeight, 0)) then
    begin
      GlyphHeight := CapHeight;
    end;
    // PDFBOX-3464, PDFBOX-448: sometimes even the cap height has a very high value, but ascent and descent are fine
    const Ascent = Descriptor.Ascent;
    const Descent = Descriptor.Descent;
    if (Ascent > 0) and (Descent < 0) and (((Ascent - Descent) / 2 < GlyphHeight) or TJavaFloat.IsSame(GlyphHeight, 0)) then
    begin
      GlyphHeight := (Ascent - Descent) / 2;
    end;
  end;

  if Font is TPDType3Font then
  begin
    Result := Font.GetFontMatrix.TransformPoint(0, GlyphHeight).Y;
  end
  else
  begin
    Result := GlyphHeight / Thousand;
  end;
end;

{ TPdfBoxTextTests }

class constructor TPdfBoxTextTests.Create;
begin
  TestDataProviderManager.RegisterProvider(ProviderName, TPdfBoxTextCaseProvider);
end;

class function TPdfBoxTextTests.ReferenceFolder: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), ReferenceTextPath);
end;

// The name of the PDF that an expected text belongs to
class function TPdfBoxTextTests.ReferenceName(const File_: string): string;
begin
  Result := File_;
  if Result.EndsWith(SortedSuffix) then
  begin
    Result := Result.Substring(0, Result.Length - SortedSuffix.Length);
  end
  else
  begin
    Result := Result.Substring(0, Result.Length - TextSuffix.Length);
  end;
end;

class function TPdfBoxTextTests.IsSorted(const File_: string): Boolean;
begin
  Result := File_.EndsWith(SortedSuffix);
end;

class function TPdfBoxTextTests.CorpusPathOf(const File_: string): string;
begin
  const PdfName = ReferenceName(File_);
  if PdfName.StartsWith(BidiSamplePrefix) then
  begin
    Result := BidiSampleFolder + PdfName;
  end
  else
  begin
    Result := InputFolder + PdfName;
  end;
end;

class function TPdfBoxTextTests.KnownDifference(const File_: string; out Reason: string): Boolean;
begin
  Reason := '';
  Result := False;
  const Path = TPath.Combine(ReferenceFolder, KnownDifferencesName);
  if not TFile.Exists(Path) then
  begin
    Exit;
  end;

  for var Line in TFile.ReadAllLines(Path, TEncoding.UTF8) do
  begin
    if Line.StartsWith('#') or (Line.Trim = '') then
    begin
      Continue;
    end;

    const Position = Line.IndexOf(ReasonSeparator);
    if (Position > 0) and (Line.Substring(0, Position).Trim = File_) then
    begin
      Reason := Line.Substring(Position + ReasonSeparator.Length).Trim;
      Exit(True);
    end;
  end;
end;

class function TPdfBoxTextTests.LoadDocument(const PdfPath: string): TPDDocument;
begin
  Result := TPDDocument.Load(TFileStream.Create(PdfPath, fmOpenRead or fmShareDenyWrite), True, TPdfLoadOptions.Default);
end;

class function TPdfBoxTextTests.WithoutBom(const Text: string): string;
begin
  Result := Text;
  if Result.StartsWith(#$FEFF) then
  begin
    Result := Result.Substring(1);
  end;
end;

class function TPdfBoxTextTests.WithoutCarriageReturns(const Text: string): string;
begin
  Result := Text.Replace(#13, '');
end;

// For looking at a difference: the text that was found goes to the folder in PDF4D_GOLDEN_OUTPUT
class procedure TPdfBoxTextTests.SaveActual(const File_, Actual: string);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, Format(SavedFileFormat, [File_])), TEncoding.UTF8.GetBytes(Actual));
  end;
end;

class function TPdfBoxTextTests.OutlineItemPageIndex(const Item: TObject): Integer;
begin
  Result := -1;
  var PageIndex: Integer;
  if (Item as TPDOutlineItem).TryGetPageIndex(PageIndex) then
  begin
    Result := PageIndex;
  end;
end;

procedure TPdfBoxTextTests.TestMatchesPdfBoxReference(const File_: string);
begin
  if File_ = '' then
  begin
    Assert.Fail('The corpus or the reference texts were not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  var Reason: string;
  if KnownDifference(File_, Reason) then
  begin
    Assert.Pass(Format(KnownDifferenceFormat, [Reason]));
    Exit;
  end;

  // TestTextStripper.init: a stripper with the line separator LF, and doTestFile: sorted by the name of the expected file
  const Stripper = TPdfTextStripper.Create;
  try
    Stripper.LineSeparator := #10;
    Stripper.SortByPosition := IsSorted(File_);
    const Document = LoadDocument(TCorpus.PdfPath(CorpusPathOf(File_)));
    try
      const Actual = Stripper.GetText(Document);
      SaveActual(File_, Actual);
      const Expected = WithoutBom(TFile.ReadAllText(TPath.Combine(ReferenceFolder, File_), TEncoding.UTF8));
      const Differences = TPdfBoxTextComparer.Compare(Expected, Actual);
      if Length(Differences) > 0 then
      begin
        const Reported = Copy(Differences, 0, MaxReportedDifferences);
        Assert.Fail(Format('%s: %d lines differ from the PDFBox test, the first %d:%s%s',
                           [File_, Length(Differences), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
      end;
    finally
      Document.Free;
    end;
  finally
    Stripper.Free;
  end;
end;

// Test whether stripping controlled by outline items works properly. The file has 4 outline items at the top level, that
// point to the 0-based pages 0, 2, 3 and 4.
procedure TPdfBoxTextTests.TestStripByOutlineItems;
begin
  const Document = LoadDocument(TCorpus.PdfPath(WithOutlinePath));
  try
    var Outline: TPDDocumentOutline;
    Assert.IsTrue(Document.Catalog.TryGetOutline(Outline));
    const Items = Outline.Children;
    Assert.AreEqual<Integer>(4, Length(Items));
    Assert.AreEqual<Integer>(0, OutlineItemPageIndex(Items[0]));
    Assert.AreEqual<Integer>(2, OutlineItemPageIndex(Items[1]));
    Assert.AreEqual<Integer>(3, OutlineItemPageIndex(Items[2]));
    Assert.AreEqual<Integer>(4, OutlineItemPageIndex(Items[3]));

    const Stripper = TPdfTextStripper.Create;
    try
      Stripper.LineSeparator := #10;
      const TextFull = Stripper.GetText(Document);
      Assert.IsFalse(TextFull.IsEmpty);
      const ExpectedTextFull = 'First level 1'#10 + 'First level 2'#10 + 'Fist level 3'#10 + 'Some content'#10 +
                               'Some other content'#10 + 'Second at level 1'#10 + 'Second level 2'#10 + 'Content'#10 +
                               'Third level 1'#10 + 'Third level 2'#10 + 'Third level 3'#10 + 'Content'#10 +
                               'Fourth level 1'#10 + 'Content'#10 + 'Content'#10;
      Assert.AreEqual(ExpectedTextFull, WithoutCarriageReturns(TextFull));

      // 0-based pages 2 and 3, 1-based pages 3 and 4, by their bookmarks
      Stripper.StartBookmark := Items[1];
      Stripper.EndBookmark := Items[2];
      const TextOi23 = Stripper.GetText(Document);
      Assert.IsFalse(TextOi23.IsEmpty);
      Assert.AreNotEqual(TextFull, TextOi23);
      const ExpectedTextOi23 = 'Second at level 1'#10 + 'Second level 2'#10 + 'Content'#10 + 'Third level 1'#10 +
                               'Third level 2'#10 + 'Third level 3'#10 + 'Content'#10;
      Assert.AreEqual(ExpectedTextOi23, WithoutCarriageReturns(TextOi23));

      // the same pages by their page numbers
      Stripper.StartBookmark := nil;
      Stripper.EndBookmark := nil;
      Stripper.StartPage := 3;
      Stripper.EndPage := 4;
      const TextP34 = Stripper.GetText(Document);
      Assert.IsFalse(TextP34.IsEmpty);
      Assert.AreEqual(TextOi23, TextP34);

      // 0-based page 2, 1-based page 3, by the bookmark
      Stripper.StartBookmark := Items[1];
      Stripper.EndBookmark := Items[1];
      const TextOi2 = Stripper.GetText(Document);
      Assert.IsFalse(TextOi2.IsEmpty);
      Assert.AreNotEqual(TextOi23, TextOi2);
      const ExpectedTextOi2 = 'Second at level 1'#10 + 'Second level 2'#10 + 'Content'#10;
      Assert.AreEqual(ExpectedTextOi2, WithoutCarriageReturns(TextOi2));

      // and by the page number
      Stripper.StartBookmark := nil;
      Stripper.EndBookmark := nil;
      Stripper.StartPage := 3;
      Stripper.EndPage := 3;
      const TextP3 = Stripper.GetText(Document);
      Assert.IsFalse(TextP3.IsEmpty);
      Assert.AreNotEqual(TextP34, TextP3);
      Assert.AreEqual(TextOi2, TextP3);

      // an orphan bookmark: no text
      const OrphanDictionary = TCosDictionary.Create;
      try
        const Orphan = TPDOutlineItem.Create(OrphanDictionary, nil);
        try
          Stripper.StartBookmark := Orphan;
          Stripper.EndBookmark := Orphan;
          Assert.IsTrue(Stripper.GetText(Document).IsEmpty);
        finally
          Stripper.StartBookmark := nil;
          Stripper.EndBookmark := nil;
          Orphan.Free;
        end;
      finally
        OrphanDictionary.Free;
      end;
    finally
      Stripper.Free;
    end;
  finally
    Document.Free;
  end;
end;

// Check that setting start and end pages work properly
procedure TPdfBoxTextTests.TestStartEndPage;
begin
  const Document = LoadDocument(TCorpus.PdfPath(TabulaPdf));
  try
    const Stripper = TPdfTextStripper.Create;
    try
      Stripper.StartPage := 2;
      Stripper.EndPage := 2;
      const Text = Stripper.GetText(Document).Trim;
      Assert.IsTrue(Text.StartsWith('Pesticides'));
      Assert.IsTrue(Text.EndsWith('1 000 10 10'));
      Assert.AreEqual<Integer>(1378, WithoutCarriageReturns(Text).Length);
    finally
      Stripper.Free;
    end;
  finally
    Document.Free;
  end;
end;

// PDFBOX-3774: test the IgnoreContentStreamSpaceGlyphs option. The first text is a run of spaces between parentheses in
// Helvetica 8 at (50, 742), the second is "overlap" in Times-Roman 16 at x = 50 + 6 times the average width of Helvetica, which
// is 542.7714 per mille, times 8 per mille.
procedure TPdfBoxTextTests.TestIgnoreContentStreamSpaceGlyphs;
begin
  const Spaces = StringOfChar(' ', 38);
  const Content = Format('BT /F1 8 Tf 50 742 Td (\(%s\)) Tj ET BT /F2 16 Tf 76.05302 742 Td (overlap) Tj ET', [Spaces]);
  const Fonts = TTextTestDocuments.HelveticaF1 + TTextTestDocuments.Separator + TimesRomanFont;
  const Models = TModelTestDocuments.Create;
  try
    const Builder = TTextTestDocuments.NewBuilder(Fonts, Content);
    try
      const Document = Models.Open(Builder);
      const Stripper = TPdfTextStripper.Create;
      try
        Stripper.LineSeparator := #10;
        Stripper.PageEnd := #10;
        Stripper.StartPage := 1;
        Stripper.EndPage := 1;
        Stripper.SortByPosition := True;
        Stripper.IgnoreContentStreamSpaceGlyphs := True;
        Assert.AreEqual('( overlap )'#10, Stripper.GetText(Document));
      finally
        Stripper.Free;
      end;
    finally
      Builder.Free;
    end;
  finally
    Models.Free;
  end;
end;

procedure TPdfBoxTextTests.TestTabula;
begin
  const Document = LoadDocument(TCorpus.PdfPath(TabulaPdf));
  try
    const Stripper = TTabulaTextStripper.Create;
    try
      const Actual = Stripper.GetText(Document);
      SaveActual(TabulaReference, Actual);
      const Expected = WithoutBom(TFile.ReadAllText(TPath.Combine(ReferenceFolder, TabulaReference), TEncoding.UTF8));
      const Differences = TPdfBoxTextComparer.Compare(Expected, Actual);
      if Length(Differences) > 0 then
      begin
        const Reported = Copy(Differences, 0, MaxReportedDifferences);
        Assert.Fail(Format('%s: %d lines differ from the PDFBox test, the first %d:%s%s',
                           [TabulaReference, Length(Differences), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
      end;
    finally
      Stripper.Free;
    end;
  finally
    Document.Free;
  end;
end;

procedure TPdfBoxTextTests.TestStringsEqual(const Expected, Actual: string; const IsEqual: Boolean);
begin
  Assert.AreEqual(IsEqual, TPdfBoxTextComparer.StringsEqual(Expected, Actual));
end;

procedure TPdfBoxTextTests.TestCompareSkipsBlankLines;
begin
  const Expected = 'one'#13#10#13#10'  '#10'two'#10;
  const Actual = 'one'#10'two'#13;

  Assert.AreEqual<Integer>(0, Length(TPdfBoxTextComparer.Compare(Expected, Actual)));
end;

procedure TPdfBoxTextTests.TestCompareReportsMissingLines;
begin
  Assert.AreEqual<Integer>(1, Length(TPdfBoxTextComparer.Compare('one'#10'two'#10, 'one'#10)));
  Assert.AreEqual<Integer>(1, Length(TPdfBoxTextComparer.Compare('one'#10, 'one'#10'two'#10)));
  Assert.AreEqual<Integer>(1, Length(TPdfBoxTextComparer.Compare('one'#10'two'#10, 'one'#10'three'#10)));
end;

end.
