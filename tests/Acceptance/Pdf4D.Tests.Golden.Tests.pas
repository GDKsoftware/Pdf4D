// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Tests.Golden.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  DUnitX.Types,
  DUnitX.InternalDataProvider,
  DUnitX.TestDataProvider,
  DUnitX.TestFramework;

type
  // One test case per file of the corpus
  TCorpusCaseProvider = class(TTestDataProvider)
  strict private
    FFiles: TArray<string>;

  public
    constructor Create; override;

    function GetCaseCount(const MethodName: string): Integer; override;
    function GetCaseName(const MethodName: string; const CaseNumber: Integer): string; override;
    function GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray; override;
  end;

  // The structure dump of every corpus file must equal what PDFBox 3.0.8 made of it (tests/golden, docs/golden-format.md)
  [TestFixture]
  TGoldenTests = class
  strict private
    class function Dump(const RelativePath: string): string; static;
    class procedure SaveActual(const RelativePath, Actual: string); static;

  public
    class constructor Create;

    [Test]
    [TestCaseProvider(TCorpusCaseProvider)]
    procedure TestCorpusMatchesPdfBox(const RelativePath: string);
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.Golden,
  Pdf4D.Tests.StructureDump;

const
  ProviderName = 'Pdf4DCorpus';
  OutputEnvironmentVariable = 'PDF4D_GOLDEN_OUTPUT';
  MaxReportedDifferences = 20;

{ TCorpusCaseProvider }

constructor TCorpusCaseProvider.Create;
begin
  FFiles := TCorpus.Files;
end;

function TCorpusCaseProvider.GetCaseCount(const MethodName: string): Integer;
begin
  // Without a corpus there is one case that reports it
  Result := Length(FFiles);
  if Result = 0 then
  begin
    Result := 1;
  end;
end;

function TCorpusCaseProvider.GetCaseName(const MethodName: string; const CaseNumber: Integer): string;
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

function TCorpusCaseProvider.GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray;
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

{ TGoldenTests }

class constructor TGoldenTests.Create;
begin
  TestDataProviderManager.RegisterProvider(ProviderName, TCorpusCaseProvider);
end;

class function TGoldenTests.Dump(const RelativePath: string): string;
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  // The dump is strict, so that a crash in a section fails the test instead of becoming an "error" line. The document is
  // released when the method ends, before the next file is loaded.
  var Document: IPdfDocument := nil;
  try
    Document := TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  except
    on Failure: EPdfException do
    begin
      Exit(TStructureDump.DumpLoadError(Failure));
    end;
  end;
  Result := TStructureDump.Dump(Document, True);
end;

// For looking at a difference: the text that was found goes to the folder in PDF4D_GOLDEN_OUTPUT
class procedure TGoldenTests.SaveActual(const RelativePath, Actual: string);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, TCorpus.GoldenName(RelativePath) + '.dump.txt'), TEncoding.UTF8.GetBytes(Actual));
  end;
end;

procedure TGoldenTests.TestCorpusMatchesPdfBox(const RelativePath: string);
begin
  if RelativePath = '' then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const Expected = TFile.ReadAllText(TCorpus.GoldenPath(RelativePath), TEncoding.UTF8);
  const Actual = Dump(RelativePath);
  SaveActual(RelativePath, Actual);

  const Known = TGoldenComparer.LoadKnownDifferences(TCorpus.KnownDifferencesPath(RelativePath));
  const Differences = TGoldenComparer.Compare(Expected, Actual, Known);
  if Length(Differences) > 0 then
  begin
    const Reported = Copy(Differences, 0, MaxReportedDifferences);
    Assert.Fail(Format('%s: %d differences with PDFBox, the first %d:%s%s',
                       [RelativePath, Length(Differences), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
  end;
end;

end.
