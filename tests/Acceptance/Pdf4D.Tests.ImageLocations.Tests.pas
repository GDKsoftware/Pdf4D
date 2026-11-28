// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ImageLocations.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  DUnitX.Types,
  DUnitX.InternalDataProvider,
  DUnitX.TestDataProvider,
  DUnitX.TestFramework;

type
  // One test case per file of the corpus and per generated file of tests/corpus/generated/extract (which stay out of the manifest)
  TImageCorpusCaseProvider = class(TTestDataProvider)
  strict private
    FFiles: TArray<string>;

  public
    constructor Create; override;

    function GetCaseCount(const MethodName: string): Integer; override;
    function GetCaseName(const MethodName: string; const CaseNumber: Integer): string; override;
    function GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray; override;
  end;

  // The images that Pdf4D finds on every page must be those of PDFBox 3.0.8 (tests/golden/*.images.txt, written by PrintImageLocations
  // with the inline image added), under the rules of docs/golden-format.md ("Image location goldens")
  [TestFixture]
  TPdfImageLocationsTests = class
  strict private
    class function Dump(const RelativePath: string): string; static;
    class procedure SaveActual(const RelativePath, Actual: string); static;

  public
    class constructor Create;

    [Test]
    [TestCaseProvider('Pdf4DImageCorpus')]
    procedure TestCorpusMatchesPdfBox(const RelativePath: string);

    [Test]
    procedure TestComparerAllowsRoundingOfTheMatrix;

    [Test]
    procedure TestComparerRejectsAnotherSizeOrCountOrPosition;

    [Test]
    procedure TestComparerSkipsKnownPagesOnTheirPlatform;

    [Test]
    procedure TestComparerAlwaysComparesLoadErrors;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ImageLocations,
  Pdf4D.Tests.StructureDump,
  Pdf4D.Tests.TextGolden;

const
  ProviderName = 'Pdf4DImageCorpus';
  OutputEnvironmentVariable = 'PDF4D_GOLDEN_OUTPUT';
  MaxReportedDifferences = 20;
  ExtractFolder = 'generated/extract';

{ TImageCorpusCaseProvider }

constructor TImageCorpusCaseProvider.Create;
begin
  FFiles := TCorpus.Files;
  if TCorpus.Folder <> '' then
  begin
    const Generated = TPath.Combine(TCorpus.Folder, ExtractFolder.Replace('/', PathDelim));
    if TDirectory.Exists(Generated) then
    begin
      var Found := TDirectory.GetFiles(Generated, '*.pdf');
      TArray.Sort<string>(Found);
      for var Path in Found do
      begin
        FFiles := FFiles + [ExtractFolder + '/' + TPath.GetFileName(Path)];
      end;
    end;
  end;
end;

function TImageCorpusCaseProvider.GetCaseCount(const MethodName: string): Integer;
begin
  // Without a corpus there is one case that reports it
  Result := Length(FFiles);
  if Result = 0 then
  begin
    Result := 1;
  end;
end;

function TImageCorpusCaseProvider.GetCaseName(const MethodName: string; const CaseNumber: Integer): string;
begin
  if Length(FFiles) = 0 then
  begin
    Result := 'NoCorpus';
  end
  else
  begin
    Result := FFiles[CaseNumber];
  end;
end;

function TImageCorpusCaseProvider.GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray;
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

{ TPdfImageLocationsTests }

class constructor TPdfImageLocationsTests.Create;
begin
  TestDataProviderManager.RegisterProvider(ProviderName, TImageCorpusCaseProvider);
end;

class function TPdfImageLocationsTests.Dump(const RelativePath: string): string;
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  var Document: IPdfDocument := nil;
  try
    Document := TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  except
    on Failure: EPdfException do
    begin
      Exit(TStructureDump.DumpLoadError(Failure));
    end;
  end;
  // Strict, so that a crash fails the test instead of becoming an "error" line
  Result := TImageLocations.Dump(Document, True);
end;

// For looking at a difference: the lines that were found go to the folder in PDF4D_GOLDEN_OUTPUT
class procedure TPdfImageLocationsTests.SaveActual(const RelativePath, Actual: string);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, TCorpus.GoldenName(RelativePath) + '.images.txt'), TEncoding.UTF8.GetBytes(Actual));
  end;
end;

procedure TPdfImageLocationsTests.TestCorpusMatchesPdfBox(const RelativePath: string);
begin
  if RelativePath = '' then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const Expected = TFile.ReadAllText(TCorpus.ImagesGoldenPath(RelativePath), TEncoding.UTF8);
  const Actual = Dump(RelativePath);
  SaveActual(RelativePath, Actual);

  const Known = TTextGoldenComparer.LoadKnownDifferences(TCorpus.ImagesKnownDifferencesPath(RelativePath));
  const Differences = TImageLocations.Compare(Expected, Actual, Known, TTextGoldenComparer.CurrentPlatform);
  if Length(Differences) > 0 then
  begin
    const Reported = Copy(Differences, 0, MaxReportedDifferences);
    Assert.Fail(Format('%s: %d differences with PDFBox, the first %d:%s%s',
                       [RelativePath, Length(Differences), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
  end;
end;

procedure TPdfImageLocationsTests.TestComparerAllowsRoundingOfTheMatrix;
begin
  const Expected = '1 0 4 4 40.00 0.00 0.00 40.00 20.00 700.00'#10;
  const Actual = '1 0 4 4 40.01 0.00 -0.01 39.99 20.02 699.99'#10;

  Assert.AreEqual<Integer>(0, Length(TImageLocations.Compare(Expected, Actual, nil, 'Win64')));
end;

procedure TPdfImageLocationsTests.TestComparerRejectsAnotherSizeOrCountOrPosition;
begin
  const Expected = '1 0 4 4 40.00 0.00 0.00 40.00 20.00 700.00'#10;

  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, '1 0 5 4 40.00 0.00 0.00 40.00 20.00 700.00'#10, nil, 'Win64')), 'Width');
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, '1 0 4 4 40.00 0.00 0.00 40.00 20.00 700.50'#10, nil, 'Win64')), 'Position');
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, '', nil, 'Win64')), 'Missing image');
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, Expected + '1 1 4 4 40.00 0.00 0.00 40.00 20.00 700.00'#10, nil, 'Win64')), 'Extra image');
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, 'error 1'#10, nil, 'Win64')), 'Error');
end;

procedure TPdfImageLocationsTests.TestComparerSkipsKnownPagesOnTheirPlatform;
begin
  const Expected = '1 0 4 4 40.00 0.00 0.00 40.00 20.00 700.00'#10'2 0 4 4 1.00 0.00 0.00 1.00 0.00 0.00'#10;
  const Actual = '1 0 4 4 40.00 0.00 0.00 40.00 20.00 700.00'#10;

  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, Actual, nil, 'Win64')));
  Assert.AreEqual<Integer>(0, Length(TImageLocations.Compare(Expected, Actual, ['2 # a reason'], 'Win64')));
  Assert.AreEqual<Integer>(0, Length(TImageLocations.Compare(Expected, Actual, ['2 Win64 # a reason'], 'Win64')));
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, Actual, ['2 Linux64 # a reason'], 'Win64')));
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare(Expected, Actual, ['1 # a reason'], 'Win64')), 'Another page');
end;

procedure TPdfImageLocationsTests.TestComparerAlwaysComparesLoadErrors;
begin
  Assert.AreEqual<Integer>(0, Length(TImageLocations.Compare('load-error: parse'#10, 'load-error: parse'#10, ['1 # a reason'], 'Win64')));
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare('load-error: parse'#10, '', nil, 'Win64')));
  Assert.AreEqual<Integer>(1, Length(TImageLocations.Compare('', 'load-error: parse'#10, nil, 'Win64')));
end;

end.
