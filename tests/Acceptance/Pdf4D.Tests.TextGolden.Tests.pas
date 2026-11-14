// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TextGolden.Tests;

interface

uses
  DUnitX.TestFramework;

type
  // The extracted text of every corpus file must equal what PDFBox 3.0.8 made of it (tests/golden/*.text.txt), under the
  // rules of docs/golden-format.md ("Text goldens")
  [TestFixture]
  TTextGoldenTests = class
  strict private
    class function Dump(const RelativePath: string): string; static;
    class procedure SaveActual(const RelativePath, Actual: string); static;
    class procedure ReportLenient(const RelativePath: string; const Count: Integer); static;

  public
    [Test]
    [TestCaseProvider('Pdf4DCorpus')]
    procedure TestCorpusTextMatchesPdfBox(const RelativePath: string);
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.StructureDump,
  Pdf4D.Tests.TextDump,
  Pdf4D.Tests.TextGolden;

const
  OutputEnvironmentVariable = 'PDF4D_GOLDEN_OUTPUT';
  LenientReportVariable = 'PDF4D_TEXT_LENIENT_REPORT';
  MaxReportedDifferences = 20;

{ TTextGoldenTests }

class function TTextGoldenTests.Dump(const RelativePath: string): string;
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
  // Strict, so that a crash in a section fails the test instead of becoming an "error" line
  Result := TTextDump.Dump(Document, True);
end;

// For looking at a difference: the text that was found goes to the folder in PDF4D_GOLDEN_OUTPUT
class procedure TTextGoldenTests.SaveActual(const RelativePath, Actual: string);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, TCorpus.GoldenName(RelativePath) + '.text.txt'), TEncoding.UTF8.GetBytes(Actual));
  end;
end;

// For counting: when PDF4D_TEXT_LENIENT_REPORT names a file, a line per file with lenient sections is added to it
class procedure TTextGoldenTests.ReportLenient(const RelativePath: string; const Count: Integer);
begin
  const FileName = GetEnvironmentVariable(LenientReportVariable);
  if (FileName <> '') and (Count > 0) then
  begin
    TFile.AppendAllText(FileName, Format('%s;%d' + sLineBreak, [RelativePath, Count]));
  end;
end;

procedure TTextGoldenTests.TestCorpusTextMatchesPdfBox(const RelativePath: string);
begin
  if RelativePath = '' then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const Expected = TFile.ReadAllText(TCorpus.TextGoldenPath(RelativePath), TEncoding.UTF8);
  const Actual = Dump(RelativePath);
  SaveActual(RelativePath, Actual);

  const Known = TTextGoldenComparer.LoadKnownDifferences(TCorpus.TextKnownDifferencesPath(RelativePath));
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, Known, TTextGoldenComparer.CurrentPlatform);
  ReportLenient(RelativePath, Comparison.LenientSections);
  if Comparison.LenientSections > 0 then
  begin
    TDUnitX.CurrentRunner.Status(Format('%s: %d sections equal after the whitespace rules', [RelativePath, Comparison.LenientSections]));
  end;
  if Length(Comparison.Differences) > 0 then
  begin
    const Reported = Copy(Comparison.Differences, 0, MaxReportedDifferences);
    Assert.Fail(Format('%s: %d differences with PDFBox, the first %d:%s%s',
                       [RelativePath, Length(Comparison.Differences), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
  end;
end;

end.
