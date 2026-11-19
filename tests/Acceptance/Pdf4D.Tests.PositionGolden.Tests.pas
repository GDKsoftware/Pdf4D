// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.PositionGolden.Tests;

interface

uses
  DUnitX.TestFramework;

type
  // The position of every line of text of every corpus file must equal what PDFBox 3.0.8 found (tests/golden/*.positions.txt),
  // under the rules of docs/golden-format.md ("Position goldens")
  [TestFixture]
  TPositionGoldenTests = class
  strict private
    class function Dump(const RelativePath: string): string; static;
    class procedure SaveActual(const RelativePath, Actual: string); static;

  public
    [Test]
    [TestCaseProvider('Pdf4DCorpus')]
    procedure TestCorpus(const RelativePath: string);
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.PositionDump,
  Pdf4D.Tests.PositionGolden,
  Pdf4D.Tests.StructureDump,
  Pdf4D.Tests.TextGolden;

const
  OutputEnvironmentVariable = 'PDF4D_GOLDEN_OUTPUT';
  MaxReportedDifferences = 20;

{ TPositionGoldenTests }

class function TPositionGoldenTests.Dump(const RelativePath: string): string;
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
  Result := TPositionDump.Dump(Document, True);
end;

// For looking at a difference: the lines that were found go to the folder in PDF4D_GOLDEN_OUTPUT
class procedure TPositionGoldenTests.SaveActual(const RelativePath, Actual: string);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, TCorpus.GoldenName(RelativePath) + '.positions.txt'), TEncoding.UTF8.GetBytes(Actual));
  end;
end;

procedure TPositionGoldenTests.TestCorpus(const RelativePath: string);
begin
  if RelativePath = '' then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const Expected = TFile.ReadAllText(TCorpus.PositionsGoldenPath(RelativePath), TEncoding.UTF8);
  const Actual = Dump(RelativePath);
  SaveActual(RelativePath, Actual);

  const Known = TTextGoldenComparer.LoadKnownDifferences(TCorpus.PositionsKnownDifferencesPath(RelativePath));
  const Differences = TPositionGoldenComparer.Compare(Expected, Actual, Known, TTextGoldenComparer.CurrentPlatform);
  if Length(Differences) > 0 then
  begin
    const Reported = Copy(Differences, 0, MaxReportedDifferences);
    Assert.Fail(Format('%s: %d differences with PDFBox, the first %d:%s%s',
                       [RelativePath, Length(Differences), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
  end;
end;

end.
